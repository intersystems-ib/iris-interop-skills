/// Rule: BestPractices_Interop_IRIS.md §5.2 "BS that runs on a schedule: use a custom adapter for wall-clock triggers"
/// Validity: Verified against IRIS for Health 2026.1. See WHAT WAS ACTUALLY VERIFIED below:
///           the behaviour asserted here was executed and mutation-checked; this %UnitTest
///           class itself was compiled, not run through the framework.
/// Severity: High (it is the only thing that can distinguish a firing adapter from a silent one).
///
/// Pattern: the test for a custom inbound adapter. It asserts the one fact a compile cannot:
/// that OnTask() actually DISPATCHES.
///
/// THE TRICK THAT MAKES THIS TESTABLE AT ALL, and it is worth knowing before you try the obvious
/// thing. Measured on 2026.1:
///   ##class(<Ens.BusinessService subclass>).%New()  ->  returns "", NOT an object, silently
///   ##class(Ens.InboundAdapter).%New()              ->  a real oref
///   Ens.Director.CreateBusinessService("X", .svc)   ->  needs X to be a registered, running item
/// So the service cannot be constructed and the adapter can. `BusinessHost` is declared
/// `As Ens.BusinessService`, but ObjectScript does not enforce an object property's declared type at
/// runtime — measured: a plain %RegisteredObject carrying a `ProcessInput` method is ACCEPTED. That
/// is what lets this test run with no production, no namespace setup and no fixtures.
///
/// THIS TEST CLASS IS ITS OWN STAND-IN HOST. It declares ProcessInput and counts the calls, then
/// assigns `$this` to the adapter's BusinessHost. One class, no separate double to keep in step —
/// and the bank's one-class-per-file rule makes a separate double a whole extra artefact for three
/// lines of behaviour.
///
/// WHAT EACH CASE EXISTS TO CATCH:
///   TestDispatchesOnMatch      the point. A matching schedule must produce exactly one dispatch.
///                              An OnTask that returns $$$OK without calling ProcessInput passes
///                              every other check in this repo and fails only here.
///   TestSilentOnNoMatch        the other direction: a non-matching schedule must dispatch ZERO
///                              times and still return $$$OK. Without this, an adapter that fires
///                              on every poll regardless of schedule would pass case 1.
///   TestStatusIsNotTheSignal   the negative control, and the whole argument in one method: it
///                              asserts that $$$OK comes back in BOTH cases. A caller checking only
///                              the %Status cannot tell a firing adapter from a silent one, which
///                              is precisely why the dispatch COUNT is what gets asserted.
///
/// WHAT WAS ACTUALLY VERIFIED, stated precisely because "tested" and "run" are not the same claim
/// and the difference is this bank's recurring failure mode.
///
/// EXECUTED: the shipped Demo.ADP.SchedulerAdapter was constructed, given a stand-in host, and
/// OnTask() called -- then again with the adapter deliberately broken two ways. The dispatch count
/// is what separates them, and note the %Status column:
///
///   as shipped                    match sc=OK dispatched=1 | nomatch sc=OK dispatched=0   PASS
///   dispatch line -> Quit $$$OK   match sc=OK dispatched=0 | nomatch sc=OK dispatched=0   FAIL
///   schedule check removed        match sc=OK dispatched=1 | nomatch sc=OK dispatched=1   FAIL
///
/// sc=OK in EVERY row, including both broken ones. That is TestStatusIsNotTheSignal's whole
/// argument, measured rather than asserted.
///
/// NOT EXECUTED: this class was not run through %UnitTest.Manager. Two things got in the way, both
/// worth knowing before you try:
///   - ##class(<test class>).%New() fails with <UNDEFINED> inside %UnitTest.TestProduction's
///     %OnNew, which takes an initvalue (the manager) -- a test case cannot be hand-constructed.
///   - %UnitTest.Manager.DebugRunTestCase() ran without error but wrote no rows to
///     %UnitTest_Result.TestMethod, so there was no verdict to read back. A zero there is
///     indistinguishable from a pass, so it is reported as inconclusive, not as green.
/// The supported route is iris_test(pattern="Demo.Tests.InboundAdapterDispatch", namespace="<NS>")
/// with ^UnitTestRoot pointing at a directory that exists ON THE SERVER. Run it at release time.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Demo.Tests.InboundAdapterDispatch", namespace="<NS>")
Class Demo.Tests.InboundAdapterDispatch Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test (see TestControl).
Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// Counts dispatches into this class acting as the adapter's host.
Property Dispatched As %Integer [ InitialExpression = 0 ];

/// Neutralises the production start/stop this superclass would otherwise drive.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// The stand-in host. This is the method the adapter calls; counting it is the assertion.
Method ProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject, ByRef pHint As %String) As %Status
{
    Set ..Dispatched = ..Dispatched + 1
    Quit $$$OK
}

/// Build the adapter with this test instance as its host.
Method NewAdapter(pSchedule As %String) As Demo.ADP.SchedulerAdapter
{
    Set ..Dispatched = 0
    Set tAdapter = ##class(Demo.ADP.SchedulerAdapter).%New()
    Set tAdapter.BusinessHost = $this
    Set tAdapter.Schedule = pSchedule
    Quit tAdapter
}

/// A matching schedule must dispatch exactly once.
Method TestDispatchesOnMatch()
{
    Set tAdapter = ..NewAdapter("* * * * *")
    Do $$$AssertTrue($IsObject(tAdapter), "the adapter must construct -- unlike a Business Service")

    Set tSC = tAdapter.OnTask()
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(..Dispatched, 1, "a matching schedule must dispatch into the host exactly once")
}

/// A non-matching schedule must dispatch nothing, and must not error.
Method TestSilentOnNoMatch()
{
    // 1 January at 03:00 only. Matches on at most one minute of the year.
    Set tAdapter = ..NewAdapter("0 3 1 1 *")

    Set tSC = tAdapter.OnTask()
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(..Dispatched, 0, "a non-matching schedule must not dispatch")
}

/// The control: $$$OK is returned either way, so the status can never be the signal. This is why
/// the assertions above count dispatches instead of checking the %Status.
Method TestStatusIsNotTheSignal()
{
    Set tMatching = ..NewAdapter("* * * * *")
    Set tScMatch = tMatching.OnTask()
    Set tFiredMatch = ..Dispatched

    Set tQuiet = ..NewAdapter("0 3 1 1 *")
    Set tScQuiet = tQuiet.OnTask()
    Set tFiredQuiet = ..Dispatched

    Do $$$AssertStatusOK(tScMatch)
    Do $$$AssertStatusOK(tScQuiet)
    Do $$$AssertNotEquals(tFiredMatch, tFiredQuiet, "control: only the dispatch COUNT separates these two, not the status")
}

}
