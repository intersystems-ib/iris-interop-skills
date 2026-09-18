# Best Practices and Gotchas — Ensemble & IRIS for Health Interoperability

> Distilled from ~10 years of customer interop projects (2014–2025) across 60+ healthcare and other customers. Synthesized 2026-05-07 by InterSystems Iberia.

## How to read this document

Each rule is tagged with:
- **Validity** — `Still valid` / `Resolved in IRIS X.Y` / `Superseded by ...` / `Historical` / `Verify against current docs`
- **Severity** — `High` (data-loss / outage risk) / `Medium` (significant operational impact) / `Low` (style / efficiency / informational)

## Provenance

Derived from field engagements; non-technical and customer-specific material was excluded.

> **Scope note (2026-05-13).** This document was originally synthesised as a generalist Ensemble/IRIS best-practices reference. It has been trimmed to focus on **IRIS Interoperability** patterns (BS/BP/BO/DTL/Rules, HL7 v2/v3/CDA, FHIR, SOAP/REST adapters, alerting, security on interop endpoints, migration of interop productions). Material on platform performance/sizing, mirroring/HA/backups, generic IRIS migration/install, and non-interop version notes was removed. Chapter numbering preserves the original §N for stable cross-references; gaps (§8, §10) are intentional.

## Table of contents

1. [Production design](#1-production-design)
2. [HL7 v2](#2-hl7-v2)
3. [HL7 v3 / CDA](#3-hl7-v3--cda)
4. [FHIR](#4-fhir)
5. [BPL & DTL patterns](#5-bpl--dtl-patterns)
6. [Adapters & connectivity](#6-adapters--connectivity)
7. [Error handling, retries & alerting](#7-error-handling-retries--alerting)
9. [Deployment, source control & CI/CD](#9-deployment-source-control--cicd)
11. [Security](#11-security)
12. [Monitoring & operations](#12-monitoring--operations)
13. [Migration of Interop productions](#13-migration-of-interop-productions)
14. [Version-specific notes (interop-relevant)](#14-version-specific-notes-interop-relevant)
15. [Appendix B — References](#appendix-b--references)

---

## 1. Production design

### 1.1 Naming convention (canonical, repeatedly observed)

All ObjectScript classes and Production components follow:

```
<Package>.<TipoComponente>.<NombreComponente>.cls
```

Total length recommended ≤ 45 characters (longer names are silently truncated by some Portal screens).

| Component type | Sub-package | Rule |
|---|---|---|
| Business Service | `.BS` | |
| Business Process | `.BP` | |
| Business Operation | `.BO` | |
| Data Transformation | `.DT` | Name as `<TipoMsgIn>To<TipoMsgOut>` (DataTransform Wizard suggestions key off this pattern) |
| Sub-Transformation | `.DTS` | |
| Message | `.MSG.<Name>{Req|Rsp}` | |
| Business Rule | `.RUL` | |
| Internal data classes (`%Serial`) | `.DAT` | |
| Adapter | `.ADP` | |
| Utility / FunctionSet | `.UTL` | |
| HL7 schema | `.HL7` | |

For **generated SOAP/XSD code** put each generated definition in its own sub-package so it can be deleted and regenerated cleanly:

| Component | Sub-package |
|---|---|
| Generated SOAP client root + proxy | `<Pkg>.<SubPkg>.WSC<Name>` |
| Generated server-side WS class | `<Pkg>.<SubPkg>.WS<Name>` |
| Generated BO | `<Pkg>.<SubPkg>.WSC<Name>.BO` |
| Generated request msg | `<Pkg>.<SubPkg>.WSC<Name>.REQ` |
| Generated response msg | `<Pkg>.<SubPkg>.WSC<Name>.RSP` |

The Production component's `Category` attribute MUST equal the package root (case-insensitive). This drives both the deployment tool and the visual filter in the portal.

- **Why.** Without the discipline, Production gets clobbered on deploy, patched system classes get lost on Ensemble upgrade, and DataTransform-Wizard auto-suggestions break.
- **Validity.** Still valid through IRIS 2024.x.
- **Severity.** High.

### 1.2 Reserved package names (portable convention)

Reserve package names for cross-cutting concerns:

- `Alt` — system classes that had to be patched (re-test on every Ensemble/IRIS upgrade).
- `<Customer>NoExport` — Production class itself + site-config table (must NEVER be deployed across sites).
- `INFRAESTRUCTURA` — system-management classes.
- `SOAPENC` — auto-generated SOAP encoding side classes; do not edit.

- **Validity.** Still valid.
- **Severity.** High.

### 1.3 When to split into multiple namespaces / productions

Drivers for splitting productions:

1. **Ownership / RBAC** — e.g. lab integrations live in their own production owned by the lab vendor.
2. **Tech-stack churn** — FHIR in its own production (DSTU2 → STU3 → R4 evolution; OAuth wizard regeneration).
3. **Security boundary** — external integrations (regional health-record exchanges, e-prescription gateways, etc.) isolated for tighter access control.
4. **Regulatory boundary** — anything subject to differential audit or data-residency rules.

Do **not** split for cosmetic reasons; each split adds operational burden (its own production-monitor, alert circuit, settings, source-control branch).

A later evolution observed at one site (2022+) consolidated to a single `INTEROP` namespace with categories per integration — managed by a deployment tool, with git source control. Both shapes are acceptable; the consolidation makes deployment simpler at the cost of weaker access boundaries.

- **Validity.** Still valid.
- **Severity.** Medium.

### 1.4 Configuration-source precedence — the four levels

Production component settings can come from four levels. Pick the level deliberately:

| Order | Portal colour | Source | Use for |
|---|---|---|---|
| 1 | green | Class property `InitialExpression` | Sensible defaults that almost never change (e.g. `Timeout = 10`) |
| 2 | black | Production XML | Values identical across all environments (these travel with the export) |
| 3 | blue | System Default Settings | Values that **differ** per environment (URLs, hostnames, credentials) |
| (advanced) | — | Registry | Rarely used |

**Visual cue at deploy time:** verify each per-environment setting shows blue in the portal after deploy — black means it is hard-coded in the production XML and will not differ between environments.

- **Why.** Site Defaults are the only settings layer that does NOT migrate via a Production XML deploy. Mis-classify a setting and a deploy clobbers production.
- **Validity.** Still valid.
- **Severity.** High.

### 1.5 Site Configuration: capture all four-environment values BEFORE deploy

When a developer adds a System Default Setting on dev, populate values for ALL environments in the site-configuration mirroring table (convention: `<YourOrg>NoExport.CFG.ConfiguracioSites`) at the same time. Don't wait for the migration day to remember which settings need values per site.

- **Validity.** Still valid.
- **Severity.** Medium.

### 1.6 Production-monitor + alert wiring (canonical baseline checklist)

Every production must include at minimum:

- A production-monitor service. The conventional *item* name is `Ens.ProductionMonitorService`; the `ClassName` you wire it to is `Ens.MonitorService`, which runs every 30 s (default) and “checks all hosts for inactivity”. Both names are real classes doing **different** jobs — `Ens.ProductionMonitorService` is the monitor service for *production status*, calling `UpdateProduction` once it notices the production is not up to date — so a wrong pick fails silently rather than at load.
- An `Ens.Alert` business process configured to handle `Ens.AlertRequest` messages.
- At least one alert-output BO (typically `EnsLib.EMail.AlertOperation` for email; a sink can equally be SMS, file, or a paging system — multiple sinks fan out through the router). Not `Ens.Alarm`: that item services `Ens.AlarmRequest` for BPL `<delay>` and timed waits, and is not an alert sink.

See §7 for the alert circuit details and the "always-on / dedupe" rules.

- **Validity.** Still valid.
- **Severity.** Medium.

### 1.7 ACK reply-code action defaults can swallow application errors

The default HL7 BO `ReplyCodeActions` `:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C` leaves application-level errors as suspended messages. For HL7 BOs whose calling BP wants to handle the ACK/NACK itself, override to `:?R=C,:?E=C,:~=C,:?A=C,:*=C,:I?=C` so all responses (including NACKs) are completed and the BP gets to inspect them.

- **Why.** Without override, an integration that intentionally returns negative ACKs (rejected admissions, etc.) creates a backlog of suspended messages that look like errors but aren't.
- **Validity.** Still valid.
- **Severity.** Medium.

### 1.8 Failure Timeout default of `-1` means infinite retries

Some HL7 BO classes ship with `Failure Timeout = -1` (retry indefinitely). Always set a finite value.

- **Why.** Pile-up of in-flight retries against an unreachable target consumes queue slots forever.
- **Validity.** Still valid.
- **Severity.** High.

### 1.9 Timeout precedence rule: BO timeouts < BP timeouts

A BO's `Tiempo de espera de respuesta` (Response Timeout) and `Tiempo de espera para error` (Failure Timeout) MUST be smaller than the calling BP's wait timeout. Otherwise the BP fires its timeout first, the BO never gets to mark its own error, and you lose the diagnostic chain.

- **Why.** Whoever times out first owns the error context; if the BP wins, the BO's `Ens.AlertRequest` and stack trace never fire.
- **Validity.** Still valid.
- **Severity.** High.

### 1.10 Scheduled BS concurrency: `PoolSize=1` alone is insufficient

To prevent concurrent execution of a scheduled Business Service: (a) set Pool Size = 1, AND (b) make all calls from the BS synchronous. Async calls let the BS finish before the work does, so a second Scheduler tick can fire while the first is still running. Also: any "manual" entry path (a Studio test or a non-scheduled inbound BS) bypasses the scheduler and is not subject to the lock.

- **Validity.** Still valid.
- **Severity.** Medium.

---

### 1.11 RecordMap file intake — configure the prebuilt service, never subclass it

The only class you author for a delimited-file intake is the **RecordMap definition**. The Business
Service, the poll loop and the per-record dispatch are all prebuilt: configure
`EnsLib.RecordMap.Service.FileService` as a production item with `RecordMap`, `TargetConfigNames`
and `HeaderCount` on target `Host`, and `FilePath`/`Charset` on target `Adapter`.

**Subclassing the FileService to reshape records does not work**, and the reason is worth knowing
before you try it. Verified with `%Dictionary.CompiledMethod` on IRIS for Health 2026.1:
`FileService.OnProcessInput` receives `pInput As %Stream.Object` — **the whole file** — and takes
three arguments. There is no per-record hook on it; `SendRecord()` exists only on the `Batch*`
services. So an override replaces the record loop the service exists to run, and a two-argument
override typed `pInput As EnsLib.RecordMap.Base` does not even compile (`#5478`). Put the reshaping
in a **DTL on the router**, which is where it belongs and where it is testable.

- **Source.** Workshop cohort 2026-09; signatures verified against 2026.1.
- **Validity.** Still valid.
- **Severity.** High — the wrong shape costs a rebuild, and the compile error names the signature, not the design.
- **Example.** `examples/ch01_production/recordmap-censo.cls`, `examples/ch01_production/production-censo-intake.cls`

### 1.12 Production class — the wiring IS the deliverable

A production class is an `Ens.Production` subclass whose entire content is one
`XData ProductionDefinition`. Everything operational lives in that XML: which items exist, their
`ClassName`, their `PoolSize`, and their settings split across target `Host` and target `Adapter`.
Getting the target wrong is the most common cause of "the setting had no effect" — `FilePath` is an
**Adapter** setting, `TargetConfigNames` is a **Host** setting, and the Portal shows them in one
list, which hides the distinction.

`Category` must equal the package root, and item names follow `<Tipo>.<Nombre>`.

- **Source.** Workshop cohort 2026-09.
- **Validity.** Still valid.
- **Severity.** Medium.
- **Example.** `examples/ch01_production/production-censo-intake.cls`

### 1.13 On IRIS for Health, an interop namespace is a FOUNDATION namespace

*Foundation Namespaces* (AFNS), opening line: **"Every interoperability-enabled production needs a
special interoperability-enabled namespace called a foundation namespace."** This is how an interop
namespace is initialised on **IRIS for Health** and **Health Connect** — it is not a FHIR detail and
not a recommendation. A Foundation namespace carries the healthcare interoperability configurations
and the `HS.*` mappings; a plain namespace has none of them.

**On plain IRIS — generic, non-healthcare integration — there is no Foundation concept and no
`HS.*`.** An interop-enabled namespace is all there is. Establish which product you are on first.

**Why it reads as a naming problem.** Without the mapping `HS.FHIRServer.*`, `HS.SDA3.*` and the
rest do not exist, so references look misspelled and people hunt for the "real" class name. And
`Ens.Director` resolves either way, so a namespace can be interop-enabled and still be missing half
the library — "interop-enabled" is not the same question as "Foundation".

| | how |
|---|---|
| **check** | `SELECT Name, Type, Activated FROM HS_Util_Installer.ConfigItem` — the table **existing** is the discriminator. Foundation: a row, `Type='Foundation'`. Plain: `SQLCODE -30, table not found` (AFNS section 1) |
| **create** | `Do ##class(HS.Util.Installer.Foundation).Install("<NS>")` from `HSLIB` (AFNS section 2) |
| **convert** | the **same call**, against the existing namespace — AFNS section 3 is explicit that this is what you must do to use IRIS for Health interoperability in a namespace not created as one |
| **SDA3** | if you use SDA3 transformations, import the SDA3 schema separately (AFNS section 4) |

`Install()` also creates `<NS>PKG.FoundationProduction`, so a production nobody wrote appears in
`iris_production(action=status)` — and a `start` of your own can then refuse with
`<Ens>ErrProductionSuspendedMismatch` naming it. That is a real production with a real class, so it
is the `exists:true` branch of the recovery ladder: stop it by name, do not reach for
`CleanProduction()`.

- **Source.** AFNS sections 1-4; HXFHIRINS section 2.3.1. Verified on IRIS for Health Community
  2026.1, including both controls on the ConfigItem check (Foundation: 1 row; `USER`: `-30`).
- **Validity.** Still valid.
- **Severity.** High — every symptom points at the wrong thing (a class name), and the real cause
  is invisible from the namespace itself.
- **Example.** `examples/ch04_fhir/production-fhir-facade.cls`

## 2. HL7 v2

### 2.1 Use a custom HL7 schema for non-standard partner messages

When a partner emits ER7 messages that deviate from the published HL7 standard (e.g., `SQM_S25` / `SRM_S25` missing `RGS` segment), define a custom HL7 schema based on v2.5 in the Portal, redefine just the affected messages, and set the BS's `MessageSchemaCategory` setting (Portal: “Message Schema Category”) to that schema name.

- **Validity.** Still valid.
- **Severity.** Medium.

### 2.2 HL7 schema changes are NOT auto-exported to source control

Custom HL7 schemas edited in the portal are stored in the namespace and are NOT auto-exported by SVN/git integration. You must manually `Export` to the SVN root after each edit. Failure to do so produces silent loss-of-work on environment refresh.

- **Validity.** Still valid.
- **Severity.** High (silent loss-of-work risk).

### 2.3 Escape special characters when constructing HL7 v2 strings

Ensemble auto-escapes HL7 v2 special chars when it generates the message itself (e.g. a system-generated NACK). When you build an HL7 message manually (e.g. a custom NACK in a BP catch), you must escape `| ^ ~ \ &` and CR/LF as `\F\ \S\ \R\ \E\ \T\ \X0D\\X0A\` via a helper like `Demo.UTL.FunctionSet.FormataTextPerHL7v2(<text>)` (or any equivalent). Inverse: `DesformataTextDesdeHL7v2`.

- **Why.** Without escaping, a `|` inside a free-text field collapses the segment structure and the receiver gets a malformed message.
- **Validity.** Still valid.
- **Severity.** Medium.
- **Example.** `examples/ch02_hl7v2/hl7v2-escape-functionset.cls`

### 2.4 Lab device integration: heterogeneous-vendor HL7 routing requires DTs in BOTH directions

When integrating with a lab analyzer / device vendor (Roche, Suitestensa, Cobas Pure, etc.), even directions that look like passthrough need a DT. Concrete example (Roche → SAP at a hospital site for OUL^R21): truncate `MSH-7` from `YYYYMMDDHHMMSS.fff` to `YYYYMMDDHHMMSS` (SAP rejects ms variant), re-order segments (move `SAC` to after `PV1`), copy technique code into `PID-2` and `PID-9` because SAP keys on those fields.

- **Validity.** Still valid.
- **Severity.** High.

### 2.5 Lab device integration: document every port pair per environment

Lab device integrations have asymmetric port pairs, often differing PRE vs PRO. Document every port pair in a single integration table per environment — don't hide it in BS/BO settings only. Don't expect symmetry: at one hospital site, PRE and PRO differ on the SAP-side port.

- **Validity.** Still valid.
- **Severity.** Medium.

### 2.6 HL7 v2 in XML form: use `intersystems-ib/Healthcare-HL7-XML`

When you need to handle HL7 v2 in XML form (e.g. carry it inside a SOAP MessageBody, or store it as XML in a non-IRIS system), use the public `intersystems-ib/Healthcare-HL7-XML` package rather than reinventing the conversion.

Test fixtures shipped with the helper package (useful as templates):

- `2.5_OBX5-ST.hl7.xml` — typical OBX-5 string-type result
- `2.5_ORMO01.hl7.xml` — order entry
- `ITB_ADTA01-EscapeField.hl7.xml` — ADT with field-escape characters (notorious bug source in custom parsers)
- `ITB_OBX5.hl7.xml` — alternate OBX-5
- `ITB_ORU-Inmutable.hl7.xml` — observation result with the "immutable" rule
- `ITB_ORUR01-FT.hl7.xml` — ORU-R01 with formatted-text segments

- **Validity.** Still valid; repo is actively maintained.
- **Severity.** Medium.

### 2.7 Mirth → Ensemble migration: don't translate channels 1:1

When migrating from Mirth, do NOT translate channels 1:1 into Productions. Group related channels (by upstream system, message family, or business process) into a single Ensemble production with shared message classes and routing tables. The Mirth-style "channel = entire flow" pattern is cheap to write but wastes Ensemble's strength (shared types, central router, common alerting).

| Mirth | Ensemble |
|---|---|
| Channel | Business Service + Business Process + Business Operation chain |
| Source + adapter | BS + adapter |
| Filter | router rule |
| Transformer | DT |
| Destination | BO |
| Postprocessor | post-execute hook (less natural in Ensemble; usually re-implemented as an additional BO step) |

- **Validity.** Still valid.
- **Severity.** Medium.

### 2.8 Rhapsody → Ensemble: parallel-run with byte-equal-diff acceptance criterion

When migrating between two HL7 engines (Rhapsody → Ensemble), run them in parallel with three namespaces:

- `PROD` — current production (customer-managed) — keeps running for legacy integrations
- `PROD-MIG` — migrated production (vendor-managed) — receives messages flagged `PENDIENTE_MIG`
- `PROD-MIG-DIFF` — comparator namespace — receives outputs from BOTH engines; compares messages for exact equality

Acceptance criterion: messages generated by `PROD-MIG` MUST be byte-equal to those generated by Rhapsody. After validation, import `PROD-MIG` into `PROD`, decommission `PROD-MIG-DIFF`. **Caveat:** during parallel, the upstream HL7 Filler/Service load doubles.

- **Validity.** Still valid.
- **Severity.** High.

### 2.9 ORM/SQL adapter: synchronous chain when source rows have ordering dependencies

When source-system rows have ordering dependencies (e.g. a "Reprogramacio" cannot be applied before its "Programacio"), prefer a synchronous BS → BP → BO chain over async messaging. The BO that writes to the source system uses `AutoCommit=0` so it can roll back row changes if the downstream call fails. Document the trade-off (throughput vs. correctness) explicitly.

- **Validity.** Still valid.
- **Severity.** Medium.

---

### 2.10 HL7 file intake — the prebuilt HL7 service and the HL7-SPECIFIC router

No custom Business Service: configure `EnsLib.HL7.Service.FileService`. Two settings carry the
whole design.

**`MessageSchemaCategory` gives every parsed message its DocType.** Unset, the message arrives with
no schema and symbolic field names stop resolving *everywhere downstream* — a segment inherits its
DocType from the message, so one missing setting silently degrades every DTL to numeric paths.

**The router must be `EnsLib.HL7.MsgRouter.RoutingEngine`, not the generic engine** (CR-6). The
generic one transports an `EnsLib.HL7.Message` perfectly well, so an end-to-end test passes either
way; what it loses is schema validation in the rule editor and `{MSH:9.1}` path syntax. The failure
is invisible until someone tries to write a rule. Pair it with `Validation="dm"` so a malformed
message reaches the `BadMessageHandler` instead of flowing on.

- **Source.** Workshop cohort 2026-09; verified against 2026.1.
- **Validity.** Still valid.
- **Severity.** High — both failures are silent and both survive a green test.
- **Example.** `examples/ch02_hl7v2/production-hl7-intake.cls`

### 2.11 Symbolic HL7 field paths — and why an empty result proves nothing

**Address segments and fields BY NAME, not by position.** `MSH:MessageType.MessageCode` rather than
`MSH:9.1`; `PV1:PatientClass` rather than `PV1:2`. A positional path is correct and unreadable, and
HL7 work is reviewed by eye — the reviewer who has to decide whether `PV1:3` is the right field is
the person the name is for. Names also survive a schema revision that renumbers nothing but tells
you, at the point of use, what you are reading.

Measured on the stock 2.5 schema:

| positional | named |
|---|---|
| `MSH:9.1` | `MSH:MessageType.MessageCode` |
| `MSH:9.2` | `MSH:MessageType.TriggerEvent` |
| `MSH:10` | `MSH:MessageControlID` |
| `MSH:6` | `MSH:ReceivingFacility` |
| `PV1:2` | `PV1:PatientClass` |
| `PV1:3` | `PV1:AssignedPatientLocation` |
| `PID:3.1` | `PID:PatientIdentifierList(1).IDNumber` |
| `PID:5.2` | `PID:PatientName(1).GivenName` |

Three rules that come with it, all measured:

1. **You cannot mix.** `MSH:MessageType.1` is **invalid** — naming the field obliges you to name the
   component too. Name the whole path or none of it.
2. **Names are case-insensitive.** `MSH:messagetype` and `MSH:MessageType` both resolve; the schema
   stores the lowercase form, and CamelCase is what reads well in a transform.
3. **A DocType must be assigned**, or only positional paths resolve — see the fixture rules below.

**Discovering a name — do not guess it.** `##class(EnsLib.HL7.Schema).GetFieldNameFromNumber(category,
segment, number)` is authoritative: `("2.5","PV1",2)` returns `patientclass`. Note the gap, measured:
it returns **empty for repeating fields** (`PID:3`, `PID:5`, `OBX:5`), so for those read the name off
the Schema Editor or confirm a candidate with `GetValueAt` and check the status. `GetFieldNumberFromName`
does the reverse when you are reading someone else's positional code.

**Where a name is not the answer at all: a routing rule's match.** Constrain on `docCategory` /
`docName` rather than comparing any MSH field, named or numbered — that is conformance criterion
CR-5, and it is a stronger statement than this section: the named form is better than the numbered
one, and not matching on MSH at all is better than both.


The mechanism has two traps, and both are silent.

**The compiler cannot check a path.** Measured on 2026.1: a DTL compiles identically with
`{PID:PatientName(1).FamilyName.Surname}` and with `{PID:PatientNameXX(1).FamilyName.Surname}`,
which resolves to nothing. Tier 2 is green on both. Only running the transform and asserting an
output field separates them.

**An empty result is ambiguous.** Measured with `GetValueAt` on one ADT^A01:

| path | value | status |
|---|---|---|
| `PID:PatientIdentifierList(1).IDNumber` | `12345` | OK |
| `PID:PatientIdentifierList(1).ID` | `""` | **ERROR** — `PropertyPath … is invalid` |
| `PID:PatientID` — a real field, empty in this message | `""` | **OK** |

A mistyped path and a legitimately empty field both yield `""`. The status is the only
discriminator — and the two-argument `GetValueAt(path)`, which is the form everyone writes and the
form a DTL `<assign>` generates, **discards it**. This is why "the assertion passed on an empty
string" is the characteristic way an HL7 transform is wrong.

Note `.IDNumber`, not `.ID`: the field name is right and the obvious component name is wrong, so
guessing the second half of a path fails the same silent way as guessing the first.

**Fixture rules, all measured:** `ImportFromString` is a classmethod whose third argument is
`pConfigItem`, *not* a schema category; segments are separated by `$Char(13)`; and **DocType is
empty after import** — it must be set with `DocTypeSet("2.5:ADT_A01")` or every symbolic path
returns `""` and the test passes on empty strings.

Set `Parameter REPORTERRORS = 1` on the transform so an unresolvable path is reported rather than
absorbed into the same `""` an empty field produces. And prefer `create='copy'` for a
normalisation step: `create='new'` starts from an empty message and silently drops every segment
you did not explicitly assign.

- **Source.** Bank audit 2026-09-18; the bank's only DTL was object→object in an HL7-first plugin.
- **Validity.** Verified against IRIS for Health 2026.1 using the stock 2.5 schemas.
- **Severity.** High — the failure is an empty field, which is also what success looks like for an optional one.
- **Example.** `examples/ch02_hl7v2/dtl-hl7-symbolic-paths.cls`

## 3. HL7 v3 / CDA

### 3.1 CDA-from-XSD class generation: Persistent + no Relationships + OnDelete Cascade

When importing CDA into ObjectScript classes from the XSD via the XML Schema Wizard, the only working combination is:

- **Persistent** — required so messages persist with Ensemble messages
- **No Relationships** — `Relationships=1` causes serialisation to XML to take ~60 s per CDA (too slow for production)
- **`OnDelete = Cascade`** — required so purging an Ensemble message also purges the CDA child rows (avoids orphan accumulation)

Tested alternatives that fail:

- Serializable classes — cyclic-reference compile error (`Component` contains `Component`).
- Persistent with Relationships — slow XML serialisation as above.

- **Validity.** Still valid.
- **Severity.** High.
- **Example.** `examples/ch03_cda/cda-from-xsd-persistence-pattern.cls`

### 3.2 Comanda/Resposta inheritance trick for "one-of-N subtypes" payloads

When the schema defines one envelope type whose actual content is one of N subclasses (e.g. `Comanda` with `SC1` or `SC2` content variants), make the generated wrapper class abstract and create concrete subclasses (`ComandaSC1`, `ComandaSC2`) that the BS instantiates based on inspection of the inbound payload. The DataTransform Wizard then sees concrete types and proposes correct mappings.

- **Validity.** Still valid.
- **Severity.** Medium.
- **Example.** `examples/ch03_cda/comanda-resposta-inheritance.cls`

### 3.3 CDA stylesheet (`cda.xsl`) security advisory: April 2014+ only

The standard HL7 CDA stylesheet had multiple security holes before April 2014: XSS via the `nonXMLBody` rendered inside an `<iframe>`, illegal table attributes (`onmouseover`), image URIs to hostile sites. Use only the patched version from the HL7 Structured Documents WG.

- **Validity.** Still valid as a sanity check on any CDA viewer shipped with a customer system.
- **Severity.** High (security).

### 3.4 SOAP carrying CDA / HL7 as MessageBody — the canonical pattern

When a third-party WSDL specifies a custom `acceptMessage(message)` with the HL7 ER7 text in a string field (NOT the standard Ensemble `EnsLib.HL7.Util.SOAPClient` shape), customise the auto-generated SOAP proxy:

- Change the parameter from `%String` to `%Stream.GlobalCharacter` (HL7 messages can exceed string limits).
- Copy `EnsLib.HL7.Operation.SOAPOperation` as the BO base.
- Override `..Adapter.WebServiceClientClass` to point to the custom proxy.
- Adapt `..Adapter.InvokeMethod("acceptMessage", ...)` (default would call `Send`).

The same pattern applies for SOAP-carrying-CDA to a regional health-record exchange (e.g. `<publishDocument>` with a CCD `<ClinicalDocument xmlns="urn:hl7-org:v3">` directly in the SOAP Body parameter).

- **Validity.** Still valid.
- **Severity.** High.
- **Example.** `examples/ch03_cda/soap-messagebody-hl7-proxy.cls`

---

## 4. FHIR

### 4.1 FHIR Façade pattern (canonical for mobile-data-into-EMR)

Use IRIS as a FHIR Façade — not a FHIR repository — when the data needs to land in an existing EMR. The Façade keeps FHIR as the public API contract; the actual data is owned by the EMR. Avoids dual-write + reconciliation.

Reference architecture (a hospital site, 2024 — personal device data ingestion):

```
device → vendor mobile app
       → Google Health Connect / Apple HealthKit
       → hospital native mobile app
       → HTTPS+OAuth2 → IRIS-for-Health 2024.1 (FHIR Façade + OAuth2 server)
       → REST/SOAP → SAP (EMR)
```

- **Validity.** Still valid; Façade is a first-class deployment mode.
- **Severity.** Medium.

### 4.2 Mobile clients: OAuth 2.0 with PKCE

For mobile clients, use the OAuth 2.0 `Authorization Code Grant Type with PKCE extension`. Don't use `client_credentials` (machine-to-machine, no user) or implicit (deprecated). PKCE protects the auth code from interception on mobile.

- **Validity.** Still valid.
- **Severity.** High.

### 4.3 Privacy-preserving identity flow on a public FHIR Façade

When the FHIR server is on the public Internet, minimise the data IRIS holds. The EMR generates a per-program patient identifier (UUID, email, opaque ID) and shares it both with IRIS (for OAuth authentication) and with the patient (who keys it into the mobile app). IRIS only ever sees the opaque ID, never PHI from the EMR.

- **Why.** Reduces both attack surface and GDPR scope.
- **Severity.** High.

### 4.4 Wire shape: Bundle of Patient + Observation resources

The data shape sent from mobile → FHIR API: a Bundle of `Patient` (with the per-program identifier) + a collection of `Observation` resources, sent as a single FHIR Bundle.

- **Severity.** Low.

### 4.5 FHIR R4 is the version targeted in 2024+

New customer FHIR work in 2024+ uses HL7-FHIR R4. Earlier customer work in this corpus (2017–2018) was DSTU2/STU3.

- **Validity.** Tag any DSTU2/STU3 finding as **Superseded by FHIR R4**.

### 4.6 FHIR Façade SOW out-of-scope checklist

Every FHIR-Façade SOW must contain an explicit "out-of-scope" list with at least these six items, since most customer escalations come from one being assumed by the wrong party:

1. The TLS server certificate (from a CA — must be requested in advance).
2. Hardware.
3. Maintenance & support phase.
4. The IRIS license (assumes an existing license can absorb the new namespace).
5. The IRIS upgrade if not already on a version that supports the FHIR R4 façade.
6. The EMR-side API (the customer's developer must expose it; IRIS calls it).

- **Severity.** Medium (process).

### 4.7 Operational requirements for a public FHIR Façade

The four canonical things to monitor on a public FHIR Façade:

1. Listing of registered users (program enrolment).
2. Listing of users + the data they sent.
3. Errors in observation reception.
4. OAuth login error log.

- **Severity.** Medium.

### 4.8 FHIR repository as DataLake backbone (2021 trend)

A 2021+ trend: customers replace ETL → DW with HL7v2 → FHIR-repository → consumer-via-FHIR. One customer's project: build a FHIR repository on infrastructure independent of the HIS; replaces FactTable/Cube exports for WebFocus reporting; consumed by Microsoft Dynamics CRM (which speaks FHIR natively).

Open architectural questions captured in that plan (useful as a checklist):

- SMART-on-FHIR layering on top of the repo
- FHIR validation enforcement
- FHIR client patterns inside IRIS for inserts/updates with linked resources (avoid duplicate-Observation insertion)
- Profile + Extension creation, IG Publishing tool
- Versioning support in IRIS
- Anonymisation requirements

- **Validity.** Snapshot 2021; verify current state at audit time.
- **Severity.** Low (planning).

### 4.9 FHIR SQL Builder (IRIS for Health 2022.1+)

The FHIR SQL Builder projects FHIR repository data to custom SQL schemas WITHOUT moving the data. Use cases: ANSI SQL queries / Power BI / Tableau against FHIR data, when data analysts know SQL but not FHIRPath. Components: IRIS for Health FHIR Repository → FHIR SQL Builder analysis engine → custom SQL projection tables → Builder Client UI. Design via match expressions (FHIRPath subset) e.g. `system='http://hospital.smarthealthit.org'` to filter Patient.identifier arrays.

Setup: Docker-based; populate via `Do ##class(HS.HC.FHIRSQL.Utils.Setup).Setup("/data/fhirdata/")` in `HSLIB` namespace; portal at `/csp/fhirsql/index.csp`.

- **Validity.** Verify current GA status; this was 2022.1 EAP.
- **Severity.** Medium.

---

### 4.10 FHIR interop — the Facade wiring, and why it needs a Foundation namespace

**The prerequisite is a namespace, not a class name, and that is why it costs time.** `HS.*` is
not mapped into an ordinary namespace: in `USER`, `HS.FHIRServer.Interop.Operation` does not exist,
so every reference reads as a typo and the reflex is to hunt for the "real" name. There isn't one.
IRIS for Health ships `HSLIB`/`HSSYS`/`HSCUSTOM` in the image; a **Foundation namespace** maps them
in and is interop-enabled at the same time (HXFHIRINS §2.3.1):

```objectscript
 Do ##class(HS.Util.Installer.Foundation).Install("FHIRFOUNDATION")
 Set $namespace = "FHIRFOUNDATION"
 Do ##class(HS.FHIRServer.Installer).InstallNamespace()
 Do ##class(HS.FHIRServer.Installer).InstallInstance(appKey, strategyClass, metadataPackages)
```

A Foundation namespace is a strict **superset** of a plain interop namespace — verified: the whole
example bank and every inline snippet compile in it with byte-identical results. So it is also what
the example gate runs in, and FHIR stops being a special case.

**The three interop classes, none of them guessable:** `HS.FHIRServer.Interop.Service` (inbound),
`HS.FHIRServer.Interop.Operation` (outbound to a **local** FHIR server), and
`HS.FHIRServer.Interop.HTTPOperation` (outbound to an **external** one). The body travelling between
them is `HS.FHIRServer.Interop.Request`/`.Response` — not a project message class and not a raw
stream, so a DTL over a FHIR payload works on the Request's `QuickStreamId`, not on properties.

**Facade vs Repository is one ClassName.** `HTTPOperation` means the resources live in the external
server and nothing persists locally; `Interop.Operation` means this namespace serves from its own
storage. Same wiring either way.

- **Source.** Verified against IRIS for Health Community 2026.1 in a Foundation namespace, 2026-09-18.
- **Validity.** Still valid.
- **Severity.** High — the namespace prerequisite is invisible until nothing resolves.
- **Example.** `examples/ch04_fhir/production-fhir-facade.cls`

## 5. BPL & DTL patterns

### 5.1 BS that exposes a SOAP service: how to wire it

When you need a Business Service that accepts inbound SOAP requests:

1. New → General → Web Service in Studio; define the WS.
2. Change the parent class from default `%SOAP.WebService` to `EnsLib.SOAP.Service`.
3. Refactor → Override the `Adapter` parameter to blank (default would be `EnsLib.SOAP.InboundAdapter`, which prevents direct inbound).
4. Implement web methods with `[WebMethod]` and parameters typed to `MSG.<Name>{Req|Rsp}` classes.
5. Override `OnProcessInput` and call the BP synchronously or asynchronously as needed.

- **Validity.** Still valid.
- **Severity.** Medium.
- **Example.** `examples/ch05_bpl_dtl/soap-business-service.cls`

### 5.2 BS that runs on a schedule: use a custom adapter for wall-clock triggers

Default Ensemble inbound adapters only do interval scheduling ("every X seconds"). For wall-clock schedules (daily 08:30, weekdays 08–18, etc.) use a custom adapter (e.g. `Demo.ADP.SchedulerAdapter`) with a cron-style format `min hour day month dayOfWeek`. Or (modern alternative) use IRIS's native task framework: subclass `%SYS.Task.Definition` and override `OnTask`. (`%SYS.TaskSuper` also exists but is documented “for internal use only” — it is the persistent superclass of `%SYS.Task` and has no `OnTask`.)

- **Validity.** Still valid; prefer native task framework for greenfield.
- **Severity.** Low.

### 5.3 XML projection of message classes — three settings to know

**`XMLIGNORENULL = 1`** (class-level, NOT property-level). Forces empty-string properties to appear in the XML output as empty elements (`<NOM/>`). **Caveat:** for `list of <T>` collections where every item is empty, the list element is omitted entirely — there is no clean way to force its presence except manual XML manipulation.

**`CONTENT = "STRING"` vs `CONTENT = "ESCAPE"`** on `%Stream.GlobalCharacter` properties. `STRING` wraps the content in `<![CDATA[...]]>`. `ESCAPE` XML-escapes the text. Pick `STRING` when the payload is XML you don't want re-escaped (e.g. the CDA going through a SOAP envelope); pick `ESCAPE` for free-text fields.

**`OUTPUTTYPEATTRIBUTE = 0`** on the SOAP proxy class — suppresses `xsi:type` attributes on every element. Some SOAP servers reject the unexpected attributes (see §6).

- **Validity.** Still valid (verify in IRIS 2024.x — long-standing quirks).
- **Severity.** Medium.
- **Example.** `examples/ch05_bpl_dtl/xml-projection-settings.cls`

### 5.4 ObjectScript error-handling idiom

```objectscript
{
    #DIM tSC as %Status = $$$OK
    #DIM errObj as %Exception.AbstractException
    try {
        $$$THROWONERROR(tSC, ..<MethodName>(<args>))
        // OR
        set tSC = ..<MethodName>(<args>)
        $$$ThrowOnError(tSC)
    } catch (errObj) {
        set tSC = errObj.AsStatus()
    }
    quit tSC
}
```

- **Why.** Ensemble libraries and wizard-generated code don't use modern try/catch; refactor opportunistically. Always return `%Status`.
- **Validity.** Still valid.
- **Severity.** Low (style).
- **Example.** `examples/ch05_bpl_dtl/objectscript-trycatch.cls`

### 5.5 Async logging: prefer `^IRISTemp.*` + `%SYSTEM.Semaphore` over IPQ

When implementing async logging from many writer processes to one (or a few) logger reader process(es), choose **temporary globals** (under `^IRISTemp.*`) over IRIS IPQ. The logger blocks on a semaphore and is woken by writers when data is added. Multiple readers possible; sync via the same semaphore.

**Get the semaphore class right.** It is `%SYSTEM.Semaphore` — singular, `%`-prefixed — reached as `$SYSTEM.Semaphore`. There is no `System.Semaphores`. It is an *instance* API, not class methods on `$SYSTEM`; there is no `Signal` and no `Wait`:

```objectscript
set sem = ##class(%SYSTEM.Semaphore).%New()
do sem.Create(name, 0)      // owner creates; joiners use sem.Open(name)
do sem.Increment(1)         // writer signals
set rc = sem.Decrement(1, timeout)  // logger waits
```

Instance methods: `Create(name,value)`, `Open(name)`, `Delete()`, `Increment(value)`, `Decrement(amount,timeout)`, `GetValue()`, `SetValue(amount)`, `AddToWaitMany()`, `RmFromWaitMany()`, `WaitCompleted()`. Class method: `WaitMany(timeout)`.

Why temporary globals over IPQ:

- IPQ is one-writer-one-reader per queue — many-writers-one-reader needs the internal undocumented `%SYSTEM.IPQSet`.
- IPQ has bounded size — full queue blocks writers, cascading pause across the application.
- IPQ is memory-only (lost on crash).

Temporary globals are not journalled, never part of the writer's transaction (no rollback risk), and only spill to disk on memory overflow — graceful degradation. IPQ's pass-by-reference benefit (`IPQ.MsgReceivedByRef()`) only matters for very-large objects; for typical log records (< 1 MB) it's dwarfed by the blocking risk.

- **Validity.** Still valid.
- **Severity.** Medium.
- **Example.** `examples/ch05_bpl_dtl/async-logger-iristemp-semaphore.cls`

---

### 5.6 Custom BPL: context variables, a sync call, and the code-block idiom

Reach for a custom BPL only when the flow is genuinely multi-step: synchronous sub-calls, conditional branches, fan-out/aggregation, error compensation. For "route this message onwards", use a MessageRouter plus a routing rule (§5.8) — a hand-written `Ens.BusinessProcess.OnRequest` doing the routing is conformance **CR-1**.

The `<context>` block is the point of the shape. Context properties persist for the BPL's whole lifetime and survive a `<call>`; locals inside a `<code>` activity do not. Anything that must cross an async boundary lives in the context.

Two traps that are not visible in the editor:

- The BPL editor writes **straight into the namespace** and bypasses the source-of-truth gate. On some IRIS versions it silently strips `XData BPL` on first open, and the class then reports `Missing BPL Data`. Recovery is a copy-paste back into the block — which only works if the class is on disk as text. After any editor session, `iris_doc(mode=get)` the class and write it back to `src/`.
- A BO's `Response Timeout` must be **smaller** than the calling BP's. Whichever side times out first owns the error context; if the BP goes first, the BO never gets to record its own failure.

- **Validity.** Still valid.
- **Severity.** Medium.
- **Example.** `examples/ch05_bpl_dtl/bpl-order-process.cls`

---

### 5.7 DTL: declare the transform, don't write it imperatively

An `Ens.DataTransformDTL` subclass with **no `XData DTL` still compiles** — and the Portal's DTL editor then opens nothing (conformance **CR-4**). Moving the same logic into a hand-written BP `OnRequest` is **CR-1**, a P1 finding. If a transform genuinely cannot be declared, that is a design signal worth raising, not a licence to write it by hand.

**The body is XML first and ObjectScript second.** The operators that collide are the ones ObjectScript uses most:

| ObjectScript | Inside XData |
|---|---|
| `&&` | `&amp;&amp;` |
| `&` | `&amp;` |
| `<`, `<=` | `&lt;`, `&lt;=` |

An unescaped `&` fails with `ERROR #6301: SAX XML Parser Error: expected entity name for reference`, and the reported line and offset point into the **XData stream**, not into your source file — the numbers will not match your editor. Wrapping raw ObjectScript in `<![CDATA[ … ]]>` avoids the whole class of problem and survives later edits better.

**Compile order matters.** `Transform` is built by a method generator that resolves `sourceClass` and `targetClass` at generation time, so both must already be compiled. Compiling a DTL in the same batch as its own message classes can fail with `#5001 <CLASS DOES NOT EXIST>` wrapped in `#5490 Error running generator`, even though the classes are in the batch. It is an ordering artefact, not a defect — compile the messages first, or just compile twice.

- **Validity.** Still valid.
- **Severity.** High.
- **Example.** `examples/ch05_bpl_dtl/dtl-order-to-vendor.cls` (+ sibling `msg-vendororder.cls`)

---

### 5.8 Routing rule: one rule per source msgClass, N sends inside it

The canonical fan-out is **one `<rule>` per source message class, with N `<send>` actions inside its `<when>` block** — not one rule per destination. Splitting per destination to "isolate failures" conflates runtime fault tolerance with architecture: it multiplies rules and makes routing harder to reason about. Flaky destinations are handled by settings on the Router **item** — `AlertOnError`, `BadMessageHandler`, `ReplyCodeActions`.

**Pair the engine with the assist class.** A rule for custom `Ens.Request` subclasses uses `EnsLib.MsgRouter.RuleAssist` with `context="EnsLib.MsgRouter.RoutingEngine"`. HL7 needs `EnsLib.HL7.MsgRouter.RuleAssist` and `EnsLib.HL7.MsgRouter.RoutingEngine`; running HL7 through the generic engine still compiles and still passes tests, but silently loses schema validation and the `{MSH:9.1}` paths (conformance **CR-6**).

**A `condition=` is not ObjectScript.** The rule XData is compiled into `evaluateRuleDefinition` by a generator that reports offsets into *generated* code, so `#5490` never points at what you wrote:

| Don't write | Write |
|---|---|
| `'=` (ObjectScript "not equal") | `!=` |
| `document.Field` | `Document.Field` — capitalised; lowercase does not resolve |
| `##class(Pkg.UTL.X).Check(Document)=1` | put the method on an `Ens.Rule.FunctionSet` subclass, call it bare: `Check(Document)=1` |

**A rule that compiles can still break at runtime.** Nothing checks that `transform=` and `target=` resolve: a missing transform class or a target that is not a production item compiles clean and fails at runtime with `<CLASS DOES NOT EXIST>` or `target 'X' not an item`. Run the pre-flight `ValidateProduction()` validator (in the `bpl` skill) before every production start.

- **Validity.** Still valid.
- **Severity.** High.
- **Example.** `examples/ch05_bpl_dtl/routing-rule-fanout.cls`

---

### 5.9 TDD for interop — `%UnitTest.TestProduction`, and what a green actually proves

Test classes extend **`%UnitTest.TestProduction`**, not `%UnitTest.TestCase`. It is the Interop
superclass: it carries the production lifecycle helpers (`..SendRequest`, `..GetEventLog`) a
routing-rule or BO test needs, and `Run()` works by class name with no `/noload` gymnastics.

**`Parameter PRODUCTION` is compile-time mandatory** — omit it, or set it to `""`, and the class
does not compile. When the production is managed outside the test, declare it anyway and neutralise
the lifecycle with a `TestControl()` that returns `$$$OK`.

**A green only means what the assertions can fail on.** Asserting the `%Status` of a
`Transform()` and nothing else passes against a transform that produced an empty target — the most
common vacuous green there is. Assert on a field the component actually **writes**, and cover both
sides of every conditional.

Run it with the tool, one compiled class per call — `pattern` does **not** expand a package:

```
iris_test(pattern="Example.Tests.OrderToVendor", namespace="<NS>")
```

A suite of N test classes is N calls, all after the last recompile. What is forbidden is mixing
generations, not adding up calls. And `^UnitTestRoot` must point at a directory that exists on the
**server**, or the run reports zero tests and still exits clean.

- **Source.** Workshop cohort 2026-09; verified against 2026.1.
- **Validity.** Still valid.
- **Severity.** High — a vacuous green is worse than a red, because it stops the search.
- **Example.** `examples/ch05_bpl_dtl/tdd-testproduction-dtl.cls`

### 5.10 Message class design — `%Persistent` must be leftmost, and no compile will tell you it is not

An interop message class needs `%Persistent` **as its leftmost superclass** to get its own storage
extent. `Ens.Request` already inherits persistence, so every spelling below compiles, projects to
SQL, saves, and reads its properties back correctly. Only where the rows LAND differs — measured on
IRIS for Health 2026.1 by reading `%Dictionary.CompiledStorage.DataLocation`:

| declaration | `DataLocation` | |
|---|---|---|
| `Extends (%Persistent, Ens.Request)` | `^MyApp.MSG.NameD` | own extent ✅ |
| `Extends (Ens.Request, %Persistent)` | `^Ens.MessageBodyD` | shared — **`%Persistent` present but not leftmost is the same as omitting it** |
| `Extends Ens.Request` | `^Ens.MessageBodyD` | shared |

IRIS takes the **leftmost** superclass as primary, and the primary superclass is what drives
storage. The middle row is the trap: it looks like the rule was followed.

**Why a shared extent costs you.** Every message body in the namespace lands in one global, so
per-message-type purging, a selective index, a `SELECT` over one message type, and any per-type
storage tuning all stop being available — and you discover this at the point where you have a
production-sized global and the least freedom to change it. The defect is invisible in development:
with a hundred test messages nothing about a shared extent looks wrong.

**No tier of the gate can catch this**, which is why it is stated here and asserted in a test. It is
not a syntax error, not a runtime error, and not a wrong result — it is a storage decision that a
compiler has no opinion about. The test reads `DataLocation` out of the dictionary and asserts the
global name; that is the only mechanical check that exists.

- **Source.** Bank audit 2026-09-18; all four interop message classes in this bank had the shared shape.
- **Validity.** Verified against IRIS for Health 2026.1.
- **Severity.** High — silent, and expensive exactly when it is discovered.
- **Example.** `examples/ch05_bpl_dtl/msg-persistent-leftmost.cls`

### 5.11 A `%Persistent` child needs a delete cascade, and the obvious cascade discards its own error

A `%SerialObject` sub-object serialises **inline** into its parent's row: purging the message purges
it too, and there is nothing to cascade. A `%Persistent` sub-object gets **its own rows**, and
`Ens.Util.Tasks.Purge` knows nothing about them — it deletes `Ens.MessageHeader` and the message
row, the child rows stay, and there is no error, no warning and nothing in the Event Log. You find
out when that table is the largest object in the namespace.

The cascade goes on the class that **references** the child. Four things in it, all of which have
shipped wrong here:

| | |
|---|---|
| `{Address}`, not `{ID}` | inside a trigger `{ID}` is the row being deleted — the carrier's own id. `%DeleteId({ID})` deletes whichever child happens to share it: an unrelated row, or none. Silent, because deleting nothing raises nothing. |
| the child must really be `%Persistent` | measured on 2026.1, `%DeleteId` **does** exist on `%SerialObject`, so pointing a cascade at one compiles — and returns `ERROR #5753: Cannot instantiate abstract class` at runtime. |
| capture the `%Status` | `Do ##class(…).%DeleteId(…)` **discards** it. With the row above, that is the entire silent failure: the call fails, the status is dropped, the trigger reports success. |
| guard the empty reference | the property is optional and `%DeleteId("")` errors, so an unguarded trigger sets `%ok = 0` and makes childless carriers **undeletable** — the trigger meant to help a purge is what stops it. |

`Set %ok = 0` aborts the parent delete, so a purge that cannot clean a child stops rather than
orphaning it. The alternative is to log and let the delete proceed. Choose deliberately; what is
never right is discarding the status, which gives you both an orphan and no record.

- **Source.** Bank audit 2026-09-18; the inline snippet this replaces aimed its cascade at a serial class.
- **Validity.** Verified against IRIS for Health 2026.1, and executed: `childBefore=1 delParent=OK childAfter=0`.
- **Severity.** High — silent, and unbounded.
- **Example.** `examples/ch05_bpl_dtl/msg-persistent-child-delete-cascade.cls`

### 5.12 Class-based `Ens.BusinessProcess` — the async reply is silently discarded unless you ask for it

`bpl` recommends a class-based BP when a BPL diagram stops being readable, and CR-1 is a rule about
the shape — but only `Ens.BusinessProcessBPL` was ever shown, so "BP" and "BPL" became synonyms.

Everything turns on the **third positional argument** of `SendRequestAsync`:

```
..SendRequestAsync(target, request, pResponseRequired, pCompletionKey, pDescription)
```

Measured by running both versions in a real production on 2026.1 and counting callbacks:

| `pResponseRequired` | `OnRequest` | operation ran | `OnResponse` | `OnComplete` |
|---|---|---|---|---|
| `1` (correct) | 1 | 1 | **1** | 1 |
| `0` (the defect) | 1 | **1** | **0** | 1 |

Read the `0` row carefully, because the intuition about it is wrong: the operation **did** run and
**did** produce a response. Nothing failed. The reply was simply never routed back, so `OnResponse`
never executes and the process completes **successfully**. The Visual Trace shows a completed BP with
a response from the operation — what it cannot show is that your handling of that response never ran.

The default is `1`, so the defect takes writing `0`, which people do when they mean "I don't need to
block here". That is not what it controls. Async versus blocking is `SendRequestAsync` versus
`SendRequestSync`; `pResponseRequired` is *"will a reply come back to me at all"*.

**Completion is not what returning `$$$OK` does.** While replies are outstanding the framework tracks
them in `..%MasterPendingResponses` and completes only after the last one is handled — then
`OnComplete` runs, and its `response` is what the caller receives. With `pResponseRequired = 0` there
is nothing to wait for, so completion is immediate, which is precisely why the defect presents as a
fast, healthy process.

The callback signatures are not guessable, and `callresponse` (the target's reply) versus `response`
(what this process returns) is easy to get backwards:

```
OnRequest(request, *response)
OnResponse(request, &response, callrequest, callresponse, pCompletionKey)
OnComplete(request, &response)
OnError(request, &response, callrequest, pErrorStatus, pCompletionKey)
```

`pCompletionKey` is how replies are told apart: with more than one outstanding call `OnResponse` is
entered once per reply and the key is the only discriminator.

- **Source.** Bank audit 2026-09-18; the bank had no class-based BP at all.
- **Validity.** Verified against IRIS for Health 2026.1 in a running production, both variants.
- **Severity.** High — the reply is dropped and everything reports success.
- **Example.** `examples/ch05_bpl_dtl/bp-class-based-async.cls`

### 5.13 Calling a function from a DTL — the two forms have opposite rules and the wrong one is silent

A DTL calls a **built-in** with `..` and a **custom** FunctionSet method with `##class()`. Those are
not stylistic alternatives; each context rejects the other form, and the *third* form — bare —
compiles everywhere and fails at runtime. All six combinations measured on 2026.1:

| context | form | compile | runtime |
|---|---|---|---|
| DTL, built-in | `..Strip(x,"<>W")` / `..Lookup(t,k,d)` | ✓ | **works** |
| DTL, built-in | `Strip(x,…)` / `Lookup(t,k,d)` — bare | ✓ | **`<UNDEFINED>`** |
| DTL, custom | `##class(Pkg.FunctionSet).Norm(x)` | ✓ | **works** |
| DTL, custom | `..Norm(x)` | **fails** `MPP5392 No such method` | — |
| DTL, custom | `Norm(x)` — bare | ✓ | **`<UNDEFINED>`** |
| business rule, custom | `AlreadyReportedErr(…)` — bare | ✓ | **works** |
| business rule, custom | `##class(Pkg.FunctionSet).Already…` | **fails** `<Ens>ErrInvalidToken` | — |

Read the last two rows against the third: **a DTL wants the call qualified and a rule wants it
bare, for the same method on the same class.** That inversion is why this is got wrong, and it is
the one-character difference people mean when they call it the most expensive mistake in a DTL.

The failures are not equally kind. `..Custom()` in a DTL and `##class()` in a rule fail at
**compile**, which is the good outcome. The **bare** form in a DTL compiles clean, so tier 2 is
green and the `<UNDEFINED>` waits for a message to flow — in production, on real data.

**`DependsOn` is mandatory on a DTL, and this is measured, not advice.** The generated `Transform`
method needs the source and target classes already compiled:

```
single batch, no DependsOn  -> FAILS
single batch, DependsOn     -> all compile
```

The failure names neither the cause nor the omission: it surfaces as
`<CLASS DOES NOT EXIST> <MessageClass> … Ens.DTL.Transform`, or as
`ERROR: Ens.DataTransformDTL.cls(Transform) of generated code compiling subclass`. A DTL without
`DependsOn` compiles only while the batch happens to reach its dependencies first — luck, not a
property of the code. `examples/ch05_bpl_dtl/dtl-order-to-vendor.cls` shipped that way for
releases and failed the moment an unrelated error perturbed the batch order.

Two smaller rules that come with the pattern: mark every FunctionSet method `[ Final ]` (EGDV
§12.1 — no polymorphism support, and without it the method is not offered as a utility function),
and always pass `..Lookup`'s third argument, the on-miss default, or a miss returns `""` and flows
on as a legitimately empty value.

- **Source.** Bank audit 2026-09-18; the bank had no gated FunctionSet consumer.
- **Validity.** Verified against IRIS for Health 2026.1; all six call forms compiled and run.
- **Severity.** High — the surviving wrong form is invisible to every tier.
- **Example.** `examples/ch05_bpl_dtl/dtl-lookup-and-functions.cls`

## 6. Adapters & connectivity

### 6.1 Generated SOAP/WSDL gotchas — patterns to fix on every import

When you import a vendor WSDL in Ensemble/IRIS, the generated SOAP client classes nearly always need at least one of these patches.

#### 6.1.1 `wsp:PolicyReference` (#6447) compile failure — confirmed at SEVEN customer sites

**Symptom.** The generated `*HTTPPortConfig` class fails to compile with `ERROR #6447: Elemento inesperado, wsp:PolicyReference, de namespace WS-Policy en el bloque XData de %SOAP.Configuration`.

**Fix.** Either (a) add `Parameter REPORTANYERROR = 0;` to the offending class and rename `…Config` to `…ConfigBACKUP`, OR (b) strip the `wsp:PolicyReference` block from the WSDL before regenerating, OR (c) delete the generated `XData OnConfigurationCompile` block. The WS-Policy assertion is not used at runtime by the Ensemble client; the actual policy (TLS, signing) is configured separately in the BO.

- **Validity.** Still valid in current IRIS; SOAP wizard still emits this XData block from WSDLs that contain WS-Policy.
- **Severity.** High.
- **Example.** `examples/ch06_adapters/soap-wsdl-policyreference-fix.cls`

#### 6.1.2 Vendor WS rejects `xsi:type`

Even with type info matching the schema, vendor SOAP server returns errors when `xsi:type` attributes appear in the request. **Fix:** set `Parameter OUTPUTTYPEATTRIBUTE = 0;` on the generated SOAP client class.

- **Severity.** Medium.
- **Example.** `examples/ch06_adapters/soap-xsi-type-suppress.cls`

#### 6.1.3 XML namespace alias must literally be `urn`

Vendor WS returns errors unless the SOAP envelope's namespace prefix happens to be `urn`. **Fix:** instantiate the SOAP client manually so the namespace prefix can be set explicitly before invocation.

- **Severity.** Low (vendor-specific).

#### 6.1.4 `Required` flags on generated properties break the call

Vendor WS chokes when IRIS validates the message has all required fields and refuses to send because one is missing — yet the WS would have accepted the partial message. **Fix:** drop `REQUIRED=1` from the generated SOAP type properties.

- **Severity.** Medium.
- **Example.** `examples/ch06_adapters/soap-required-flag-drop.cls`

#### 6.1.5 Strongly-typed dates/times rejected by vendor; downgrade to `%String`

Where the WSDL specifies `xs:date` / `xs:time` and the vendor server cannot actually parse the typed values, change the generated property to `%String`. The transmitted lexical form (`2020-03-02`, `11:00:00`) is correct anyway.

- **Severity.** Medium.
- **Example.** `examples/ch06_adapters/soap-typed-dates-to-string.cls`

#### 6.1.6 `RESPONSENAMESPACE` doesn't match what the vendor actually returns

The WSDL specifies one response namespace but the actual SOAP responses come back with a different one. **Fix:** edit the generated proxy and override `Parameter RESPONSENAMESPACE` to the actual value. **General rule: don't trust the WSDL — sniff the actual response, then adjust.**

- **Severity.** Medium.
- **Example.** `examples/ch06_adapters/soap-response-namespace-override.cls`

#### 6.1.7 Generated classes ARE meant to be edited — document every patch

The naming rule (`<Pkg>.WSC<Name>` sub-package, see §1.1) is partly motivated by this: generated SOAP/XSD classes need to be regeneratable in isolation, AND every patch needs to be reapplied each time. Document every patch in the class header. A useful pattern: prefix every author-edit line with `///<initials><date><tag>:`.

- **Severity.** Low (process).

### 6.2 Per-BO `Alt.SOAP.WebClient` for SOAP tracing

Rather than relying on the global `^ISCSOAP("Log")` toggle (which forces all components in a namespace to share one log file), change every generated SOAP proxy's superclass from `%SOAP.WebClient` to a customer-internal copy (`Alt.SOAP.WebClient`) and add a `SoapLogFile` setting on each BO. This gives one log file per BO, settable from the Portal at runtime.

```objectscript
Property SoapLogFile As %String(MAXLEN="512") [ InitialExpression = "" ];
Parameter SETTINGS = "<...>,SoapLogFile";

Method OnMessage(...) {
    If (..SoapLogFile'="") {
        set ^ISCSOAP("Log")="ios"
        set ^ISCSOAP("LogFile")=..SoapLogFile
    }
    // invoke proxy...
    If (..SoapLogFile'="") { set ^ISCSOAP("Log")="" }
}
```

**Caveat.** The `^ISCSOAP` global is process-scoped; this still has races in heavy multi-process scenarios. Treat as a debug aid, not always-on tracing.

- **Validity.** Still valid.
- **Severity.** High (debuggability).
- **Example.** `examples/ch06_adapters/alt-soap-webclient-tracing.cls`

### 6.3 HTTP Basic auth in a SOAP service: parse `HTTP_AUTHORIZATION` in `OnPreWebMethod()`

When you can't (or don't want to) put authentication at the gateway and the inbound is SOAP, do it in `OnPreWebMethod()` — but you MUST use `EnsLib.SOAP.InboundAdapter` (not an adapter that strips headers).

- **Severity.** Low.

### 6.4 SQL adapter: use the ParmArray forms for typed parameters

**Bind parameters with an explicit SQL type — `ExecuteUpdateParmArray()` / `ExecuteQueryParmArray()` — rather than letting the driver guess.**

`ExecuteUpdate(sql, p1, p2, …)` carries no type information, so the adapter asks the driver via ODBC `SQLDescribeParam`. Several JDBC drivers cannot answer, and IRIS then falls back to **SQL type 12, VARCHAR** (ESQL §8.2.2.1, scenario 3). Everything becomes a string: an empty value binds as an empty VARCHAR instead of a typed NULL, so a nullable `DATE` or `NUMERIC` column either rejects the row or silently stores a zero; a `%Date` binds as its internal day count. The usual workaround — concatenating values into the statement text, with `NULL` spliced in by hand — is both an injection surface and exactly what these methods exist to remove.

Three rules, all verifiable:

- **Type parameter 1 or type nothing.** The adapter decides whether to honour your descriptors by testing `$D(pParms(1,"SqlType"))||$D(pParms(1,"CType"))` — parameter **1 only** (`EnsLib.SQL.OutboundAdapter::privPrepare`; stated in ESQL §8.2.2). Leave parameter 1 untyped and every other descriptor is ignored, silently.
- **The top level of the array is the parameter COUNT**, not a value: `set parms = 4`.
- **`Kill` the array before every call.** ESQL §8.2.2: *"If you execute multiple queries that use the parameter array, kill and recreate the parameter array before each query."* A stale subscript is bound without complaint.

**The macros need an `Include`, and there are two spellings — both real.** Neither is automatic in an `Ens.BusinessOperation`: without it you get `MPP5610 Referenced macro not defined`, which reads like a typo. `Include EnsSQLTypes` gives the mixed-case set — `$$$SqlVarchar` 12, `$$$SqlInteger` 4, `$$$SqlNumeric` 2, `$$$SqlDecimal` 3, `$$$SqlDouble` 8, `$$$SqlChar` 1 — and `Include %occODBC` gives the same values under UPPERCASE names.

**Date/time has four families, and picking the wrong one is silent.** Verified by compiling the macros and printing their expansions on 2026.1: legacy `$$$SqlDate`/`$$$SqlTime`/`$$$SqlTimestamp` = **9 / 10 / 11**; ODBC 3.x `$$$SqlTypeDate`/`$$$SqlTypeTime`/`$$$SqlTypeTimestamp` = **91 / 92 / 93**; **JDBC aliases** `$$$SqlJDate`/`$$$SqlJTime`/`$$$SqlJTimeStamp` = aliases of the ODBC 3.x set (**91 / 92 / 93**); and C-type aliases `$$$SqlCDate`/`$$$SqlCTimeStamp` aliasing the legacy set. `EnsLib.SQL.OutboundAdapter` runs JDBC whenever `JDBCDriver` is set, so **`$$$SqlJDate`/`$$$SqlJTimeStamp` are the semantically correct choice there** — though `$$$SqlDate` (9) is field-proven against Oracle `DATE` over Oracle JDBC across dozens of production BOs, so this is a legibility preference, not a defect to go and fix. Two collisions to know about: `$$$SqlDate` = `$$$SqlDateTime` = 9, and `$$$SqlTime` = `$$$SqlInterval` = 10 — a misremembered name in either pair still compiles. **Prefer `EnsSQLTypes` in interop code**; it is the Ensemble include and the mixed-case spelling is what existing field code uses. Both verified by compiling against IRIS for Health 2026.1.

`"SqlType"` and `"CType"` are **both** honoured — `privPrepare` contains `Set:""=tSqlType tSqlType=tCType, tCType="" ; for back compatibility we support CType used as SqlType`. `"SqlType"` is the primary name; a lot of production code uses `"CType"`, and it works — don't "fix" it.

Two historical `<SUBSCRIPT>` gotchas from the same family, kept for recognition only — both Caché 2016.2 / 2017 era, not reproduced on 2026.1:

- `<SUBSCRIPT>` at `^CacheTemp.EnsRuntimeAppData(...,"%QParms")` → moving to the ParmArray form also fixed this.
- `<SUBSCRIPT>` at `...,"%QCols"` → shorten the BO class name; long names overflowed the global subscript.

- **Source.** Emporsis 2017 §7.8 for the `<SUBSCRIPT>` pair; the typing rules verified against IRIS for Health 2026.1.
- **Validity.** Still valid, and the reason is stronger than the original note suggested — this is a data-correctness rule, not a cosmetic one.
- **Severity.** High (silent data corruption via VARCHAR coercion).
- **Example.** `examples/ch06_adapters/sql-bo-typed-parmarray.cls`

### 6.5 DIME protocol legacy support (rare)

Some legacy partner services (e.g. an e-prescription gateway) return PDF attachments via the obsolete DIME protocol (predecessor of MTOM, obsolete since 2002). Ensemble has no native DIME support; if you must integrate with a DIME-emitting service, build a `DIMEWebClient` (copy of `%SOAP.WebClient`) with extended response parsing recognising `Content-Type: application/dime`. The proxy class extends both `%SOAP.WebClient` and `DIMEWebClient` (multi-inheritance with `Inheritance = right`).

**Do NOT use DIME for any new integration — use MTOM.**

- **Validity.** Historical / Superseded.
- **Severity.** Low (legacy).

### 6.6 Java integration via JavaGateway

When a third-party library is only available as Java (e.g. a legacy partner-supplied SAML module, customer JAR), call it from Ensemble via the JavaGateway:

1. Deploy the JAR to a fixed directory (e.g. `/opt/iris/javalib/`).
2. Use Studio → Tools → Java Gateway Wizard to generate ObjectScript proxy classes.
3. Write a BO that extends `EnsLib.JavaGateway.AbstractOperation` and calls the proxy via `obj.<javaMethod>(...)`.
4. Add the JAR to the Java Gateway classpath. Two settings can do this, both under the Portal's **Additional Settings** group (the Spanish Portal renders that group heading as “Parámetros adicionales” — it is a category, not a setting name, so always search by the XML name): `ClassPath` on the Java Gateway service item (`EnsLib.JavaGateway.Service`, platform-delimited) and `AdditionalPaths` on the BO (`EnsLib.JavaGateway.AbstractOperation`, comma-delimited, appended to the service's `ClassPath`). JVM options are a separate setting, `JVMArgs` — not the classpath.

In 2025+, prefer external services or ObjectScript reimplementation (the 2017+ SAML JavaGateway pattern was superseded by the public `intersystems-ib/SAML-COS` ObjectScript implementation).

- **Validity.** Still valid; flag as **"Use sparingly in 2025+"**.
- **Severity.** Medium.
- **Example.** `examples/ch06_adapters/javagateway-bo.cls`

---

### 6.7 Custom Business Service with a bare adapter — the case where you DO write the class

Use this shape only when no prebuilt service fits: delimited files are a RecordMap (§1.11), HL7 is
`EnsLib.HL7.Service.FileService` (§2.10). Writing it otherwise means re-implementing a poll loop, a
parser and a dispatch that already exist.

What makes the shape legal is that the adapter is named by `Parameter ADAPTER` on an
`Ens.BusinessService`, so **`OnProcessInput`'s signature is yours to define**. On a prebuilt
`EnsLib.*.Service.*` the base class fixes it — and on a RecordMap/HL7 `FileService` it is
`(pInput As %Stream.Object, Output pOutput, ByRef pHint)`, the whole file, with no per-record hook.
Getting that wrong is `#5478`. Note also that `##super()` in `OnInit` is *not* needed here (the
inherited one does nothing, ESQL §6.5) but **is mandatory on a prebuilt service** (CR-14).

- **Source.** Workshop cohort 2026-09. **Validity.** Still valid. **Severity.** Medium.
- **Example.** `examples/ch06_adapters/bs-file-bare-adapter.cls`

### 6.8 REST inbound — `EnsLib.REST.Service` and the dispatch that is not a MessageMap

`EnsLib.REST.Service` extends `%CSP.REST`, so dispatch is by URL through `XData UrlMap` — **not** by
message type through `XData MessageMap`, which is the BO mechanism. A MessageMap on a REST service
is never consulted.

There is **no inbound adapter** (`Parameter ADAPTER = ""`): the web application accepts the socket.
Consequences: the service never visibly "starts", and a 404 is a **web application** problem, not a
production one. And because `%CSP.REST` dispatches to a *classmethod*, there is no instance and no
`..SendRequestAsync()` — get one with `Ens.Director.CreateBusinessService()`, which is what makes
the production item load-bearing.

- **Source.** Workshop cohort 2026-09. **Validity.** Still valid. **Severity.** Medium.
- **Example.** `examples/ch06_adapters/bs-rest-inbound.cls`

### 6.9 SQL inbound — poll a table with GenericService, and the JGService precondition

`EnsLib.SQL.Service.GenericService` is configured, not subclassed: the query, the key field and the
dispatch are settings.

**`JGService` is mandatory for any `jdbc:` DSN, and its absence is not a connection failure — the
host terminates at startup.** It must name an `EnsLib.JavaGateway.Service` item in the same
production, character for character (ESQL §2.1, §3.1). That item is required and **not** deprecated.
Without it: `<INVALID OREF> 192 initAdapterJG+2^EnsLib.JavaGateway.Common.1`, a frame naming neither
the gateway nor the item nor `JGService`.

**`KeyFieldName` is what makes the poll incremental.** Without it the same rows are re-read every
`CallInterval` and re-sent forever — a duplicate-message source that looks like a working
integration. Prefer a watermark `WHERE` clause over deleting consumed rows: a delete is
irreversible if the downstream fails, and the message is then the only copy.

- **Source.** Workshop cohort 2026-09; verified against 2026.1. **Validity.** Still valid.
- **Severity.** High. **Example.** `examples/ch06_adapters/production-sql-poll.cls`

### 6.10 File passthrough relay — `Ens.StreamContainer`, and the read that only works once

Moving a file from A to B unchanged is the commonest shape in the field and was the least
documented here: `Ens.StreamContainer` had **zero** hits across all 20 skills and the whole bank,
while `production-lifecycle` already wired `EnsLib.File.PassthroughOperation` as the canonical alert
sink.

**Write no classes.** `EnsLib.File.PassthroughService` polls, reads the file and wraps it;
`EnsLib.File.PassthroughOperation` receives it and writes it out. Verified from the operation's own
signature — `OnMessage(pRequest As Ens.StreamContainer, ...)` — the body travelling between them is
an `Ens.StreamContainer`, not a project message class and not a raw stream.

`Ens.StreamContainer` is **not** an `Ens.Request`. Its verified superclass list is
`(%Library.Persistent, Ens.Util.MessageBodyMethods, %XML.Adaptor)`. So a DTL over a relay operates on
the container and its `Stream`, not on properties — and note that `%Persistent` is leftmost, exactly
as §5.10 requires of your own message classes.

**The silent failure is the second read.** A `%Stream` keeps a read position and `Read()` advances
it. Measured on 2026.1 against a saved-and-reopened container:

| call | result |
|---|---|
| `Read(100)` | `line-1` |
| `Read(100)` again | `""` — no error, no warning, nothing in the Event Log |
| `Rewind()` then `Read(100)` | `line-1` |

The shape that produces it looks careful: log the content, then write it out. The log gets the data,
the write gets `""`, and the output file is created **empty** — so the run reports success and the
problem surfaces downstream as "the file arrived but it's blank".

The rule is therefore: **any method that reads a stream it did not create rewinds FIRST, not after.**
After is a convention you must remember at every exit path including the error ones; before is one
line that cannot be skipped, and rewinding a stream already at 0 costs nothing.

A separate business host is not at risk — message bodies travel by id and each host opens its own
instance at position 0. The exposure is entirely *within* one method, or one object passed along
in-process.

`OriginalFilename` is the only link back to the source file; the operation's `%f` substitution in its
`Filename` setting is simply a read of that property. Note also that `Filename` is a **Host** setting
while `FilePath` is an **Adapter** setting — the Portal shows both in one panel, and a setting on the
wrong target is accepted and never read.

- **Source.** Bank audit 2026-09-18; flagged by review as a prescribed-but-unmapped component type.
- **Validity.** Verified against IRIS for Health 2026.1; the read/rewind sequence was executed.
- **Severity.** High — an empty output file from a run that reported success.
- **Example.** `examples/ch06_adapters/production-file-passthrough.cls`

## 7. Error handling, retries & alerting

### 7.1 Alert circuit — the canonical pattern

In every Business Host of the production, enable “Send Alert on Error” (the setting is `AlertOnError`). The exception (always) is the Ens.Alert circuit itself: **Ens.Alert and the BO that sends the alert must have this checkbox DISABLED** to avoid infinite loops.

Canonical wiring:

- `Ens.Alert` implemented as `EnsLib.MsgRouter.RoutingEngine`.
- `EnsLib.EMail.AlertOperation` BO sends `Ens.AlertRequest` messages by email to a distribution list.
- A **filter routing rule** dedupes alerts to avoid mailbox saturation (see §7.2 for the FunctionSet).

- **Validity.** Still valid.
- **Severity.** High.
- **Example.** `examples/ch07_alerting/production-alert-circuit.cls`

### 7.2 Alert deduplication FunctionSet (verbatim)

```objectscript
Class Demo.FilterAlerts.FunctionSet Extends Ens.Rule.FunctionSet [ LegacyInstanceContext, Not ProcedureBlock ] {

/// Returns true if (SourceConfigName, ErrorMessage) was already reported within Interval seconds today.
ClassMethod AlreadyReportedErr(SourceConfigName, ErrorMessage, Interval = 60) As %Boolean {
    set datetime=$H, day=+datetime, seconds=$p(datetime,",",2)
    kill ^FilterAlerts("Err",day-1)  // Purge previous day
    if $data(^FilterAlerts("Err",day,seconds\Interval,$extract(ErrorMessage,1,200))) {
        quit 1
    } else {
        set ^FilterAlerts("Err",day,seconds\Interval,$extract(ErrorMessage,1,200))=""
    }
    quit 0
}

/// Returns true if any alert was already produced for this Ensemble session today.
ClassMethod AlreadyReportedPerSession() As %Boolean {
    set SessionId=%Ensemble("SessionId"), day=+$H
    kill ^FilterAlerts("Session",day-1)
    if ($data(^FilterAlerts("Session",day,SessionId))) {
        quit 1
    } else {
        set ^FilterAlerts("Session",day,SessionId)=""
    }
    quit 0
}
}
```

Use as routing-rule guards:

```
when AlreadyReportedErr(SourceConfigName, ErrorMessage, 60) → skip
```

What this protects against (both real, repeatedly observed):

1. A BP and a BO in the same session both raise an alert → duplicate email.
2. A failing BO retries every N seconds and emits an alert each retry → mailbox flood.

- **Validity.** Still valid; portable function-set.
- **Severity.** High.
- **Example.** `examples/ch07_alerting/alert-dedup-functionset.cls`

### 7.3 Production-component settings to always check on a BO

| Setting | Recommended value | Why |
|---|---|---|
| Send Alert on Error (`AlertOnError`) | ✔ (everything except Ens.Alert + Email AlertOperation) | as §7.1 |
| Alert on Queue Wait (`QueueWaitAlert`) | 30 s | catches messages piling up when downstream is slow |
| Reply Code Actions (`ReplyCodeActions`) | review per-host | HL7 BO defaults are correct; non-HL7 BO defaults often are not |
| Failure Timeout | finite (NEVER `-1`) | infinite retries pile up forever (§1.8) |

- **Severity.** Medium.

---

## 9. Deployment, source control & CI/CD

### 9.1 The home-grown deploy tool: `IRIS-Interop-Deployment`

Out of the box, IRIS keeps Site Default Settings separate per environment, which makes exporting from DEV→PROD lose those values. Either document them by hand, or use a tool. The tool used at multiple sites: `https://github.com/PYDuquesnoy/IRIS-Interop-Deployment` (open-source, **not** InterSystems-supported). It evolved across several customer projects (2017+) into the open-source `PYDuquesnoy/IRIS-Interop-Deployment`.

Key behaviours:

- Stores per-environment values in `InteropTools_CFG.ConfigurationSites` table, with columns `ValueDEV / ValueDEVLOCAL / ValuePRE / ValuePROD`.
- Triggers on `Ens.Config.DefaultSettings` keep that table in sync — **requires `ENSLIB` to be RW** during install.
- Export: `InteropTools.Deploy.Export("CAT1,CAT2", "<dir>")` produces 4 files: `.xml` (classes), `.prd` (production cfg), `.sit` (site cfg), `.vxm` (virtual docs).
- Import auto-backups, imports, recompiles, restarts production, prints rollback command (`InteropTools.Deploy.Restore(<path>)`).

**`DEVLOCAL` site-import behaviour:** when the deploy tool imports into a namespace flagged `Site = DEVLOCAL`, it does NOT load classes nor modify the running production; it only syncs the Site Configuration values from DEV. A developer working locally on uncommitted changes shouldn't have those overwritten by an incoming deploy — but their config still gets refreshed.

- **Validity.** Still valid.
- **Severity.** Medium.

### 9.2 Git source control on a shared dev IRIS — three Windows gotchas

When using `git-source-control` (ZPM) on Windows where IRIS runs as a service:

#### 9.2.1 CVE-2022-24765 (`fatal: unsafe repository`)

git ≥ 2.35 verifies the repo owner matches the running user. IRIS-as-LocalSystem hits this. Three fixes:

1. Run the IRIS service as the `Intersystems` (or domain) user instead of LocalSystem.
2. `chown` (Windows owner) the repo to the same user.
3. `git config --global --add safe.directory <path>` for whichever user runs IRIS. **Don't forget the trailing `/` on the path** for some git versions.

#### 9.2.2 ZPM install paradox

`zpm install` works only when IRIS is started as LocalSystem (uses `$ZU(-1)` which fails for non-system users). After install, you can switch service user. Document this dance — it's non-obvious.

- **Severity.** Medium.

### 9.3 HL7 schemas — manual export to source control required

Custom HL7 schemas edited in the portal are NOT auto-exported. Manually `Export` to the SVN/git root after each edit (see also §2.2).

- **Severity.** High (silent loss-of-work risk).

### 9.4 Customer + vendor share git for migration projects

When customer and vendor work in parallel during a migration: vendor uses Git in a dedicated namespace (`PROD-MIG`); customer feeds their concurrent production-base changes (in original `PROD`) to the migration team as Ensemble XML exports. Vendor merges these into the migration namespace alongside the migration work.

- **Why.** Customer can't freeze production-base changes during a multi-month migration; without explicit sync mechanism, the migration namespace drifts and is unmergeable at cutover.
- **Severity.** Medium.

---

## 11. Security

### 11.1 SAML 2.0 — native `%SAML` charset bug (2017–2019)

Native Ensemble `%SAML.Assertion`-generated SAML 2.0 assertions are rejected by a partner SOAP platform with a SOAP fault from the partner platform (in effect: “Error validating the SAML ticket — the SAML ticket signature is not valid”) whenever the assertion contains any non-Latin-1 character (any character whose value differs between Latin-1 and UTF-8). Latin-1-only assertions validate successfully.

Confirmed by independent third-party validators: same cert, same XML structure — only difference is a non-ASCII char (e.g. corrupted euro sign `â¬` in a NameID) → bad hash & signature.

**Workaround in 2017–2019:** generate the SAML assertion via external Java code (a partner-supplied module, or a custom JAR called via JavaGateway).

**Permanent fix (2019+):** use the public `intersystems-ib/SAML-COS` ObjectScript implementation — built specifically to address this issue.

Affected sites: multiple production sites, as documented in a vendor support report.

- **Validity.** **Resolved by `intersystems-ib/SAML-COS`** — verify against current IRIS native `%SAML` if not using SAML-COS.
- **Severity.** High.

### 11.2 SAML 2.0 — assertion must be self-contained

When sending a SAML 2.0 assertion as a SOAP `wsse:Security` header, the assertion must declare ALL its own XML namespaces and prefixes. Once the receiver extracts it from the SOAP envelope, it is processed by a separate module that does not see the parent envelope's `xmlns:` declarations. Generating the SAML inside the SOAP-envelope-aware code path produces an assertion whose signature breaks once standalone.

- **Validity.** Still valid (constraint applies to SAML 1.1 too).
- **Severity.** High.

### 11.3 SAML 2.0 — attaching a custom security header to a generated SOAP BO

```objectscript
Set ..Adapter.WebServiceClientClass = "Demo.WSxxx.WSxxx"

///<initials>+: Instantiate the Web Service Client to attach a SAML Header
set ..Adapter.%Client = $classmethod(..Adapter.WebServiceClientClass, "%New")
set tSC = ..GenSecurityHeader(pRequest.atributosSAML, .tHeader)
Quit:$$$ISERR(tSC) tSC
set ..Adapter.%Client.SecurityOut = tHeader
///<initials>-

Set tSC = ..Adapter.InvokeMethod("methodName", .tResponse, ...)
```

The BO sets a `SAMLCredentials` setting (alias of an X509 credentials configuration in IRIS) so the cert used to sign the SAML can be changed per-environment without code change.

- **Severity.** High.
- **Example.** `examples/ch11_security/saml2-custom-security-header.cls`

### 11.4 SAML 1.1 — `SAML11.*` package for a legacy e-prescription gateway

Some legacy e-prescription gateways require SAML 1.1 in the SOAP header. Native Ensemble `%SAML` is 2.0-only. `SAML11.*` was built by copying `%SAML` and adapting:

- Namespace `urn:oasis:names:tc:SAML:1.0:assertion`
- `AssertionID` instead of `ID`
- `MajorVersion` / `MinorVersion` instead of `Version`
- `Issuer` is a string attribute, not a `NameID` element
- Subject moves into the StatementList
- `%XML.Security.Signature` cloned to `SAML11.XML.Security.Signature` so `GetNodeById` matches `AssertionID` instead of `ID`
- **GUID-style AssertionIDs are rejected by some partner platforms**; use a fixed-format ID like `_23f8a4ad91cd56ff7715912dd6ab072f`
- In `SAML11.AttributeValue`, suppress the `xsi:type` attribute (emitting it triggers a 1.1 validation error)

Canonical published version: `intersystems-ib/SAML11-COS`.

- **Severity.** High.

### 11.5 OAuth 2.0 + LDAP server-side broker pattern

Use IRIS as an OAuth 2.0 broker between a third-party SaaS app and on-premise Active Directory. Configure the OAuth 2.0 Server in Portal (`System Administration / Security / OAuth 2.0 / Server`) with grant type `Authorization Code Grant`. Set the customisation namespace and supply two custom subclasses:

- `OAuth2.Server.Authenticate` — login UI customisation (logo, skip `DisplayPermissions` by using `btnAccept` instead of `btnLogin`)
- `OAuth2.Server.ValidateLDAP` — credential check via `%SYS.LDAP` (copy of `^LDAP.MAC` example1: bind anonymously → switch to TLS → bind as admin → look up UserDN by `sAMAccountname` → re-bind with user's password → cleanup)

**HAProxy URL routing.** Ensemble exposes its OAuth endpoints under `/<csp-app>/oauth2/...` (e.g. `/demoapp/oauth2`). When fronted by HAProxy with a different external path (`/dev/oauth2`), add an HAProxy rule that maps `/dev/oauth2` → `/demoapp/oauth2`.

**`OAuth2.Server.Client.ValidateRedirectURL` may need patching** when the redirect URI host is constrained externally.

**Smoke test.** Verify the OAuth server reachable via `<server>/<csp-app>/oauth2/.well-known/openid-configuration` (OIDC discovery endpoint).

- **Validity.** Still valid.
- **Severity.** High.
- **Example.** `examples/ch11_security/oauth2-server-validate-ldap.cls.xml`

### 11.6 OAuth 2.0 + PKCE for mobile clients

See §4.2.

### 11.7 SSL/TLS server certificate validation in IRIS — build the trusted CA chain

To enforce strict server-cert validation in an IRIS client SSL configuration:

1. Set `Server Certificate Validation = Require` on the SSL config.
2. Build the chain `.PEM` using IRIS-bundled OpenSSL:

   ```bash
   $IRIS_HOME/bin/openssl s_client -servername <hostname> -connect <hostname>:443 -prexit -showcerts
   ```

   **Critical:** the `-servername` parameter is REQUIRED for TLS Server Name Indication. Without it, `s_client` returns a default Kubernetes/wildcard cert and validation will fail mysteriously.

3. The output contains 2 certs (server + immediate CA). Append the ROOT CA fetched from the public source (e.g., USERTrust RSA Certification Authority) to complete the chain.
4. Order in the file: server cert → intermediate CA → root CA.

**Optimisation.** Once the chain works, REMOVE the server's own cert from the `.PEM` file — keep only the intermediate CA + root CA. The chain still validates because the server's own cert is sent in the TLS handshake. This decouples the IRIS client config from the server's annual cert renewal cycle.

- **Severity.** High.
- **Example.** `examples/ch11_security/ssl-trusted-ca-chain.sh`

### 11.8 ZAUTHENTICATE for external LDAP with password expiry

When migrating an application that authenticated against external LDAP with password-expiry-driven password change, implement via Caché/IRIS `ZAUTHENTICATE` mechanism (a customisable `%SYS` routine; implement to call `%SYS.LDAP`, force password change on expiry response).

- **Severity.** Medium.

### 11.9 `CSPSystem` is an internal user — give it its own strong password

`CSPSystem` is an internal account used by the Web Gateway. Give it its own strong, unique password — distinct from `_SYSTEM`, `Admin`, `SuperUser`. It is NOT a regular interactive user.

- **Severity.** Medium.

### 11.10 Initial Security Settings: prefer `Locked Down` on production interop hosts

Several legacy installs (2015, 2020) used `Normal` Initial Security. **In current IRIS the recommendation has shifted** — for production interop hosts use `Locked Down` when feasible (or `Normal` only if the network is fully trusted).

- **Validity.** Updated since 2015 — prefer Locked Down where operationally feasible.
- **Severity.** Medium.

### 11.11 SAML 2.0 attribute reference (regional health-record exchange)

When generating a SAML 2.0 assertion for a regional health-record exchange, the assertion's `<saml:AttributeStatement>` may be required to include attribute names such as (case-sensitive):

- `ResponsibleUser`, `Profile`, `ProviderOrganization`, `Entity`, `GivenName`, `FirstFamilyName`, `SecondFamilyName`, `DocumentType`, `documentNumber`, `code`, plus one or more region-specific identifier attributes (typically a regional patient identifier and an issuing-organisation code)

The list is **illustrative**. Attribute names, casing and the region-specific identifiers are defined by the exchange's own integration specification — take them from that spec, never from here.

- **Severity.** Low (reference data).

### 11.12 XAdES EPES signature policy (Spanish e-invoicing TicketBAI / facturae)

When integrating with Spanish public-sector e-invoicing (TicketBAI, facturae), the signature must include a `<xades:SignaturePolicyIdentifier>` block with the SHA-1 base64 digest of the policy PDF or URL. Reference: `https://www.facturae.gob.es/formato/Paginas/politicas-firma-electronica.aspx`.

- **Severity.** Low (reference).

---

## 12. Monitoring & operations

### 12.1 InterSystems API Manager (IAM) operational rules

#### 12.1.1 IAM upgrade RBAC orphan cleanup

During an IAM major-version upgrade (e.g. 0.34 → 2.x), corrupt rows in the embedded PostgreSQL `public.rbac_user_roles` table can block migration. Fix: shell into the IAM PostgreSQL container, connect via psql, and `DELETE FROM public.rbac_user_roles WHERE user_id='<id>';` for the offending rows before re-running the migration container.

```bash
docker exec -it <iam-db-container> /bin/bash
psql -U iam -h localhost
\dt
DELETE FROM public.rbac_user_roles WHERE user_id='<id>';
```

- **Severity.** Medium.

#### 12.1.2 IAM admin GUI cookie config must match Developer Portal cookie config

The cookie configuration in `KONG_ADMIN_GUI_SESSION_CONF` (docker-compose env var) must use the same `cookie_name`, `secret`, `cookie_samesite`, and `cookie_secure` settings as the Developer Portal's session config. Mismatch produces "login succeeds, then immediately logs out".

- **Severity.** Medium.

#### 12.1.3 Use `decK` for IAM declarative config sync

```bash
docker pull kong/deck
docker run -v /local/path:/tmp kong/deck:latest dump --kong-addr <url> -w <workspace> --with-id -o /tmp/content.yml
docker run -v /local/path:/tmp kong/deck:latest sync --kong-addr <url> -s /tmp/content.yml
```

- **Severity.** Low.

#### 12.1.4 Kong cross-version schema breaks: `run_on` field removed

When restoring Kong/IAM configuration from an older version into a newer one, plugin definitions that used `run_on` (a now-removed field) fail with HTTP 400 "schema violation (run_on: unknown field)". Clean the input YAML by stripping `run_on:` lines before sync.

**General rule:** when upgrading any declarative-config tool, expect schema-field deprecations to fail silently in the source YAML; pre-process before sync.

- **Severity.** Medium.

### 12.2 Operational requirements baked into a public FHIR Façade

See §4.7.

### 12.3 SAM (System Alerting and Monitoring)

A 2021 consulting agenda named SAM (Prometheus + Grafana + custom metrics) as a primary monitoring topic for IRIS for Health. Verify deployment recommendations against current InterSystems Capacity Planning Series.

- **Severity.** Medium.

### 12.4 Per-BO `Alt.SOAP.WebClient` for SOAP-trace files

See §6.2.

### 12.5 Alert-circuit dedup FunctionSet

See §7.2.

---

## 13. Migration of Interop productions

> Pure-platform migration topics (IP-swap upgrades, legacy `.cbk` restores, OpenVMS, Universe Multivalue, journal restore via `JRNRESTD`, mass-recompile baselines, generic OS install order) were trimmed out of this document — they are not interop-specific. What remains here is the interop-touching subset: credentials, auto-start, package shadowing, Windows service account for File adapters, startup protocols, and Mirth/Rhapsody migration paths.

### 13.7 Credentials migration: walk `Ens.Config.Credentials`, export, re-import

Ensemble credentials store passwords in a separate "Secondary" database encrypted with the instance key. Standard backup-restore preserves the credential RECORDS but the passwords are unreadable in the new instance. Recovery: write a small ObjectScript utility that walks all `Ens.Config.Credentials` instances in the source namespace, exports the credential pairs (name, username, password) to a file, then re-imports them on the target IRIS.

- **Severity.** High.
- **Example.** `examples/ch13_migration/credentials-export-reimport.cls`

### 13.8 NEVER auto-start migrated productions

Set `EnsembleAutoStart = 0` (or its IRIS equivalent) on the freshly installed/migrated IRIS. The restored productions point at REAL endpoints; auto-starting them will inject test traffic into production systems. Manually validate each component's settings before enabling.

- **Severity.** High.

### 13.9 `Ens.<X>` package shadowing fix

If a customer-written ObjectScript class is in package `Ens.<something>`, the ENSLIB-→-namespace mapping returns the system version (or none), shadowing the customer class and causing `<PROTECT>` runtime errors. Fix: export the affected classes, rename the package (prefix with a customer-owned namespace, e.g. `COD.<...>`), then re-import. **Side effect:** the storage definition changes; old persistent messages of the renamed class become unreadable.

- **Severity.** High.

### 13.11 IRIS service account on Windows: NOT LocalSystem when File adapters use UNC paths

Default Windows installs of IRIS run the service as `LocalSystem`, which has no rights to UNC paths. Any FileService / FileOperation / FTP-mount adapter that points at `\\server\share\...` will fail silently after migration. Fix: change the IRIS Windows service to run as a domain user with read/write to the UNC paths.

- **Severity.** High.

### 13.12 Production startup protocol — operational checklist template

A 30-step migration cannot be done from memory; one missed step ships a non-functional production. Build a documented, line-by-line startup protocol covering: disable user logins, wait for old-system backups, restore each `.bck` to its target directory, restore the CPF, reconfigure environment globals, modify routines for new file paths, register license / credentials, configure ODBC for new DSN, configure Reflection terminal connections.

- **Severity.** High (process).

### 13.14 Mirth → Ensemble migration

See §2.7.

### 13.15 Rhapsody → Ensemble migration

See §2.8.

---

## 14. Version-specific notes (interop-relevant)

> Pure-platform version notes (Cached Queries DB move in Caché 2017.2, generic SQL changes, `EnableLongStrings`, `SQL AnsiPrecedence` / `SQL AutoParallel`, `ccontrol`→`iris` command map, 2019 Mirror & Journal alert, IRIS 2025.1.2 ODBC issue) were trimmed out — they are not interop-specific. What remains is the small set of interop-relevant version notes.

### IRIS — BPL editor regression: `Missing BPL Data`

A class that compiles fine in Caché 2012 may report `Missing BPL Data` (i.e. `<XDATA BPL>` missing) on IRIS. The BPL editor in some IRIS versions silently strips the XDATA on first open. Fix: paste the original BPL XML back into the XDATA section and recompile.

- **Severity.** Medium.

### Ensemble vs IRIS default ports

| Default | Ensemble (≤2017) | IRIS (2018+) |
|---|---|---|
| SuperServer | 1972 | 1972 |
| Web (Apache) | 57772 | 52773 |

The SuperServer default is unchanged at 1972; only the web port moved. Never assume it — read the instance's own `iris.cpf` `[Startup] DefaultPort` (or `##class(Config.Startup).Get()`), which is authoritative, and remember that a container may publish it on a different host port.

Watch for hardcoded port references in client code and firewall rules during migration.

---

## Appendix B — References

### Public InterSystems / community repos cited

- `https://github.com/intersystems-ib/SAML-COS` — SAML 2.0 ObjectScript implementation, addresses the charset bug (§11.1).
- `https://github.com/intersystems-ib/SAML11-COS` — SAML 1.1 ObjectScript implementation (§11.4).
- `https://github.com/intersystems-ib/Healthcare-HL7-XML` — HL7 v2 in XML form (§2.6).
- `https://github.com/intersystems-ib/workshop-iris-dicom-interop` — DICOM interop workshop (local snapshot at `BestPractices/external/workshop-iris-dicom-interop/`).
- `https://github.com/PYDuquesnoy/IRIS-Interop-Deployment` — open-source deploy tool (§9.1).

### InterSystems documentation

Cited for verification:

- ZAUTHENTICATE customisation in `%SYS`.
- HL7 community CDA stylesheet (post-April 2014 patched version) — `http://gforge.hl7.org/gf/project/strucdoc/frs/?action=index`.

### Third-party references (cited as context)

- A regional health-record exchange SAML security guide (partner-supplied integration documentation).
- Spanish XAdES EPES signature policy hashes — `https://www.facturae.gob.es/formato/Paginas/politicas-firma-electronica.aspx`.

### Validity-tag taxonomy

Restated from "How to read this document"; every rule and every example header uses one of these:

| Tag | Meaning |
|---|---|
| `Still valid` | Applies to current IRIS as written |
| `Resolved in IRIS X.Y` | The underlying defect or limitation was fixed in that release |
| `Superseded by ...` | A newer mechanism replaces the pattern described |
| `Historical` | Kept for context; do not apply to new work |
| `Verify against current docs` | Was true when recorded; re-check before relying on it |
