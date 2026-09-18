/// Rule: BestPractices_Interop_IRIS.md §5.9 "TDD for interop — %UnitTest.TestProduction, and what a green actually proves"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (a vacuous green is worse than a red).
///
/// Pattern: the canonical unit test for a DTL. It exercises Example.DT.OrderToVendor, which
/// ships in this same directory, so the test and its subject are gated together.
///
/// WHY %UnitTest.TestProduction AND NOT %UnitTest.TestCase. TestProduction is the Interop
/// superclass: it brings the production lifecycle helpers (..SendRequest, ..GetEventLog) that
/// a routing-rule or BO test needs, and Run() works by class name without /noload gymnastics.
/// A DTL test does not strictly need the production, but extending TestProduction anyway keeps
/// one baseline across the suite and costs nothing.
///
/// PARAMETER PRODUCTION IS COMPILE-TIME MANDATORY. Omit it, or set it to "", and the class does
/// not compile. When the production is managed outside the test, declare it and neutralise the
/// lifecycle with a TestControl that just returns OK — that is the line below, and it is the
/// single most-copied line of this file.
///
/// THE ASSERTIONS ARE THE POINT, AND THEY MUST BE ABLE TO FAIL.
///   - $$$AssertStatusOK on the Transform status catches the transform erroring out.
///   - $$$AssertEquals on a field the transform WRITES catches it doing nothing. A test that
///     only asserts the status passes against a transform that produced an empty target, which
///     is the most common vacuous green in this codebase's history.
///   - The negative case (TestPriorityLowWhenEmpty) exists so the <if> branch is covered in
///     both directions. One branch tested is half a test.
///
/// HOW TO RUN IT, literally — the tool takes ONE COMPILED CLASS per call and does not expand a
/// package:
///     iris_test(pattern="Example.Tests.OrderToVendor", namespace="<NS>")
/// "Example.Tests" comes back NO_TESTS_FOUND with a did_you_mean list. A suite of N test
/// classes is N calls, all made after the last recompile; what is forbidden is mixing a green
/// from before a recompile with one from after.
///
/// ^UnitTestRoot must point at a directory that EXISTS ON THE IRIS SERVER, or the run reports
/// zero tests and still exits clean — see unit-tests §"Storage".
///
/// THIS TEST WAS MUTATION-CHECKED, not merely run. Replacing the DTL's
///   <assign value='source.OrderId' property='target.VendorRef'/>
/// with a constant produces, on 2026.1:
///   AssertStatusOK:tSC                          (passed)   <-- note
///   AssertTrue:transform must produce a target  (passed)   <-- note
///   AssertEquals:OrderId -> VendorRef           (FAILED)
/// The two assertions that a lazy test would have stopped at BOTH still pass against the
/// broken transform. Only the assertion on a written field catches it. That is the whole
/// argument for the rule above, and it is why the mutation is worth running once per component:
/// a test you have never seen fail has not been shown to test anything.
Class Example.Tests.OrderToVendor Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test (see TestControl).
Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// Neutralises the production start/stop this superclass would otherwise drive.
/// Delete this method when you DO want the framework to bring the production up.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// Verifies that OrderId is carried into VendorRef, and that Note is composed from both
/// source fields. Asserting on a field the transform WRITES is what stops this passing
/// against a transform that produced an empty target.
Method TestOrderIdIsCarried()
{
    Set tSrc = ##class(Example.MSG.AcceptOrderReq).%New()
    Set tSrc.OrderId = "ORD-1001"
    Set tSrc.PatientId = "P-42"

    Set tSC = ##class(Example.DT.OrderToVendor).Transform(tSrc, .tTgt)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertTrue($IsObject(tTgt), "transform must produce a target object")
    Do $$$AssertEquals(tTgt.VendorRef, "ORD-1001", "OrderId -> VendorRef")
    Do $$$AssertEquals(tTgt.Priority, "NORMAL", "both fields present -> NORMAL")
    Do $$$AssertEquals(tTgt.Note, "ref=ORD-1001 pid=P-42", "Note composed from both fields")
}

/// The other side of the <if>. Without this the LOW branch is never executed and the
/// conditional is effectively untested.
Method TestPriorityLowWhenEmpty()
{
    Set tSrc = ##class(Example.MSG.AcceptOrderReq).%New()
    Set tSrc.OrderId = ""
    Set tSrc.PatientId = ""

    Set tSC = ##class(Example.DT.OrderToVendor).Transform(tSrc, .tTgt)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tTgt.Priority, "LOW", "both fields empty -> LOW")
}

}
