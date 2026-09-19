/// Rule: BestPractices_Interop_IRIS.md §5.16 "`ConvertDateTime` validates ranges, never the calendar — and the `$ZDATEH` equivalent is not equivalent"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (its two failure modes are both silent, and one of them produces a date).
///
/// Pattern: the ORACLE for the `..ConvertDateTime` cheat-sheet in `transformations`. Five format
/// pairs had been carried as a table headed "Verified conversions" with nothing executing them.
///
/// THE GOOD NEWS FIRST, because it is the less common outcome in this bank: **all five documented
/// rows are exactly right.** Executed on 2026.1, every one produces the documented output to the
/// character. `TestDocumentedTable` below is what keeps them that way, and it is the reason this
/// file is worth its length even though it found the table correct.
///
/// WHAT THE TABLE DID NOT SAY, and it is the whole risk of the function. `ConvertDateTime`
/// validates the numeric RANGES of the fields and never the CALENDAR, which splits bad input into
/// two silent failure modes with completely different signatures:
///
///   day 1-31 AND month 1-12  ->  REFORMATTED, calendar unchecked. Measured:
///       31/02/1958  ->  1958-02-31        February has 28 days
///       30/02/1958  ->  1958-02-30
///       29/02/2023  ->  2023-02-29        2023 is not a leap year
///       31/04/1958  ->  1958-04-31        April has 30 days
///     This is the dangerous half. The output is WELL-FORMED — it will satisfy a length check, a
///     regex, a `LIKE '____-__-__'`, and any eyeball — and it is not a date. It travels.
///
///   anything outside those ranges  ->  RETURNED UNCHANGED. Measured:
///       32/01/1958, 00/01/1958, 31/13/1958, 31/00/1958, 13/13/1958, 99/99/9999   all unchanged
///     This is the half the skill described. The original text reaches the column and fails at the
///     JDBC bind, far from the DTL that caused it.
///
/// Neither raises anything. So "it came back looking like a date" is not evidence of anything, and
/// the only reliable check is a calendar validation you perform yourself, in the DTL.
///
/// AND THE CORRECTION THIS FILE FORCED. `transformations` offered a "raw ObjectScript equivalent":
///
///     $ZDATE($ZDATEH("22/07/1958", 4), 3)   ->  1958-07-22
///
/// It is not equivalent, and the difference is precisely validation. Measured side by side:
///
///                     ..ConvertDateTime          $ZDATE($ZDATEH(...))
///     31/12/1958      1958-12-31                 1958-12-31            agree
///     31/02/1958      1958-02-31                 <ILLEGAL VALUE>       DISAGREE
///     32/01/1958      32/01/1958 (unchanged)     <ILLEGAL VALUE>       DISAGREE
///     99/99/9999      99/99/9999 (unchanged)     <ILLEGAL VALUE>       DISAGREE
///
/// `$ZDATEH` checks the calendar and throws; `ConvertDateTime` does not and returns something. The
/// word "equivalent" hid the one property you would choose between them for. Both forms are still
/// legitimate — prefer `..ConvertDateTime` in a DTL for the reasons the skill gives (it is in the
/// picker and round-trips through the visual editor) — but choose it knowing it will not refuse
/// 31 February, and validate separately if that matters.
///
/// `%Q` IS A TIMESTAMP AND IT IS THE DEFAULT FOR BOTH ARGUMENTS. Measured:
///     ConvertDateTime("22/07/1958", "%d/%m/%Y", "%Q")  ->  1958-07-22 00:00:00.000
///     ConvertDateTime("22/07/1958")                    ->  22/07/1958   (unchanged!)
/// The second line is the trap inside the trap: called with no formats at all, `in` defaults to `%Q`,
/// the input does not match it, and the value is returned unchanged — a no-op that looks like a call.
///
/// RUN AND MUTATION-CHECKED. Executed via `%UnitTest.Manager.RunTest()` with `^UnitTestRoot` set to
/// a server directory, and read back with `Example.UTL.UnitTestResult.Verdict()` from this same
/// directory -- the reader whose own documented invocation was broken until v1.37.0:
///
///     as shipped                                  PASSED 6/6
///     table row 1 expects 1958-07-23              TestDocumentedTable            FAILS
///     31/02 expected to be refused                TestCalendarIsNotValidated     FAILS
///     day 32 expected to convert                  TestOutOfRangeIsReturnedUnchanged FAILS
///     %Q expected to give a bare date             TestQIsATimestampAndTheDefault FAILS
///     $ZDATEH expected NOT to throw               TestRawZDateHIsNotEquivalent   FAILS
///
/// Each mutation reddens exactly its own test and nothing else. All six versions compile.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.ConvertDateTime", namespace="<NS>")
Class Example.Tests.ConvertDateTime Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. This suite touches no production.
Parameter PRODUCTION = "Example.Productions.CensoIntake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Shorthand, so the assertions below read as the cheat-sheet does.
ClassMethod Conv(pVal As %String, pIn As %String, pOut As %String) As %String [ Private ]
{
    Quit ##class(Ens.Util.FunctionSet).ConvertDateTime(pVal, pIn, pOut)
}

/// THE ORACLE. Every row of the `transformations` "Verified conversions" table, executed. If a row
/// is ever edited to something the platform does not do, this is what says so.
Method TestDocumentedTable()
{
    Do $$$AssertEquals(..Conv("22/07/1958", "%d/%m/%Y", "%Y-%m-%d"), "1958-07-22", "CSV DD/MM/YYYY -> SQL DATE")
    Do $$$AssertEquals(..Conv("07/22/1958", "%m/%d/%Y", "%Y-%m-%d"), "1958-07-22", "US MM/DD/YYYY -> SQL DATE")
    Do $$$AssertEquals(..Conv("1958-07-22", "%Y-%m-%d", "%d/%m/%Y"), "22/07/1958", "SQL DATE -> CSV DD/MM/YYYY")
    Do $$$AssertEquals(..Conv("19580722143000", "%Y%m%d%H%M%S", "%Y-%m-%d %H:%M:%S"), "1958-07-22 14:30:00", "HL7 TS -> SQL TIMESTAMP")
    Do $$$AssertEquals(..Conv("1958-07-22 14:30:00", "%Y-%m-%d %H:%M:%S", "%Y%m%d%H%M%S"), "19580722143000", "SQL TIMESTAMP -> HL7 TS")
}

/// THE DANGEROUS HALF: in-range but non-existent dates are reformatted into well-formed nonsense.
/// Each of these outputs would pass a regex, a length check and a glance.
Method TestCalendarIsNotValidated()
{
    Do $$$AssertEquals(..Conv("31/02/1958", "%d/%m/%Y", "%Y-%m-%d"), "1958-02-31", "31 February is reformatted, not refused")
    Do $$$AssertEquals(..Conv("30/02/1958", "%d/%m/%Y", "%Y-%m-%d"), "1958-02-30", "30 February likewise")
    Do $$$AssertEquals(..Conv("29/02/2023", "%d/%m/%Y", "%Y-%m-%d"), "2023-02-29", "29 February in a non-leap year likewise")
    Do $$$AssertEquals(..Conv("31/04/1958", "%d/%m/%Y", "%Y-%m-%d"), "1958-04-31", "31 April likewise")

    // The control: a genuinely valid date in the same shape, so the four above cannot be explained
    // by the function simply never converting anything.
    Do $$$AssertEquals(..Conv("31/12/1958", "%d/%m/%Y", "%Y-%m-%d"), "1958-12-31", "control: a real date converts")
}

/// THE OTHER HALF: out-of-range fields are returned unchanged, so the raw text travels onward.
Method TestOutOfRangeIsReturnedUnchanged()
{
    Do $$$AssertEquals(..Conv("32/01/1958", "%d/%m/%Y", "%Y-%m-%d"), "32/01/1958", "day 32 is out of range -> unchanged")
    Do $$$AssertEquals(..Conv("00/01/1958", "%d/%m/%Y", "%Y-%m-%d"), "00/01/1958", "day 0 -> unchanged")
    Do $$$AssertEquals(..Conv("31/13/1958", "%d/%m/%Y", "%Y-%m-%d"), "31/13/1958", "month 13 -> unchanged")
    Do $$$AssertEquals(..Conv("31/00/1958", "%d/%m/%Y", "%Y-%m-%d"), "31/00/1958", "month 0 -> unchanged")
    Do $$$AssertEquals(..Conv("99/99/9999", "%d/%m/%Y", "%Y-%m-%d"), "99/99/9999", "wholly invalid -> unchanged")
    Do $$$AssertEquals(..Conv("not a date", "%d/%m/%Y", "%Y-%m-%d"), "not a date", "free text -> unchanged")
    Do $$$AssertEquals(..Conv("", "%d/%m/%Y", "%Y-%m-%d"), "", "empty -> empty")
}

/// `%Q` is a full ODBC timestamp, and it is the default for BOTH arguments -- so calling the
/// function with no formats is a no-op that looks like a conversion.
Method TestQIsATimestampAndTheDefault()
{
    Do $$$AssertEquals(..Conv("22/07/1958", "%d/%m/%Y", "%Q"), "1958-07-22 00:00:00.000", "%Q out yields a timestamp, which a DATE column will not take")
    Do $$$AssertEquals(##class(Ens.Util.FunctionSet).ConvertDateTime("22/07/1958"), "22/07/1958", "with no formats, in defaults to %Q, does not match, and the value passes through")
}

/// THE NON-EQUIVALENCE. `$ZDATEH` validates the calendar and throws; `ConvertDateTime` does not.
/// This is the assertion that catches the word "equivalent" if it ever comes back.
Method TestRawZDateHIsNotEquivalent()
{
    // They agree on a valid date -- the control, without which "they differ" proves nothing.
    Do $$$AssertEquals($ZDate($ZDateH("31/12/1958", 4), 3), ..Conv("31/12/1958", "%d/%m/%Y", "%Y-%m-%d"), "control: on a real date the two forms agree")

    // And they disagree on 31 February: one refuses, the other invents.
    Set tThrew = 0
    Try {
        Set tIgnored = $ZDate($ZDateH("31/02/1958", 4), 3)
    }
    Catch tEx {
        Set tThrew = 1
        Set tName = tEx.Name
    }
    Do $$$AssertEquals(tThrew, 1, "$ZDATEH must REFUSE 31 February")
    Do $$$AssertEquals($Get(tName), "<ILLEGAL VALUE>", "and refuse it with <ILLEGAL VALUE>")
    Do $$$AssertEquals(..Conv("31/02/1958", "%d/%m/%Y", "%Y-%m-%d"), "1958-02-31", "while ConvertDateTime returns a well-formed non-date")
}

}
