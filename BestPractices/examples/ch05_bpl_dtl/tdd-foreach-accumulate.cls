/// Rule: BestPractices_Interop_IRIS.md §5.26 "Gathering N responses into ONE target: `<foreach>` + a collection context property + `create='existing'`"
/// Validity: Verified against IRIS for Health 2026.1 (Build 235U) — the assertions below were EXECUTED.
/// Severity: Medium (with `create='new'` the process delivers only the LAST answer and nothing errors).
///
/// Pattern: the test for §5.26. It exercises `Example.DT.AppendCycle` DIRECTLY rather than through a
/// running production, because the claim under test is about the DTL's `create=` attribute and a
/// direct call is the only way to assert it without standing a production up.
///
/// WHY THESE ASSERTIONS AND NOT A GREEN COMPILE. `create='new'` versus `create='existing'` is a
/// one-word difference that COMPILES EITHER WAY, so tier 2 is green on the broken version. The only
/// observable difference is across two calls: with `existing` the second call adds to the first
/// one's target, with `new` it replaces it. Every assertion below is on state after the SECOND call
/// for that reason.
///
/// A `create='new'` mutant is killed by TestAppendedBothTurns, TestTotalAccumulated and
/// TestSameOrefCameBack — three of the four. TestFirstTurnAlreadyWorks is the control that
/// distinguishes "accumulation broke" from "the DTL never ran at all".
/// A MACRO CALL CANNOT SPAN LINES. `Do $$$AssertStatusOK(...,` with the message on the next line
/// gives `MPP5612 : Referenced macro missing right paren`, then a cascade of `#1026 Invalid command`
/// and finally `#5123 Unable to find entry point` for the method — eight errors from one wrap, none
/// of which names line continuation. Keep each assertion on one line however long it gets.
Class Example.Tests.ForeachAccumulate Extends %UnitTest.TestProduction
{

/// Named so the suite is runnable, but no production is started: see TestControl.
Parameter PRODUCTION = "Example.Productions.BplAssertions";

/// The inherited body starts PRODUCTION, waits MINRUN seconds and then STOPS it -- and test methods
/// run in name order, so everything after it would run against a production that had just shut down.
/// Every suite in this bank overrides it; this one needs no production at all.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// One facility's answer. Distinct Cycles values so a sum cannot be confused with a replace.
ClassMethod Answer(pCode As %String, pCycles As %Integer) As Example.MSG.FacilityCycleRsp [ Private ]
{
    Set tRsp = ##class(Example.MSG.FacilityCycleRsp).%New()
    Set tRsp.FacilityCode = pCode
    Set tRsp.Cycles = pCycles
    Quit tRsp
}

/// Runs the DTL twice against ONE target, the way the `<foreach>` does, and hands back the target
/// plus the OREF it started as.
ClassMethod RunTwice(Output pStartOref As %String) As Example.MSG.CycleBatchReq [ Private ]
{
    Set tBatch = ##class(Example.MSG.CycleBatchReq).%New()
    Set pStartOref = tBatch
    Set tSC = ##class(Example.DT.AppendCycle).Transform(..Answer("HCLP", 3), .tBatch)
    If $$$ISERR(tSC) Quit tBatch
    Set tSC = ##class(Example.DT.AppendCycle).Transform(..Answer("HGUV", 4), .tBatch)
    Quit tBatch
}

/// The control. If this fails the DTL is not running at all, and the three accumulation
/// assertions below would be failing for a reason that has nothing to do with `create=`.
Method TestFirstTurnAlreadyWorks()
{
    Set tBatch = ##class(Example.MSG.CycleBatchReq).%New()
    Do $$$AssertStatusOK(##class(Example.DT.AppendCycle).Transform(..Answer("HCLP", 3), .tBatch), "the DTL runs and returns OK on a single call")
    Do $$$AssertEquals(tBatch.Codes.Count(), 1, "one call appended one element")
    Do $$$AssertEquals(tBatch.TotalCycles, 3, "one call wrote its own Cycles")
}

/// Killed by create='new': the second call would hand back a target holding ONE element.
Method TestAppendedBothTurns()
{
    Set tBatch = ..RunTwice(.tStart)
    Do $$$AssertEquals(tBatch.Codes.Count(), 2, "two turns appended two elements")
    Do $$$AssertEquals(tBatch.Codes.GetAt(1), "HCLP", "the FIRST turn's element survived the second")
    Do $$$AssertEquals(tBatch.Codes.GetAt(2), "HGUV", "and the second turn's is after it, in order")
}

/// Killed by create='new': TotalCycles would read 4, the last answer, not 7.
Method TestTotalAccumulated()
{
    Set tBatch = ..RunTwice(.tStart)
    Do $$$AssertEquals(tBatch.TotalCycles, 7, "3 + 4: the DTL read the target it was handed")
}

/// The mechanism itself. `create='existing'` means the DTL fills the object it was GIVEN, which is
/// why the BPL's `Set context.Batch = iscTemp` round trip preserves the accumulation -- and why the
/// context property needs instantiate='1'.
Method TestSameOrefCameBack()
{
    Set tBatch = ..RunTwice(.tStart)
    Do $$$AssertEquals(tBatch, tStart, "create='existing' mutated the target in place, it did not make a new one")
}

/// The `aux` finding, asserted where it can be: the BPL element MODELS an auxiliary value, so an
/// author has every reason to think `<transform aux='...'>` works. Nothing populates it --
/// `Ens.BPL.Parser:parseTransform` reads only class, source and target (§5.26). This pins the
/// half that is checkable, so the day the platform starts parsing `aux` this test fails and the
/// guidance gets revisited instead of quietly rotting.
Method TestBplTransformStillModelsAnUnparsedAux()
{
    Do $$$AssertTrue(##class(%Dictionary.CompiledProperty).%ExistsId("Ens.BPL.Transform||Aux"), "Ens.BPL.Transform still carries an Aux property the parser never fills")
}

}
