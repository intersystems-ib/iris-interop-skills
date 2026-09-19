/// Rule: BestPractices_Interop_IRIS.md §12.6 "Resend and edit-and-resend: two APIs, and the shared body row that rewrites history"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN against a started production.
/// Severity: High (the defect it guards rewrites what a delivered message said, with no error anywhere).
///
/// Pattern: the oracle for `resend-edit-and-resend.cls`, running against
/// `Example.Productions.ResendFixture` because both resend APIs refuse to work without a live
/// production.
///
/// TestPlainResendSharesTheBodyRow IS THE ONE THAT DOCUMENTS THE DEFECT, and it asserts the defect
/// rather than the fix: two headers over ONE body row, and an edit to that row visible through the
/// ORIGINAL header. That is not a bug in IRIS and the test does not treat it as one — it is the
/// documented consequence of a header referencing its body by id. What makes it dangerous is that
/// nothing reports it, so the assertion exists to make the behaviour impossible to be surprised by.
///
/// WHY THE ASSERTIONS ARE ABOUT DELIVERY AND NOT STATUS. Every call here returns `$$$OK` for work
/// that has only been queued, so `$$$AssertStatusOK` alone would pass against a resend that delivered
/// nothing, delivered to the wrong target, or delivered the unedited body. The sink records what it
/// received, and the assertions read that.
///
/// MEASURED VALUES this pins, from the probe run that preceded it:
///     ResendMessage(125)                 OK, sink received the payload again, newest header STILL 125
///                                        -- it re-queues the ORIGINAL header, creating no new row
///     ResendDuplicatedMessage(123, ...)  OK, new header 124, original body 18, new body 18 -> SHARED
///     the same, with a saved clone        new body 15, SHARED=0, original still reads "ORIGINAL B"
///     the same, with an UNSAVED clone     new body 12, and the sink received "EDITED BUT UNSAVED"
///                                        -- so pNewBody is persisted for you
///     link between the pair               new.Description = "Resent 123", SessionId 123 on BOTH,
///                                        CorrespondingMessageId EMPTY on both,
///                                        Resent EMPTY on both after EITHER api
///     with no production running           <Ens>ErrProductionNotRunning / ProductionNotRunning
///
/// RUN AND MUTATION-CHECKED, measured, five mutations, every one of them reddening exactly the test
/// it breaks and nothing else:
///
///     as shipped                                        PASSED 7/7 (6 tests + the TestControl no-op)
///     1 the same-row guard removed                       TestEditingTheOriginalRowIsRefused  FAIL
///     2 CloneBody returns the body, not a clone          TestEditedResendLeavesTheOriginal
///                                                       + TestEditedResendReachesTheTarget  FAIL
///     3 ResendEdited drops pBody (a plain resend)        the same two                        FAIL
///     4 the null-body guard removed                      TestNullBodyIsRefused               FAIL
///     5 ResendUnchanged ignores pNewTarget                TestResendHonoursTheNewTarget      FAIL
///
/// AND A NOTE ON HOW MUTATION 2 NEARLY SHIPPED AS THE TRUTH. A first run of that harness was killed
/// by a timeout mid-mutation, so `Set pClone = tBody` stayed on disk and every later "baseline" was
/// the mutant. Three rounds of diagnosis went into explaining a `%ConstructClone` that was never
/// being called — five A/B probes all showed it cloning correctly — and a confidently worded
/// "measured" comment about `%Id()` being unreliable was written into the sibling artefact on the
/// strength of the mutant's behaviour before the file itself was read. A green baseline that turns
/// red is a reason to read the file under test BEFORE forming a hypothesis about the platform.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.ResendEditAndResend", namespace="<NS>")
Class Example.Tests.ResendEditAndResend Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.ResendFixture";

/// A no-op override. The inherited TestControl() starts the production, hangs MINRUN seconds and
/// stops it again, which would both slow the suite down and leave nothing running for the tests that
/// follow it. See OnBeforeAllTests below.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// THE PRODUCTION IS STARTED HERE, AND THAT IS NOT BOILERPLATE.
///
/// `%UnitTest.TestProduction` defines `TestControl()` — and it is a TEST METHOD, not a hook. Its
/// built-in body starts the production named by `PRODUCTION`, waits `MINRUN` seconds (default 10),
/// and then STOPS it. Test methods run in name order, so `TestControl` runs FIRST and every other
/// test in the suite then runs against a production that has just been shut down. The bank's other
/// `%UnitTest.TestProduction` suites override it to `Quit $$$OK` for exactly that reason; none of
/// them needs a live production, so nothing surfaced.
///
/// This suite does need one, and the first version of it did only the override — every resend then
/// failed with `<Ens>ErrProductionNotRunning: No production is running` while
/// `Ens.Director.IsProductionRunning()` answered 1 from outside the run, because the production had
/// been started and stopped before the failing tests began. So: `TestControl` stays a no-op, and the
/// lifecycle is taken over explicitly below where it can be asserted.
Method OnBeforeAllTests() As %Status
{
    Set tSC = ##class(Ens.Director).StartProduction(..#PRODUCTION)
    Quit:$$$ISERR(tSC) tSC
    // Wait for it to actually be up: StartProduction returns before every item is running, and a
    // resend into a half-started production fails for a reason that looks like the bug under test.
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
    Do ##class(Ens.Director).StopProduction(10, 1)
    Quit $$$OK
}

/// Every test starts from an empty sink, or it measures the previous one.
Method OnBeforeOneTest(testname As %String) As %Status
{
    Quit ##class(Example.BO.MessageSink).Reset()
}

/// One completed message on BO.Sink, built directly: a resend's situation is that the original
/// already exists, so there is nothing to gain from routing one in through a service first.
ClassMethod Seed(pText As %String, Output pHeaderId As %String) As %Status [ Private ]
{
    Set pHeaderId = ""
    Set tBody = ##class(Ens.StringContainer).%New(pText)
    Set tSC = tBody.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set tSC = ##class(Ens.MessageHeader).NewRequestMessage(.tHeader, tBody, .tSession)
    Quit:$$$ISERR(tSC) tSC
    Set tHeader.SourceConfigName = "BO.Sink"
    Set tHeader.TargetConfigName = "BO.Sink"
    Set tHeader.TargetQueueName = "BO.Sink"
    Set tHeader.Status = 9
    Set tSC = tHeader.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set pHeaderId = tHeader.%Id()
    Quit $$$OK
}

/// The body text a header currently points at.
ClassMethod BodyText(pHeaderId As %String) As %String [ Private ]
{
    Set tHeader = ##class(Ens.MessageHeader).%OpenId(pHeaderId)
    Quit:'$IsObject(tHeader) "<no header>"
    Set tBody = $classmethod(tHeader.MessageBodyClassName, "%OpenId", tHeader.MessageBodyId)
    Quit $Select($IsObject(tBody):tBody.StringValue, 1:"<no body>")
}

ClassMethod BodyId(pHeaderId As %String) As %String [ Private ]
{
    Set tHeader = ##class(Ens.MessageHeader).%OpenId(pHeaderId)
    Quit $Select($IsObject(tHeader):tHeader.MessageBodyId, 1:"")
}

/// Wait for the queue to drain. A resend returns OK the moment the header is queued, so an assertion
/// made immediately measures the queue, not the delivery.
ClassMethod WaitFor(pCount As %Integer, pSeconds As %Integer = 10) As %Integer [ Private ]
{
    For i = 1:1:(pSeconds * 4) {
        // An If, not `Quit:<cond>`: a postconditional's expression ends at the first SPACE, so
        // `Quit:X >= pCount` parses `>= pCount` as the RETURN VALUE and gives #1054 at the `>=`.
        If ##class(Example.BO.MessageSink).Count() >= pCount { Quit }
        Hang 0.25
    }
    Quit ##class(Example.BO.MessageSink).Count()
}

/// THE DEFECT, asserted as behaviour. Two headers, one body row, and the edit is visible through the
/// original — so the audit trail now says the original message contained something it never did.
Method TestPlainResendSharesTheBodyRow() As %Status
{
    Do $$$AssertStatusOK(..Seed("ORIGINAL A", .tId), "seeded a completed message")
    Do $$$AssertStatusOK(##class(Example.UTL.ResendEditAndResend).ResendUnchanged(tId, "BO.Reprocess", .tNewId), "resent unchanged")
    Do $$$AssertNotEquals(tNewId, tId, "a NEW header was created -- ResendDuplicatedMessage duplicates, unlike ResendMessage")
    Do $$$AssertEquals(..BodyId(tNewId), ..BodyId(tId), "and it points at the SAME body row: that is the documented behaviour, not a bug")
    // Now the consequence, which is the part nothing warns about.
    Set tBody = ##class(Ens.StringContainer).%OpenId(..BodyId(tId))
    Set tBody.StringValue = "EDITED AFTER A PLAIN RESEND"
    Do $$$AssertStatusOK(tBody.%Save(), "the shared row saves cleanly")
    Do $$$AssertEquals(..BodyText(tId), "EDITED AFTER A PLAIN RESEND", "and the ORIGINAL header now reads the edit -- history has been rewritten")
    Do $$$AssertEquals(..BodyText(tNewId), "EDITED AFTER A PLAIN RESEND", "as does the resend, because there is only one row")
    Quit $$$OK
}

/// The guard: handing ResendEdited the original's own row is refused, and the message says what to do.
Method TestEditingTheOriginalRowIsRefused() As %Status
{
    Do $$$AssertStatusOK(..Seed("ORIGINAL B", .tId), "seeded")
    Set tOwnRow = ##class(Ens.StringContainer).%OpenId(..BodyId(tId))
    Do $$$AssertTrue($IsObject(tOwnRow), "the original's body opened")
    Set tSC = ##class(Example.UTL.ResendEditAndResend).ResendEdited(tId, "BO.Reprocess", tOwnRow, .tNewId)
    Do $$$AssertStatusNotOK(tSC, "resending the original's OWN row is refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "CloneBody", "and the error says what to do instead")
    Do $$$AssertEquals(tNewId, "", "and no header was created")
    Quit $$$OK
}

/// A null body would silently become a plain resend, which is what the caller was avoiding.
Method TestNullBodyIsRefused() As %Status
{
    Do $$$AssertStatusOK(..Seed("ORIGINAL C", .tId), "seeded")
    Set tSC = ##class(Example.UTL.ResendEditAndResend).ResendEdited(tId, "BO.Reprocess", $$$NULLOREF, .tNewId)
    Do $$$AssertStatusNotOK(tSC, "a null body is refused rather than treated as 'unchanged'")
    Do $$$AssertEquals(tNewId, "", "and no header was created")
    Quit $$$OK
}

/// The correct shape end to end: clone, edit the clone, resend it, and the original is untouched.
Method TestEditedResendLeavesTheOriginal() As %Status
{
    Do $$$AssertStatusOK(..Seed("ORIGINAL D", .tId), "seeded")
    Set tOriginalBodyId = ..BodyId(tId)
    Do $$$AssertStatusOK(##class(Example.UTL.ResendEditAndResend).CloneBody(tId, .tClone), "cloned the body")
    Do $$$AssertEquals(tClone.%Id(), "", "the clone has no id of its own yet, which is why editing it is safe")
    Set tClone.StringValue = "EDITED ON A CLONE"
    // Deliberately NOT saved: ResendDuplicatedMessage persists pNewBody. Measured.
    Do $$$AssertStatusOK(##class(Example.UTL.ResendEditAndResend).ResendEdited(tId, "BO.Reprocess", tClone, .tNewId), "resent the edited clone")
    Do $$$AssertNotEquals(..BodyId(tNewId), tOriginalBodyId, "the resend has its own body row")
    Do $$$AssertEquals(..BodyText(tId), "ORIGINAL D", "and the original still says what it always said")
    Do $$$AssertEquals(..BodyText(tNewId), "EDITED ON A CLONE", "while the resend carries the edit")
    Quit $$$OK
}

/// It has to actually arrive, and carry the edit. $$$OK means queued, not delivered.
Method TestEditedResendReachesTheTarget() As %Status
{
    Do $$$AssertStatusOK(..Seed("ORIGINAL E", .tId), "seeded")
    Do $$$AssertStatusOK(##class(Example.UTL.ResendEditAndResend).CloneBody(tId, .tClone), "cloned")
    Set tClone.StringValue = "DELIVERED EDIT"
    Do $$$AssertStatusOK(##class(Example.UTL.ResendEditAndResend).ResendEdited(tId, "BO.Reprocess", tClone, .tNewId), "resent")
    Do $$$AssertEquals(..WaitFor(1), 1, "exactly one message arrived")
    Do $$$AssertEquals(##class(Example.BO.MessageSink).Received("BO.Reprocess"), "DELIVERED EDIT", "at BO.Reprocess, carrying the edit and not the original")
    Quit $$$OK
}

/// pNewTarget is honoured: it arrives at the new target and NOT at the original one.
Method TestResendHonoursTheNewTarget() As %Status
{
    Do $$$AssertStatusOK(..Seed("ORIGINAL F", .tId), "seeded with TargetConfigName BO.Sink")
    Do $$$AssertStatusOK(##class(Example.UTL.ResendEditAndResend).ResendUnchanged(tId, "BO.Reprocess", .tNewId), "resent to BO.Reprocess")
    Do $$$AssertEquals(..WaitFor(1), 1, "one message arrived")
    // Both halves: a resend that ignored pNewTarget would satisfy the first assertion alone.
    Do $$$AssertEquals(##class(Example.BO.MessageSink).Received("BO.Reprocess"), "ORIGINAL F", "it arrived at the NEW target")
    Do $$$AssertEquals(##class(Example.BO.MessageSink).Received("BO.Sink"), "", "and not at the original one")
    Quit $$$OK
}

}
