/// Rule: BestPractices_Interop_IRIS.md §6.7 "Custom Business Service with a bare adapter — the case where you DO write the class"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: Medium.
///
/// Pattern: the genuine custom-BS case. Use this shape ONLY when no prebuilt service fits —
/// for delimited files use a RecordMap and configure EnsLib.RecordMap.Service.FileService (§1.11),
/// and for HL7 use EnsLib.HL7.Service.FileService (§2.10). Writing this class when a prebuilt
/// service would do means re-implementing a poll loop, a parser and a dispatch that already exist.
///
/// THE DIFFERENCE FROM SUBCLASSING A PREBUILT SERVICE, which is what makes this shape legal:
/// here the adapter is named by Parameter ADAPTER on an Ens.BusinessService, so OnProcessInput's
/// signature is YOURS to define. On a prebuilt EnsLib.*.Service.* the base class fixes it — and
/// on a RecordMap/HL7 FileService it is (pInput As %Stream.Object, Output pOutput, ByRef pHint),
/// the WHOLE FILE, with no per-record hook. Getting that wrong is #5478.
///
/// Do NOT declare Parameter ADAPTER when extending a prebuilt …Service.FileService — that
/// keyword names an adapter, and a FileService is a Business Service, not one.
///
/// ##super() IS NOT NEEDED HERE and that is not an oversight: the inherited
/// Ens.BusinessService.OnInit does nothing by default (ESQL §6.5 "Initializing the Adapter"),
/// so there is nothing to chain to. On a PREBUILT service it is mandatory — the base OnInit is
/// the only place the parser state is initialised, and skipping it makes the service consume and
/// delete its input while emitting no message and no Event Log entry (CR-14).
Class Example.BS.CensusFileReader Extends Ens.BusinessService
{

Parameter ADAPTER = "EnsLib.File.InboundAdapter";

Parameter SETTINGS = "TargetConfigNames:Basic";

Property TargetConfigNames As %String(MAXLEN = 1000);

/// Fail loud at production start, not at the first message.
Method OnInit() As %Status
{
    If ..TargetConfigNames = "" Quit $$$ERROR($$$EnsErrGeneral, "TargetConfigNames is required")
    Quit $$$OK
}

/// The adapter hands us the file as a stream. Signature is ours because the adapter is named
/// by Parameter ADAPTER rather than fixed by a prebuilt superclass.
Method OnProcessInput(pInput As %Stream.Object, Output pOutput As %RegisteredObject) As %Status
{
    #DIM tSC As %Status = $$$OK
    #DIM errObj As %Exception.AbstractException
    try {
        // Ens.StringContainer stands in for a project message class only to keep the example
        // self-contained; a real service sends its own <Pkg>.MSG.<Name>Req.
        Set tRequest = ##class(Ens.StringContainer).%New()
        Set tRequest.StringValue = pInput.Read(32000)

        // Async: fire-and-forget to the router. SendRequestSync would block a pool slot for
        // the whole downstream chain.
        Set tSC = ..SendRequestAsync(..TargetConfigNames, tRequest)
    }
    catch (errObj) {
        Set tSC = errObj.AsStatus()
    }
    Quit tSC
}

}
