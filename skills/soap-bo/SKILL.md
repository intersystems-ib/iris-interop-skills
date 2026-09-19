---
name: soap-bo
description: SOAP wizard BO, WSDL, %Persistent payloads, CDA. Triggers: SOAP, WSDL, SOAP Wizard, web service, BO SOAP, %SerialObject, %Persistent payload, CDA, cliente SOAP.
---

# SOAP Business Operations — Wizard-driven

For SOAP destinations, IRIS provides a **SOAP Wizard** that generates a Business Operation class plus request/response message classes from a WSDL. This is almost always the right starting point — hand-rolling SOAP serialization in IRIS is rarely worth the effort.

## When to use this skill

The user wants to call a SOAP web service from IRIS Interoperability, has a WSDL (URL or file), and needs the BO class + message types to wire into a production.

## How to invoke the wizard

Management Portal → **Interoperability → Build → SOAP Wizard** (or "Web Service Client Wizard" in some versions).

1. Provide the WSDL (URL or uploaded file).
2. Choose the package name where generated classes will land (e.g. `MyApp.SOAP.WeatherService`).
3. Confirm operation list — wizard generates one method per WSDL operation.
4. Select Business Operation generation (vs. plain web client) — yes for productions.

Output:
- A BO class extending `Ens.BusinessOperation` with one method per WSDL operation, plus `MessageMap` dispatch.
- One request class and one response class per operation, plus shared type classes.

### Export the generated classes to `src/` — the wizard writes only to the namespace

**The wizard is the largest single producer of namespace-only classes in this toolset.** One
WSDL yields the proxy, the BO, `WSC.*`, `SOAPENC.*`, and a request/response pair per operation
— none of which pass through disk. The PreToolUse source-of-truth gate cannot help here: it
watches `iris_doc(mode=put)`, and the wizard bypasses that entirely.

So the rule for generated code is the mirror image of the rule for hand-written code:

```
hand-written:  Write src/… .cls   →  iris_doc(mode=put)      (gate enforces this order)
generated:     run the wizard     →  iris_doc(mode=get)  →  Write src/… .cls
```

Immediately after the wizard runs, `iris_doc(mode=get)` **every** class it created and write it
to `src/` in the Atelier nested layout. Do it before you start patching them — the patches
below (`OUTPUTTYPEATTRIBUTE`, dropped `[ Required ]`, widened `MAXLEN`, the
`wsp:PolicyReference` removal) are exactly the edits you cannot afford to lose, and they are
invisible to anyone reading the WSDL.

Measured on a workshop VM: 28 classes on disk, 29 in IRIS, only 22 in common — with drift in
**both** directions, including generated SOAP classes that existed on disk but no longer in the
namespace. See `production-lifecycle` for the `DriftReport` check.

## Review the generated payloads — the `MAXLEN=50` truncation trap

When the WSDL declares a string type **without a length facet**, the wizard-generated property comes out as a **bounded `%String` with the default `MAXLEN=50`** — and a longer value is **rejected on save with `ERROR #7201`**, not silently truncated (measured on 2026.1 across `%Save`, `%ValidateObject` and SQL `INSERT`; the in-memory value is never shortened). Always audit the generated payload classes after running the wizard and **widen** affected string properties to `%String(MAXLEN="")` (unbounded, ~3.6 MB ceiling) or `%Stream.GlobalCharacter` for large content. Same trap, longer treatment in `messages` (`%String` length section), including what the measurement does and does not cover.

## Storage decision: %SerialObject vs %Persistent for payloads

> The general rule for **any** object property inside a message — not just wizard output — lives in
> `messages` (**Complex properties**): `%SerialObject` by default, `%Persistent` only for a reason,
> and a delete cascade whenever it is `%Persistent`. This section is the SOAP-specific slice.

The wizard generates payload classes (the WSDL types). By default these are `%SerialObject` — embedded inside the carrying request/response, no separate storage. **Change to `%Persistent` when:**

| Symptom / situation | Use %Persistent + delete trigger |
|---|---|
| Payload contains recursive structures (e.g. CDA `<section>` containing `<section>` containing `<section>`) | YES |
| Payload is large (>100KB serialized) and you'll be retaining many | YES |
| You want to query message bodies by property in `message-search-debug` | YES |
| Simple flat payload, low volume, no recursion | NO — `%SerialObject` is fine |

### Why the recursion case matters

`%SerialObject` serializes inline. For a deeply recursive structure (CDA documents are the worst offender — sections containing sections, entries containing components containing entries), the serialized form blows up `Ens.MessageBodyD` and inflates retention storage in ways that don't free cleanly. Switching the recursive payload class to `%Persistent` gives each instance its own table and storage; the parent message references them by ID.

### The delete trigger

When a payload class is `%Persistent`, it has a separate row from its carrier. When the carrier message is purged (via Ens purge schedules), the payload **does not auto-delete** — you'll leak rows forever. Add a delete trigger:

```objectscript
/// On the CARRIER. {Payload} is the carrier's reference property — the column holding the
/// payload's id. NOT {ID}: inside a trigger {ID} is the row being deleted, i.e. the CARRIER's
/// own id, so %DeleteId({ID}) deletes whichever payload happens to share that id — an
/// unrelated row, or none. It leaks exactly what the trigger was added to clean up, and
/// silently, because deleting nothing raises nothing.
Trigger DeleteCascade [ Event = DELETE, Foreach = row/object ]
{
    Do ##class(MyApp.SOAP.PayloadType).%DeleteId({Payload})
}
```

Or, equivalently, override `%OnDelete` on the carrier to clean up the payload references explicitly. **The wizard does NOT generate this for you** — you have to add it after switching to `%Persistent`. That is the SOAP-specific trap: the rest of the reasoning, and the reference-property form of the trigger, are in `messages`.

## Properties on the carrier vs the payload

Add business properties to the **payload class**, not the wizard-generated carrier. The wizard regenerates carriers when you re-import a WSDL — anything on the carrier is overwritten. Payload classes are also regenerated, but the recursion you're guarding against is the persistence pattern, not custom properties; if you need custom properties, subclass the payload.

## WSDL gotchas — patches to apply on nearly every vendor WSDL

When you import a vendor WSDL, the wizard-generated classes almost always need at least one of these patches. None of them are bugs in IRIS per se — they're vendor-specific deviations from the SOAP standard that the wizard reproduces faithfully and the receiver then rejects.

The wizard-generated classes **are meant to be edited**. Document every patch you apply (header comment with a date tag like `///PYD20260513:` on each modified line) so the next regeneration of the WSDL can re-apply them by greppable diff.

### `wsp:PolicyReference` compile failure (#6447)

**Symptom**: the generated `*HTTPPortConfig` class fails to compile with `ERROR #6447: Unexpected element wsp:PolicyReference in WS-Policy namespace inside %SOAP.Configuration XData block`.

**Fix** — any of:

- Add `Parameter REPORTANYERROR = 0;` to the offending class and rename the `…Config` class to `…ConfigBACKUP`.
- Strip the `<wsp:PolicyReference/>` block from the WSDL before regenerating.
- Delete the generated `XData OnConfigurationCompile` block.

The WS-Policy assertion is not used at runtime by the IRIS client — the actual TLS / signing policy is configured separately on the BO (SSL config setting, credentials, etc.). The XData block is dead weight that happens to break compilation.

Worked example: `assets/soap-wsdl-policyreference-fix.cls`.

### Vendor rejects `xsi:type` attributes

Even when types match the schema, some vendor SOAP servers (notably SAP and certain Spanish public-sector services) return errors when the request contains `xsi:type` attributes on element bodies.

**Fix**: `Parameter OUTPUTTYPEATTRIBUTE = 0;` on the generated SOAP client class. See `messages` for the same setting in the XML-projection context.

Worked example: `assets/soap-xsi-type-suppress.cls`.

### Drop `REQUIRED=1` flags on generated properties

Some vendor services accept SOAP messages with fewer fields than the WSDL declares as required. The IRIS-side validation refuses to send because a "required" field is missing — yet the vendor would have accepted the partial message.

**Fix**: drop `[ Required ]` (`REQUIRED=1` in CDL) from the affected generated properties. Document each one in the patch comments.

Worked example: `assets/soap-required-flag-drop.cls`.

### Strongly-typed dates / times — downgrade to `%String`

Where the WSDL declares `xs:date` or `xs:time` and the vendor server cannot actually parse the typed form (despite the WSDL claiming it does), change the generated property type to `%String`.

The transmitted lexical form (`2026-05-13` for date, `14:30:00` for time) is correct regardless — the IRIS-side type was forcing a normalization step the vendor couldn't reverse. With `%String`, the field passes through unchanged.

Worked example: `assets/soap-typed-dates-to-string.cls`.

### `RESPONSENAMESPACE` doesn't match what the vendor actually returns

The WSDL specifies one response namespace; the actual SOAP responses come back with a different one. Strict parsers reject the mismatch.

**Fix**: override `Parameter RESPONSENAMESPACE` on the generated proxy to the actual namespace the vendor returns. **General rule** for any SOAP integration: don't trust the WSDL blindly — capture an actual response (with `message-search-debug` SOAP tracing) and align the generated client to what's on the wire.

Worked example: `assets/soap-response-namespace-override.cls`.

### XML namespace alias must literally be `urn`

Vendor services occasionally return errors unless the SOAP envelope's namespace prefix is literally `urn` (not the default `s` or `soap` the wizard emits).

**Fix**: instantiate the SOAP client manually so the namespace prefix can be set explicitly before invocation. Same instantiation pattern as the SAML custom-header example (see `security` §"Custom security header on a generated SOAP BO").

### Generated classes ARE meant to be edited

The naming convention's reserved `<Pkg>.<SubPkg>.WSC<Name>` sub-package (see `interop` §"Naming convention") is partly motivated by these patches. Generated SOAP/XSD classes need to be **regeneratable in isolation** (delete the sub-package, re-run the wizard, re-apply patches) AND every patch needs to be applied each time.

Document every patch in the class header with a stable tag (e.g. `///PYD20260513:` prefix on each modified line) — a grep across the regenerated classes finds the patches to re-apply by tag, not by line position.

## SOAP tracing per BO

For diagnosing wire-level issues on a SOAP BO, use a per-BO `SoapLogFile` setting rather than the namespace-wide `^ISCSOAP("Log")` toggle. Each BO writes to its own log file path, settable at runtime from the portal — covered in `message-search-debug` §"Per-BO SOAP tracing".

## Canonical pattern — the SOAP BO class

The wizard generates the *client* (`Pkg.WSC.*`); it does **not** generate the Business Operation.
You write that, and it is an ordinary `Ens.BusinessOperation` whose adapter is the typed SOAP one:

```objectscript
Class MyApp.BO.WeatherService Extends Ens.BusinessOperation
{
Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter";
Parameter INVOCATION = "Queue";

/// Re-declare Adapter with the concrete type so `..Adapter.<method>` resolves to the
/// adapter's own API instead of the generic Ens.OutboundAdapter.
Property Adapter As EnsLib.SOAP.OutboundAdapter;

Method GetForecast(pReq As MyApp.SOAP.WeatherService.GetForecastRequest,
                   Output pResp As MyApp.SOAP.WeatherService.GetForecastResponse) As %Status
{
    Set tClient = ##class(MyApp.WSC.WeatherService).%New()
    Set tClient.Location = ..Adapter.WebServiceURL   // adapter owns the endpoint + credentials
    // ... invoke the generated client method, map its result onto pResp ...
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="MyApp.SOAP.WeatherService.GetForecastRequest">
    <Method>GetForecast</Method>
  </MapItem>
</MapItems>
}
}
```

> **Compiled example, and the alternative this fence does not show.** The snippet above hardcodes the
> generated client (`##class(MyApp.WSC.WeatherService).%New()`), which gives you its **typed methods**
> but puts the class name in code. The adapter also carries a `WebServiceClientClass` **setting** —
> see `security` — which puts the name in the production instead, at the cost that `..Adapter.%Client`
> is typed `%SOAP.WebClient` and the generated operations go late-bound through `$METHOD`. Neither is
> wrong; know which you picked. The configuration form is compiled and tested at
> `assets/soap-bo-typed-adapter.cls`, with its two
> message siblings and §6.16. Also measured there: `WebServiceURL` defaults to the **literal string**
> `"<default>"`, so a `= ""` guard never fires.

**`Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter";` is the line that makes this a SOAP BO.**
Extending the adapter directly instead yields an empty, non-functional component — and a
PreToolUse gate blocks that put (see `component-map` for the task→component map). Take the
endpoint, credentials and timeout from the adapter's settings rather than hard-coding them in the
generated client; that is the whole reason for using the typed adapter over a bare
`%SOAP.WebClient`.

## Canonical pattern — calling the SOAP BO

```objectscript
// In a BPL or a calling method
Set tReq = ##class(MyApp.SOAP.WeatherService.GetForecastRequest).%New()
Set tReq.City = "Madrid"
Set tSC = ..SendRequestSync("BO_WeatherService", tReq, .tResp)
If $$$ISERR(tSC) Quit tSC
Set tForecast = tResp.GetForecastResult
```

Sync vs Async: SOAP calls are usually synchronous (you want the response). But if the BP doesn't need the response immediately, Async + a callback pattern keeps pool slots free.

## Common pitfalls

- **Treating `%SerialObject` payloads as universally fine** → recursive CDA payloads bloat or break.
- **Forgetting the delete trigger** when switching to `%Persistent` → orphaned payload rows, eternal storage growth.
- **Adding properties on the wizard-generated carrier** → overwritten on next WSDL re-import.
- **No timeout on the SOAP outbound** → a hung remote endpoint blocks the BO pool indefinitely.
- **Hardcoded WSDL URL in code** → use a setting (`SOAPClient.Endpoint` or similar) so DEV/TEST/PROD differ.
- **Re-running the SOAP Wizard over modified generated classes** → wipes your changes. If you've customized, either don't re-run or use a subclass for customizations.
- **`EnableStandardRequests` set on `Target="Host"`** → Portal accepts it silently; runtime fails with `<Ens>ErrSOAPNotEnabled`. The setting belongs on `Target="Adapter"` (see the production-item section below).
- **Parsing a SOAP boolean with `=1`** → SOAP serialises booleans as `true`/`false`; the test is false for every response, silently. Compare against `"true"`.

## Testing / how to verify

1. Compile the generated classes via the MCP server. WSDL ambiguities surface as compile errors.
2. **Inside the wizard's Test page** → invoke each operation with sample input. Confirms the BO can reach the endpoint and parse the response.
3. From a unit test (`unit-tests`), invoke the BO method directly with a constructed request. Stub the endpoint with a local mock if the real endpoint isn't reachable.
4. Use `message-search-debug` to confirm Visual Trace shows the request → response cycle correctly when the BO is called from a BP.

## Headless WSDL→client generation (no Portal UI)

> **There is no `%SOAP.WSDL.Client` class. The class is `%SOAP.WSDL.Reader`.**
> `##class(%SOAP.WSDL.Client)` **compiles clean** and dies at the first call with
> `<CLASS DOES NOT EXIST> … *%SOAP.WSDL.Client`, so a clean compile is not evidence you named it right.

The Portal's SOAP Wizard is just a UI over **`%SOAP.WSDL.Reader`**, and that class **is invocable headless via `iris_execute`** — there is no Portal-only restriction on the generation itself (only the REST API has no dedicated "wizard" endpoint). So in an MCP-only / headless workflow you do **not** have to hand-roll SOAP: drive the Reader directly when the WSDL is reachable at build time.

```objectscript
// Generate the SOAP client + payload classes from a WSDL — runs fine through iris_execute.
Set reader = ##class(%SOAP.WSDL.Reader).%New()
// MakeBusinessOperation defaults to 0: you get the proxy client and nothing else. Set it to 1 and the
// Reader also generates a Business Operation plus an Ens.Request/Ens.Response pair per operation —
// which is the point of doing this inside an interop project at all.
Set reader.MakeBusinessOperation = 1
Set sc = reader.Process("http://host/path/Service.cls?WSDL", "Pkg.WSC.MyService")
If $$$ISERR(sc) { /* $System.Status.GetErrorText(sc) */ }
// Read the generated source with iris_doc(get) and commit it — these are generated classes, and the
// filesystem is still the source of truth.
//
// WHAT LANDS WHERE, measured on a one-operation WSDL (deliverable §6.20):
//   MakeBusinessOperation = 0 ->  Pkg.<Svc>Soap          %SOAP.WebClient
//                                 Pkg.<Svc>Soap.<Op>     %SOAP.ProxyDescriptor
//   MakeBusinessOperation = 1 ->  the two above, PLUS a BusOp SUB-PACKAGE:
//                                 Pkg.BusOp.<Svc>Soap    Ens.BusinessOperation
//                                 Pkg.BusOp.<Op>Request  Ens.Request
//                                 Pkg.BusOp.<Op>Response Ens.Response
// pLocationURL also accepts a LOCAL FILE PATH, which is what makes this testable with no endpoint up.
```

Verified on IRIS-for-Health 2026.1: `Process` is an **instance** method with signature
`Process(pLocationURL As %String, pPackage As %String = "", pTest As %Boolean = 0, schemaReader As %XML.Utils.SchemaReader = "")`,
and there is also `GenerateService(pService, pNamespace, pPort, PackageName, ClientClassName, ServiceClassName)`
for the service-class variant.

**What `MakeBusinessOperation = 1` adds, with the DEFAULT packages** — measured property defaults on
2026.1, not a promise about names you can also change:

| Reader property | default | what it controls |
|---|---|---|
| `MakeClient` | `1` | the proxy client class |
| `MakeBusinessOperation` | **`0`** | the BO + request/response pair |
| `BusinessOperationPackage` | `"BusOp"` | where the BO lands |
| `RequestPackage` / `ResponsePackage` | `"Request"` / `"Response"` | where the message classes land |
| `MakeService` / `MakeEnsembleClasses` | `0` / `0` | server-side and Ensemble extras, both off |
| `HttpRequest` | `""` | the `%Net.HttpRequest` used to FETCH the WSDL — see Trap 1 below |

So with `Pkg.WSC.MyService` as the package you get `Pkg.WSC.MyService.BusOp.*`, `…Request.*` and
`…Response.*` unless you set those three properties. Because the packages are settable, treat the names
as defaults rather than as the contract.

Caveats that make this genuinely fiddly (so it isn't always the easy win): the URL must be a real WSDL
**reachable from the IRIS server** (a non-WSDL response yields `ERROR #6411: Element 'definitions' or 'schema' is missing`), it usually needs Basic auth baked into the URL or a configured credential, the generated
classes carry the same vendor patches documented above (re-apply on regeneration), and `%SOAP.WebClient`
runtime faults surface as opaque `<ZSOAP> 64`.

**Trap 1 — an unauthenticated fetch of a CSP-hosted WSDL returns HTTP 200, not 401.** A
password-protected CSP app answers **200 with the login page** and no `WWW-Authenticate` header, so the
Reader parses HTML and you get `ERROR #6301: SAX XML Parser Error: expected entity name for reference`
— which reads as a malformed WSDL and is not one. Measured on 2026.1 against a real WSDL behind
`/csp/healthshare/fhirtest` (`AutheEnabled` 8224, no unauthenticated bit): `code=200`,
`ctype=text/html`, `wwwauth=""`, a `<title>Login IRIS</title>` body carrying four bare `&`, and
`Process` failing `#6301` at line 10. Read the two errors as the different things they are:

| error | means |
|---|---|
| `#6301 … expected entity name for reference` | the body is **not XML at all** — almost always a login page |
| `#6411 Element 'definitions' or 'schema' is missing` | the body **is** XML, but it is not a WSDL |

The fix is to hand the Reader a request that carries credentials:

```objectscript
Class MyApp.UTL.WsdlFetch Extends %RegisteredObject
{

/// Generate from a WSDL that sits behind Basic auth. Credentials go on the HttpRequest the Reader
/// uses to FETCH the WSDL -- never in the URL (see below).
ClassMethod Generate(pUrl As %String, pPackage As %String, pUser As %String, pPwd As %String) As %Status
{
    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Username = pUser
    Set tReq.Password = pPwd

    Set tReader = ##class(%SOAP.WSDL.Reader).%New()
    Set tReader.HttpRequest = tReq              // the Reader fetches the WSDL through THIS request
    Set tReader.MakeBusinessOperation = 1
    Quit tReader.Process(pUrl, pPackage)
}

}
```

Measured: that returns the WSDL and `Process` succeeds. `%Net.HttpRequest` sends the Basic header on
the **first** request whenever `Username` is set, so there is no need to set `InitiateAuthentication`
yourself. **Do not put credentials in the URL** — `&IRISUsername=…&IRISPassword=…` measures as *still*
returning the login page and *still* failing `#6301`: those are the login form's field names, not a GET
credential channel. Note the scope — this is **build-time WSDL retrieval**, not the runtime SOAP call;
the anti-pattern further down about credentials on the call itself still stands.

**Trap 2 — a disabled or password-expired account fails identically**, because the login page is what
comes back either way. Check the account, not the URL: `##class(Security.Users).Get(user, .info)` then
`info("Enabled")`. Re-enable with `Set props("Enabled") = 1` and
`##class(Security.Users).Modify(user, .props)` — and **do not put a `Roles` subscript in that array**: measured, `Modify` REPLACES the role list rather than adding to it, and returns `$$$OK` either way. With only `Enabled` set the roles are untouched. To add a role use `AddRoles` (see `security`). `ChangePassword` is a **property**, not a method, and
assigning `usr.Password` raises `<CANNOT SET THIS PROPERTY>`.

### When to fall back to HTTP-manual envelope instead

When the WSDL is **not reachable at build time**, or you want full wire visibility / debuggability, skip the
Reader and **use `EnsLib.HTTP.OutboundAdapter` + a hand-crafted SOAP envelope** (covered in `business-operations`).

| | `%SOAP.WSDL.Reader` (generate) | HTTP-manual envelope |
|---|---|---|
| Strongly-typed request/response classes | ✓ generated | ✗ build XML/parse XML by hand |
| Native credential / SSL settings on the client | ✓ | ✗ wire Basic/SSL by hand on the adapter |
| Headless / MCP-invocable | ✓ (`iris_execute` → `%SOAP.WSDL.Reader`) | ✓ |
| Needs the WSDL reachable at build time | yes | no |
| Visibility into wire | poor (`%SOAP.WebClient` hides everything) | full (you write the bytes) |
| Debuggability when remote returns 4xx/5xx fault | hard (`<ZSOAP> 64`, no detail) | easy (read response body, see fault XML) |
| Maintenance burden when WSDL evolves | re-run the Reader, may overwrite customizations | hand-edit the envelope |

Generate from the WSDL for stable, long-term services where the WSDL is reachable and you want the typed
classes + native credential/SSL settings. Use HTTP-manual for: unreachable-at-build-time WSDLs, quirky WSDLs
the stack chokes on, or any case where `%SOAP.WebClient` gives `<ZSOAP> 64` and you can't tell why. **Do not**
fall back to hand-injecting an `Authorization: Basic` header by reaching into `..Adapter.%CredentialsObj` —
that's the anti-pattern this section exists to prevent; either generate the client (native `Credentials`) or
set the adapter's `Credentials`/`SSLConfig` settings. Document the choice in the project's decision log.

### HTTP-manual client details that each cost a debug cycle

Verified in a real integration using the hand-crafted-envelope pattern:

- **SOAP booleans arrive as the literal strings `true`/`false`, not `1`/`0`.** Code that parses
  the response by hand and tests `=1` silently treats **every** response as false. Compare
  against `"true"`, or map to an IRIS boolean at the parse boundary.
- `EnsLib.HTTP.OutboundAdapter.SendFormDataArray(.resp, "POST", httpReq, "", , url)` sends the
  `%Net.HttpRequest`'s `EntityBody` as a **raw body** when `pFormVarNames=""` — that's how you
  POST the envelope through the adapter.
- The SOAPAction of an IRIS `%SOAP.WebService` is `{namespace}/{fullClassName}.{method}` — the
  target namespace, a slash, then the fully-qualified class name, dot, method name.
- Read the response with `tResp.Data.Rewind()` then `tResp.Data.Read()` — without the rewind the
  stream reads empty.

## Server-side: hosting a SOAP service in an IRIS namespace

When you're on the **other side** — exposing a SOAP service that an external client (or a sibling IRIS namespace) will call — `%SOAP.WebService`:

- Web app config (Security.Applications): `AutheEnabled=32` — `32` is the password (Instance Authentication) bit, the one HTTP Basic exercises. `4` is **Kerberos** (`AutheK5API`), not password, and answers `Negotiate` rather than `Basic`; `96` is `32+64` and also admits unauthenticated callers, so use it only when anonymous access is intended. See `business-services` for the bit table.
- The authenticated user must have **read access to the system globals** the SOAP framework touches (`^ISCSOAP`). The error `<PROTECT> OnPage+9^%SOAP.WebService.1 ^ISCSOAP("LogMaxFileSize")` is the symptom of missing it. **Do not grant `%All` to reach it** — not even in a workshop. `%All` is instance superuser, and a service account is the one principal an external caller controls the credentials of. Three resources cover it: `U` on the web application, `RW` on `%DB_<NAMESPACE>`, and `R` on `%DB_IRISSYS`. `security` has the compiled recipe, and the reason the shortcut looks necessary is usually that the **anonymous** principal was given `%All` first — fix that end, not this one.
- `Parameter SERVICENAME` and `Parameter NAMESPACE` (the XML target namespace) drive the WSDL. They must match what clients expect from `<service name>` and `targetNamespace` respectively.

### Registering the service as a production item — two silent misconfigurations

- **`EnableStandardRequests` goes on target `Adapter`, not `Host`:**

  ```xml
  <Setting Target="Adapter" Name="EnableStandardRequests">1</Setting>
  ```

  The Portal accepts the `Target="Host"` misconfiguration silently; the first call then fails at
  runtime with `ERROR <Ens>ErrSOAPNotEnabled: Adapter Setting EnableStandardRequests is not set`
  — an error that names the setting but **not** the target it belongs on.

- **The SOAP item's Name must equal the FQCN of the web-service class**
  (`MyApp.WS.OperationWebService`, not `BS.X`) — URL dispatch resolves the production item by
  class name, so a `Tipo.Nombre`-style name breaks WSDL resolution. Same rule as `component-map`
  states it: *production item Name = class FQCN or the WSDL won't resolve*.

## When NOT to use this skill — fall back to docs

- REST endpoints (`EnsLib.HTTP.OutboundAdapter` — there is no `EnsLib.REST.OutboundAdapter`) → see `business-operations`.
- WS-Security / WS-Addressing customization beyond what the wizard supports → docs.
- WCF / `.NET`-specific SOAP quirks → not workshop-validated.

## See also

- `messages` — payload class storage decisions live here too; SOAP envelopes carrying HL7 / CDA
- `business-operations` — generic BO patterns (non-SOAP destinations); HTTP-manual envelope fallback; settings checklist
- `unit-tests` — testing the generated BO methods
- `message-search-debug` — verifying end-to-end SOAP calls; per-BO SOAP tracing
- `security` — attaching SAML / WS-Security custom headers to the generated proxy
- `interop` — §"Naming convention" (generated-class sub-package, `WSC<Name>` pattern)
