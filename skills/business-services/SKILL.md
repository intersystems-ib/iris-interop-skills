---
name: business-services
description: BS inbound - File, TCP, SOAP, REST, Record Mapper CSV. Routed from interop. Triggers: Business Service, BS, inbound, File Service, RecordMap, CSV, REST inbound, TCP/MLLP, leer fichero, servicio de entrada, adapterless.
---

# Business Services — inbound entry points

A Business Service is the boundary where external data enters a production. One BS = one source (one TCP port, one directory, one FTP location). One HL7 BS handles one schema version.

## When to use this skill

The user wants to receive data from the outside world: read files, accept TCP connections, expose a REST endpoint, consume from a queue, etc.

## Decision tree

```
What's the input?
├── HL7 v2.x over TCP/MLLP → EnsLib.HL7.Service.TCPService
├── HL7 v2.x in files → EnsLib.HL7.Service.FileService (or FTPService)
├── SOAP / REST → use the SOAP wizard or EnsLib.REST.* base classes
├── CSV or flat structured non-HL7 file → use Record Mapper, NOT a hand-rolled parser
├── Custom protocol → custom BS extending Ens.BusinessService + appropriate adapter
└── No external trigger (scheduled / on-demand) → BS with no adapter, called via Ens.Director
```

**Record Mapper is the right tool for CSV/flat files.** Do not write a custom parser unless the format is genuinely unmappable (e.g. binary, mixed-record, deeply hierarchical).

## Canonical pattern — custom BS skeleton

```objectscript
Class MyApp.BS.PatientCensusFromCSV Extends Ens.BusinessService
{
Parameter ADAPTER = "EnsLib.RecordMap.Service.FileService";
Parameter SETTINGS = "TargetConfigNames:Basic,RequiredField:Basic";

Property TargetConfigNames As %String(MAXLEN=1000);
Property RequiredField As %String;

Method OnInit() As %Status
{
    // Validate required settings — fail loud at startup, not at first message
    If $$$ISERR(..ValidateSettings()) Quit $$$ERROR($$$EnsErrGeneral, "missing settings")
    Quit $$$OK
}

Method OnProcessInput(pInput As EnsLib.RecordMap.Base, Output pOutput As %RegisteredObject) As %Status
{
    Set tRequest = ##class(MyApp.Msg.PatientCensusRequest).%New()
    // populate tRequest from pInput
    Quit ..SendRequestAsync(..TargetConfigNames, tRequest)
}
}
```

### `OnProcessInput`'s signature is fixed by the base class — there is not one shape

The skeleton above is the **RecordMap / File** shape. Other base classes require a different argument
list, and the compiler rejects anything else outright:

```
ERROR #5478: Keyword signature error in MyApp.BS.PacientesREST:Method:OnProcessInput,
keyword 'method argument/s signature' must be
'%Library.RegisteredObject,%Library.RegisteredObject,%Library.String' or its subclass
  > ERROR #5030: An error occurred while compiling class 'MyApp.BS.PacientesREST'
```

Read that message literally: it **states the exact signature required** and is the authoritative answer
for that superclass — match it instead of reasoning about what the arguments ought to be. Types may be
narrowed to a subclass (`pInput As EnsLib.RecordMap.Base` in a `%RegisteredObject` slot), but the
**arity cannot change**.

Measured over a workshop cohort: **8 of 18 students** hit `#5478`, mostly by carrying the two-argument
RecordMap shape onto a REST or HTTP service. When unsure, `docs_introspect` the base class's
`OnProcessInput` before writing the override.

## Production naming — `Tipo.Nombre`

Every BS/BO/Router/Util item has a name in the production XML. Use the convention `<Type>.<Name>` consistently across the production:

| Component | Prefix | Example |
|---|---|---|
| Business Service | `BS.` | `BS.HL7Census` |
| Business Operation | `BO.` | `BO.WriteCensusToSQL` |
| Message Router / BP | `Router.` | `Router.Census` |
| Utility (gateway, scheduler) | `Util.` | `Util.JDBCGateway` |
| Alert router | **fixed: `Ens.Alerts`** | `Ens.Alerts` — the framework looks up this exact name |

`Ens.Alerts` is **non-negotiable** — `Ens.Alerting` discovers the alert router by name. Other prefixes are convention, but consistent application makes the Management Portal much easier to scan. See `iris-interop` §1.1 for the project-wide naming convention.

## Sync vs Async dispatch

| Dispatch method | When |
|---|---|
| `SendRequestAsync(target, request)` | Default. The BS doesn't wait for the response. Fire-and-forget routing. |
| `SendRequestSync(target, request, .response)` | Only when the BS *needs* the response on the same call (e.g. to ACK back to the caller with a result code). Synchronous calls block the BS pool. |
| `SendRequestSync(..., timeout)` | Same as above but with explicit timeout. Always set one — never default to no timeout. |

Prefer Async unless there is a specific reason to wait. Sync ties up a BS pool slot for the duration of the downstream chain.

## TargetConfigNames

`TargetConfigNames` is a **comma-separated list of component names** (typically the Message Router or directly a BO). Best practice: each BS has its own dedicated Message Router as target — don't share routers across services. Keeps routing logic isolated and traceable.

## OnInit settings validation

`OnInit()` runs once when the production starts the BS. Use it to fail loud on misconfiguration:

```objectscript
Method OnInit() As %Status
{
    If ..TargetConfigNames="" Quit $$$ERROR($$$EnsErrGeneral,"TargetConfigNames is required")
    If ..RequiredField="" Quit $$$ERROR($$$EnsErrGeneral,"RequiredField is required")
    Quit $$$OK
}
```

The user-stated principle: a BS that needs a setting should refuse to start if the setting is missing, not silently swallow nulls and fail at first message.

## Common pitfalls

- **One BS handling multiple HL7 schema versions** → not allowed; each BS is one schema. Create separate BSes for v2.3 and v2.5.
- **Hand-rolled CSV parser** → use Record Mapper. Hand-rolled parsing fails on quoted fields, embedded delimiters, encoding edge cases.
- **Sending Sync when Async would do** → blocks pool slots, kills throughput.
- **Skipping `OnInit` validation** → bugs surface at first message instead of at production start.
- **Multiple targets in one chain** → if you fan out to multiple operations, route through a Message Router; don't list them in `TargetConfigNames` for orchestration.
- **Pool size of 1 for high-volume sources** → set Pool Size to expected concurrency. (Default `PoolSize=1` is correct for everything until you measure a bottleneck — don't raise it preemptively.)
- **Diagnosing an FTPS `Unexpected SSL EOF` as a TLS problem** → it is often a failed `LIST *.csv` against a server that doesn't glob. Set `MLSD=1` — and then rewrite `FileSpec` as a regex (see the FTPS section below).
- **Forcing `SourceFilename` / `SourceLine` onto a Record Mapper-generated `.Record`** → Record Mapper doesn't emit those properties; a manual subclass that adds them won't get them populated at runtime either. If you need CSV-line forensics, capture the filename in a **custom BS** (not Record Mapper) or read it from `Ens.MessageHeader` propagated by the adapter (`%Source` / `%FileName`).

## Record Mapper — file gotchas

When using `EnsLib.RecordMap.Service.FileService` with a generated Record Map class:

- **Line terminators are compiled in**: the Record Map's `recordTerminator` is **baked into the generated `.Record` class** at compile time. Default is CRLF (`&#xD;&#xA;`). CSVs produced on Unix or by many ETL pipelines are LF-only (`&#xA;` = `$char(10)`). Set the terminator to match the **actual** input file — and **recompile the Record Map** after changing it. The runtime reads the compiled value, not the editor state.
- **After ANY Record Map edit, recompile**: Studio F7, Management Portal "Compile", or `iris_compile` via MCP. A stale `.Record` class silently uses the previous definition; symptom is "edit had no effect".
- **Charset**: set the adapter's `Charset` setting to `UTF-8` explicitly when headers/values contain non-ASCII characters (`ñ`, tildes). Platform-default charset may differ and produces header names that don't match field names ("Acompañante" header read as "AcompaÃ±ante" → mapping fails).
- **Quoted fields with embedded delimiters**: configure the Record Map's `Quote Character` (typically `"`) so the parser respects RFC-4180 quoting. `"García, hijo"` is one field with a literal comma; a `$PIECE`-by-comma hand-rolled parser corrupts it.
- **Use the pre-built `FileService` class directly** — declare `ClassName="EnsLib.RecordMap.Service.FileService"` on the production item and set the `RecordMap`, `FilePath`, `Charset`, and `HeaderCount` settings (the last three on target `Adapter`; `RecordMap`, `HeaderCount`, `TargetConfigNames` on target `Host`). Don't subclass unless you genuinely need to override behaviour. See the canonical pattern above for the subclass case (custom BS that wraps Record Mapper output into a project-specific message).

### Authoring the `XData RecordMap` block — the exact schema the validator accepts

This is the **only** part you write by hand. Everything else in the class — `GetObject`,
`PutObject`, `GetRecord`, `PutRecord`, `GetGeneratedClasses`, `getType`, `Parameter OBJECTNAME`
and the whole `.Record` class — is written by the generator (next section). Write the skeleton
plus the XData, generate, then `iris_doc get` the result back.

A delimited CSV (comma-separated, UTF-8, LF line endings, `"` quoting), verbatim from a working
production:

```objectscript
Class MyApp.RecordMap.Censo Extends EnsLib.RecordMap.RecordMap [ Not ProcedureBlock ]
{

XData RecordMap [ XMLNamespace = "http://www.intersystems.com/Ensemble/RecordMap" ]
{
<Record xmlns="http://www.intersystems.com/Ensemble/RecordMap"
        name="MyApp.RecordMap.Censo"
        type="delimited"
        char_encoding="UTF-8"
        recordTerminator="&#xA;"
        targetClassname="MyApp.RecordMap.Censo.Record"
        escaping="quote"
        escapeSequence="&quot;">
  <Separators>
    <Separator>,</Separator>
  </Separators>
  <annotation>Censo de pacientes leído desde CSV.</annotation>
  <Field name="ID"     datatype="%String" />
  <Field name="Nombre" datatype="%String" />
  <Field name="Planta" datatype="%String" />
</Record>
}

}
```

**`fieldSeparator` is the trap that costs the most attempts.** For `type="delimited"` the
attribute must be **absent**. Setting it to the obvious `fieldSeparator=","` fails with:

```
ERROR <EnsRecordMap>ErrInvalidRecordProp: Invalid value for property 'fieldSeparator' in Record of type delimited
```

which reads as "your value is malformed" but actually means "this property must not be set for
this type at all". The IRIS validator is explicit — anything that is not `fixedwidth` must leave
it empty:

```objectscript
If '(..type = "fixedwidth") {
    If ..fieldSeparator '= "" Quit $$$ERROR($$$EnsRecordMapErrInvalidRecordProp, ..type, "fieldSeparator")
```

The separator for a delimited record goes in `<Separators>`, as one `<Separator>` element per
nesting level (one element for a flat CSV).

| What gets written | What the schema wants |
|---|---|
| `fieldSeparator=","` / `separator=","` attribute | **omit it**; use `<Separators><Separator>,</Separator></Separators>` |
| `<Field type="%String"/>` | `datatype="%String"` |
| `<Field>` outside `<Record>` | every `<Field>` nested inside `<Record>`; a `<Record>` with none fails `#5661 Collection property 'EnsLib.RecordMap.Model.Record::Contents' is required` |
| `<RecordMap>` as the root element | the root is `<Record>` |
| `recordTerminator="\n"` | an XML entity: `&#xA;` (or `&#10;`) for LF, `&#xD;&#xA;` for CRLF |
| `[ DependsOn = MyApp.RecordMap.Censo.Record ]` on the first write | leave it off until the `.Record` exists — otherwise `#5373 Class '…Record', used by '…:dependson', does not exist` and the class is skipped. The generator adds it. |

**`targetClassname` is the class the generator will create**, and it is free — it does not have to
be `<RecordMap class>.Record`. Both conventions are in production use: a `.Record` suffix on the
map's own name (`MyApp.RecordMap.Censo` → `MyApp.RecordMap.Censo.Record`), or a sibling package
(`REDSA.RecordMap.Ifa` → `REDSA.Record.Ifa`). `name` is the record's identifier; it commonly
mirrors either the map class or `targetClassname`.

**On `xmlns`**: the `XMLNamespace` on the `XData` header is what matters. Repeating it as
`xmlns=` on `<Record>` is optional — hand-written maps routinely omit it and generate fine, and
the generator adds it when it rewrites the block, which is why classes read back from IRIS show
it. Both `http://www.intersystems.com/recordmap` and
`http://www.intersystems.com/Ensemble/RecordMap` are accepted.

### Fixed-width instead of delimited

`type="fixedWidth"` — **camelCase**. No `<Separators>`; every `<Field>` carries `position` (1-based,
absolute within the record) and `width`. Verbatim from a running production, one of eight
fixed-width maps generated at container start:

```objectscript
Class REDSA.RecordMap.Ifa Extends EnsLib.RecordMap.RecordMap
{

XData RecordMap [ XMLNamespace = "http://www.intersystems.com/recordmap" ]
{
<Record name="REDSA.Record.Ifa" type="fixedWidth" recordTerminator="&#10;" targetClassname="REDSA.Record.Ifa">
  <Field name="TipoReg"       datatype="%String" position="1"   width="3"  />
  <Field name="NumFactura"    datatype="%String" position="4"   width="15" />
  <Field name="NumAlbaran"    datatype="%String" position="19"  width="15" />
  <Field name="FechaFactura"  datatype="%String" position="34"  width="8"  />
  <Field name="NumLinea"      datatype="%String" position="594" width="7"  />
</Record>
}

}
```

Positions are absolute and must be contiguous with the widths — field N starts at
`position(N-1) + width(N-1)`. Gaps you don't care about still need a field; the common idiom is a
trailing `FILLER` that pads the record to its declared length (600 chars here).

**Multi-record-type files** (a header type, N detail types, a trailer — discriminated by a type
code at a fixed offset) need **one RecordMap class per record type**, not one map with variants.
Before reaching for `EnsLib.RecordMap.Service.ComplexBatchFileService`, know that it — like
`BatchFileService` — emits **one message per whole file**, not one per logical sub-batch. If you
need a message per invoice/episode/block, no native ARM service does that: write a custom BS that
reads the lines and assembles the sub-batch itself.

### Generating the Record Map (the `.Record` class + GetObject) — **a plain compile does NOT do this**

The Record Map's `<Map>.Record` class **and** the `GetObject`/`PutObject`/`GetRecord`/`PutRecord` method bodies are written by the **wizard / generator into the source**, exactly like a generated SOAP client. A normal `iris_compile` (or `iris_doc put` with `compile=true`) of a Record Map class that contains only the XData block compiles green but produces **no working `GetObject`** — at runtime the FileService dies with `<METHOD DOES NOT EXIST>GetObject ... ^EnsLib.RecordMap.Service.Base.1`.

When the Portal wizard is not available (MCP / headless), generate via the official API **wrapped in a `[SqlProc]`** (because `iris_execute`'s objectgenerator mode silently no-ops class-generating calls — see the friction log):

```objectscript
ClassMethod GenerateRecordMap(pRM As %String) As %String [ SqlProc ]
{
    Set sc = ##class(EnsLib.RecordMap.Generator).GenerateObject(pRM)
    Quit $Select($$$ISOK(sc): "ok", 1: "FAIL:"_$system.Status.GetErrorText(sc))
}
```

Invoke with `SELECT Pkg_Bootstrap_GenerateRecordMap('Pkg.RecordMap.X')`. Notes:
- `GenerateObject` errors `#5768 Class already exists` if the `.Record` already exists — delete it first, then regenerate.
- **`GetObject` lives on the RecordMap class, not on `.Record`.** Verifying with
  `##class(Pkg.RecordMap.X.Record).GetObject(...)` raises the same `<METHOD DOES NOT EXIST>` as
  a missing generation, and sends you chasing the wrong cause. Check
  `##class(Pkg.RecordMap.X).GetObject(...)`, or assert on the existence of the `.Record` class.
- The generated `.Record` extends `(%Persistent, %XML.Adaptor, Ens.Request, EnsLib.RecordMap.Base)` with `Parameter INCLUDETOPFIELDS = 1`. It IS the source class for the routing rule and DTL.
- **Disk is the source of truth**: after generating, `iris_doc get` both the Record Map class (now carrying the method bodies) and the `.Record`, and write them to `src/` — the generated code must be committed, not just live in IRIS. Regenerate whenever you edit the XData.

### FTP / FTPS instead of a local file

The spec often calls for the CSV to arrive over **FTPS**, while you develop/test against a **local folder**. The two use **different service classes** — you cannot just change a setting:

- `EnsLib.RecordMap.Service.FileService` — local/mounted folder (adapter `EnsLib.File.InboundAdapter`).
- `EnsLib.RecordMap.Service.FTPService` — FTP/FTPS (adapter `EnsLib.FTP.InboundAdapter`); for TLS set the adapter `SSLConfig` to an SSL/TLS configuration name plus `FTPServer`/`FTPPort`/`Credentials`.

Both share the **same `RecordMap`** and should point at the **same Router**. Pattern when the spec mandates FTPS but no FTPS server exists yet: register **two BS items at the same Router** — the `FTPService` one (`Enabled="false"`, faithful to the spec) and a `FileService` one (`Enabled="true"`, for local drop-a-file verification). This keeps the solution spec-compliant and testable without inventing infrastructure.

#### FTPS against a real server — `MLSD=1`, and `FileSpec` becomes a regex

The FTP adapter's directory listing is **`LIST <FileSpec>`** — e.g. `LIST *.csv` — and it expects
the *server* to expand the glob. `vsftpd`, IIS and `curl` do; `pyftpdlib` and others treat the
pattern as a literal path and answer `550 Invalid argument`. The symptom is misleading: what you
actually see is an **`Unexpected SSL EOF`** on the data channel, which sends you diagnosing TLS.
TLS is fine — the transfer never started, because the listing failed.

The working configuration against a non-globbing server:

1. Set **`MLSD=1`** on the adapter. IRIS then lists the directory with `MLSD` (no pattern) and
   filters client-side.
2. **With `MLSD=1`, `FileSpec` is evaluated as a REGULAR EXPRESSION, not a glob.** Use
   `.*\.csv`; keeping `*.csv` fails with `#8311 Syntax error in regexp pattern`. This reversal is
   the part nobody guesses.
3. IRIS still issues `LIST <pattern>` for `getSize`, so the server must at least tolerate the
   command.

TLS client side: create the SSL configuration with `Security.SSLConfigs.Create(name, .props)`
using `Type=0` (client) and `VerifyPeer=0` for a self-signed certificate, then point the
adapter's `SSLConfig` at it — the adapter does AUTH TLS + PROT P from there.

The two facts worth remembering, because neither is discoverable from the error messages: *"SSL
EOF" can mean a failed LIST, not a TLS problem*, and *`FileSpec` flips from glob to regex when
`MLSD=1`*.

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

Five non-obvious rules (each cost a debug cycle — see friction log):
- **Write to the `pOutput` the framework passes in — do NOT `Set pOutput = ##class(%GlobalBinaryStream).%New()`.** Rebinding the local variable orphans the framework's response stream; the HTTP reply comes back `200` with an **empty body**.
- **The route handler runs as an INSTANCE method of the service host** (`EnsLib.REST.Service` dispatches no-class-prefix routes via `$method($this,...)`), so `..SendRequestSync(target, req, .resp)` to a BP/BO works directly inside it.
- **`%DynamicObject` keys with underscores need `%Get`/`%Set`** — `tJSON.codigo_acto` parses as `tJSON.codigo _ acto` (the `_` is the concat operator) and breaks compilation. Use `tJSON.%Get("codigo_acto")`.
- **Exposure:** with `EnsLib.HTTP.InboundAdapter` the service listens on its own `Port` (clean URL `http://host:PORT/demo/preauth`). Via the **CSP gateway** (web app `DispatchClass=App.BS.Preauth`) `EnsLib.REST.Service` requires `?CfgItem=<configItemName>` appended to the URL (stated in the class doc-comment) — a wart; prefer the InboundAdapter port unless you must go through the gateway. BS is tested from outside (curl), not from inside IRIS.
- **`ErrHTTPConfigName` = the dispatcher can't resolve a config item by that name.** Through the CSP gateway, the `?CfgItem=<name>` (or the URL segment) **must exactly match the production item Name** of the REST service. Renaming the item (e.g. from `BS.PacientesREST` to `pacientes`) without updating the caller's URL — or vice-versa — yields `ErrHTTPConfigName` and a 500. Keep the item Name and the dispatch name in lockstep; this single mismatch is a notorious repeat-offender across separate debugging passes.

## Testing / how to verify

1. Compile via the MCP server. Confirm no errors.
2. Add the BS to the production via the MCP server (or Management Portal). Set `TargetConfigNames`.
3. Drop a sample input (file, message, etc.). Watch the Event Log; confirm the BS picked it up and dispatched.
4. Use `message-search-debug` to follow the Visual Trace from the BS through downstream components.
5. Negative test: omit a required setting. The BS should refuse to start (red status, error in Event Log).

## HL7 Business Service: schema assignment is **non-negotiable**

For any HL7 BS (`EnsLib.HL7.Service.FileService`, `TCPService`, `SOAPService`, etc.) **always assign Version + MessageType** — not just version. The standard format combines both as a colon-separated `MessageSchemaCategory`:

```xml
<Item Name="BS.HL7Census" ClassName="EnsLib.HL7.Service.FileService" ...>
  <Setting Target="Host" Name="MessageSchemaCategory">2.5:ADT_A01</Setting>
  ...
</Item>
```

If the messages are **Ad-hoc** — Z-segments, custom structures, fields the standard schema doesn't expose — define an Ad-hoc HL7 schema via Management Portal → Interoperability → Build → HL7 Schema Editor (see `hl7-schemas`) and reference it with the same `MessageSchemaCategory` setting.

**Why this matters**: the schema assignment is what lets downstream DTLs use **symbolic field names** (`source.GetValueAt("PID:PatientName(1).GivenName")`) instead of fragile numeric paths (`source.GetValueAt("PID:5(1).2")`). Without schema, the parser treats the message as generic and only numeric paths resolve. The DTL becomes unreadable and refactors brittle. See `transformations` for the segment-iteration patterns once a schema is assigned.

## BS that exposes an inbound SOAP service

When you need a Business Service that accepts inbound SOAP requests:

1. New → General → Web Service in Studio (or generate from a WSDL via the SOAP wizard).
2. Change the parent class from the default `%SOAP.WebService` to **`EnsLib.SOAP.Service`** — this is what makes it an Interop entry point.
3. Override the `Adapter` parameter to blank (default would be `EnsLib.SOAP.InboundAdapter`, which is a separate inbound model and prevents direct WS invocation).
4. Implement web methods with `[WebMethod]` and parameters typed to your `MSG.<Name>Req|Rsp` classes.
5. Override `OnProcessInput` and call the BP synchronously or asynchronously as the use case requires.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/soap-business-service.cls`.

## Scheduled BS — wall-clock vs interval

Default Ensemble inbound adapters do **interval** scheduling ("every X seconds"). For **wall-clock** schedules (daily 08:30, weekdays 08:00–18:00 only, etc.) two options:

- **Custom scheduler adapter** with a cron-style format `min hour day month dayOfWeek`. Most legacy customer projects built one of these.
- **IRIS native task framework** (`%SYS.TaskSuper`) that triggers a passive BS via `Ens.Director.CreateBusinessService`. Preferred for new work.

### Scheduled BS concurrency — `PoolSize=1` alone is not enough

To prevent concurrent execution of a scheduled Business Service, **both** are required:

(a) Set `Pool Size = 1` on the BS item.
(b) Make **all calls from the BS synchronous** (`SendRequestSync`).

Async calls let the BS return before the work downstream finishes. The scheduler's next tick fires while the first execution is still in-flight → two concurrent BS instances racing.

Also: any **manual** entry path (a Studio test, a non-scheduled inbound message sent by a different BS) bypasses the scheduler entirely and is not subject to the lock. If concurrency matters for correctness, defend in code (a global lock / semaphore inside the BS).

## Synchronous chain for source-system ordering dependencies

When the source system has row-ordering dependencies (e.g. an UPDATE that depends on its prior INSERT, a "Reprogramacion" that depends on its "Programacion"), prefer a synchronous BS → BP → BO chain over async messaging. Async queues are free to reorder; sync chains preserve order at the cost of throughput.

Document the trade-off explicitly in the production. See `bpl` for the BP-side pattern.

## HTTP Basic Auth on an inbound SOAP BS

When authentication must live in IRIS (not at the gateway / reverse proxy) and the inbound is SOAP, do it in `OnPreWebMethod()`:

```objectscript
Method OnPreWebMethod() As %Status
{
    Set authHeader = $get(%request.CgiEnvs("HTTP_AUTHORIZATION"))
    // parse "Basic <base64(user:pwd)>", validate against your credential store
    // raise SOAP fault on failure
}
```

This requires `EnsLib.SOAP.InboundAdapter` (an adapter that strips Authorization headers would defeat the pattern). For non-SOAP REST inbound, use the CSP web app's `AutheEnabled` bitmask (covered above) and let the gateway handle Basic — OnPreWebMethod is specific to SOAP service classes.

## REST/CSP entry point: Business Service **without an adapter**

When the BS is invoked from REST/CSP code (an `%CSP.REST` handler, a custom CSP page, etc.) rather than from a transport adapter, the pattern is a custom BS class with **no adapter at all**:

```objectscript
Class MyApp.BS.RestEntry Extends Ens.BusinessService
{
Parameter ADAPTER;
Parameter SERVICEINPUTCLASS = "MyApp.Msg.SomeRequest";
Parameter SERVICEOUTPUTCLASS = "Ens.Response";

Method OnProcessInput(pInput As MyApp.Msg.SomeRequest, Output pOutput As Ens.Response) As %Status
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
| `AutheEnabled` | **96** or **97** | Bitmask. **`96` = Password + Kerberos prompt** — accepts HTTP Basic Auth on `Authorization: Basic ...` headers. `97` = `96 + 1` adds tolerance for unauthenticated. The IRIS 2026.1 doc value `4=Password` does **NOT** accept Basic — the request gets a login form back. Use the same value as `/csp/user` (96) for confidence. |
| `DispatchClass` | Your `%CSP.REST` impl | For REST web apps |
| `NameSpace` | Target namespace | Where the dispatch class lives |
| `Path` | `<InstallDir>csp\<webappname>\` | CSP routing filesystem mapping |

**Smoke test pattern**: `curl -u user:pwd <URL>` must return **data** (JSON / XML payload), not an HTML login form. If you get the login form, the web app's `AutheEnabled` is wrong (or the user lacks resources on the target namespace).

## When NOT to use this skill — fall back to docs

- DICOM inbound (`EnsLib.DICOM.Service.*`) → see `dicom` (stub).
- Email inbound (`EnsLib.EMail.InboundAdapter`) — covered by docs; this skill doesn't have validated examples.
- Workflow tasks / human steps — not a BS pattern.

## IRIS SQL dialect — quick cheat-sheet

When a RecordMap BS reads/writes through a SQL Gateway, or you verify a run with `iris_query`, keep
these IRIS-SQL specifics in mind:

- **Class ↔ table names.** A persistent class `Pkg.Sub.Cls` projects to SQL table `Pkg_Sub.Cls` —
  package dots become `_`, and the **last** dot separates schema from table. So class `Ens.Util.Log`
  is table `Ens_Util.Log`; `Ens.MessageHeader` stays `Ens.MessageHeader`. Real interop tables:
  `Ens_Util.Log` (event log), `Ens.MessageHeader` (message headers), `EnsLib_*` schemas for adapter data.
- **Reserved words.** `DOMAIN`, `LANGUAGE`, `OUTPUT`, `CONNECTION`, `DEFAULT`, `USER`, `VALUE`, `SECTION`
  and friends are reserved. If a column/table is named one of them, **delimit it with double quotes**
  (`SELECT "Connection" FROM …`). Unquoted, you get SQLCODE -1/-12.
- **ObjectScript is not SQL.** `iris_query` runs SQL SELECTs only. `set`/`write`/`do`/`##class(...)`,
  `&sql(...)`, and `^global` references are ObjectScript — run them with `iris_execute`, not `iris_query`.
- **Discover, don't guess.** Before querying, use `iris_table_info` (or `docs_introspect`) to get the
  real table/column names rather than guessing system-catalog tables.

## See also

- `iris-interop-skills:messages` — design the message class first
- `iris-interop-skills:bpl` — what the Message Router/BP target looks like; sync chain for ordering dependencies
- `iris-interop-skills:production-lifecycle` — wiring the BS into the production class
- `iris-interop-skills:security` — when authentication needs more than HTTP Basic (SAML, OAuth)
- `iris-interop-skills:soap-bo` — the outbound side; many of the same WSDL caveats apply
