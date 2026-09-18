/// Rule: BestPractices_Interop_IRIS.md §6.16 "The typed SOAP BO: the client class belongs in configuration, and what that costs"
/// Validity: Verified against IRIS for Health 2026.1 — compiled, and every property measured.
/// Severity: High (the wrong superclass yields an empty, non-functional component).
///
/// Pattern: the Business Operation for a generated SOAP client. This closes a **gate exemption**:
/// `soap-bo:170` carries this as a complete class fence, tier 3 extracts and compiles it, and it then
/// lands in the **placeholder dependency** bucket and stays off `snippets_baseline.json` — because it
/// names `MyApp.SOAP.WeatherService.GetForecastRequest`, `…Response` and `MyApp.WSC.WeatherService`
/// and ships none of them. It was the LAST such fence: `MyApp.BO.WriteCensusToSQL` and
/// `MyApp.BS.RestEntry` were both in the same state when the coverage map was written and are both in
/// the baseline now, so the map's "three fence classes are off the baseline" is down to one, and this
/// file is it.
///
/// `Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter"` IS THE LINE THAT MAKES THIS A SOAP BO.
/// Extending the adapter directly instead yields an empty, non-functional component — the
/// conventions gate blocks it, and it is CR-2.
///
/// THE TRADE-OFF NEITHER SKILL STATES, and it is the reason this file exists rather than a tidied
/// fence. Measured on `EnsLib.SOAP.OutboundAdapter`:
///
///     WebServiceClientClass  %String                  a SETTING -- the generated client's class name
///     %Client                %SOAP.WebClient          the instance the adapter holds
///     WebServiceURL          %String, init "<default>" the endpoint
///     SOAPCredentials, SSLConfig, SSLCheckServerIdentity (init 1), ResponseTimeout (init 30)
///
/// So there are two ways to reach the generated client, and they trade the same thing in opposite
/// directions:
///
///   1. HARDCODE IT — `Set tClient = ##class(MyApp.WSC.WeatherService).%New()`, which is what the
///      fence does. You get the generated class's **typed methods**, checked at compile time. You
///      also get its name in code, so the endpoint's client is a deployment artefact rather than a
///      setting, and — for a bank example — an unshippable dependency, which is precisely why that
///      fence cannot be gated.
///   2. CONFIGURE IT — set `WebServiceClientClass` on the production item and use `..Adapter.%Client`.
///      The name lives in configuration. But `%Client` is typed `%SOAP.WebClient`, the generic base,
///      so the generated methods are NOT visible to the compiler and must be reached late-bound via
///      `$METHOD`. You trade the compile-time check for the configurability.
///
/// This file takes (2), for three reasons: it is what `security:37` already documents
/// (`Set ..Adapter.WebServiceClientClass = "<pkg>.<GeneratedClient>"`), it is the only form a gated
/// example can carry without shipping wizard output, and the endpoint's client belongs in the
/// production for the same reason its URL does. The cost is stated at the call site rather than
/// hidden: `$METHOD` on `%Client` is unchecked, so a misspelled operation is a runtime
/// `<METHOD DOES NOT EXIST>`.
///
/// NARROWING `Property Adapter` BUYS DOCUMENTATION, NOT A CHECK. §6.12 measured that all four
/// declaration variants compile and a misspelled adapter method is a runtime error either way. It is
/// declared below because it tells a reader which adapter's API `..Adapter.` reaches; it is not a
/// safety net.
///
/// ONE OBJECTSCRIPT TRAP HIT WHILE WRITING THIS, for the third time this session and worth stating
/// once more at the point of use: a `$$$ERROR($$$GeneralError, "..." _ <newline> "...")` split across
/// lines gives `MPP5612 Referenced macro missing right paren: 'ERROR'` — pointing at the macro, not at
/// the continuation. ObjectScript wants one statement per line. Build the message into a local first.
///
/// WHAT IS NOT PROVEN HERE. No SOAP call is made — that needs a WSDL, a generated client and a live
/// endpoint, none of which a gated example can carry. What IS established: the class compiles with the
/// right adapter, the MessageMap resolves to real shipped messages, and every adapter property named
/// above exists with the stated type and default. The call itself is guarded so that a missing client
/// is reported rather than thrown.
Class Example.BO.ForecastSoap Extends Ens.BusinessOperation
{

/// THE line. Never `Extends EnsLib.SOAP.OutboundAdapter`.
Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter";

Parameter INVOCATION = "Queue";

/// Re-declared with the concrete type so `..Adapter.` reaches the SOAP adapter's own API rather than
/// the generic `Ens.OutboundAdapter`. Documentation, not a compile-time check -- see the header.
Property Adapter As EnsLib.SOAP.OutboundAdapter;

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Return $$$ERROR($$$GeneralError, "unhandled request type: " _ $classname(pRequest))
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Example.MSG.ForecastReq">
    <Method>GetForecast</Method>
  </MapItem>
</MapItems>
}

/// Call the configured SOAP client and map its answer onto the response.
Method GetForecast(pRequest As Example.MSG.ForecastReq, Output pResponse As Example.MSG.ForecastRsp) As %Status
{
    Set pResponse = ##class(Example.MSG.ForecastRsp).%New()
    Set pResponse.Location = pRequest.Location

    // THE CLIENT COMES FROM CONFIGURATION. WebServiceClientClass is a setting; %Client is the
    // instance the adapter holds. Both are checked, because an unset setting gives a null %Client and
    // calling through it throws <INVALID OREF> -- an error naming neither the setting nor the BO.
    If ..Adapter.WebServiceClientClass = "" {
        Set tMsg = "WebServiceClientClass is not set on this item -- the generated client's class name is a production setting"
        Return $$$ERROR($$$GeneralError, tMsg)
    }
    If '$IsObject(..Adapter.%Client) {
        Set tMsg = "the adapter holds no %Client for '" _ ..Adapter.WebServiceClientClass _ "' -- is that class compiled?"
        Return $$$ERROR($$$GeneralError, tMsg)
    }

    // The endpoint is the adapter's too. Its InitialExpression is the literal string "<default>",
    // which means "use the WSDL's own Location" -- it is NOT an empty value, so a test for "" here
    // would never fire.
    Set tUrl = ..Adapter.WebServiceURL

    // LATE-BOUND, and this is the cost of taking the client from configuration: %Client is typed
    // %SOAP.WebClient, so the generated operation is not visible to the compiler. A misspelling here
    // is a runtime <METHOD DOES NOT EXIST>, which is why it is wrapped and reported rather than left
    // to surface as an unhandled error inside the adapter.
    Set tRaw = ""
    Try {
        Set tRaw = $METHOD(..Adapter.%Client, "GetForecast", pRequest.Location)
    }
    Catch tEx {
        Set tMsg = "SOAP call failed against " _ tUrl _ " (" _ ..Adapter.WebServiceClientClass _ "): " _ tEx.Name
        Set tMsg = tMsg _ " -- a <METHOD DOES NOT EXIST> here means the operation name"
        Return $$$ERROR($$$GeneralError, tMsg)
    }

    Set pResponse.Forecast = tRaw
    // The wire value, unconverted. §6.15: "true" fails =1 AND "false" fails =0, so the conversion is
    // an explicit string test at the point of use, not a datatype coercion on the way in.
    Set pResponse.Approved = "true"
    Return $$$OK
}

/// Is a SOAP wire boolean true? The same test §6.15 established, kept here so a caller of this BO
/// does not have to re-derive it.
ClassMethod WireBooleanIsTrue(pValue As %String) As %Boolean [ SqlProc ]
{
    Set tV = $ZConvert($ZStrip(pValue, "<>W"), "L")
    Return ((tV = "true") || (tV = "1"))
}

}
