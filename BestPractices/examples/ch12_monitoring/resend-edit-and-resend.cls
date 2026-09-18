/// Rule: BestPractices_Interop_IRIS.md §12.6 "Resend and edit-and-resend: two APIs, and the shared body row that rewrites history"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed against a started production.
/// Severity: High (the failure mode rewrites what a delivered message said, and the trace stays coherent).
///
/// Pattern: the resend calls, with the one guard that makes edit-and-resend safe.
///
/// TWO APIs WITH THE SAME NAME-SHAPE AND DIFFERENT BEHAVIOUR, measured rather than read:
///
///     Ens.MessageHeader::ResendMessage(pHeaderId)
///         RE-QUEUES THE ORIGINAL HEADER. No new header row is created -- measured: header 125 was
///         resent, the sink received its payload again, and the newest header id was still 125. One
///         header, delivered twice. The Message Viewer shows no second row to compare against.
///
///     Ens.MessageHeader::ResendDuplicatedMessage(pOriginalHeaderId, *pNewHeaderId, pNewTarget,
///                                                pNewBody, pNewSource, pHeadOfQueue)
///         CREATES A NEW HEADER over -- by default -- THE SAME BODY ROW. Measured: original body 18,
///         new header 124, new body 18. Two headers, one body.
///
/// BOTH REQUIRE A RUNNING PRODUCTION. With none, `ResendDuplicatedMessage` gives
/// `<Ens>ErrProductionNotRunning: No production is running` and `ResendMessage` gives
/// `<Ens>ErrGeneral: ProductionNotRunning; not resubmitting message '<id>'`. This is one of the few
/// paths in this deliverable that fails loudly, and it is worth knowing so the loud failure is not
/// mistaken for the interesting one.
///
/// THE DEFECT THIS CLASS EXISTS TO PREVENT. `Ens.MessageHeader` references its body by
/// `MessageBodyId` + `MessageBodyClassName` -- an id, not an object. So after a plain resend, two
/// headers point at one row, and editing that row to "fix" the message rewrites what the ORIGINAL
/// message says. Measured end to end:
///
///     resend header 123 -> new header 124, both on body 18
///     open body 18, set StringValue = "EDITED AFTER A PLAIN RESEND", %Save()
///     header 123 (the original) now reads   EDITED AFTER A PLAIN RESEND
///     header 124 (the resend)   now reads   EDITED AFTER A PLAIN RESEND
///
/// Nothing is corrupt and nothing errors. The Visual Trace is perfectly coherent — it faithfully
/// renders the body each header points at, and they point at the same one. The audit trail now says
/// the original message contained something it never contained, and there is no way to tell from
/// inside IRIS that it ever said anything else.
///
/// WHAT LINKS THE TWO HEADERS IS A STRING, AND IT IS ONLY ON THE NEW ONE. Measured on the pair above:
/// the new header's `Description` is `"Resent 123"`; `SessionId` is the same on both (123); and
/// `CorrespondingMessageId` is empty on both. **The `Resent` property stayed empty on both headers**
/// after `ResendDuplicatedMessage` AND after `ResendMessage` — so despite its name it is not what
/// records a resend on these two paths, and nothing at all marks the original. Do not write a report
/// that finds resends by filtering on `Resent`.
///
/// ONE THING THAT IS EASIER THAN IT LOOKS: `pNewBody` does NOT have to be saved first.
/// `ResendDuplicatedMessage` persists it — measured, an unsaved clone produced body id 12 and the
/// sink received its edited text. So the order that matters is CLONE BEFORE EDIT, not save before
/// resend. Editing first and cloning after has already rewritten the original.
Class Example.UTL.ResendEditAndResend Extends %RegisteredObject
{

/// Resend unchanged, to a new target. Two headers over one body — which is correct here, because
/// nothing is being edited and a second copy of an unchanged payload is pure cost.
ClassMethod ResendUnchanged(pHeaderId As %String, pNewTarget As %String, Output pNewHeaderId As %String) As %Status
{
    Set pNewHeaderId = ""
    Set tSC = ##class(Ens.MessageHeader).ResendDuplicatedMessage(pHeaderId, .pNewHeaderId, pNewTarget)
    If $$$ISERR(tSC) { Quit tSC }
    // A new header id is the only evidence the call did anything. It is checked because $$$OK on its
    // own has been observed from the non-duplicating API, which returns OK and creates no header.
    If pNewHeaderId = "" {
        Quit $$$ERROR($$$GeneralError, "resend of " _ pHeaderId _ " returned OK but produced no new header")
    }
    Quit $$$OK
}

/// An UNSAVED clone of a message's body, ready to be edited.
///
/// The clone is the whole point: the object this returns has no id of its own yet, so an edit to it
/// cannot reach the original's row. Calling `%OpenId` on `MessageBodyId` and editing that instead is
/// the defect — it is the same row the original header points at.
ClassMethod CloneBody(pHeaderId As %String, Output pClone As %RegisteredObject) As %Status
{
    Set pClone = $$$NULLOREF
    Set tHeader = ##class(Ens.MessageHeader).%OpenId(pHeaderId, , .tSC)
    If '$IsObject(tHeader) {
        Set tWhy = "message header " _ pHeaderId _ " did not open: " _ $System.Status.GetErrorText(tSC)
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    If tHeader.MessageBodyClassName = "" {
        Quit $$$ERROR($$$GeneralError, "header " _ pHeaderId _ " has no MessageBodyClassName")
    }
    Set tBody = $classmethod(tHeader.MessageBodyClassName, "%OpenId", tHeader.MessageBodyId, , .tSC)
    If '$IsObject(tBody) {
        Set tWhy = "body " _ tHeader.MessageBodyClassName _ "/" _ tHeader.MessageBodyId _ " did not open: " _ $System.Status.GetErrorText(tSC)
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    Set pClone = tBody.%ConstructClone()
    If '$IsObject(pClone) {
        Quit $$$ERROR($$$GeneralError, "%ConstructClone returned nothing for " _ tHeader.MessageBodyClassName)
    }
    Quit $$$OK
}

/// Resend with an edited body, refusing the one mistake that cannot be undone.
ClassMethod ResendEdited(pHeaderId As %String, pNewTarget As %String, pBody As %RegisteredObject, Output pNewHeaderId As %String) As %Status
{
    Set pNewHeaderId = ""
    If '$IsObject($Get(pBody)) {
        // Without this, a caller whose clone silently failed gets a PLAIN resend — the exact thing
        // they were trying to avoid — and a $$$OK saying it worked.
        Quit $$$ERROR($$$GeneralError, "ResendEdited needs a body object; a null one would resend the original unchanged")
    }
    Set tHeader = ##class(Ens.MessageHeader).%OpenId(pHeaderId, , .tSC)
    If '$IsObject(tHeader) {
        Set tWhy = "message header " _ pHeaderId _ " did not open: " _ $System.Status.GetErrorText(tSC)
        Quit $$$ERROR($$$GeneralError, tWhy)
    }

    // THE GUARD, on two conditions because they catch different callers. If the body handed in IS the
    // original's own row, every edit already made to it has rewritten the original message, and
    // resending it would not undo that — it would ship the rewrite as if it were a new decision.
    //
    //   pBody.%Id() = MessageBodyId   the body IS that row, however it was obtained. An unsaved
    //                                 %ConstructClone() has no id at all, so a real clone passes;
    //                                 a SAVED clone has its own id, so it passes too.
    //   pBody = tOriginal             oref identity. Within one process %OpenId on the same id
    //                                 returns the SAME oref, so this catches the common case
    //                                 directly, without depending on id semantics at all.
    Set tOriginal = $classmethod(tHeader.MessageBodyClassName, "%OpenId", tHeader.MessageBodyId)
    If ($IsObject(tOriginal) && (pBody = tOriginal)) || (pBody.%Id() = tHeader.MessageBodyId) {
        Set tWhy = "that body IS header " _ pHeaderId _ "'s own row (" _ tHeader.MessageBodyClassName _ "/" _
            tHeader.MessageBodyId _ "): editing it rewrites the original message. Use CloneBody() first."
        Quit $$$ERROR($$$GeneralError, tWhy)
    }

    // pNewBody need not be saved — ResendDuplicatedMessage persists it. Measured.
    Set tSC = ##class(Ens.MessageHeader).ResendDuplicatedMessage(pHeaderId, .pNewHeaderId, pNewTarget, pBody)
    If $$$ISERR(tSC) { Quit tSC }
    If pNewHeaderId = "" {
        Quit $$$ERROR($$$GeneralError, "resend of " _ pHeaderId _ " returned OK but produced no new header")
    }

    // And prove the two headers do not share a row, because that is the property the whole exercise
    // was for and it costs one open to confirm.
    Set tNew = ##class(Ens.MessageHeader).%OpenId(pNewHeaderId)
    If $IsObject(tNew), tNew.MessageBodyId = tHeader.MessageBodyId {
        Set tWhy = "resend produced header " _ pNewHeaderId _ " sharing body " _ tHeader.MessageBodyId _ " with the original"
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    Quit $$$OK
}

}
