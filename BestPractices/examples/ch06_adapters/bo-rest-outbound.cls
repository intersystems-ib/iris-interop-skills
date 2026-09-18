/// Rule: BestPractices_Interop_IRIS.md §6.12 "REST outbound — there is no REST adapter, and Post takes no URL"
/// Validity: Verified against IRIS for Health 2026.1 — signatures read from the dictionary, the non-2xx path RUN.
/// Severity: High (three skills named an adapter class that does not exist).
///
/// Pattern: a custom Business Operation calling an external REST endpoint. Four things here were
/// wrong in this plugin's own guidance until v1.28.0, and all four are measured.
///
/// 1. THERE IS NO `EnsLib.REST.OutboundAdapter`. It does not exist. The `EnsLib.REST` package has
///    `Operation`, `GenericOperation`, `Service`, `GenericService`, `GenericMessage` — and no
///    outbound adapter at all. Measured, every REST outbound host declares the HTTP one:
///        EnsLib.REST.Operation          ADAPTER = EnsLib.HTTP.OutboundAdapter
///        EnsLib.REST.GenericOperation   ADAPTER = EnsLib.HTTP.OutboundAdapter
///        EnsLib.HTTP.GenericOperation   ADAPTER = EnsLib.HTTP.OutboundAdapter
///    So the choice is not "which adapter" — it is always this one. The choice is whether to write
///    a custom BO like this, or to configure the prebuilt `EnsLib.REST.Operation`.
///
/// 2. `Post` TAKES NO URL. The real signature is
///        Post(*pHttpResponse As %Net.HttpResponse, pFormVarNames As %String, pData...)
///    The URL comes from the adapter's `URL` **setting**. The URL-taking variant is a different
///    method, `PostURL(pURL, *pHttpResponse, pFormVarNames, pData...)`, with the URL FIRST.
///    Writing `Post(.resp, url, body)` — which this plugin prescribed — passes the URL as
///    pFormVarNames and posts the body to whatever the setting happens to hold.
///
/// 3. NARROWING THE ADAPTER PROPERTY BUYS NOTHING AT COMPILE TIME. `..Adapter` is declared
///    `As Ens.Adapter` on `Ens.Host`, so every member access is late-bound. Measured all four
///    combinations: with and without `Property Adapter As EnsLib.HTTP.OutboundAdapter`, both a real
///    call and `..Adapter.NoSuchMethodAtAll(...)` COMPILE. Narrowing helps a human and an IDE; it
///    does not make a typo a compile error, so do not rely on it as a check.
///
/// 4. A NON-2xx DOES FAIL THE %Status — the adapter is not lenient. Measured inside a running
///    production against a deliberately missing path on IRIS's own web server:
///        GET /definitely/not/here   ->  httpCode=404, and the returned %Status is an ERROR
///    There is no setting that makes a non-2xx acceptable; the adapter's property list has none.
///    So the risk here is NOT that the adapter stays quiet: it is that the CALLER throws the status
///    away. `Do ..Adapter.Post(...)` discards it, the operation returns `$$$OK`, and the message is
///    marked Completed while the far end rejected it. Capture it, as below.
///
/// `resp.StatusCode` IS MULTIDIMENSIONAL, so reading it on a failed call can itself raise. Read it
/// inside the Try, after checking $IsObject — never as the first thing you touch in a Catch.
Class Example.BO.RestOutbound Extends Ens.BusinessOperation
{

/// The only adapter there is for this job. See header note 1.
Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

/// Narrowed for readability and editor help, NOT as a compile-time check — see header note 3.
Property Adapter As EnsLib.HTTP.OutboundAdapter;

Method Submit(pRequest As Ens.StringContainer, Output pResponse As Ens.StringContainer) As %Status
{
    Set tSC = $$$OK
    Try {
        // CAPTURE the status. Discarding it is the silent failure this example exists for:
        // the adapter reports a 404 correctly, and `Do ..Adapter.Post(...)` throws that away.
        // No URL argument -- it is the adapter's URL setting (header note 2).
        Set tSC = ..Adapter.Post(.tHttpResponse, "", pRequest.StringValue)

        // StatusCode is multidimensional, so guard the object first.
        Set tCode = ""
        If $IsObject($Get(tHttpResponse)) {
            Set tCode = tHttpResponse.StatusCode
        }

        // Belt and braces: the adapter already fails the status on a non-2xx, but an explicit
        // check documents the contract and survives a future adapter that is more permissive.
        If $$$ISOK(tSC), tCode '= "", (tCode < 200) || (tCode > 299) {
            Set tSC = $$$ERROR($$$GeneralError, "REST endpoint returned HTTP " _ tCode)
        }
        Quit:$$$ISERR(tSC)

        Set pResponse = ##class(Ens.StringContainer).%New("HTTP " _ tCode)
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.StringContainer">
    <Method>Submit</Method>
  </MapItem>
</MapItems>
}

}
