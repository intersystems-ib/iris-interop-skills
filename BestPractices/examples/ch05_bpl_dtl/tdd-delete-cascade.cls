/// Rule: BestPractices_Interop_IRIS.md §5.11 "A `%Persistent` child needs a delete cascade, and the obvious cascade discards its own error"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (the defect it guards leaves no trace at all).
///
/// Pattern: the test for the cascade pair in this directory. It is one of the few tests in this
/// bank whose assertion cannot be satisfied by a component that does nothing.
///
/// WHY A COMPILE PROVES NOTHING HERE. Every wrong version of this cascade compiles: the trigger
/// pointed at a `%SerialObject` compiles, the trigger using `{ID}` instead of the reference
/// property compiles, and the trigger that discards its `%Status` compiles. All three then leave
/// the child row exactly where it was. The only thing that separates a working cascade from a
/// decorative one is reading the child table back AFTER deleting the parent.
///
/// THE THREE CASES, and each exists because dropping it would let a broken cascade pass:
///
///   TestCascadeDeletesChild   the point. Child exists, delete the parent, child is GONE.
///                             Without the "child exists first" assertion this passes against a
///                             child that was never saved -- absence proves nothing unless
///                             presence was established first.
///   TestChildlessCarrierDeletes  the empty-reference guard. A carrier that never had a child
///                             must still delete. Without the `If {Address} '= ""` guard in the
///                             trigger, %DeleteId("") errors, %ok is set to 0, and the row becomes
///                             UNDELETABLE -- the trigger added to help a purge is what stops it.
///   TestOrphanIsObservable    the negative control. It deletes a child directly and asserts the
///                             table can be seen to shrink, so that a green in case 1 cannot be
///                             produced by %ExistsId always answering 0.
///
/// MEASURED BEHAVIOUR this test pins, run on 2026.1 before it was written:
///     childBefore=1  delParent=OK  childAfter=0  |  childlessDelete=OK
///
/// MUTATION-CHECKED against every defect §5.11 names. Each was applied to the carrier, the pair
/// recompiled, and the child table read back on 2026.1:
///
///   as shipped                    childAfter=0  childlessDelete=OK    both tests PASS
///   {Address} -> {ID}             childAfter=1                        TestCascadeDeletesChild FAILS
///   Trigger block removed         childAfter=1                        TestCascadeDeletesChild FAILS
///   empty guard removed           childlessDelete=BLOCKED             TestChildlessCarrierDeletes FAILS
///
/// All four versions COMPILE, so tier 2 is green on every one of them.
///
/// A NOTE ON THE MUTATION ITSELF, because it nearly produced a false conclusion. The first attempt
/// at "remove the trigger" only RENAMED it -- `Trigger DeleteCascade` -> `Trigger ZZUnused` -- and
/// a trigger fires on its `[ Event = DELETE ]` clause, not on its name. The child was still
/// deleted, and it read exactly like the test failing to detect a removed cascade. A mutation that
/// does not mutate looks identical to a test that does not test; excise the whole block and
/// re-check before believing either.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.DeleteCascade", namespace="<NS>")
Class Example.Tests.DeleteCascade Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test (see TestControl).
Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// Neutralises the production start/stop this superclass would otherwise drive.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// Save a child and a carrier that references it. Returns the two ids by reference.
ClassMethod MakePair(Output pParentId As %String, Output pChildId As %String) As %Status [ Private ]
{
    Set tAddr = ##class(Example.DAT.Address).%New()
    Set tAddr.Street = "Main St"
    Set tAddr.City = "Barcelona"
    Set tSC = tAddr.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set pChildId = tAddr.%Id()
    Set tMsg = ##class(Example.MSG.PersonReqCascade).%New()
    Set tMsg.Name = "Ana"
    Set tMsg.Address = tAddr
    Set tSC = tMsg.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set pParentId = tMsg.%Id()
    Quit $$$OK
}

/// The point of the whole pair: deleting the carrier must take the child row with it.
Method TestCascadeDeletesChild()
{
    Set tSC = ..MakePair(.tParentId, .tChildId)
    Do $$$AssertStatusOK(tSC)

    // Establish PRESENCE first. Asserting only "gone afterwards" passes against a child that was
    // never saved, which is the vacuous form of this test.
    Do $$$AssertEquals(##class(Example.DAT.Address).%ExistsId(tChildId), 1, "child must exist before the delete")

    Set tSC = ##class(Example.MSG.PersonReqCascade).%DeleteId(tParentId)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(##class(Example.DAT.Address).%ExistsId(tChildId), 0, "cascade must delete the child row")
}

/// The empty-reference guard. Without it the trigger makes childless carriers undeletable.
Method TestChildlessCarrierDeletes()
{
    Set tMsg = ##class(Example.MSG.PersonReqCascade).%New()
    Set tMsg.Name = "NoAddress"
    Set tSC = tMsg.%Save()
    Do $$$AssertStatusOK(tSC)

    Set tSC = ##class(Example.MSG.PersonReqCascade).%DeleteId(tMsg.%Id())
    Do $$$AssertStatusOK(tSC)
}

/// Negative control: prove the child table can be observed to change at all, so that a green in
/// TestCascadeDeletesChild cannot come from %ExistsId simply always answering 0.
Method TestOrphanIsObservable()
{
    Set tAddr = ##class(Example.DAT.Address).%New()
    Set tAddr.Street = "Control St"
    Do $$$AssertStatusOK(tAddr.%Save())
    Set tId = tAddr.%Id()

    Do $$$AssertEquals(##class(Example.DAT.Address).%ExistsId(tId), 1, "control: a saved child reads back as present")
    Do $$$AssertStatusOK(##class(Example.DAT.Address).%DeleteId(tId))
    Do $$$AssertEquals(##class(Example.DAT.Address).%ExistsId(tId), 0, "control: a deleted child reads back as absent")
}

}
