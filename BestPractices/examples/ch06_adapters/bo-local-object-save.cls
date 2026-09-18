/// Rule: BestPractices_Interop_IRIS.md §6.14 "The adapter-less BO — and the discarded `%Save()` status that reports success"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (an unchecked save completes the message and writes nothing).
///
/// Pattern: the BUSINESS OPERATION WITH NO ADAPTER. `business-operations:31` recommends this shape
/// more strongly than any other — "when the destination is a `%Persistent` class in the same
/// namespace as the production, the cleanest BO has **no adapter at all**" — and until this file no
/// bank artefact showed it.
///
/// MEASURED FIRST, because the coverage map's count was wrong and the correction matters for anyone
/// re-checking. The row said "all five [bank BOs] carry an adapter". Resolving `$parameter(cls,
/// "ADAPTER")` on every business operation in the bank gives **eight**, of which **seven** carry one
/// and one (`Example.Adapters.BO.JavaGateway`) already carries none. So the premise was wrong twice
/// over — and the conclusion still holds, because a Java Gateway BO is not this shape. What was
/// absent is the adapter-less LOCAL SAVE, which is what this file is.
///
/// WHY NO ADAPTER IS THE RIGHT ANSWER HERE, and it is not "one less thing to configure". An adapter
/// exists to reach OUTSIDE the IRIS process — a socket, a file handle, a JDBC connection, an HTTP
/// client. A `%Persistent` class in the same namespace is reached by `%Save()`. Routing that through
/// `EnsLib.SQL.OutboundAdapter` means a JDBC round trip to the database you are already inside, plus
/// a connection, plus credentials, plus a DSN that can be wrong. Fewer moving parts is the small
/// benefit; the large one is that this BO is directly unit-testable with no external state at all.
///
/// WHAT REPLACES `Parameter ADAPTER`: nothing. There is no `Adapter` property to narrow, no
/// `OnInit` to `##super()`, no connection to test. `INVOCATION` still matters — `Queue` means the
/// caller does not block on the save, which for a local write is usually right.
///
/// THE DEFECT THIS SHAPE INVITES, and it is the reason the file has a companion test.
/// `Do obj.%Save()` and `Set sc = obj.%Save()` are one character apart and neither fails to compile.
/// Measured, with a `PostCode` 11 characters long against `MAXLEN = 10`:
///
///     Set tSC = tAddr.%Save()   Return tSC      ->  ERROR #7201, message goes to Errored, row absent
///     Do tAddr.%Save()          Return $$$OK    ->  message COMPLETED, row absent, Event Log empty
///
/// The second line is the whole problem. The production is green, the Visual Trace shows a completed
/// request, the operator has nothing to look at, and the row is not there. It is the same silent
/// shape as the discarded cascade status in §5.11, one layer up — and unlike that one it is trivial
/// to get right, which is exactly why it gets skipped.
///
/// NOT REUSING A REQUEST WOULD HAVE BEEN WORSE. This takes `Example.MSG.PersonReqCascade` and writes
/// `Example.DAT.Address` — both already in the bank, from §5.11. A near-duplicate pair would have
/// added two artefacts to say nothing new.
Class Example.BO.LocalSave Extends Ens.BusinessOperation
{

/// No `Parameter ADAPTER`. That is the point of the file, so it is stated rather than merely absent.
/// Measured: `$parameter("Example.BO.LocalSave", "ADAPTER")` returns "", and the class compiles --
/// `Ens.BusinessOperation` requires no adapter.
Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    // Dispatch is by MessageMap below; this is the fallback for anything unmapped, and it must be
    // an ERROR rather than $$$OK -- a BO that silently accepts a message it cannot handle is the
    // same silent-success defect as the discarded save.
    Return $$$ERROR($$$GeneralError, "unhandled request type: " _ $classname(pRequest))
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Example.MSG.PersonReqCascade">
    <Method>SaveAddress</Method>
  </MapItem>
</MapItems>
}

/// Copy the request's address into its own row and RETURN the save status.
Method SaveAddress(pRequest As Example.MSG.PersonReqCascade, Output pResponse As Ens.StringResponse) As %Status
{
    Set pResponse = ##class(Ens.StringResponse).%New()

    If '$IsObject(pRequest.Address) {
        // Nothing to save is not the same as a failed save. Say which.
        Set pResponse.StringValue = "no address on the request; nothing saved"
        Return $$$OK
    }

    Set tAddr = ##class(Example.DAT.Address).%New()
    Set tAddr.Street = pRequest.Address.Street
    Set tAddr.City = pRequest.Address.City
    Set tAddr.PostCode = pRequest.Address.PostCode

    // THE LINE. `Set tSC = ...` then return it. `Do tAddr.%Save()` compiles, completes the message
    // and writes nothing.
    Set tSC = tAddr.%Save()
    If $$$ISERR(tSC) {
        Return tSC
    }

    // The id is the evidence the row exists. Returning it lets a caller -- or a test -- read the
    // row back rather than trust this method's word for it.
    Set pResponse.StringValue = tAddr.%Id()
    Return $$$OK
}

}
