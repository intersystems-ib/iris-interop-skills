---
name: soap-bo
description: SOAP wizard BO, WSDL, %Persistent payloads, CDA. Routed from interop. Triggers: SOAP, WSDL, SOAP Wizard, web service, BO SOAP, %SerialObject, %Persistent payload, CDA, cliente SOAP.
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

When the WSDL declares a string type **without a length facet**, the wizard-generated property comes out as a **bounded `%String` with the default `MAXLEN=50`** — longer values are then **silently truncated** on save (no error). Always audit the generated payload classes after running the wizard and **widen** affected string properties to `%String(MAXLEN="")` (unbounded, ~3.6 MB ceiling) or `%Stream.GlobalCharacter` for large content. Same trap, longer treatment in `messages` (`%String` length section).

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
Trigger DeleteCascade [ Event = DELETE, Foreach = row/object ]
{
    Do ##class(MyApp.SOAP.PayloadType).%DeleteId({ID})
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

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/soap-wsdl-policyreference-fix.cls`.

### Vendor rejects `xsi:type` attributes

Even when types match the schema, some vendor SOAP servers (notably SAP and certain Spanish public-sector services) return errors when the request contains `xsi:type` attributes on element bodies.

**Fix**: `Parameter OUTPUTTYPEATTRIBUTE = 0;` on the generated SOAP client class. See `messages` for the same setting in the XML-projection context.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/soap-xsi-type-suppress.cls`.

### Drop `REQUIRED=1` flags on generated properties

Some vendor services accept SOAP messages with fewer fields than the WSDL declares as required. The IRIS-side validation refuses to send because a "required" field is missing — yet the vendor would have accepted the partial message.

**Fix**: drop `[ Required ]` (`REQUIRED=1` in CDL) from the affected generated properties. Document each one in the patch comments.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/soap-required-flag-drop.cls`.

### Strongly-typed dates / times — downgrade to `%String`

Where the WSDL declares `xs:date` or `xs:time` and the vendor server cannot actually parse the typed form (despite the WSDL claiming it does), change the generated property type to `%String`.

The transmitted lexical form (`2026-05-13` for date, `14:30:00` for time) is correct regardless — the IRIS-side type was forcing a normalization step the vendor couldn't reverse. With `%String`, the field passes through unchanged.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/soap-typed-dates-to-string.cls`.

### `RESPONSENAMESPACE` doesn't match what the vendor actually returns

The WSDL specifies one response namespace; the actual SOAP responses come back with a different one. Strict parsers reject the mismatch.

**Fix**: override `Parameter RESPONSENAMESPACE` on the generated proxy to the actual namespace the vendor returns. **General rule** for any SOAP integration: don't trust the WSDL blindly — capture an actual response (with `message-search-debug` SOAP tracing) and align the generated client to what's on the wire.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/soap-response-namespace-override.cls`.

### XML namespace alias must literally be `urn`

Vendor services occasionally return errors unless the SOAP envelope's namespace prefix is literally `urn` (not the default `s` or `soap` the wizard emits).

**Fix**: instantiate the SOAP client manually so the namespace prefix can be set explicitly before invocation. Same instantiation pattern as the SAML custom-header example (see `security` §"Custom security header on a generated SOAP BO").

### Generated classes ARE meant to be edited

The naming convention's reserved `<Pkg>.<SubPkg>.WSC<Name>` sub-package (see `interop` §"Naming convention") is partly motivated by these patches. Generated SOAP/XSD classes need to be **regeneratable in isolation** (delete the sub-package, re-run the wizard, re-apply patches) AND every patch needs to be applied each time.

Document every patch in the class header with a stable tag (e.g. `///PYD20260513:` prefix on each modified line) — a grep across the regenerated classes finds the patches to re-apply by tag, not by line position.

## SOAP tracing per BO

For diagnosing wire-level issues on a SOAP BO, use a per-BO `SoapLogFile` setting rather than the namespace-wide `^ISCSOAP("Log")` toggle. Each BO writes to its own log file path, settable at runtime from the portal — covered in `message-search-debug` §"Per-BO SOAP tracing".

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

The Portal's SOAP Wizard is just a UI over **`%SOAP.WSDL.Reader`**, and that class **is invocable headless via `iris_execute`** — there is no Portal-only restriction on the generation itself (only the REST API has no dedicated "wizard" endpoint). So in an MCP-only / headless workflow you do **not** have to hand-roll SOAP: drive the Reader directly when the WSDL is reachable at build time.

```objectscript
// Generate the SOAP client + payload classes from a WSDL — runs fine through iris_execute.
Set reader = ##class(%SOAP.WSDL.Reader).%New()
Set sc = reader.Process("http://host/path/Service.cls?WSDL", "Pkg.WSC.MyService")
If $$$ISERR(sc) { /* $System.Status.GetErrorText(sc) */ }
// -> compiles the client + request/response classes into package Pkg.WSC.MyService.
// Read the generated source with iris_doc(get); wrap the client in an Ens BO using
// EnsLib.SOAP.OutboundAdapter.
```

Verified on IRIS-for-Health 2026.1: `Process` is an **instance** method with signature
`Process(pLocationURL As %String, pPackage As %String = "", pTest As %Boolean = 0, schemaReader = "")`,
and there is also `GenerateService(pService, pNamespace, pPort, PackageName, ClientClassName, ServiceClassName)`
for the service-class variant. (Note: there is **no** `%SOAP.WSDL.Client` class — use `%SOAP.WSDL.Reader`.)

Caveats that make this genuinely fiddly (so it isn't always the easy win): the URL must be a real WSDL
**reachable from the IRIS server** (a non-WSDL response yields `ERROR #6411: Element 'definitions' or 'schema' is missing`), it usually needs Basic auth baked into the URL or a configured credential, the generated
classes carry the same vendor patches documented above (re-apply on regeneration), and `%SOAP.WebClient`
runtime faults surface as opaque `<ZSOAP> 64`.

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

- Web app config (Security.Applications): `AutheEnabled=96` (Password + Kerberos, accepts HTTP Basic) — **not** `4=Password` per the docs, which doesn't accept Basic in IRIS 2026.1. See `business-services` for the full table.
- The authenticated user must have **read access to the system globals** the SOAP framework touches (`^ISCSOAP`). Granting `%All` to the service user is the simplest workshop pattern; production should grant `%DB_<TARGET>_DATA:RW` plus enough on `IRISSYS` to read `^ISCSOAP`. The error `<PROTECT> OnPage+9^%SOAP.WebService.1 ^ISCSOAP("LogMaxFileSize")` is the symptom of missing this read access.
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

- REST endpoints (`EnsLib.REST.OutboundAdapter`) → see `business-operations`.
- WS-Security / WS-Addressing customization beyond what the wizard supports → docs.
- WCF / `.NET`-specific SOAP quirks → not workshop-validated.

## See also

- `messages` — payload class storage decisions live here too; SOAP envelopes carrying HL7 / CDA
- `business-operations` — generic BO patterns (non-SOAP destinations); HTTP-manual envelope fallback; settings checklist
- `unit-tests` — testing the generated BO methods
- `message-search-debug` — verifying end-to-end SOAP calls; per-BO SOAP tracing
- `security` — attaching SAML / WS-Security custom headers to the generated proxy
- `interop` — §"Naming convention" (generated-class sub-package, `WSC<Name>` pattern)
