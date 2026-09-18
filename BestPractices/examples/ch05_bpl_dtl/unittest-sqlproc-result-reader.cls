/// Rule: BestPractices_Interop_IRIS.md §5.14 "Reading a %UnitTest verdict from a SqlProc — and how an assert-scanner reports a green for a failed run"
/// Validity: Verified against IRIS for Health 2026.1 — every row shape below was read from a real failing run.
/// Severity: High (this is the shape that lets a self-graded test claim a pass, which is CR-7).
///
/// Pattern: report a %UnitTest verdict from a headless `[SqlProc]`, correctly. CR-7 exists because
/// a self-graded SqlProc is trusted far more readily than it has earned, and the honest reader is
/// only a few lines away from the dishonest one.
///
/// FIRST, THE PART THAT IS NOT OPTIONAL: `DebugRunTestCase` PERSISTS NOTHING. Measured on 2026.1,
/// twice, with a case that genuinely fails:
///     ##class(%UnitTest.Manager).DebugRunTestCase("", "<case>", "", "")
///       -> no rows in %UnitTest_Result.TestMethod
///       -> ^UnitTest.Result not even defined
/// It writes to the DEVICE. So any SqlProc that calls it and then returns "passed=N failed=M" is
/// reporting numbers it did not read from the run — which is the whole of CR-7 in one sentence.
/// Results are persisted by `%UnitTest.Manager.RunTest(<suite>, <qspec>)` with `^UnitTestRoot` set
/// to a directory that exists ON THE IRIS SERVER; that run loads and compiles the `.cls` files it
/// finds under the suite directory. `/nodelete` keeps them afterwards.
///
/// SECOND, THE ROW SHAPES, because guessing them is what produces the false green. From one run of
/// a case with one passing and one failing method:
///
///   %UnitTest_Result.TestMethod    TestBad   Status=0      TestGood  Status=1
///   %UnitTest_Result.TestCase      <case>    Status=0      (the failure rolls up correctly)
///   %UnitTest_Result.TestAssert    TestBad/1   AssertEquals  Status=0  "FAILS"
///                                  TestBad/2   LogMessage    Status=1  "Duration of execution: …"
///                                  TestGood/1  AssertEquals  Status=1  "passes"
///                                  TestGood/2  LogMessage    Status=1  "Duration of execution: …"
///
/// AND THERE IS THE TRAP. **Every method gets a trailing `LogMessage` row with Status = 1.** A
/// reader that scans TestAssert without filtering `Action`, and takes the last row per method,
/// sees `LogMessage`/1 for BOTH methods and reports **passed=2, failed=0** — for a case whose own
/// Status is 0 and which %UnitTest printed as FAILED. Nothing about that reader looks wrong.
///
/// SO: READ `TestMethod.Status`. It is the verdict, already rolled up, one row per method. If you
/// must touch TestAssert, filter `Action <> 'LogMessage'` — but there is no reason to: the status
/// you want is one table up.
///
/// The ID is a `||`-delimited composite — `<instance>||<suite>||<case>||<method>` — so
/// `$Piece(id, "||", 4)` is the method node when you need to locate one. It is not a %List, which
/// is worth saying because the shape invites `$ListGet` and that returns nothing useful.
///
/// THIRD AND FOURTH, both found in v1.37.0 by using this reader on a fresh run — and both produce
/// a confident wrong answer rather than an error, which is the same failure class the rest of this
/// file is about.
///
/// 3. THE CASE NAME IS NOT A PREFIX OF THE ID. Until v1.37.0 this class's own doc comment said to
///    call it as `Verdict('Example.Tests.DeleteCascade')`, and the query was
///    `WHERE TestCase %STARTSWITH ?`. The ID begins with the INSTANCE number, so a bare class name
///    is a prefix of nothing. Measured against a run that had just passed 8 of 8:
///        Verdict('Example.Tests.MaxLenTruncation')                -> "NO RESULTS … nothing was persisted"
///        Verdict('20||ZZS29||Example.Tests.MaxLenTruncation')     -> "PASSED 8/8"
///    The prescribed call reported "nothing ran" for a run that ran and passed, and the message
///    sends you to fix a test runner that is working. `Verdict()` now takes the bare case name —
///    matching `TestCase.Name`, which is what actually holds it — and still accepts a full ID.
///
/// 4. `MAX(ID)` PICKS THE WRONG RUN, because the ID is a STRING. `MAX()` on
///    `<instance>||<suite>||<case>` compares lexically, so `'9||…'` beats `'13||…'` and you read
///    run 9. Order by `CAST($PIECE(ID, '||', 1) AS INTEGER)` instead. And scoping to ONE run is
///    not optional: results accumulate, so an unscoped reader sums every run ever recorded —
///    measured, five runs of this 8-method suite reported `methods=40`, with a mutation's failure
///    still visible three runs after it was reverted.
Class Example.UTL.UnitTestResult Extends %RegisteredObject
{

/// The honest verdict for one test case, from its MOST RECENT run.
/// Returns "PASSED n/n" or "FAILED: <method>, <method>".
/// Invoke via: SELECT Example_UTL.UnitTestResult_Verdict('Example.Tests.DeleteCascade')
/// A full '<instance>||<suite>||<case>' ID also works, and then names that exact run.
ClassMethod Verdict(pCase As %String) As %String [ SqlProc ]
{
    Set tTotal = 0, tFailed = 0, tNames = ""

    // Resolve the argument to ONE TestCase row. A bare class name matches TestCase.Name -- it is
    // NOT a prefix of the ID, which starts with the instance number (see the header). Ordering is
    // on the instance piece CAST TO INTEGER because the ID is a string and '9||' > '13||'.
    If pCase [ "||" {
        Set tCaseId = pCase
    } Else {
        Set tIdSQL = "SELECT TOP 1 ID FROM %UnitTest_Result.TestCase WHERE Name = ? "_
                     "ORDER BY CAST($PIECE(ID, '||', 1) AS INTEGER) DESC"
        Set tIdRS = ##class(%SQL.Statement).%ExecDirect(, tIdSQL, pCase)
        Set tCaseId = ""
        If tIdRS.%Next() {
            Set tCaseId = tIdRS.%Get("ID")
        }
        If tCaseId = "" {
            Quit "NO RESULTS for '" _ pCase _ "' -- no TestCase row of that name, so either the run "_
                 "never persisted anything or the name is wrong"
        }
    }

    // TestMethod.Status IS the verdict. One row per method, already rolled up. Scoped to the one
    // run resolved above: results ACCUMULATE, and an unscoped reader sums every run ever.
    Set tSQL = "SELECT Name, Status FROM %UnitTest_Result.TestMethod WHERE TestCase = ?"
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, tCaseId)
    While tRS.%Next() {
        Set tTotal = tTotal + 1
        If 'tRS.%Get("Status") {
            Set tFailed = tFailed + 1
            Set tNames = tNames _ $Select(tNames = "": "", 1: ", ") _ tRS.%Get("Name")
        }
    }

    // NO ROWS IS NOT A PASS. It means the run never persisted anything -- most likely
    // DebugRunTestCase, or RunTest with ^UnitTestRoot pointing somewhere IRIS cannot see.
    If tTotal = 0 {
        Quit "NO RESULTS for '" _ tCaseId _ "' -- the case row exists but has no method rows, so "_
             "there is no verdict to report"
    }

    Quit $Select(tFailed = 0: "PASSED " _ tTotal _ "/" _ tTotal,
                 1: "FAILED: " _ tNames _ " (" _ tFailed _ " of " _ tTotal _ ")")
}

/// The WRONG reader, kept so the difference is demonstrable rather than described. It scans
/// TestAssert and takes the last row per method -- which is a LogMessage with Status 1 every time.
/// Measured on the same failing run: this returns passed=2 failed=0 while Verdict() returns FAILED.
/// It is Private so nothing can call it by accident.
ClassMethod NaiveVerdict(pCase As %String) As %String [ Private ]
{
    Set tPassed = 0, tFailed = 0
    Set tSQL = "SELECT TestMethod, Status FROM %UnitTest_Result.TestAssert WHERE TestMethod %STARTSWITH ? ORDER BY ID"
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, pCase)
    While tRS.%Next() {
        // the bug: no Action filter, so the trailing LogMessage overwrites the real result
        Set tLast($Piece(tRS.%Get("TestMethod"), "||", 4)) = tRS.%Get("Status")
    }
    Set k = ""
    For {
        Set k = $Order(tLast(k))
        Quit:k=""
        If tLast(k) { Set tPassed = tPassed + 1 } Else { Set tFailed = tFailed + 1 }
    }
    Quit "passed=" _ tPassed _ " failed=" _ tFailed
}

/// Run both readers against the same persisted result set, so the difference is demonstrable
/// rather than asserted. `NaiveVerdict` is Private, so this has to live inside the class --
/// which is itself worth knowing: `$classmethod()` on a Private method raises <PRIVATE METHOD>.
/// Invoke via: SELECT Example_UTL.UnitTestResult_Compare('<instance>||<suite>||<case>')
ClassMethod Compare(pCase As %String) As %String [ SqlProc ]
{
    Quit "correct=[" _ ..Verdict(pCase) _ "]  naive=[" _ ..NaiveVerdict(pCase) _ "]"
}

}
