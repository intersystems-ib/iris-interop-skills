/// Rule: BestPractices_Interop_IRIS.md §4.11 "The FHIR payload is a stream id, and every way of touching it fails quietly"
/// Validity: Verified against IRIS for Health Community 2026.1 in a Foundation namespace — compiled AND executed.
/// Severity: High (the failure mode is a forwarded FHIR request whose body is empty, or is the caller's own).
///
/// Pattern: the Business Process that owns the stream handling, so that the DTL beside it and any
/// Business Operation downstream never have to. It is a plain `Ens.BusinessProcess` and not a
/// MessageRouter because it is not routing — it is editing a payload, which a rule cannot do.
///
/// THE THREE THINGS A CALLER GETS WRONG HERE, each of them returning $$$OK:
///
///   1. Guarding with `%ExistsId`. It returns 0 for a stream that plainly exists, so the guard
///      rejects every real payload. `$IsObject(%OpenId(...))` is the test. See §4.11 for why:
///      HS.SDA3.QuickStream has no storage definition and no SQL table at all.
///   2. Reading with a single `Read()`. The default length is 32000, not "all of it", so a Bundle
///      larger than that arrives silently truncated and the FHIR server downstream rejects a
///      message that looks perfectly well-formed in the trace.
///   3. Forwarding `source.QuickStreamId` unchanged and calling it a transform. That is a reference
///      copy: two headers, one body.
///
/// WHY THE STREAM LIFETIME IS THE PROCESS'S PROBLEM AND NOT THE PLATFORM'S. Nothing deletes a
/// QuickStream when its message goes. Measured: `$D(^HS.Stream("18"))` is 11 before AND after
/// `%DeleteId` on the message, and the stream still opens and reads; there is no `%OnDelete`
/// anywhere on HS.FHIRServer.Interop.Request -> HS.Util.EnsRequest -> Ens.Request ->
/// Ens.MessageBody. So a message purge does not reclaim `^HS.Stream`. This process creates exactly
/// one new stream per request it edits, which is the number you can reason about later; a retry
/// loop that creates one per attempt is the number you cannot.
///
/// ONE MEASURED DETAIL WORTH THE LINE IT COSTS. `Clear()` is the obvious way to rewrite a payload in
/// place. It empties GRef and Id, the following Write() returns $$$OK, and Flush() throws
/// <SYNTAX>Flush+4^HS.SDA3.QuickStream.1. Catching that is not enough -- the broken object throws
/// AGAIN when it is destroyed, after the method has already returned its value, so the caller sees
/// the error attributed to a frame that looks fine. There is no in-place rewrite; there is only a
/// new stream.
Class Example.BP.FhirRequestQuickStream Extends Ens.BusinessProcess
{

/// Where the edited request goes. A Setting, so the same process serves a local
/// HS.FHIRServer.Interop.Operation and an external .HTTPOperation without an edit.
Property TargetConfigName As Ens.DataType.ConfigName;

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems}";

Method OnRequest(pRequest As HS.FHIRServer.Interop.Request, Output pResponse As HS.FHIRServer.Interop.Response) As %Status
{
    // The metadata IS on the message, so decisions that can be made from it should be.
    // pRequest.Request is an HS.FHIRServer.API.Data.Request: RequestMethod, RequestPath, Type,
    // Interaction, Id, QueryString, Prefer. Nothing about it requires opening the stream.
    If '$IsObject(pRequest.Request) {
        Quit $$$ERROR($$$GeneralError, "FHIR interop request carries no Request metadata")
    }

    // A read-only interaction has no body to edit, and building a stream for it would leave one
    // more orphan in ^HS.Stream for nothing.
    If (pRequest.Request.RequestMethod = "GET") || (pRequest.QuickStreamId = "") {
        Quit ..SendRequestSync(..TargetConfigName, pRequest, .pResponse)
    }

    // NOT %ExistsId -- see the header. This is the only honest existence test for a QuickStream.
    Set tProbe = ##class(HS.SDA3.QuickStream).%OpenId(pRequest.QuickStreamId, , .tSC)
    If '$IsObject(tProbe) {
        Set tWhy = "FHIR payload stream " _ pRequest.QuickStreamId _ " did not open: " _ $System.Status.GetErrorText(tSC)
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    Set tProbe = ""

    // The DTL creates the new stream and puts its id on the target. Doing it here as well would
    // create two, and the one nobody references is the one nobody ever notices.
    Set tSC = ##class(Example.DT.FhirRedact).Transform(pRequest, .tEdited)
    If $$$ISERR(tSC) { Quit tSC }

    // The assertion that separates a working transform from a clean no-op. A DTL that failed to
    // build its stream leaves the id empty and still returns $$$OK, and the request then travels on
    // with no body at all -- which the FHIR server downstream reports as a malformed request,
    // several hops away from the cause.
    If tEdited.QuickStreamId = "" {
        Quit $$$ERROR($$$GeneralError, "transform produced no payload stream")
    }
    If tEdited.QuickStreamId = pRequest.QuickStreamId {
        Set tWhy = "transform shared the inbound payload stream " _ pRequest.QuickStreamId _ " instead of creating one"
        Quit $$$ERROR($$$GeneralError, tWhy)
    }

    Quit ..SendRequestSync(..TargetConfigName, tEdited, .pResponse)
}

}
