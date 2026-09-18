/// Rule: BestPractices_Interop_IRIS.md §15.4 "Modality Worklist date parsing — `$ZDATEH(value, 5)` and the error trap"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN.
/// Severity: High (the failure it guards is a green production and a blank modality screen).
///
/// Pattern: the oracle for `dicom-mwl-date-functionset.cls`.
///
/// THE CENTRAL ASSERTION IS AN OFF-BY-ONE, AND I MADE IT WHILE WRITING THE SUBJECT. The error trap is
/// the **ninth** positional argument of both `$ZDATEH` and `$ZDATE`. The first version of
/// `HorologToDicomDate` put it in the tenth slot -- eight commas instead of seven -- which compiles,
/// runs, and does nothing. Measured:
///
///     $ZDate(999999999, 8, , , , , , , , "")   ->  <VALUE OUT OF RANGE>   trap in slot 10: IGNORED
///     $ZDate(999999999, 8, , , , , , , "")     ->  ""                     trap in slot 9:  works
///
/// So the function whose entire purpose is to stop an exception reaching the worklist process was
/// throwing one, and it compiled clean. `TestTheTrapMustBeTheNinthArgument` is what catches that, and
/// it is the reason this test exists rather than a paragraph saying "remember the trap".
///
/// WHY A THROW IS THE WRONG FAILURE HERE, which is what makes the trap worth a test. A modality asks
/// for a worklist. If the date cannot be parsed and the process throws, the modality gets **no
/// C-FIND response at all** — and IRIS shows a green production with the query in the Visual Trace.
/// A trapped `-1` lets the process answer with an empty-but-well-formed worklist, which the modality
/// can display. Same absence of results; completely different diagnosability.
///
/// MEASURED VALUES this pins:
///     20260918 -> 67831      2026-09-18 -> 67831 (format 5 accepts the dashed form)
///     notadate -> -1         20261332  -> -1      "" -> -1
///     67831 -> 20260918      -5 -> ""             999999999 -> ""
///     IsDicomDate: 20260918=1  2026-09-18=0  2026091=0  notadate=0  20261332=0
///     ranges: 20260101-20260131 -> 67571^67601 | 20260101- -> 67571^ | -20260131 -> ^67601
///             20260918 -> 67831^67831 | bad-20260131 -> "" | "" -> ""
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                   PASSED 8/8
///     the $ZDATEH trap removed                      4 tests FAIL
///     the $ZDATE trap moved back to the TENTH slot   TestTheTrapMustBeTheNinthArgument FAILS
///     $ZDATEH format 3 instead of 5                  6 tests FAIL
///     IsDicomDate drops the shape test               TestIsDicomDateChecksShapeNotJustParse FAILS
///     an open range end returns -1 instead of ""     TestDicomDateRange FAILS
///     StudyDateOrDefault ignores its default         TestStudyDateOrDefault FAILS
///
/// All seven versions compile. The second mutation is the defect that actually shipped in the first
/// draft, and the test written for it is what caught it.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.DicomMwlDate", namespace="<NS>")
Class Example.Tests.DicomMwlDate Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Valid DICOM dates parse to the right day number.
Method TestDicomDatesParse()
{
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateToHorolog("20260918"), 67831, "YYYYMMDD is $ZDATEH format 5")
    // Format 5 also accepts the dashed form. Asserted because it is a tolerance people rely on
    // without knowing, and a pipeline mixing the two shapes works until it meets a third.
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateToHorolog("2026-09-18"), 67831, "format 5 also accepts YYYY-MM-DD, giving the SAME day")
}

/// Unparseable values come back as -1 rather than throwing.
Method TestInvalidDatesReturnMinusOne()
{
    // Positive control first: without it, every -1 below could come from a function that always
    // returns -1.
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateToHorolog("20260918"), 67831, "control: a real date still parses")

    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateToHorolog("notadate"), -1, "free text -> -1, not a throw")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateToHorolog("20261332"), -1, "month 13 / day 32 -> -1")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateToHorolog(""), -1, "empty -> -1")
}

/// THE OFF-BY-ONE. The trap is the ninth argument; the tenth slot is ignored.
Method TestTheTrapMustBeTheNinthArgument()
{
    // $ZDATEH: trap in slot 9 returns the sentinel.
    Do $$$AssertEquals($ZDateH("notadate", 5, , , , , , , -1), -1, "$ZDATEH trap in slot 9 returns -1")

    // And without any trap it THROWS -- the behaviour the function exists to prevent.
    Set tThrew = 0
    Try {
        Set tIgnored = $ZDateH("notadate", 5)
    }
    Catch tEx {
        Set tThrew = 1
        Set tName = tEx.Name
    }
    Do $$$AssertEquals(tThrew, 1, "with no trap, $ZDATEH throws")
    Do $$$AssertEquals($Get(tName), "<ILLEGAL VALUE>", "and it throws <ILLEGAL VALUE>")

    // $ZDATE: the tenth slot is IGNORED. This is the mistake that shipped in the first draft.
    Set tThrew10 = 0
    Try {
        Set tIgnored2 = $ZDate(999999999, 8, , , , , , , , "")
    }
    Catch tEx2 {
        Set tThrew10 = 1
        Set tName2 = tEx2.Name
    }
    Do $$$AssertEquals(tThrew10, 1, "a trap in the TENTH slot is ignored -- it still throws")
    Do $$$AssertEquals($Get(tName2), "<VALUE OUT OF RANGE>", "with <VALUE OUT OF RANGE>")

    // The ninth slot works.
    Do $$$AssertEquals($ZDate(999999999, 8, , , , , , , ""), "", "the NINTH slot traps it and returns the sentinel")

    // And the shipped function uses the right one.
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).HorologToDicomDate(999999999), "", "so the function must not throw either")
}

/// Round trip, both directions.
Method TestRoundTrip()
{
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).HorologToDicomDate(67831), "20260918", "day number back to YYYYMMDD")
    Set tH = ##class(Example.UTL.DicomDate).DicomDateToHorolog("20260918")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).HorologToDicomDate(tH), "20260918", "and round trips")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).HorologToDicomDate(-5), "", "a negative day number gives empty, not a throw")
}

/// IsDicomDate checks the SHAPE as well as the parse -- which is why the dashed form fails it.
Method TestIsDicomDateChecksShapeNotJustParse()
{
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).IsDicomDate("20260918"), 1, "the DICOM shape passes")
    // The discriminating case: this PARSES (67831) and is not a DICOM date.
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateToHorolog("2026-09-18"), 67831, "control: the dashed form does parse")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).IsDicomDate("2026-09-18"), 0, "but it is NOT a DICOM date -- shape matters")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).IsDicomDate("2026091"), 0, "seven digits is not eight")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).IsDicomDate("notadate"), 0, "nor is free text")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).IsDicomDate("20261332"), 0, "right shape, impossible date")
}

/// The worklist entry point: answer the C-FIND even when the date is unusable.
Method TestStudyDateOrDefault()
{
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).StudyDateOrDefault("20260918", 67000), 67831, "a good date is used")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).StudyDateOrDefault("notadate", 67000), 67000, "a bad one falls back to the default")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).StudyDateOrDefault("notadate"), -1, "with no default, -1 propagates so the caller decides")
}

/// Worklist date ranges, including the open-ended forms.
Method TestDicomDateRange()
{
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateRange("20260101-20260131"), "67571^67601", "a closed range")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateRange("20260101-"), "67571^", "open upper end leaves its half EMPTY")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateRange("-20260131"), "^67601", "open lower end likewise")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateRange("20260918"), "67831^67831", "a single date is that day only")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateRange("bad-20260131"), "", "an unparseable end voids the whole range")
    Do $$$AssertEquals(##class(Example.UTL.DicomDate).DicomDateRange(""), "", "and empty stays empty")
}

}
