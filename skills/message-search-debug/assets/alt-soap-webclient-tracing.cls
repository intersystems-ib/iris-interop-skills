/// Rule: BestPractices_Interop_IRIS.md §6.2 "Per-BO Alt.SOAP.WebClient for SOAP tracing"
/// Validity: Still valid.
/// Severity: High (debuggability).
///
/// What this file shows: the BO half of the §6.2 pattern - the SoapLogFile setting
/// and the scoped ^ISCSOAP toggle around one call.
///
/// The other half is NOT reproduced here: Alt.SOAP.WebClient is a copy of the
/// InterSystems system class %SOAP.WebClient placed in the reserved `Alt` package
/// (see message-search-debug §"Per-BO SOAP tracing" for the copy steps, and
/// §1.2 for why `Alt` is the reserved package for patched system classes). It is
/// vendor source; the example bank cannot carry it. Generated SOAP proxies then
/// extend Alt.SOAP.WebClient instead of %SOAP.WebClient, which is what lets the
/// per-BO log file be honoured on the client side.
///
/// Scope of ^ISCSOAP - read this before treating the pattern as safe:
/// ^ISCSOAP is an ordinary global, so it is namespace-wide and shared by every
/// process in the namespace, not process-private. What the pattern buys is
/// *one log file per BO* (each BO points LogFile at its own path around its own
/// call), NOT isolation: two BOs tracing concurrently interleave into whichever
/// file was set last, and either one's restore switches the other's tracing off.
/// Treat it as a debug aid on one interface at a time, not always-on tracing,
/// and clear the SoapLogFile setting once the issue is diagnosed.
///
/// The restore below runs on the exception path too. A throw between the set and
/// the reset would otherwise leave namespace-wide SOAP tracing on, writing every
/// payload to disk indefinitely - a real exposure on a PHI-carrying interface.
///
/// Also referenced from §12.4 (Monitoring chapter — SOAP-trace files).
Class Example.Adapters.BO.SOAPClient Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter";

Property SoapLogFile As %String(MAXLEN = 512) [ InitialExpression = "" ];

Parameter SETTINGS = "SoapLogFile";

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    #DIM tSC as %Status = $$$OK
    #DIM errObj as %Exception.AbstractException
    #DIM tTracing as %Boolean
    #DIM tPrevLog as %String = ""
    #DIM tPrevFile as %String = ""

    set tTracing = (..SoapLogFile '= "")
    try {
        if tTracing {
            set tPrevLog = $get(^ISCSOAP("Log"))
            set tPrevFile = $get(^ISCSOAP("LogFile"))
            set ^ISCSOAP("Log") = "ios"
            set ^ISCSOAP("LogFile") = ..SoapLogFile
        }

        // ... invoke the SOAP proxy here ...
        // set tSC = ..Adapter.InvokeMethod("methodName", .pResponse, pRequest.arg1)
    } catch (errObj) {
        set tSC = errObj.AsStatus()
    }

    // Restore on BOTH paths - never leave tracing on after a throw.
    if tTracing {
        set ^ISCSOAP("Log") = tPrevLog
        set ^ISCSOAP("LogFile") = tPrevFile
    }
    quit tSC
}

}
