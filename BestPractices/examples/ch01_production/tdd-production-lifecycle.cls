/// Rule: BestPractices_Interop_IRIS.md §1.18 "`RecoverProduction()` returns `$$$OK` having done nothing — verify the STATE, not the status"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN against live productions.
/// Severity: High (the defect it isolates reports a recovered production that is still down).
///
/// Pattern: the oracle for `production-lifecycle-helper.cls`. It starts and stops real productions,
/// which makes it the most stateful test in this bank — see the cleanup note below.
///
/// THE ASSERTION THAT MATTERS. `RecoverProduction()` returns `$$$OK` from a STOPPED production and
/// leaves it stopped. Measured:
///
///     STOPPED -> RecoverProduction() -> $$$OK, state still 2 (Stopped)
///     RUNNING -> RecoverProduction() -> $$$OK, state still 1 (Running)
///
/// So a helper reporting from the status alone emits `{"state":"2","success":true}` about a
/// production that is not running. `TestRecoverFromStoppedIsReportedAsFailure` is what stops that
/// shape coming back, and `TestRawRecoverReturnsOkFromStopped` pins the platform behaviour it rests
/// on — so if a future IRIS makes `RecoverProduction` refuse, this says so rather than leaving the
/// helper's caution as folklore.
///
/// CLEANUP IS NOT OPTIONAL HERE, and this bank has the scar. A production left SUSPENDED (state 3)
/// blocks every subsequent `StartProduction` in the namespace, and `RecoverProduction` does not clear
/// it -- only `CleanProduction` does. Earlier work in this repo left one suspended and every later
/// start failed until it was cleaned. `OnAfterAllTests` therefore force-stops whatever is running,
/// and is the reason that callback's spelling matters (§5.18: a misspelled one is never invoked).
///
/// STATE CODES, from the `$$$eProductionState*` macros: 1 Running, 2 Stopped, 3 Suspended,
/// 4 Troubled.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                      PASSED 8/8
///     recovery reports from the STATUS not the state   TestRecoverFromStoppedIsReportedAsFailure FAILS
///     the already-Running branch removed               TestStartingTwiceIsNotAnError             FAILS
///     the different-production branch removed          TestStartingADifferentOneIsBlocked        FAILS
///     the empty-name guard removed                     TestEmptyNameIsRefused                    FAILS
///
/// Each reddens exactly its own test. All five versions compile, and the namespace was left at
/// state 2 (Stopped) with no production named after every run.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.ProductionLifecycle", namespace="<NS>")
Class Example.Tests.ProductionLifecycle Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

Parameter OTHERPROD = "Example.Productions.Hl7Intake";

/// This suite drives the lifecycle itself, so the superclass must not also.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// Leave the namespace stopped, whatever happened. A production left running or -- far worse --
/// Suspended breaks every later test and every later start in this namespace.
Method OnAfterAllTests() As %Status
{
    Do ##class(Ens.Director).StopProduction(10, 1)
    Quit $$$OK
}

ClassMethod State() As %Integer [ Private ]
{
    Set tName = ""
    Set tState = ""
    Do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
    Quit +$Get(tState)
}

ClassMethod ForceStop() As %Status [ Private ]
{
    Do ##class(Ens.Director).StopProduction(10, 1)
    Quit $$$OK
}

/// The state-code mapping, asserted -- every verdict in the helper depends on it.
Method TestStateNamesAreCorrect()
{
    Do $$$AssertEquals(##class(Example.UTL.ProductionLifecycle).StateName(1), "Running", "1 is Running")
    Do $$$AssertEquals(##class(Example.UTL.ProductionLifecycle).StateName(2), "Stopped", "2 is Stopped")
    Do $$$AssertEquals(##class(Example.UTL.ProductionLifecycle).StateName(3), "Suspended", "3 is Suspended -- the one that blocks every start")
    Do $$$AssertEquals(##class(Example.UTL.ProductionLifecycle).StateName(4), "Troubled", "4 is Troubled")
    Do $$$AssertEquals($Find(##class(Example.UTL.ProductionLifecycle).StateName(9), "Unknown") > 0, 1, "an unexpected code is named as unknown, not silently mapped")
}

/// THE PLATFORM BEHAVIOUR the helper is built on. Pinned so the caution is justified, not assumed.
Method TestRawRecoverReturnsOkFromStopped()
{
    Do ..ForceStop()
    Do $$$AssertEquals(..State(), 2, "control: the production is Stopped")

    Set tSC = ##class(Ens.Director).RecoverProduction()

    Do $$$AssertStatusOK(tSC, "RecoverProduction returns $$$OK even from Stopped -- that is the trap")
    Do $$$AssertEquals(..State(), 2, "and it leaves the production Stopped -- it did nothing")
    Do $$$AssertEquals(##class(Ens.Director).IsProductionRunning(), 0, "nothing is running")
}

/// THE POINT. The helper must call that a failure, because the production is not running.
Method TestRecoverFromStoppedIsReportedAsFailure()
{
    Do ..ForceStop()
    Set tVerdict = ##class(Example.UTL.ProductionLifecycle).RecoverAndVerify()

    Do $$$AssertEquals($Find(tVerdict, "NOT RECOVERED") > 0, 1, "recovering a stopped production is NOT a success: " _ tVerdict)
    Do $$$AssertEquals($Find(tVerdict, "Stopped") > 0, 1, "and the verdict must name the state it actually found")
    Do $$$AssertEquals($Find(tVerdict, "OK:") > 0, 0, "and must not contain an OK verdict")
}

/// And the positive control: from Running, recovery IS reported as success -- otherwise the test
/// above could pass against a helper that calls everything a failure.
Method TestRecoverFromRunningIsReportedAsSuccess()
{
    Do ..ForceStop()
    Do $$$AssertEquals($Find(##class(Example.UTL.ProductionLifecycle).StartAndWait(..#PRODUCTION, 15), "OK:") > 0, 1, "control: the production starts")

    Set tVerdict = ##class(Example.UTL.ProductionLifecycle).RecoverAndVerify()
    Do $$$AssertEquals($Find(tVerdict, "OK:") > 0, 1, "recovering a RUNNING production reports success: " _ tVerdict)
    Do $$$AssertEquals($Find(tVerdict, "NOT RECOVERED") > 0, 0, "and not a failure")

    Do ..ForceStop()
}

/// Starting what is already running is not an error, and must be distinguishable from having started it.
Method TestStartingTwiceIsNotAnError()
{
    Do ..ForceStop()
    Set tFirst = ##class(Example.UTL.ProductionLifecycle).StartAndWait(..#PRODUCTION, 15)
    Do $$$AssertEquals($Find(tFirst, "OK:") > 0, 1, "first start: " _ tFirst)
    Do $$$AssertEquals($Find(tFirst, "is Running (confirmed") > 0, 1, "and it says it CONFIRMED the state")

    Set tSecond = ##class(Example.UTL.ProductionLifecycle).StartAndWait(..#PRODUCTION, 15)
    Do $$$AssertEquals($Find(tSecond, "was already Running") > 0, 1, "the second start says so rather than pretending to have started it: " _ tSecond)

    Do ..ForceStop()
}

/// Starting a DIFFERENT production while one runs must be refused by name, not reported as a generic
/// failure -- the reader needs to know which one is in the way.
Method TestStartingADifferentOneIsBlocked()
{
    Do ..ForceStop()
    Do $$$AssertEquals($Find(##class(Example.UTL.ProductionLifecycle).StartAndWait(..#PRODUCTION, 15), "OK:") > 0, 1, "control: the first one starts")

    Set tVerdict = ##class(Example.UTL.ProductionLifecycle).StartAndWait(..#OTHERPROD, 15)
    Do $$$AssertEquals($Find(tVerdict, "BLOCKED") > 0, 1, "a different production must be blocked: " _ tVerdict)
    Do $$$AssertEquals($Find(tVerdict, ..#PRODUCTION) > 0, 1, "and the verdict must name the one in the way")

    Do ..ForceStop()
}

/// An empty name must be refused rather than defaulting to whatever ran last. Called from
/// ObjectScript because a SQL literal '' arrives as a space, which trips the next guard instead.
Method TestEmptyNameIsRefused()
{
    Do ..ForceStop()
    Set tVerdict = ##class(Example.UTL.ProductionLifecycle).StartAndWait("", 5)

    Do $$$AssertEquals($Find(tVerdict, "REFUSED") > 0, 1, "an empty name must be refused: " _ tVerdict)
    Do $$$AssertEquals($Find(tVerdict, "LAST one started") > 0, 1, "and the verdict must say why -- StartProduction defaults to it")
    Do $$$AssertEquals(..State(), 2, "and nothing may have been started")
}

}
