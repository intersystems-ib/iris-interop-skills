# REST and CSP inbound

`EnsLib.REST.Service`, the adapter-less Business Service used as a CSP/REST entry point, and the web-application permissions an inbound endpoint needs. Read this only when the inbound is HTTP.

## Contents

- REST inbound — `EnsLib.REST.Service`
- REST/CSP entry point: Business Service **without an adapter**
- CSP/Web app permissions for inbound endpoints

## REST inbound — `EnsLib.REST.Service`

For a JSON REST endpoint that feeds a production (e.g. `POST /demo/preauth`), subclass `EnsLib.REST.Service` (it is BOTH a `%CSP.REST` and an `Ens.BusinessService`). Skeleton:

```objectscript
Class App.BS.Preauth Extends EnsLib.REST.Service
{
Parameter ADAPTER = "EnsLib.HTTP.InboundAdapter";   // listens on its own Port
Parameter SETTINGS = "TargetConfigName:Basic";
Property TargetConfigName As %String [ InitialExpression = "BP.Preauth" ];

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{ <Routes><Route Url="/demo/preauth" Method="POST" Call="Preauth"/></Routes> }

Method Preauth(pInput As %Stream.Object, Output pOutput As %Stream.Object) As %Status
{
  Set tJSON = ##class(%DynamicObject).%FromJSON(pInput)
  Set tReq = ##class(App.MSG.PreauthRequest).%New()
  Set tReq.Dni = tJSON.%Get("dni")                       // %Get, NOT tJSON.dni
  Set tSC = ..SendRequestSync(..TargetConfigName, tReq, .tResp)   // instance method!
  Quit:$$$ISERR(tSC) tSC
  Set tOut = ##class(%DynamicObject).%New()
  Do tOut.%Set("estado", tResp.Estado)                   // %Set, NOT tOut.estado
  Set pOutput.Attributes("Content-Type") = "application/json; charset=UTF-8"
  Do tOut.%ToJSON(pOutput)                                // write to the GIVEN pOutput
  Quit $$$OK
}
}
```

Five non-obvious rules (each cost a debug cycle):
- **Write to the `pOutput` the framework passes in — do NOT `Set pOutput = ##class(%GlobalBinaryStream).%New()`.** Rebinding the local variable orphans the framework's response stream; the HTTP reply comes back `200` with an **empty body**.
- **The route handler runs as an INSTANCE method of the service host** (`EnsLib.REST.Service` dispatches no-class-prefix routes via `$method($this,...)`), so `..SendRequestSync(target, req, .resp)` to a BP/BO works directly inside it.
- **`%DynamicObject` keys with underscores need `%Get`/`%Set`** — `tJSON.codigo_acto` parses as `tJSON.codigo _ acto` (the `_` is the concat operator) and breaks compilation. Use `tJSON.%Get("codigo_acto")`.
- **Exposure:** with `EnsLib.HTTP.InboundAdapter` the service listens on its own `Port` (clean URL `http://host:PORT/demo/preauth`). Via the **CSP gateway** (web app `DispatchClass=App.BS.Preauth`) `EnsLib.REST.Service` requires `?CfgItem=<configItemName>` appended to the URL (stated in the class doc-comment) — a wart; prefer the InboundAdapter port unless you must go through the gateway. BS is tested from outside (curl), not from inside IRIS.
- **`ErrHTTPConfigName` = the dispatcher can't resolve a config item by that name.** Through the CSP gateway, the `?CfgItem=<name>` (or the URL segment) **must exactly match the production item Name** of the REST service. Renaming the item (e.g. from `BS.PacientesREST` to `pacientes`) without updating the caller's URL — or vice-versa — yields `ErrHTTPConfigName` and a 500. Keep the item Name and the dispatch name in lockstep; this single mismatch is a notorious repeat-offender across separate debugging passes.


## REST/CSP entry point: Business Service **without an adapter**

When the BS is invoked from REST/CSP code (an `%CSP.REST` handler, a custom CSP page, etc.) rather than from a transport adapter, the pattern is a custom BS class with **no adapter at all**:

```objectscript
/// The request this endpoint accepts. Declared in the SAME fence as the service so the pair is a
/// complete compilation unit — with the class referenced but never shown, the gate could only
/// report the service as a placeholder dependency and never actually compile it.
/// `%Persistent` is leftmost deliberately: see `messages` §"Why `%Persistent` must be leftmost".
Class MyApp.MSG.SomeRequest Extends (%Persistent, Ens.Request)
{
Property Payload As %String(MAXLEN = 4096);
}

Class MyApp.BS.RestEntry Extends Ens.BusinessService
{
Parameter ADAPTER;
Parameter SERVICEINPUTCLASS = "MyApp.MSG.SomeRequest";
Parameter SERVICEOUTPUTCLASS = "Ens.Response";

Method OnProcessInput(pInput As MyApp.MSG.SomeRequest, Output pOutput As Ens.Response) As %Status
{
    Set pOutput = ##class(Ens.Response).%New()
    Set tSC = ..SendRequestAsync("Router.MyRouter", pInput)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}
}
```

Declared in the production XML with `PoolSize="0"` (no scheduled actor — the REST handler creates an instance on demand via `Ens.Director.CreateBusinessService("BS.RestEntry", .bs)` and calls `bs.ProcessInput(req, .resp)` directly).

`PoolSize="0"` + no adapter = "passive" BS: it doesn't poll anything, it sits in the production as a dispatch point with Visual Trace coverage. This is the canonical pattern for REST inbound, message-queue consumers that already dispatch from outside Ens, or anything where the source isn't an Ens-supported transport.

## CSP/Web app permissions for inbound endpoints

When you create a CSP/REST web app to front a BS (or to expose a SOAP service that a BO calls):

| Setting | Value | Why |
|---|---|---|
| `AutheEnabled` | **32** — or **96** only when anonymous access is intended | Bitmask, not a menu index. `32` = password (Instance Authentication), and it is the bit HTTP Basic exercises, so `Authorization: Basic ...` is honoured with `32` alone. `96` = `64 + 32` = password **plus unauthenticated**: with bit `64` set, IRIS first runs the request as `UnknownUser` and only challenges if that user lacks the privileges the endpoint needs — so at `96` whether an anonymous caller gets in depends on `UnknownUser`'s roles, not on this setting. `97` = `96 + 1` does not make it stricter: bit `1` is `AutheK5CCache` (a Kerberos credential cache) and is not among the bits `Security.Applications` lists for a web app. |
| `DispatchClass` | Your `%CSP.REST` impl | For REST web apps |
| `NameSpace` | Target namespace | Where the dispatch class lives |

**The bits, from `%sySecurityMacros.inc` and `Security.Applications`' own class reference:**

| Bit value | Method |
|---|---|
| 1 | `AutheK5CCache` (Kerberos credential cache) |
| 2 | `AutheK5Prompt` (Kerberos, prompt) |
| **4** | `AutheK5API` — **Kerberos**, not password |
| 8 | `AutheK5KeyTab` |
| 16 | `AutheOS` |
| **32** | `AuthePassword` — Instance Authentication, the bit Basic uses |
| **64** | `AutheUnauthenticated` |
| 2048 | `AutheLDAP` |
| 8192 | `AutheDelegated` |

*General Installation Details* §5.2.4 publishes three of them — "commonly used values are 4=`Kerberos`,
32=`password`, and 64=`unauthenticated`" — and `Security.Applications` documents which bits are legal on
a web app (2, 5, 6, 11, 13, 14, 20, 21 → 4, 32, 64, 2048, 8192, 16384, 1048576, 2097152). Its
`AutheEnabled` **InitialExpression is 64**, i.e. a web app created with defaults is unauthenticated.

**What each value actually does to an unauthenticated request**, measured on 2026.1:

| `AutheEnabled` | unauthenticated GET |
|---|---|
| `32` | **401**, always |
| `96` / `97` | **401 only while `UnknownUser` lacks the privilege** the endpoint needs. Grant that user a role and the same URL answers 200 — so `96` cannot be relied on to protect anything. A CSP *page* returns the HTML login form at status 200 rather than a 401; a `%CSP.REST` dispatch class returns a real 401 (with `OPTIONS` still 200, which is `%CSP.REST.Login`'s documented shape). |

Read it back rather than trusting the Portal:
`##class(Security.Applications).Get(path, .props)`.

A guard like `If $USERNAME = "UnknownUser"` inside the dispatch class is not a substitute — it is lost
the moment `%REST.API.CreateApplication` regenerates `disp.cls`.

**The observation that `4` gets you a login form instead of honouring Basic is real** — but the reason
is that `4` is Kerberos (`AutheK5API`), which answers `Negotiate`, not `Basic`. It was never the
"documented password value".
| `Path` | `<InstallDir>csp\<webappname>\` | CSP routing filesystem mapping |

**Smoke test pattern**: `curl -u user:pwd <URL>` must return **data** (JSON / XML payload), not an HTML login form. If you get the login form, the web app's `AutheEnabled` is wrong (or the user lacks resources on the target namespace).

