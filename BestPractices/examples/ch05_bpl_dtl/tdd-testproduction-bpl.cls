/// Rule: BestPractices_Interop_IRIS.md §5.23 "Asserting a BPL ran: `$IsObject(resp)` passes on a process that failed every call"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (the assertion it replaces reports success on a process that did nothing).
///
/// Pattern: what a `%UnitTest.TestProduction` must assert about a BPL, and why the obvious pair is not
/// enough. `tdd`'s own gated snippet asserted exactly two things:
///
///     Do $$$AssertStatusOK(..SendRequest("BP.MyProcess", req, .resp, 1, 30))
///     Do $$$AssertEquals($IsObject(resp), 1, "Got a response back")
///
/// `TestWeakAssertionsPassOnAFailedProcess` below runs BOTH of those against
/// `Example.BP.SwallowedFault` with an input that makes every `<call>` fail -- and asserts that **both
/// pass**. That is the point of this suite: it is a test whose subject is another test's blind spot.
///
/// MEASURED, same input to two BPLs in one production:
///
///     target              input    SendRequest    $IsObject(resp)   response.StringValue
///     BP.SwallowedFault   HAPPY    $$$OK          1                 "none"
///     BP.SwallowedFault   FAIL     $$$OK          1                 "caught: ERROR #5001: ..."
///     BP.ScopedOrder      FAIL     ERROR          --                --
///
/// So the swallowing shape is indistinguishable from success through those two assertions, while the
/// propagating shape (§5.21) is caught by the first one. **The gap belongs to the BPL shape, not to
/// BPL in general** — which is why the contrast is asserted here rather than assumed.
///
/// WHAT DOES DISCRIMINATE, measured on the failing session:
///
///     response.StringValue     starts with "caught: " instead of being "none"
///     Ens.MessageHeader        BO.Failing at Status 8 (Error); every other header in the session is 9
///     Ens_Util.Log             2 rows of Type 2 (Error), one naming BO.Failing with the #5001 text
///                              -- and ZERO rows on the happy session, which is what makes it a test
///
/// `Ens.DataType.LogType` measured: 1 Assert, **2 Error**, 3 Warning, 4 Info, 5 Trace, 6 Alert.
/// `Ens.DataType.MessageStatus`: 8 Error, 9 Completed.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=393  6 methods, 0 failed
///     the catchall records nothing                run=394  1 failed
///     the response is never filled                run=395  1 failed
///     the context starts empty, not "none"        run=396  1 failed
///     the catchall PROPAGATES                     run=397  3 failed -- including
///                                                          WeakAssertionsPassOnAFailedProcess
///     reverted                                    run=398  6 methods, 0 failed
///
/// Mutation 4 is the one that anchors this suite. Making the fixture honest — adding the `set status`
/// line §5.21 prescribes — breaks the headline test, because the weak assertions then DO catch the
/// failure. Without that mutation, "the weak assertions pass" could have been true for some unrelated
/// reason.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.TestProductionBpl", namespace="<NS>")
Class Example.Tests.TestProductionBpl Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.BplAssertions";

/// A no-op override: the inherited TestControl() starts the production, hangs and stops it again,
/// leaving nothing running for the tests that follow.
Method TestControl() As %Status
{
    Quit $$$OK
}

Method OnBeforeAllTests() As %Status
{
    Set tSC = ##class(Ens.Director).StartProduction(..#PRODUCTION)
    Quit:$$$ISERR(tSC) tSC
    For i = 1:1:40 {
        If ##class(Ens.Director).IsProductionRunning() { Quit }
        Hang 0.25
    }
    If '##class(Ens.Director).IsProductionRunning() {
        Quit $$$ERROR($$$GeneralError, "production " _ ..#PRODUCTION _ " did not come up")
    }
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Do ##class(Ens.Director).StopProduction(15, 1)
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ##class(Example.BO.FailOnDemand).Reset()
    Kill ^Example.ScopedOrder
    Quit $$$OK
}

/// Send one request synchronously and hand back everything a caller can see.
/// pSession is the session id, needed to read the headers and the log for THIS run only.
ClassMethod Drive(pTarget As %String, pText As %String, Output pResp As %RegisteredObject, Output pSession As %String) As %Status [ Private ]
{
    Set pResp = "", pSession = ""
    Set tBaseLog = ..MaxLogId()
    Set tReq = ##class(Ens.StringContainer).%New(pText)
    Set tSC = ..SendRequest(pTarget, tReq, .pResp, 1, 30)
    // The session is on the response's own header when there is one; otherwise fall back to the
    // newest header, which is what the log rows below are keyed to.
    Set pSession = ..NewestSessionAfter(tBaseLog)
    Quit tSC
}

ClassMethod MaxLogId() As %Integer [ Private ]
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT NVL(MAX(ID),0) AS n FROM Ens_Util.Log")
    Quit:tRs.%SQLCODE<0 0
    Do tRs.%Next()
    Quit tRs.%Get("n")
}

/// The newest session id in the message headers -- the run just driven.
ClassMethod NewestSessionAfter(pBaseLogId As %Integer) As %String [ Private ]
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SessionId FROM Ens.MessageHeader ORDER BY ID DESC")
    Quit:tRs.%SQLCODE<0 ""
    Quit $Select(tRs.%Next():tRs.%Get("SessionId"), 1:"")
}

/// How many headers in this session sit at a given status, and which config names they are.
ClassMethod HeadersAt(pSession As %String, pStatus As %Integer, Output pNames As %String) As %Integer [ Private ]
{
    Set pNames = "", tCount = 0
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TargetConfigName FROM Ens.MessageHeader WHERE SessionId = ? AND Status = ?", pSession, pStatus)
    Quit:tRs.%SQLCODE<0 -1
    While tRs.%Next() {
        Set tCount = tCount + 1
        Set pNames = pNames _ $Select(pNames="":"", 1:",") _ tRs.%Get("TargetConfigName")
    }
    Quit tCount
}

/// Error rows (Type 2) logged for this session, with their text.
ClassMethod ErrorLogRows(pSession As %String, Output pText As %String) As %Integer [ Private ]
{
    Set pText = "", tCount = 0
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT ConfigName, Text FROM Ens_Util.Log WHERE SessionId = ? AND Type = 2 ORDER BY ID", pSession)
    Quit:tRs.%SQLCODE<0 -1
    While tRs.%Next() {
        Set tCount = tCount + 1
        Set pText = pText _ "[" _ tRs.%Get("ConfigName") _ ": " _ $Extract(tRs.%Get("Text"), 1, 70) _ "]"
    }
    Quit tCount
}

/// THE SUBJECT OF THIS SUITE. Both of `tdd`'s original assertions pass on a process whose every call
/// failed. Asserted positively, so that if IRIS ever starts reporting the failure through either of
/// them this test fails and the section needs revisiting.
Method TestWeakAssertionsPassOnAFailedProcess() As %Status
{
    Set tSC = ..Drive("BP.SwallowedFault", "FAIL this order", .tResp, .tSession)
    Do $$$AssertStatusOK(tSC, "WEAK ASSERTION 1 passes: SendRequest returns $$$OK although the BO failed")
    Do $$$AssertEquals($IsObject(tResp), 1, "WEAK ASSERTION 2 passes: a response object came back although the BO failed")
    // POSITIVE CONTROL: the BO really was reached and really did fail. Without this the two passes
    // above could mean the message never got that far.
    Do $$$AssertEquals(##class(Example.BO.FailOnDemand).Attempts(), 1, "POSITIVE CONTROL: the BO was called exactly once, so there WAS a failure to miss")
    Quit $$$OK
}

/// The field value is the discriminator inside the reply.
Method TestTheFieldValueDistinguishesHappyFromFailed() As %Status
{
    Set tSC = ..Drive("BP.SwallowedFault", "HAPPY path", .tHappy, .tSessionA)
    Do $$$AssertStatusOK(tSC, "the happy run succeeds")
    Do $$$AssertEquals($IsObject(tHappy), 1, "POSITIVE CONTROL: the happy run returned an object to read a field from")
    Do $$$AssertEquals(tHappy.StringValue, "none", "on success the field still holds the context initial expression, got: " _ tHappy.StringValue)
    Do ##class(Example.BO.FailOnDemand).Reset()
    Set tSC = ..Drive("BP.SwallowedFault", "FAIL this order", .tFailed, .tSessionB)
    Do $$$AssertEquals($IsObject(tFailed), 1, "POSITIVE CONTROL: the failing run also returned an object -- which is the problem")
    Do $$$AssertTrue($Extract(tFailed.StringValue, 1, 8) = "caught: ", "and ONLY the field value says the call failed: " _ tFailed.StringValue)
    Do $$$AssertNotEquals(tFailed.StringValue, tHappy.StringValue, "the two runs are distinguishable by value and by nothing else in the reply")
    Quit $$$OK
}

/// Outside the reply, the BO's own header carries the truth.
Method TestTheBusinessOperationHeaderIsAtError() As %Status
{
    Set tSC = ..Drive("BP.SwallowedFault", "FAIL this order", .tResp, .tSession)
    Do $$$AssertNotEquals(tSession, "", "POSITIVE CONTROL: a session id was resolved, so the queries below address this run")
    Set tErrors = ..HeadersAt(tSession, 8, .tErrNames)
    Do $$$AssertEquals(tErrors, 1, "exactly one header in the session is at Status 8 (Error), found " _ tErrors _ ": " _ tErrNames)
    Do $$$AssertEquals(tErrNames, "BO.Failing", "and it is the Business Operation's, not the process's: " _ tErrNames)
    // POSITIVE CONTROL: the rest of the session really did complete, so "one error" is a discrimination
    // and not simply an empty session.
    Set tDone = ..HeadersAt(tSession, 9, .tDoneNames)
    Do $$$AssertTrue(tDone >= 2, "POSITIVE CONTROL: other headers in the same session are at 9 Completed, found " _ tDone)
    Quit $$$OK
}

/// And `Ens_Util.Log` records it -- asserted as a difference from the happy run, because "there are
/// error rows" is also true of anything else that happened to fail on this instance.
Method TestEnsUtilLogRecordsTheSwallowedError() As %Status
{
    Set tSC = ..Drive("BP.SwallowedFault", "HAPPY path", .tResp, .tHappySession)
    Set tHappyRows = ..ErrorLogRows(tHappySession, .tHappyText)
    Do $$$AssertEquals(tHappyRows, 0, "the happy run logs NO error rows, found " _ tHappyRows _ ": " _ tHappyText)
    Do ##class(Example.BO.FailOnDemand).Reset()
    Set tSC = ..Drive("BP.SwallowedFault", "FAIL this order", .tResp2, .tFailSession)
    Set tFailRows = ..ErrorLogRows(tFailSession, .tFailText)
    Do $$$AssertTrue(tFailRows >= 1, "the swallowed failure DOES log a Type 2 (Error) row, found " _ tFailRows)
    Do $$$AssertTrue(tFailText [ "BO.Failing", "naming the Business Operation: " _ tFailText)
    Do $$$AssertTrue(tFailText [ "asked to fail", "and carrying the BO's own reason: " _ tFailText)
    Quit $$$OK
}

/// THE CONTRAST. The propagating shape of §5.21 IS caught by the first weak assertion, so the gap
/// belongs to the BPL's fault handling and not to BPL, SendRequest or TestProduction.
Method TestThePropagatingBplIsCaughtByStatusAlone() As %Status
{
    Set tSC = ..Drive("BP.ScopedOrder", "FAIL this order", .tResp, .tSession)
    Do $$$AssertNotTrue($$$ISOK(tSC), "SendRequest reports an ERROR for the propagating BPL, so $$$AssertStatusOK alone would catch it")
    // POSITIVE CONTROL: the same target succeeds on a good payload, so the error above is about the
    // failure and not about this BP being unreachable.
    Do ##class(Example.BO.FailOnDemand).Reset()
    Set tOk = ..Drive("BP.ScopedOrder", "HAPPY path", .tResp2, .tSession2)
    Do $$$AssertStatusOK(tOk, "POSITIVE CONTROL: the same BP returns $$$OK on a payload that succeeds")
    Quit $$$OK
}

}
