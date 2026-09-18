/// Rule: BestPractices_Interop_IRIS.md §15.4 "Modality Worklist date parsing — `$ZDATEH(value, 5)` and the error trap"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (a green production and a blank modality screen).
///
/// Pattern: the date conversions a Modality Worklist C-FIND needs, as a `[ Final ]` FunctionSet so a
/// DTL or a business rule can call them by name. Pure core ObjectScript — it touches no
/// `EnsLib.DICOM` class, so it compiles and runs on IRIS community, which is what makes it the
/// cheapest thing in this chapter to gate.
///
/// WHY THIS IS THE FIRST DICOM ARTEFACT. DICOM's failure modes are almost all invisible from the IRIS
/// side. A modality asks for a worklist; if the date in `DataSet.StudyDate` cannot be parsed, the
/// worklist process throws, the modality gets **no C-FIND response at all** — or an empty one — and
/// IRIS shows a green production with the query sitting in the Visual Trace. Nobody looking at IRIS
/// sees a problem. The radiographer sees a blank screen.
///
/// DICOM DATES ARE `$ZDATEH` FORMAT 5. `YYYYMMDD`, no separators. Measured:
///
///     $ZDATEH("20260918", 5)   ->  67831
///     $ZDATEH("2026-09-18", 5) ->  67831        <-- format 5 also accepts the dashed form
///     $ZDATEH("notadate", 5)   ->  <ILLEGAL VALUE>
///     $ZDATEH("20261332", 5)   ->  <ILLEGAL VALUE>       month 13, day 32
///
/// THE ERROR TRAP IS THE NINTH POSITIONAL ARGUMENT, which is why it gets left out — eight commas is
/// not a thing anyone writes by accident:
///
///     $ZDATEH(v, 5, , , , , , , -1)   ->  -1 instead of <ILLEGAL VALUE>
///
/// Measured on the same four inputs: the two valid ones return 67831 either way, and the two invalid
/// ones return **-1** with the trap where they threw without it. A sentinel you can test beats an
/// exception thrown from inside a business process, because the process can then answer the C-FIND
/// with an empty-but-well-formed response instead of not answering.
///
/// THE RANGE CHECK THE TRAP DOES NOT DO. `-1` means "this is not a date". It does not mean "this date
/// is sensible". A worklist query for `19000101` parses fine and matches nothing, which is a
/// different bug with the same symptom — a blank modality — so `StudyDateOrDefault` below separates
/// "unparseable" from "parsed, and here it is" and leaves the plausibility judgement to the caller.
///
/// FORMAT 5 ACCEPTING `2026-09-18` IS WORTH KNOWING. It means a value arriving from a non-DICOM
/// source — a SQL worklist feed, a hand-edited test fixture — parses rather than failing loudly, so a
/// mixed-format pipeline can work for months and then break on the one row that has neither shape.
/// That is why `IsDicomDate` tests the SHAPE as well as the parse.
Class Example.UTL.DicomDate Extends Ens.Rule.FunctionSet
{

/// DICOM `YYYYMMDD` to a `$Horolog` day number, or -1 when it cannot be parsed.
/// `[ Final ]` is required for a FunctionSet method to be usable as a utility function.
///
/// The ninth positional argument is the error trap. Without it this throws `<ILLEGAL VALUE>`.
ClassMethod DicomDateToHorolog(pValue As %String) As %Integer [ Final ]
{
    If pValue = "" {
        Return -1
    }
    Return $ZDateH(pValue, 5, , , , , , , -1)
}

/// A `$Horolog` day number back to DICOM `YYYYMMDD`. Format 8 is the unseparated form.
///
/// The trap is the NINTH argument here too -- `$ZDATE(h, dformat, monthlist, yearopt, startwin,
/// endwin, mindate, maxdate, erropt)`. Writing it in the tenth slot compiles and does nothing:
/// measured, `$ZDate(999999999, 8, , , , , , , , "")` still threw `<VALUE OUT OF RANGE>` while
/// `$ZDate(999999999, 8, , , , , , , "")` returns "". Eight commas versus seven, and the wrong count
/// leaves you with an uncaught error in the function whose whole purpose is catching it. Count them
/// against the signature, not by eye.
ClassMethod HorologToDicomDate(pHorolog As %Integer) As %String [ Final ]
{
    If (pHorolog = "") || (pHorolog < 0) {
        Return ""
    }
    Return $ZDate(pHorolog, 8, , , , , , , "")
}

/// Is this a DICOM date in BOTH senses -- the right shape AND parseable?
///
/// The shape test is not redundant. `$ZDATEH(v, 5)` also accepts `2026-09-18`, so a value from a
/// non-DICOM source parses cleanly and a pipeline mixing the two forms works until it meets the one
/// row that has neither.
ClassMethod IsDicomDate(pValue As %String) As %Boolean [ Final ]
{
    If $Length(pValue) '= 8 {
        Return 0
    }
    If pValue '? 8N {
        Return 0
    }
    Return (..DicomDateToHorolog(pValue) '= -1)
}

/// The worklist entry point: parse `DataSet.StudyDate`, falling back to pDefaultHorolog when it
/// cannot be parsed.
///
/// A worklist process wants to ANSWER the C-FIND even when the date is unusable -- an empty,
/// well-formed response is a worklist with no entries, which the modality can display. Throwing
/// means no response at all, which it cannot. Pass `$Horolog` to default to today, or -1 to make
/// "unparseable" propagate so the caller decides.
ClassMethod StudyDateOrDefault(pValue As %String, pDefaultHorolog As %Integer = -1) As %Integer [ Final ]
{
    Set tParsed = ..DicomDateToHorolog(pValue)
    If tParsed = -1 {
        Return pDefaultHorolog
    }
    Return tParsed
}

/// A DICOM date RANGE as a worklist query uses it: "20260101-20260131", or an open-ended
/// "20260101-" / "-20260131", or a single date meaning that day only.
///
/// Returns "from^to" as $Horolog day numbers, or "" when either end is unparseable. Open ends come
/// back empty in their half, so a caller can tell "no lower bound" from "bad lower bound" -- which
/// a single -1 sentinel could not express.
ClassMethod DicomDateRange(pValue As %String) As %String [ Final ]
{
    If pValue = "" {
        Return ""
    }
    If pValue '[ "-" {
        Set tOne = ..DicomDateToHorolog(pValue)
        If tOne = -1 {
            Return ""
        }
        Return tOne _ "^" _ tOne
    }

    // Split on the LAST separator is wrong for "20260101-20260131" and right for nothing here, so
    // split on the first: a DICOM date carries no internal hyphen in the 8N form.
    Set tFrom = $Piece(pValue, "-", 1)
    Set tTo = $Piece(pValue, "-", 2)

    Set tFromH = ""
    If tFrom '= "" {
        Set tFromH = ..DicomDateToHorolog(tFrom)
        If tFromH = -1 {
            Return ""
        }
    }
    Set tToH = ""
    If tTo '= "" {
        Set tToH = ..DicomDateToHorolog(tTo)
        If tToH = -1 {
            Return ""
        }
    }
    Return tFromH _ "^" _ tToH
}

}
