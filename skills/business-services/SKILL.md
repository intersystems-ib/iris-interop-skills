---
name: business-services
description: BS inbound - File, TCP, SOAP, REST, Record Mapper CSV. Triggers: Business Service, BS, inbound, File Service, RecordMap, CSV, REST inbound, TCP/MLLP, leer fichero, servicio de entrada, adapterless.
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

**First decide whether you need a custom BS at all.** For a RecordMap flow you usually do not —
configure the prebuilt `EnsLib.RecordMap.Service.FileService` and put any reshaping in a DTL on the
router. See [references/recordmap.md](references/recordmap.md) for the prebuilt-component table.

**And know what subclassing `FileService` actually gives you**, because the obvious move does not
work. Verified against IRIS for Health 2026.1 with `%Dictionary.CompiledMethod`:

| class | `OnProcessInput` receives |
|---|---|
| `EnsLib.RecordMap.Service.FileService` | `pInput As %Stream.Object` — **the whole file** |
| `EnsLib.RecordMap.Service.FTPService` | `pInput As %Stream.Object` — the whole file |
| `EnsLib.RecordMap.Service.Standard` / `.Base` | `pInput As %RegisteredObject` |

All three take **three** arguments: `(pInput, Output pOutput As %RegisteredObject, ByRef pHint As %String)`.

So overriding `OnProcessInput` on a `FileService` hands you the **stream, not a record**, and
replaces the record loop that service exists to run — you would have to re-implement parsing.
There is no per-record hook on it either: `SendRecord()` exists only on the `Batch*` services.
A 2-argument override typed `pInput As EnsLib.RecordMap.Base` does not compile at all:

```
ERROR #5478: Keyword signature error in ...:Method:OnProcessInput, keyword 'method argument/s
signature' must be '%Stream.Object,%Library.RegisteredObject,%Library.String' or its subclass
```

**The genuine custom-BS case** is a bare adapter, where the signature is yours to define — this is
the skeleton to copy:

```objectscript
Class MyApp.BS.PatientCensusFromCSV Extends Ens.BusinessService
{

Parameter ADAPTER = "EnsLib.File.InboundAdapter";

Parameter SETTINGS = "TargetConfigNames:Basic,RequiredField:Basic";

Property TargetConfigNames As %String(MAXLEN = 1000);

Property RequiredField As %String;

/// EVERY Property OnInit requires must be in SETTINGS. A Property absent from SETTINGS does not
/// appear in the Portal's settings panel, so an operator cannot re-point the service without
/// hand-editing the production XML — and this class's OnInit *requires* TargetConfigNames.
/// Declaring one and not the other is the shape the bank runs copied.
/// Validate settings, and fail loud at startup rather than at first message.
/// NOTE: "at startup" holds for an adapter-driven service like this one. On a PoolSize="0" passive
/// BS there is no actor to start, so OnInit runs at the FIRST REQUEST instead — see
/// references/rest-csp.md.
/// On a PREBUILT EnsLib service you would call ##super() FIRST — the base OnInit is the only
/// place the parser state is initialised. Here the inherited Ens.BusinessService.OnInit does
/// nothing by default (ESQL §6.5 "Initializing the Adapter"), so there is nothing to chain to.
Method OnInit() As %Status
{
    If ..TargetConfigNames = "" Quit $$$ERROR($$$EnsErrGeneral, "TargetConfigNames is required")
    If ..RequiredField = "" Quit $$$ERROR($$$EnsErrGeneral, "RequiredField is required")
    Quit $$$OK
}

Method OnProcessInput(pInput As %Stream.Object, Output pOutput As %RegisteredObject) As %Status
{
    Set tRequest = ##class(Ens.StringContainer).%New()
    Set tRequest.StringValue = pInput.Read(32000)
    Quit ..SendRequestAsync(..TargetConfigNames, tRequest)
}

}
```

`Ens.StringContainer` stands in for a project message class only so the snippet is self-contained
and compilable; a real service sends its own `<Pkg>.MSG.<Name>Req`.

Do **not** declare `Parameter ADAPTER` when you extend a prebuilt `…Service.FileService` — that
keyword names an *adapter*, and `FileService` is a Business Service, not one.

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

> **The path goes in the Setting, not in the `.cls`.** `FilePath`, `Filename` and `JDBCClasspath`
> are adapter settings of the **production item** (ESQL §3.1), so a literal `C:\…` or `/tmp/…`
> inside a BS/BO/BP/DTL class is a CR-10 finding. Bootstrap/`UTL` helpers and `%UnitTest` fixtures
> are exempt — they have no production item, hence no Setting, and a fixture must name a real file
> on the server.

## Production naming — `Tipo.Nombre`

Every BS/BO/Router/Util item has a name in the production XML. Use the convention `<Type>.<Name>` consistently across the production:

| Component | Prefix | Example |
|---|---|---|
| Business Service | `BS.` | `BS.HL7Census` |
| Business Operation | `BO.` | `BO.WriteCensusToSQL` |
| Message Router / BP | `Router.` | `Router.Census` |
| Utility (gateway, scheduler) | `Util.` | `Util.JDBCGateway` |
| Alert router | **fixed: `Ens.Alert`** | `Ens.Alert` — the framework looks up this exact name |

`Ens.Alert` is **non-negotiable** — the framework dispatches `Ens.AlertRequest` to the production item with this exact name (verified in `Ens.Host` source, IRIS 2026.1). Other prefixes are convention, but consistent application makes the Management Portal much easier to scan. See `interop` for the project-wide naming convention.

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

`OnInit()` runs once when the production starts the BS. Use it to fail loud on misconfiguration —
but hand control to the base class first:

```objectscript
Method OnInit() As %Status
{
    Set tSC = ##super()                 // MANDATORY on a prebuilt EnsLib.* service
    Quit:$$$ISERR(tSC) tSC

    If ..TargetConfigNames="" Quit $$$ERROR($$$EnsErrGeneral,"TargetConfigNames is required")
    If ..RequiredField="" Quit $$$ERROR($$$EnsErrGeneral,"RequiredField is required")
    Quit $$$OK
}
```

The user-stated principle: a BS that needs a setting should refuse to start if the setting is missing, not silently swallow nulls and fail at first message.

> **`OnInit()` without `##super()` on a prebuilt service — silent, and it destroys the input.**
> Symptom: the BS picks the file up and deletes it, **0 messages, 0 Event Log entries, component
> green in the Portal**. There is no error text anywhere; that is the whole difficulty. The base
> `OnInit` is the only place the parser state is initialised — verified on IRIS for Health 2026.1,
> `EnsLib.RecordMap.Service.Base` declares both `OnInit` and `recordMapFull`, and
> `EnsLib.HL7.Service.Standard` declares both `OnInit` and `%Parser`.
>
> Applies to subclasses of **prebuilt** `EnsLib.*.Service.*` and `EnsLib.*.Operation.*`. A direct
> subclass of `Ens.BusinessService` that declares `Parameter ADAPTER` has **no** such obligation —
> its inherited `OnInit()` does nothing by default (ESQL §6.5 "Initializing the Adapter"), so
> `##super()` there adds nothing.
>
> Put `##super()` FIRST rather than `Quit ##super()` last: the validation then runs against a fully
> initialised host, and the base `%Status` is propagated instead of discarded.

## Common pitfalls

- **`##class(Pkg.BS.X).%New()` to test the service directly** → a BS does not instantiate. `Ens.BusinessService` declares no `%New`; a subclass returns `""`, and the error surfaces a line later as `<INVALID OREF>`. See `tdd` §"Pitfalls specific to Interop TDD".
- **One BS handling multiple HL7 schema versions** → not allowed; each BS is one schema. Create separate BSes for v2.3 and v2.5.
- **Hand-rolled CSV parser** → use Record Mapper. Hand-rolled parsing fails on quoted fields, embedded delimiters, encoding edge cases.
- **Sending Sync when Async would do** → blocks pool slots, kills throughput.
- **Skipping `OnInit` validation** → bugs surface at first message instead of at production start.
- **An `OnInit()` override on a prebuilt `EnsLib.*` service that never calls `##super()`** → the base class never initialises the parser (`..recordMapFull`, `..%Parser`), so the service starts green, eats and deletes its input, and emits nothing at all — no message, no Event Log entry, no error. See §"OnInit settings validation". Not applicable to a plain `Ens.BusinessService` + `Parameter ADAPTER` subclass.
- **Multiple targets in one chain** → if you fan out to multiple operations, route through a Message Router; don't list them in `TargetConfigNames` for orchestration.
- **Pool size of 1 for high-volume sources** → set Pool Size to expected concurrency. (Default `PoolSize=1` is correct for everything until you measure a bottleneck — don't raise it preemptively.)
- **Diagnosing an FTPS `Unexpected SSL EOF` as a TLS problem** → it is often a failed `LIST *.csv` against a server that doesn't glob. Set `MLSD=1` — and then rewrite `FileSpec` as a regex (see the FTPS section below).
- **Forcing `SourceFilename` / `SourceLine` onto a Record Mapper-generated `.Record`** → Record Mapper doesn't emit those properties; a manual subclass that adds them won't get them populated at runtime either. If you need CSV-line forensics, capture the filename in a **custom BS** (not Record Mapper) or read it from `Ens.MessageHeader` propagated by the adapter (`%Source` / `%FileName`).

## Record Mapper — file intake

A delimited or fixed-width file intake is a **RecordMap**, never a hand-written parser
(that is conformance criterion CR-2).

**`fieldSeparator` is the trap that costs the most attempts, and its error names the wrong thing.**
For `type="delimited"` the attribute must be **absent**. Writing the obvious `fieldSeparator=","`
gives:

```
ERROR <EnsRecordMap>ErrInvalidRecordProp: Invalid value for property 'fieldSeparator' in Record of type delimited
```

That reads as *"your value is malformed"* and actually means *"this property must not be set for
this type at all"*.

**The class compiles CLEAN with it** — measured both ways, the error comes only from
`GenerateObject`, never the compiler. A green compile is not evidence the map is valid. The separator goes in `<Separators>`, one `<Separator>` per nesting level —
one element for a flat CSV. Minimum correct shape, copy this:

```xml
<Record xmlns="http://www.intersystems.com/Ensemble/RecordMap"
        name="Censo" type="delimited"
        targetClassname="MyApp.RecordMap.Censo.Record"
        recordTerminator="&#xA;">
  <Separators><Separator>,</Separator></Separators>
  <Field name="Id"     datatype="%String"/>
  <Field name="Nombre" datatype="%String"/>
</Record>
```

Five more, each of which costs a compile:

| What gets written | What the schema wants |
|---|---|
| `fieldSeparator=","` or `separator=","` | omit it entirely; use `<Separators>` |
| `<Field type="%String"/>` | `datatype="%String"` |
| `<Field>` outside `<Record>` | every `<Field>` nested inside `<Record>`; a `<Record>` with none fails `#5661 Collection property '…Record::Contents' is required` |
| `<RecordMap>` as the root element | the root element is `<Record>` |
| `recordTerminator="\n"` | an XML entity: `&#xA;` for LF, `&#xD;&#xA;` for CRLF |

`targetClassname` is the class the generator creates and is free — it need not be
`<map class>.Record`. After generating, **export the `.Record` class to disk**: the generator writes
it into the namespace only, and CR-12 fails a class that exists nowhere else.

Fixed-width, building a map programmatically, testing the parser, and FTP/FTPS:
[references/recordmap.md](references/recordmap.md).

## REST inbound — three routes, and they are not interchangeable

- **The adapter's own port** (`EnsLib.HTTP.InboundAdapter`) and **a hand-written `%CSP.REST`
  dispatcher**: [references/rest-csp.md](references/rest-csp.md).
- **Spec-first** — one Swagger 2.0 document generates the dispatcher and an implementation stub.

### Spec-first — the whole sequence

Three classes, one of them yours:

```
Pkg.REST.spec   YOU AUTHOR    Extends %REST.Spec, holds the XData OpenAPI document
Pkg.REST.disp   GENERATED     Extends %CSP.REST — the web app points here. Never edit: rewritten every time.
Pkg.REST.impl   GENERATED 1x  Extends %REST.Impl — your method bodies. Edits SURVIVE regeneration.
```

1. **`swagger: "2.0"` is mandatory.** An OpenAPI **3.0** document is the expensive mistake, and the
   two ways of generating disagree about it — the one you reach for by hand is the silent one:

   | route | Swagger 2.0 | OpenAPI 3.0 |
   |---|---|---|
   | compile the hand-authored `.spec` class | generates `.disp` + `.impl` | **compiles CLEAN, generates NOTHING, no error** |
   | `##class(%REST.API).CreateApplication(name, dynObj, .err)` | `$$$OK`, generates all three | `ERROR #8738 … <$.swagger>`, names the exact JSON path |

2. **Never trust the compile — check the artifacts exist:**

   ```
   Write ##class(%Dictionary.CompiledClass).%ExistsId("Pkg.REST.disp"),!
   Write ##class(%Dictionary.CompiledClass).%ExistsId("Pkg.REST.impl"),!
   ```

3. **A failed regeneration leaves the previous dispatcher serving.** Re-running
   `CreateApplication` with a bad document errors, and the old `.disp`/`.impl` stay live answering
   the old contract. The error alone does not tell you which version is deployed.

4. **The generated dispatcher validates almost nothing.** Read out of the generated routine:
   `required` and a duplicate occurrence are enforced with `$data` tests; **`minimum`, `maximum`,
   `pattern` and `enum` generate no code at all**, and the projected `.impl` signature is a bare
   `%String` / `%Integer` with no `VALUELIST` or `MINVAL`. An invalid enum value reaches your
   implementation untouched — if the contract promises a 400, **you** must write it.

5. **The `.impl` class is not a Business Service.** Build the canonical message there and hand it to
   the production — an adapterless BS (`Parameter ADAPTER = "";`) invoked through
   `##class(Ens.Director).CreateBusinessService(.tService)` is the conformant route.

Depth, including auth guards and the web-application wiring:
[references/rest-spec-first.md](references/rest-spec-first.md).

## Testing / how to verify

1. Compile via the MCP server. Confirm no errors.
2. Add the BS to the production via the MCP server (or Management Portal). Set `TargetConfigNames`.
3. Drop a sample input (file, message, etc.). Watch the Event Log; confirm the BS picked it up and dispatched.
4. Use `message-search-debug` to follow the Visual Trace from the BS through downstream components.
5. Negative test: omit a required setting. The BS should refuse to start (red status, error in Event Log).

### Waiting for a file BS to pick the file up — never a blind `sleep`

Step 3 above says "drop a sample input". The file inbound adapter is a **poller**, so *how long*
that takes is a setting, not a guess: it checks the directory every `CallInterval` seconds —
**default 5, minimum 0.1** (EFIL, *Call Interval*). Nothing here is event-driven.

`cp … && sleep 6` is a guess. An escalating `sleep 6, 7, 8, 12, 15, 20` is the same guess repeated,
and it is invisible to every quality signal you have: **`sleep` always exits 0**. Worse, the `cp` you
repeat because nothing showed up double-counts rows you then have to reconcile, and the loop cannot
tell "hasn't polled yet" from "will never arrive".

**1. Read the interval instead of guessing it.**

```
iris_production_item(namespace="<NS>", action="get_settings", item="<BS item>")
```

Look for `CallInterval` on target `Adapter`. Absent means it was never set and the default applies:
5 s. Budget `2 × CallInterval` before concluding anything.

**2. Take a watermark before copying, then poll the watermark.** `iris_interop_query` orders by
`ID DESC`, so `limit=1` gives you the current high-water mark, and `since_id` then tails only what
is new — no `SELECT MAX(ID)` first, and no risk of counting a previous run's rows.

```
# a. watermark: highest IDs right now
iris_interop_query(namespace="<NS>", what="messages", limit=1)     -> ID = 4711
iris_interop_query(namespace="<NS>", what="logs",     limit=1)     -> ID = 9088

# b. copy the file into the watched directory ONCE
cp ./samples/<input file>  <FilePath>/

# c. poll, a second or two apart, for at most 2 x CallInterval
iris_interop_query(namespace="<NS>", what="messages", since_id=4711)
iris_interop_query(namespace="<NS>", what="logs",     since_id=9088)
```

Poll **both**: `what=messages` catches the success path, `what=logs` catches the case where the
adapter did pick the file up and the BS then threw. The first call that returns a row ends the wait.

**3. After `2 × CallInterval` with nothing, stop. Do not re-copy.** The directory tells you which
failure you have:

| `IN/` after the wait | What it means | Next move |
|---|---|---|
| file gone, new message rows | it worked | `iris_interop_query(what=trace, session_id=<n>)` to follow it downstream |
| file gone or moved, **no** new rows | the adapter processed it and the BS produced nothing | `iris_interop_query(what=logs, since_id=<watermark>)`. **The adapter renames or deletes only if the method did NOT return an error** (EFIL) — so a file that moved while emitting nothing means the BS returned *success* having done nothing, which is the `OnInit()`-without-`##super()` signature exactly. Re-copying just feeds it another file |
| file still sitting there | it was **not** consumed — or the BS returned an error | Under defaults a processed file is **gone**, so this is not "it worked and simply did not move". Read `iris_interop_query(what=logs, since_id=<watermark>)` first: error rows mean the call returned `$$$ERROR` and the adapter left the file where it was. Look for one `Skipping previously errored file '<path>' with timestamp '<ts>'` warning — that is the adapter declining to retry it, not a poll failure. No rows at all → `iris_production(action=status)`, then `FilePath` / `FileSpec` / `ConfirmComplete` on the item: BS disabled, production not running, or watching a different directory |

**Where the file ends up is a SETTING, not a constant — do not reason from "it disappeared".**
EFIL publishes a six-scenario table; the three that matter while developing:

| `ArchivePath` / `WorkPath` | After a successful call (`DeleteFromServer` at its default `1`) |
|---|---|
| neither set | **deleted — the file is gone.** It survives only if you explicitly set `DeleteFromServer` = 0 |
| `ArchivePath` set, different from `FilePath`, `WorkPath` unset | moved to `ArchivePath` + filename |
| `WorkPath` set, `ArchivePath` unset | processed via `WorkPath` and **deleted from there**. The property comment says `DeleteFromServer` is ignored when a `WorkPath` is set; the disposal branch requires a non-empty `ArchivePath`, so with only a `WorkPath` the file still goes. Set both if you want to keep it |
| both set and different | processed via `WorkPath`, ends at `ArchivePath` + filename |

`EnsLib.File.InboundAdapter` declares `Property DeleteFromServer As %Boolean [ InitialExpression = 1 ]`,
and no file-inbound service in the product overrides it — checked on the live instance for
`EnsLib.File.PassthroughService`, `EnsLib.HL7.Service.FileService`,
`EnsLib.RecordMap.Service.FileService` and `EnsLib.EDI.XML.Service.FileService`: all four instantiate
`EnsLib.File.InboundAdapter` with `DeleteFromServer=1`, `ArchivePath=""`, `WorkPath=""`.

Two consequences worth holding on to, both from EFIL:

- **The adapter renames or deletes the file only if the method did NOT return an error.** So a file
  that moved is evidence the BS returned success — which is what makes "moved, but zero messages"
  point straight at an `OnInit()` that skipped `##super()` rather than at a crash.
- **A file still in the input directory is not the resting place of a processed file.** Under
  defaults it means the file was not consumed, or the call returned an error. Read the watermark
  *and* the Event Log, not the directory alone.
- **After an error the file stays, and is then SKIPPED — not retried for ever.** The adapter marks
  the path plus its timestamp before processing and clears the mark only on success; on the next
  poll it logs one warning and moves on. Measured: a failing target, `CallInterval` 2s, ~7 polls →
  the file delivered **once**, and **one** `Skipping previously errored file …` warning. So the tell
  is a single warning, and the file becomes eligible again only when its modified time changes or it
  disappears. Do not expect a retry loop, and do not read the surviving file as "still queued".

**`ArchivePath` is part of the item definition, not a debugging aid.** Without it the input is
consumed and the run is not repeatable; set it deliberately, in the production, not just while
developing:

```
iris_production_item(namespace="<NS>", action="set_settings", item="<BS item>",
                     settings={"Adapter.ArchivePath": "<archive dir>/"})
```

## HL7 Business Service: schema assignment is **non-negotiable**

For any HL7 BS (`EnsLib.HL7.Service.FileService`, `TCPService`, `SOAPService`, etc.) **always assign
`MessageSchemaCategory`** — an HL7 service with none parses every message as generic, and only numeric
paths resolve (see "Why this matters" below).

Assign the **category alone**. Quoting the property's own description on 2026.1: it is the *"category
to apply to incoming message types to produce a complete DocType specification… combines with the
document type Name (MSH:9)"*. So the version is what you set, and the structure comes from each
message:

```xml
<Item Name="BS.HL7Census" ClassName="EnsLib.HL7.Service.FileService" ...>
  <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  ...
</Item>
```

This corrects earlier guidance in this skill to "always assign Version + MessageType" as a
colon-separated `2.5:ADT_A01`. **That form does not work at all** — measured on 2026.1 by calling the
service's own resolution step, `EnsLib.HL7.Schema.ResolveSchemaTypeToDocType()`:

| `MessageSchemaCategory` | MSH-9 | Result |
|---|---|---|
| `2.5` | `ADT_A01` | DocType `2.5:ADT_A01`, `$$$OK` |
| `2.5` | `ADT_A08` | DocType `2.5:ADT_A01` — the DocType names the **structure**, not the trigger event |
| `2.5:ADT_A01` | `ADT_A01` | `<Ens>ErrGeneral: DocType not found for message type 2.5:ADT_A01:ADT_A01` |

The category is **concatenated** with MSH-9, so a colon-separated value produces the nonsense
`2.5:ADT_A01:ADT_A01` and resolves nothing. The gated example
(`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch02_hl7v2/production-hl7-intake.cls`) has always used
the bare category.

**The conflation to avoid, because both are written `a:b` and only one of them belongs here:** a
**DocType** is `category:structure` (`2.5:ADT_A01`) and is what you put in a DTL's `sourceDocType` or
pass to `DocTypeSet()`. A **schema category** is the left half alone, and is what this setting takes.

A colon does appear in this setting, but only inside a **per-type override**, never as the whole
value. The full grammar is a comma-separated list where each entry after the default category maps a
type Name (with `*` as a trailing wildcard) to a category or a full DocType:

```xml
<Setting Target="Host" Name="MessageSchemaCategory">2.3.1, ADT_*=2.5, BAR_P10=2.4, ORM_O01_6=2.4:RDE_O01</Setting>
```

Use that when one feed mixes versions. Note also, from the same description: *"a DocType assignment
may be needed for Validation or SearchTableClass indexing"* — an unassigned DocType silently disables
both.

If the messages are **Ad-hoc** — Z-segments, custom structures, fields the standard schema doesn't expose — define an Ad-hoc HL7 schema via Management Portal → Interoperability → Build → HL7 Schema Editor (see `hl7-schemas`) and reference it with the same `MessageSchemaCategory` setting.

**Why this matters**: the schema assignment is what lets downstream DTLs use **symbolic field names** (`source.GetValueAt("PID:PatientName(1).GivenName")`) instead of fragile numeric paths (`source.GetValueAt("PID:5(1).2")`). Without schema, the parser treats the message as generic and only numeric paths resolve. The DTL becomes unreadable and refactors brittle. See `transformations` for the segment-iteration patterns once a schema is assigned.

## BS that exposes an inbound SOAP service

See [references/soap-inbound.md](references/soap-inbound.md) for the class shape and
for HTTP Basic Auth on it.

## HTTP Basic Auth on an inbound SOAP BS

See [references/soap-inbound.md](references/soap-inbound.md).

## REST/CSP entry point, and endpoint permissions

A BS with no adapter used as a CSP/REST entry point, and the web-app permissions an
inbound endpoint needs: see [references/rest-csp.md](references/rest-csp.md).

## When NOT to use this skill — fall back to docs

- DICOM inbound (`EnsLib.DICOM.Service.*`) → see `dicom` (stub).
- Email inbound (`EnsLib.EMail.InboundAdapter`) — covered by docs; this skill doesn't have validated examples.
- Workflow tasks / human steps — not a BS pattern.

## Scheduled, and order-sensitive, services

Wall-clock vs interval scheduling, `PoolSize` concurrency, and the synchronous chain for
sources with ordering dependencies: [references/scheduling.md](references/scheduling.md).
None of it is needed for a standard file, HL7 or REST intake.

## IRIS SQL dialect

Cheat-sheet moved to [references/sql-dialect.md](references/sql-dialect.md) — it is a SQL
topic, not an inbound-service one.

## See also

- `iris-interop-skills:messages` — design the message class first
- `iris-interop-skills:bpl` — what the Message Router/BP target looks like; sync chain for ordering dependencies
- `iris-interop-skills:production-lifecycle` — wiring the BS into the production class
- `iris-interop-skills:security` — when authentication needs more than HTTP Basic (SAML, OAuth)
- `iris-interop-skills:soap-bo` — the outbound side; many of the same WSDL caveats apply
