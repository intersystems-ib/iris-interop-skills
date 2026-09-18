/// Rule: BestPractices_Interop_IRIS.md §6.15 "Reading an HTTP response: the three things that are not what the skills say"
/// Validity: Verified against IRIS for Health 2026.1 — compiled, and every claim measured against a REAL HTTP response.
/// Severity: High (one of the four failure modes makes every boolean test false).
///
/// Pattern: a Business Operation that builds its own HTTP request and reads the response by hand —
/// the shape you need when the payload is not a generated SOAP proxy: a hand-rolled envelope, a REST
/// call with an unusual content type, a legacy endpoint that wants form data.
///
/// FOUR CLAIMS THE COVERAGE MAP MADE ABOUT THIS. Two hold, one is false, and one is right for the
/// wrong reason. All four were measured, the last three against a real `%Net.HttpResponse` obtained
/// from a live HTTP call rather than a stream written in-process — which matters, and is why the
/// third one came out differently than expected.
///
/// 1. THE TWO SKILLS PRESCRIBE DIFFERENT ARITIES OF THE SAME CALL — confirmed, and the difference is
///    not cosmetic:
///
///        soap-bo:290              SendFormDataArray(.resp, "POST", httpReq, "", , url)    6 args
///        business-operations:605  ..Adapter.SendFormDataArray(.response, "POST", httpReq)  3 args
///
///    Measured signature: `SendFormDataArray(*pHttpResponse, pOp, pHttpRequestIn,
///    pFormVarNames As %String = "", &pData, pURL, …)`. Both calls are legal. The 6-arg form passes
///    the URL **at the call**; the 3-arg form omits it and the adapter uses its own `URL` setting.
///    So the choice decides WHERE THE ENDPOINT LIVES — in code or in the production — and neither
///    skill says so. Prefer the 3-arg form: the endpoint belongs in configuration.
///
/// 2. `pFormVarNames` MUST BE `""` FOR A RAW BODY. It is the fourth parameter and defaults to `""`,
///    so the 3-arg form gets it right by accident. Pass something there and the adapter treats your
///    body as form variables. This is the argument the 6-arg form has to state explicitly, and the
///    reason `soap-bo`'s call has a bare `""` sitting in the middle of it.
///
/// 3. `Data.Rewind()` BEFORE THE FIRST `Read` — **NOT NEEDED, and the map's claim is false.** It said
///    that without it "the response reads empty with `$$$OK`". Measured on a real response:
///
///        StatusCode=200  Data class=%Stream.GlobalCharacter  size=445  AtEnd BEFORE any read = 0
///        first Read(80) without Rewind  ->  len 80, the start of the body
///        after Rewind, Read(80)         ->  identical
///
///    The adapter leaves the stream positioned at the START. So a first read works, and the "empty
///    with $$$OK" outcome does not occur. **Where Rewind genuinely matters is a SECOND read** — and
///    that is a real situation, because anything that has already inspected the body (a trace, a log
///    line, a content-type sniff) leaves the stream at the end and the next read gets nothing. So
///    `Rewind` before read is cheap and harmless insurance, and this file does it; what it is not is
///    the fix for a first-read-returns-empty bug, because that bug does not exist.
///
/// 4. `StatusCode` NEEDS A GUARD, but not for the reason given. The map says "MultiDim". Measured:
///    `%Net.HttpResponse.StatusCode` is `%Library.Integer` with `MultiDimensional = False`. The real
///    reason is simpler and worse: when the send fails, `pHttpResponse` comes back **unset**, and
///    `nullResponse.StatusCode` throws `<INVALID OREF>` — an error that names neither the adapter nor
///    the endpoint. So check `$IsObject` first; a `Try` around the property access treats the symptom.
///
/// 5. AND THE ONE THAT BITES EVERY TIME: SOAP AND JSON BOOLEANS ARRIVE AS THE STRINGS `"true"` AND
///    `"false"`. Measured:
///
///        "true" = 1   ->  0            +"true"   ->  0
///        "false" = 0  ->  0            +"false"  ->  0
///
///    Both are worse than the map said. It noted that `= 1` is false for every response; `= 0` is
///    **also** false for every response, so you cannot test either polarity numerically. `+"true"` is
///    0, so a `$Select` on the numeric value takes the false branch for a true answer. Compare to the
///    STRING, which is what `IsTrue()` below does.
///
/// ON THE ROW'S CI NOTE. It said this is gateable "only with the narrowed Adapter property —
/// otherwise the call stays late-bound and unchecked". §6.12 measured that narrowing the `Adapter`
/// property gives **no** compile-time checking: all four declaration variants compile, and a
/// misspelled adapter method is a runtime `<METHOD DOES NOT EXIST>` either way. The property is
/// narrowed below because it documents intent and helps a reader, not because it buys a check.
Class Example.BO.HttpManualEnvelope Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

/// Narrowed for the reader, not for the compiler -- see the header's last paragraph.
Property Adapter As EnsLib.HTTP.OutboundAdapter;

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Return $$$ERROR($$$GeneralError, "unhandled request type: " _ $classname(pRequest))
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.StringRequest">
    <Method>PostEnvelope</Method>
  </MapItem>
</MapItems>
}

/// POST a hand-built body and read the response by hand.
Method PostEnvelope(pRequest As Ens.StringRequest, Output pResponse As Ens.StringResponse) As %Status
{
    Set pResponse = ##class(Ens.StringResponse).%New()

    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.ContentType = "application/xml"
    Do tReq.EntityBody.Write(pRequest.StringValue)

    // THREE ARGUMENTS. pFormVarNames defaults to "" -- which is what a raw body needs -- and the URL
    // comes from the adapter's own setting, so the endpoint lives in the production rather than here.
    Set tResp = ""
    Set tSC = ..Adapter.SendFormDataArray(.tResp, "POST", tReq)
    If $$$ISERR(tSC) {
        Return tSC
    }

    // THE GUARD. On a failed send tResp is unset, and touching .StatusCode on it throws
    // <INVALID OREF> -- an error naming neither the adapter nor the endpoint.
    If '$IsObject(tResp) {
        Return $$$ERROR($$$GeneralError, "the adapter returned OK but no response object")
    }

    Set tStatus = tResp.StatusCode
    Set pResponse.StringValue = ..ReadBody(tResp)

    // A non-2xx is a failure even when the adapter's own %Status was OK.
    If (tStatus < 200) || (tStatus > 299) {
        Return $$$ERROR($$$GeneralError, "HTTP " _ tStatus _ ": " _ $Extract(pResponse.StringValue, 1, 200))
    }
    Return $$$OK
}

/// The whole body as a string.
///
/// `Rewind` first. Not because a first read fails -- measured, the adapter leaves the stream at the
/// start and a first read works -- but because ANYTHING that has already looked at the body (a trace,
/// a log line, a content-type sniff) leaves it at the end, and then a read without Rewind returns "".
/// It costs nothing and removes the ordering dependency.
ClassMethod ReadBody(pResponse As %Net.HttpResponse) As %String [ SqlProc ]
{
    If '$IsObject(pResponse) {
        Return ""
    }
    If '$IsObject(pResponse.Data) {
        // Data is %RawString on a response that carries no body -- not a stream. Reading it as one
        // throws <INVALID OREF>, which is why this is checked rather than assumed.
        Return pResponse.Data
    }
    Do pResponse.Data.Rewind()
    Set tOut = ""
    While 'pResponse.Data.AtEnd {
        Set tOut = tOut _ pResponse.Data.Read(32000)
    }
    Return tOut
}

/// A SOAP or JSON boolean, tested correctly.
///
/// The strings "true" and "false" both fail a numeric comparison: `"true"=1` is 0 AND `"false"=0` is
/// 0, and `+"true"` is 0. So neither polarity can be tested numerically and a `$Select` on the
/// numeric value takes the false branch for a true answer. Compare to the string, case-insensitively,
/// and accept the numeric forms a different serialiser might send.
ClassMethod IsTrue(pValue As %String) As %Boolean [ SqlProc ]
{
    Set tV = $ZConvert($ZStrip(pValue, "<>W"), "L")
    Return ((tV = "true") || (tV = "1") || (tV = "y") || (tV = "yes"))
}

}
