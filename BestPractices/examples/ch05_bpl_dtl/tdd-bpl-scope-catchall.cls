/// Rule: BestPractices_Interop_IRIS.md §5.21 "BPL <scope>: the fault handler that completes the process green"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN against a started production.
/// Severity: High (the defect it guards reports success to the caller of a process that failed).
///
/// Pattern: the oracle for `bpl-scope-catchall-compensation.cls`.
///
/// THE CENTRAL ASSERTION IS THE BUSINESS PROCESS'S OWN HEADER STATUS, not the trace and not the call.
/// A caught-and-logged fault leaves the failed CALL visible at Status=8 while the PROCESS reports
/// Status=9 Completed — so any assertion that reads the downstream header, or the Event Log, passes
/// against the defect. The only value that separates the two is the BP's own row.
///
/// MEASURED VALUES this pins, both shapes, same fixture:
///
///     catchall logs and falls through      BP hdr Status=9 (Completed) IsError=0   <- the defect
///     catchall sets `status`               BP hdr Status=8 (Error)                 <- as shipped
///     a payload that succeeds              BP hdr Status=9, catchall never ran
///
/// and the enumeration those numbers come from, read from the dictionary rather than remembered:
/// 1=Created 2=Queued 3=Delivered 4=Discarded 5=Suspended 6=Deferred 7=Aborted 8=Error 9=Completed.
///
/// TestCompensationIsNotReachedHere ASSERTS A SCHEMA CONSTRAINT BEHAVIOURALLY. `<compensate>` is legal
/// only as a direct child of `<catchall>`, and a catchall takes exactly one activity — so a catchall
/// that uses a `<sequence>` to do two things *cannot* also compensate. The shipped BPL declares a
/// `<compensationhandler>` and never reaches it, which is the honest state of that shape; the test
/// pins it so nobody reads the declaration as evidence that it fires.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                        PASSED 6/6 (5 tests + the TestControl no-op)
///     1 the `set status` line removed                     TestPropagatingCatchallEndsInError  FAIL
///     2 the catchall's Record step neutered               TestCatchallRanOnFailure +
///                                                        TestCompensationIsNotReachedHere    FAIL
///     3 the status enumeration asserted as 9=Error        TestStatusEnumerationIsWhatItSeems  FAIL
///
/// MUTATION 1 IS THE ONE THAT MATTERS AND IT REDDENS EXACTLY ONE TEST. Removing `set status` leaves
/// every other assertion green -- the catchall still fires, still records the fault, the compensation
/// handler is still unreached, the enumeration is still right -- and the process silently reports
/// success. That is the defect in one line, and only the header-status assertion sees it.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.BplScopeCatchall", namespace="<NS>")
Class Example.Tests.BplScopeCatchall Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.BplScope";

/// A no-op override: the inherited TestControl() starts the production, hangs MINRUN seconds and
/// stops it, leaving nothing running for the tests after it. See OnBeforeAllTests.
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
    Kill ^Example.ScopedOrder
    Quit $$$OK
}

/// Drive one message into the BP and return its own header id.
ClassMethod Drive(pText As %String, Output pHeaderId As %String) As %Status [ Private ]
{
    Set pHeaderId = ""
    Set tReq = ##class(Ens.StringContainer).%New(pText)
    Set tSC = tReq.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set tSC = ##class(Ens.MessageHeader).NewRequestMessage(.tHdr, tReq, .tSession)
    Quit:$$$ISERR(tSC) tSC
    Set tHdr.SourceConfigName = "TestDriver"
    Set tHdr.TargetConfigName = "BP.ScopedOrder"
    Set tHdr.TargetQueueName = "BP.ScopedOrder"
    Set tHdr.Status = 2
    Set tHdr.Invocation = 1
    Set tSC = tHdr.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set pHeaderId = tHdr.%Id()
    Set tSC = ##class(Ens.Queue).EnQueue(tHdr)
    Quit:$$$ISERR(tSC) tSC
    // Wait for the BP's own header to leave Queued/Delivered rather than sleeping a fixed amount.
    For i = 1:1:80 {
        Set tNow = ..HeaderStatus(pHeaderId)
        If (tNow '= 2), (tNow '= 3) { Quit }
        Hang 0.25
    }
    Hang 2
    Quit $$$OK
}

ClassMethod HeaderStatus(pHeaderId As %String) As %Integer [ Private ]
{
    Set tHdr = ##class(Ens.MessageHeader).%OpenId(pHeaderId)
    Quit $Select($IsObject(tHdr):tHdr.Status, 1:-1)
}

/// THE ONE THAT MATTERS. With `set status` in the catchall the process ends in ERROR, so the caller
/// is told the truth. Without it this same fixture ends at 9 (Completed) -- see the header.
Method TestPropagatingCatchallEndsInError() As %Status
{
    Do $$$AssertStatusOK(..Drive("FAIL this order", .tId), "drove a failing order")
    Do $$$AssertNotEquals(tId, "", "the BP header exists")
    Do $$$AssertEquals(..HeaderStatus(tId), 8, "the BUSINESS PROCESS's own header is Error (8), not Completed (9)")
    Quit $$$OK
}

/// And the catchall really ran -- so test 1 is passing because the fault was handled and propagated,
/// not because the process never got that far.
Method TestCatchallRanOnFailure() As %Status
{
    Do $$$AssertStatusOK(..Drive("FAIL this order", .tId), "drove a failing order")
    Do $$$AssertEquals(+$Get(^Example.ScopedOrder("caught")), 1, "the catchall fired exactly once")
    Do $$$AssertTrue($Get(^Example.ScopedOrder("caught", 1)) [ "asked to fail", "and recorded the fault the BO returned: " _ $Get(^Example.ScopedOrder("caught", 1)))
    Quit $$$OK
}

/// The negative control: a payload that succeeds must complete green AND not touch the handler. Without
/// this, a catchall wired to fire on everything would satisfy the two tests above.
Method TestSuccessCompletesGreenAndSkipsTheHandler() As %Status
{
    Do $$$AssertStatusOK(..Drive("all good", .tId), "drove an order that succeeds")
    Do $$$AssertEquals(..HeaderStatus(tId), 9, "a successful order completes (9)")
    Do $$$AssertEquals(+$Get(^Example.ScopedOrder("caught")), 0, "and the catchall did not run")
    Quit $$$OK
}

/// The schema constraint, asserted by behaviour: the declared compensation handler is NOT reached,
/// because <compensate> cannot live inside the <sequence> this catchall uses.
Method TestCompensationIsNotReachedHere() As %Status
{
    Do $$$AssertStatusOK(..Drive("FAIL this order", .tId), "drove a failing order")
    Do $$$AssertEquals(+$Get(^Example.ScopedOrder("caught")), 1, "the catchall ran")
    Do $$$AssertEquals(+$Get(^Example.ScopedOrder("compensated")), 0, "and the compensation handler did NOT -- a <compensate> must be the catchall's only activity, so a sequence-based catchall cannot reach one")
    Quit $$$OK
}

/// The two status numbers this suite rests on, from the dictionary. Asserted so that "8" and "9" are
/// not folklore, and so that a platform change to the enumeration fails here rather than silently
/// inverting every assertion above.
Method TestStatusEnumerationIsWhatItSeems() As %Status
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ""_Default"" AS d FROM %Dictionary.CompiledParameter WHERE parent = ? AND Name = 'DISPLAYLIST'", "Ens.DataType.MessageStatus")
    Do $$$AssertTrue(tRs.%Next(), "Ens.DataType.MessageStatus has a DISPLAYLIST")
    Set tList = tRs.%Get("d")
    // ",Created,Queued,Delivered,Discarded,Suspended,Deferred,Aborted,Error,Completed" -- piece N+1 is status N.
    Do $$$AssertEquals($Piece(tList, ",", 9), "Error", "status 8 is Error: " _ tList)
    Do $$$AssertEquals($Piece(tList, ",", 10), "Completed", "status 9 is Completed: " _ tList)
    Quit $$$OK
}

}
