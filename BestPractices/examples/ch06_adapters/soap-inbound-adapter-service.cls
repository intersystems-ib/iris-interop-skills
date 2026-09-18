/// Rule: BestPractices_Interop_IRIS.md §6.17 "A SOAP inbound service has two deployment modes, and `EnableStandardRequests` only exists in one of them"
/// Validity: Verified against IRIS for Health 2026.1 — compiled, and both modes measured.
/// Severity: High (the setting is unsettable in one mode and mandatory in the other).
///
/// Pattern: a SOAP inbound service in **adapter mode** — it keeps the adapter
/// `EnsLib.SOAP.Service` gives it by default, rather than blanking it.
///
/// WHY THIS EXISTS ALONGSIDE `soap-business-service.cls`. That one declares `Parameter ADAPTER;` with
/// no value, deliberately, and its header explains why: blanking it is what allows direct inbound
/// through the CSP web application. Measured, the two are genuinely different components:
///
///     EnsLib.SOAP.Service          ADAPTER _Default = "EnsLib.SOAP.InboundAdapter"   the inherited default
///     Example.BS.SoapAdapterMode   ADAPTER _Default = "EnsLib.SOAP.InboundAdapter"   kept (this file)
///     Example.BS.MyService         ADAPTER _Default = ""                             blanked on purpose
///
/// So `Parameter ADAPTER;` is not a no-op declaration: it records an EMPTY default, overriding the
/// inherited one. (Note the column is `_Default`, not `Default` — `Default` is a reserved word and a
/// query using it returns zero rows with the reason only in the status.)
///
/// And that single difference decides whether `EnableStandardRequests` is a thing you can set at all:
///
///     EnsLib.SOAP.InboundAdapter    EnableStandardRequests   init 0    <-- the ONLY place it lives
///     EnsLib.HTTP.Service           EnableStandardRequests   init 1    <-- Target="Host", different family
///     EnsLib.SOAP.Service           does NOT have it
///     Example.BS.SoapAdapterMode    does NOT have it
///     Example.BS.MyService          does NOT have it
///
/// No SERVICE has the property — it is the adapter's. `Target="Adapter"` is what routes the setting to
/// the adapter instance, so an item whose service blanked its adapter has nothing to route it to.
///
/// `EnsLib.SOAP.Service` extends `Ens.Helper.Service.SyncResponseHandler.HTTP, Ens.BusinessService,
/// %SOAP.WebService` — **not** `EnsLib.HTTP.Service` — so it inherits no Host copy of the setting. For
/// SOAP the answer is unambiguous: the setting belongs on the ADAPTER, and only when there is one.
/// The Host variant with default 1 belongs to the HTTP/REST family, which is a different decision
/// tree, not an alternative place to put it here.
///
/// WHAT THE SKILL DOES NOT SAY. `soap-bo:237` is correct that the setting "belongs on
/// `Target="Adapter"`", and gives no hint that there is a mode in which the setting cannot be applied
/// at all. A reader holding `soap-business-service.cls` — the bank's own SOAP example, in direct mode
/// — who follows that advice adds a setting to an item with no adapter. So the rule needs its
/// precondition stated: **Target="Adapter" if and only if the service kept its adapter.**
///
/// AND THE FAILURE IS LOUD, NOT SILENT — which is why this row was relabelled. The coverage map filed
/// it as a silent failure; its own cell says the first call dies with
/// `<Ens>ErrSOAPNotEnabled: Adapter Setting EnableStandardRequests is not set`, which **names the
/// setting**. That is loud-but-misdirecting: it tells you the setting and not the target, so the
/// natural next move is to set it again on the wrong one. Severity is the cost of the misdirection,
/// not of silence.
Class Example.BS.SoapAdapterMode Extends EnsLib.SOAP.Service
{

/// NO `Parameter ADAPTER;` HERE. Omitting the declaration keeps the inherited default
/// `EnsLib.SOAP.InboundAdapter`; declaring it blank -- as `soap-business-service.cls` does on purpose
/// -- erases it and with it the only place `EnableStandardRequests` can live.

Parameter NAMESPACE = "http://example.org/adaptermode";

Parameter SERVICENAME = "AdapterModeService";

/// Production ITEM name of the target, not a class name -- items are `<Tipo>.<Name>`.
Parameter TARGETBP = "BP.OrderProcess";

/// The inbound contract. Marked [ WebMethod ] so the WSDL carries it.
Method AcceptOrder(pRequest As Example.MSG.AcceptOrderReq) As Example.MSG.AcceptOrderRsp [ WebMethod ]
{
    Set tSC = ..OnProcessInput(pRequest, .tResponse)
    If $$$ISERR(tSC) {
        Quit ""
    }
    Quit tResponse
}

Method OnProcessInput(pInput As Example.MSG.AcceptOrderReq, Output pOutput As Example.MSG.AcceptOrderRsp) As %Status
{
    Set pOutput = ##class(Example.MSG.AcceptOrderRsp).%New()
    Set pOutput.Accepted = 1
    Quit $$$OK
}

}
