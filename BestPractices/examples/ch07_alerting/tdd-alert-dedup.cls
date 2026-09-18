/// Rule: BestPractices_Interop_IRIS.md §7.4 "Testing the alert circuit without an SMTP server"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN against a started production.
/// Severity: High (a suppressed alert stream is indistinguishable from a healthy production).
///
/// Pattern: the oracle for §7.2's dedup FunctionSet and for the circuit of §7.1, replacing the
/// six-step manual procedure that needed an SMTP server, a real mailbox and a human to look in it.
///
/// WHAT MAKES THIS WORTH AUTOMATING. The dedup guards are the only code in the alert circuit, they sit
/// in front of every alert the production will ever send, and their failure mode is SILENCE. An
/// inverted guard, or one whose key is wrong, suppresses everything — and a production that sends no
/// alerts looks exactly like a production with nothing to alert about. The manual procedure is run
/// once at go-live and never again, so nothing would catch a regression.
///
/// SO THE FIRST ASSERTION IS ALWAYS THAT AN ALERT DOES ARRIVE. `TestReturnedErrorReachesTheAlert`
/// asserts a positive before it asserts anything about suppression; a suite that only checked "the
/// second alert was suppressed" would pass against a circuit that suppresses all of them.
///
/// MEASURED VALUES this pins, from the probe run that preceded it:
///     AlreadyReportedErr("BO.X","boom")  first 0, second 1, "different" 0
///     AlreadyReportedErr("BO.OTHER","boom")            1  -- SourceConfigName is NOT part of the key
///     AlreadyReportedPerSession() with no %Ensemble    0  -- returns, does not throw
///     the §7.2 VERBATIM form, `Set s = %Ensemble("SessionId")`   <UNDEFINED>
///     PerSession in session 4242    first 0, second 1;  session 4343  0
///     PurgeDaysBefore: day-5 and day-1 planted, one call, BOTH gone, today present
///     production: an OK message      attempts 1, alerts recorded 0
///     production: a FAIL message     alerts recorded 1, AlertText
///                                    "ERROR #5001: FailOnDemand was asked to fail: FAIL please"
///
/// WHAT IS DELIBERATELY *NOT* ASSERTED END TO END, and why. The dedup arithmetic is asserted against
/// the FunctionSet directly, not by counting alerts out of the production. The key includes
/// `seconds\Interval`, so with the default 60 two sends that straddle a minute boundary land in
/// DIFFERENT buckets and are both forwarded — correctly. An end-to-end count would therefore fail
/// roughly twice an hour for a reason that is not a defect, and a test that fails for reasons that are
/// not defects gets muted. The FunctionSet tests are exact; the production tests assert that the
/// circuit fires and carries the right text.
///
/// RUN AND MUTATION-CHECKED, measured, six mutations:
///
///     as shipped                                          PASSED 7/7 (6 tests + the TestControl no-op)
///     1 AlreadyReportedErr always returns 0                TestDedupErrTextFirstSecondControl  FAIL
///     2 AlreadyReportedErr always returns 1                TestDedupErrTextFirstSecondControl
///                                                         + TestReturnedErrorReachesTheAlert   FAIL
///     3 PerSession uses a BARE %Ensemble reference          TestPerSessionOutsideAHostProcess   FAIL
///     4 the purge kills only day-1 (the §7.2 form)          TestPurgeRemovesEveryEarlierDay     FAIL
///     5 OnMessage returns $$$OK instead of $$$ERROR         TestReturnedErrorReachesTheAlert    FAIL
///     6 the dedup rule moved AFTER the send in the rule     NO FAILURE -- see below
///
/// MUTATION 2 IS THE INFORMATIVE ONE. Making the guard say "already reported" for everything reddens
/// the end-to-end test as well as the unit one, which is the proof that the assertion in
/// `TestReturnedErrorReachesTheAlert` really does depend on the alert getting past the guard. That is
/// the silent failure of this whole chapter — every alert suppressed, nothing to see — and it is
/// caught here.
///
/// MUTATION 6 SURVIVES, AND IT IS A KNOWN GAP RATHER THAN A SURPRISE. Moving the dedup rule after the
/// send means no alert is ever suppressed; with one failing message producing one alert there is
/// nothing to suppress, so nothing changes. Catching it needs two alerts with identical text inside
/// one `seconds\Interval` bucket — which is the end-to-end count the note above explains is
/// deliberately not asserted, because two sends straddling a minute boundary are both forwarded
/// correctly and the test would fail roughly twice an hour for no defect. The rule's ordering is
/// therefore covered by the comment in `rul-alert-dedup-fixture.cls` and by mutation 2 at the
/// FunctionSet level, not by an end-to-end count.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.AlertDedup", namespace="<NS>")
Class Example.Tests.AlertDedup Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.AlertDedupFixture";

/// A no-op override. The inherited TestControl() starts the production, hangs MINRUN seconds and
/// stops it again, leaving nothing running for the tests that follow — see OnBeforeAllTests.
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

/// Every test starts from empty state. `^FilterAlerts` in particular: a bucket left by the previous
/// test is indistinguishable from one this test created, and "already reported" would be true before
/// the test reported anything.
Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill ^FilterAlerts
    Do ##class(Example.BO.FailOnDemand).Reset()
    Do ##class(Example.BO.AlertRecorder).Reset()
    Quit $$$OK
}

/// Queue one message to BO.Failing and wait for the circuit to settle.
ClassMethod Send(pText As %String, pExpectAlerts As %Integer) As %Status [ Private ]
{
    Set tReq = ##class(Ens.StringContainer).%New(pText)
    Set tSC = tReq.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set tSC = ##class(Ens.MessageHeader).NewRequestMessage(.tHeader, tReq, .tSession)
    Quit:$$$ISERR(tSC) tSC
    Set tHeader.SourceConfigName = "TestDriver"
    Set tHeader.TargetConfigName = "BO.Failing"
    Set tHeader.TargetQueueName = "BO.Failing"
    Set tHeader.Status = 2
    Set tHeader.Invocation = 1
    Set tSC = tHeader.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set tSC = ##class(Ens.Queue).EnQueue(tHeader)
    Quit:$$$ISERR(tSC) tSC
    // Wait for the expected number of alerts, then a moment longer: waiting only for "at least one"
    // would let a test that expects ZERO pass instantly, before the circuit had a chance to fire.
    For i = 1:1:60 {
        If ##class(Example.BO.AlertRecorder).Count() >= pExpectAlerts { Quit }
        Hang 0.25
    }
    Hang 2
    Quit $$$OK
}

/// first 0 / second 1 / a different message 0 — the third is the positive control. Without it, a
/// function that returned 1 for everything after the first call would pass.
Method TestDedupErrTextFirstSecondControl() As %Status
{
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedErr("BO.X", "boom", 60), 0, "the first report of an error is not a duplicate")
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedErr("BO.X", "boom", 60), 1, "the second, in the same bucket, is")
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedErr("BO.X", "different", 60), 0, "POSITIVE CONTROL: a different message is not suppressed, so the key is really consulted")
    // The documented trade-off, asserted so it cannot drift silently: SourceConfigName is ACCEPTED so
    // the rule reads naturally, and is NOT part of the key, so a BP and a BO reporting the same text
    // dedupe against each other. That is the behaviour §7.2 wants; it is also surprising.
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedErr("BO.OTHER", "boom", 60), 1, "a DIFFERENT source with the same text IS suppressed: the source is not part of the key")
    Quit $$$OK
}

/// Outside a business-host process there is no %Ensemble. The bank's form returns 0; the §7.2
/// verbatim form raises <UNDEFINED>, which surfaces as a rule-evaluation error and loses the alert.
Method TestPerSessionOutsideAHostProcess() As %Status
{
    Kill %Ensemble
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedPerSession(), 0, "with no session context the honest answer is 'not reported yet'")
    // And the hazard it avoids, asserted rather than described.
    Set tThrew = 0
    Try {
        Set tIgnored = %Ensemble("SessionId")
    } Catch tEx {
        Set tThrew = tEx.Name
    }
    Do $$$AssertEquals(tThrew, "<UNDEFINED>", "a BARE %Ensemble(""SessionId"") reference -- the §7.2 verbatim form -- raises <UNDEFINED>")
    Quit $$$OK
}

/// Within one session: first 0, second 1. A new session starts clean — the positive control again.
Method TestPerSessionDedupesWithinASession() As %Status
{
    Set %Ensemble("SessionId") = 4242
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedPerSession(), 0, "first alert in a session")
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedPerSession(), 1, "second alert in the same session is a duplicate")
    Set %Ensemble("SessionId") = 4343
    Do $$$AssertEquals(##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedPerSession(), 0, "POSITIVE CONTROL: a different session is not suppressed")
    Kill %Ensemble
    Quit $$$OK
}

/// The fix §7.2's verbatim version does not have. `kill ^FilterAlerts(kind, day-1)` only ever reaches
/// YESTERDAY, so every day on which no alert was evaluated leaks its subtree for ever.
Method TestPurgeRemovesEveryEarlierDay() As %Status
{
    Set tToday = +$Horolog
    Set ^FilterAlerts("Err", tToday - 5, 0, "five days old") = ""
    Set ^FilterAlerts("Err", tToday - 1, 0, "yesterday") = ""
    Do $$$AssertNotEquals($Data(^FilterAlerts("Err", tToday - 5)), 0, "the stale day was planted")
    Do ##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedErr("BO.X", "now", 60)
    Do $$$AssertEquals($Data(^FilterAlerts("Err", tToday - 5)), 0, "a day FIVE days old is purged, not just yesterday")
    Do $$$AssertEquals($Data(^FilterAlerts("Err", tToday - 1)), 0, "and so is yesterday")
    Do $$$AssertNotEquals($Data(^FilterAlerts("Err", tToday)), 0, "while today's bucket is there -- purging everything would be a different bug")
    Quit $$$OK
}

/// A message that succeeds produces no alert. Asserted with the attempt count, so "no alert" cannot
/// be confused with "the operation was never reached".
Method TestSuccessProducesNoAlert() As %Status
{
    Do $$$AssertStatusOK(..Send("all good", 0), "queued a message that will succeed")
    Do $$$AssertTrue(##class(Example.BO.FailOnDemand).Attempts() >= 1, "the operation really ran: " _ ##class(Example.BO.FailOnDemand).Attempts() _ " attempt(s)")
    Do $$$AssertEquals(##class(Example.BO.AlertRecorder).Count(), 0, "and no alert reached the end of the circuit")
    Quit $$$OK
}

/// THE ONE THAT REPLACES THE MANUAL PROCEDURE. An OnMessage RETURNING $$$ERROR drives AlertOnError,
/// the alert travels through Ens.Alert and the dedup rule, and arrives carrying the returned reason.
Method TestReturnedErrorReachesTheAlert() As %Status
{
    Do $$$AssertStatusOK(..Send("FAIL please", 1), "queued a message that will fail")
    Do $$$AssertTrue(##class(Example.BO.AlertRecorder).Count() >= 1, "an alert reached the end of the circuit: " _ ##class(Example.BO.AlertRecorder).Count())
    // The TEXT matters: it proves the alert carries the status OnMessage returned, rather than a
    // generic framework message, which is what makes an alert actionable.
    Do $$$AssertTrue(##class(Example.BO.AlertRecorder).Texts() [ "FailOnDemand was asked to fail", "and it carries the reason the operation returned: " _ ##class(Example.BO.AlertRecorder).Texts())
    Quit $$$OK
}

}
