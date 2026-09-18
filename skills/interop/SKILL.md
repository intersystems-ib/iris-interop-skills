---
name: interop
description: Router/index for IRIS For Health Interoperability work. Use when the user is building a production, defining components (BS/BP/BO), HL7 messaging, transformations, or asks anything that mentions InterSystems Interoperability, IRIS for Health, Ensemble, HealthConnect. Triggers: producción, integración, mensajería HL7, transformación. ALWAYS load `iris-interop-skills:tdd` as a companion skill in the same turn whenever the user proposes building or modifying ANY Interop component (BS/BP/BO/DTL/Rule/Message class), even if they don't mention tests or TDD. TDD is the default workflow, not opt-in.
---

# IRIS Interoperability — Skill Router

This skill is an index. Its job is to point Claude at the right sibling skill, enforce the load-bearing **messages-first** principle, and carry the project-wide conventions (naming, reserved packages, namespace strategy, config precedence) that apply to every other skill.

## Load-bearing principle: messages first

In IRIS Interoperability, **messages are the foundational building block**. They are the parameters of Business Processes and Business Operations, and the response types of Business Services. Design and create messages **before** authoring BS/BP/BO. If the user asks to "build a service" without a message class in mind, stop and design the message first using `iris-interop-skills:messages`.

**Two exceptions — the message is *generated*, not hand-authored first:**
1. The **SOAP Wizard** (which can be driven **programmatically**, not only from the Portal UI) generates the request/response payload classes from the WSDL — see `iris-interop-skills:soap-bo`.
2. The **Record Mapper** and **Complex Record Mapper** generate the record message class from the CSV/fixed-width layout — see `iris-interop-skills:business-services`.

In both cases the message class comes *from the generator*: don't hand-write it first. You still review it, apply the naming convention, and design any *wrapping* request/response message around the generated payload.

A message in IRIS is one of:
- `EnsLib.HL7.Message` (HL7 v2.x — pre-built, never subclass for storage)
- A persistent class extending **both** `Ens.Request` (or `Ens.Response`) **and** `%Persistent` — gives the message its own storage location separate from `Ens.MessageBodyD`.
- A `%SerialObject`-based payload (typical for SOAP-wizard-generated messages used as request properties).

## Naming convention — every class, every component

All ObjectScript classes and production components follow:

```
<Package>.<TipoComponente>.<NombreComponente>
```

Recommended total length ≤ 45 characters (longer names are silently truncated by some Portal screens).

| Component type | Sub-package | Note |
|---|---|---|
| Business Service | `.BS` | |
| Business Process | `.BP` | |
| Business Operation | `.BO` | |
| Data Transformation | `.DT` | Name `<TipoMsgIn>To<TipoMsgOut>` — the DataTransform Wizard suggestions key off this pattern |
| Sub-Transformation | `.DTS` | |
| Message | `.MSG.<Name>{Req|Rsp}` | |
| Business Rule | `.RUL` | |
| Internal data classes (`%SerialObject`) | `.DAT` | |
| Custom Adapter | `.ADP` | |
| Utility / FunctionSet | `.UTL` | |
| Custom HL7 schema (programmatic) | `.HL7` | |

For **generated SOAP / XSD code**, put each generated set in its own sub-package so it can be deleted and regenerated cleanly:

| Component | Sub-package |
|---|---|
| Generated SOAP client root + proxy | `<Pkg>.<SubPkg>.WSC<Name>` |
| Generated server-side WS class | `<Pkg>.<SubPkg>.WS<Name>` |
| Generated BO (from wizard) | `<Pkg>.<SubPkg>.WSC<Name>.BO` |
| Generated request message | `<Pkg>.<SubPkg>.WSC<Name>.REQ` |
| Generated response message | `<Pkg>.<SubPkg>.WSC<Name>.RSP` |

The production component's `Category` attribute MUST equal the package root (case-insensitive). This drives both deployment tooling and the visual filter in the portal.

**Why** the discipline matters: without it, production gets clobbered on deploy, patched system classes get lost on IRIS upgrade, DataTransform-Wizard auto-suggestions break, and exported bundles miss dependencies.

**Production Item Name** follows `<Tipo>.<Nombre>` (`BS.Census`, `BO.SQL`, `Router.Census`, `Util.JDBCGateway`, fixed `Ens.Alert`). Items whose name breaks the pattern (`Java.Gateway`, `Censo`, `myBS`) get renamed before merge — cosmetic but it affects portal grouping, search, and category-level operations.

### Invariants when writing ANY ObjectScript class (not only messages)

These two live in depth in `iris-interop-skills:messages`, because that is where they bite first.
They apply to **every** class you author, and both surface as the same useless parse error.

**Identifiers are letters and digits only — never `_`.** `_` is the concatenation operator, so
`Method TestADT_A01ContainsZdi()` or `Parameter IN_DIR = "…"` aborts the UDL parser with the most
misleading message in the product (RCOS Appendix A, §§A.7/A.9):

```
ERROR #5559: The class definition for class 'X' could not be parsed correctly,
             possibly due to non-matching {} or () characters
ERROR #16006: Document Pkg.DT.ADT_A01ToMenuReq.cls name is invalid
```

The braces are balanced. The name is not. **On `#5559`, grep the source for `_` in class and member
names before you count a single brace.** This bites hardest on HL7 work, where the message type is
`ADT_A01` and every derived name inherits the underscore:

| Wrong | Right |
|---|---|
| `Pkg.DT.ADT_A01ToMenuReq` | `Pkg.DT.AdtA01ToMenuReq` |
| `Method TestADT_A01ContainsZDI()` | `Method TestAdtA01ContainsZdi()` |
| `Parameter IN_DIR = "…/IN/"` | `Parameter InDir = "…/IN/"` |

The string `ADT_A01` itself is fine everywhere it is **data** — `MessageSchemaCategory`, a DocType,
an `XData` schema, a `Lookup()` key. It is illegal only as an identifier. A member name *can*
legally carry other characters if it is delimited — `Property "My Property" As %String;`
(GOBJ §2.6.3) — but that is for mapping a foreign schema, never for a component you author.

**Do not hand-write a `Storage` block.** IRIS generates the storage definition on first compile.
Writing one yourself makes `iris_doc(mode=put)` refuse with `STORAGE_STRIP_BLOCKED`, and the fix is
to leave the block out, not to pass `allow_storage_regeneration: true` — see `messages`. Note that
**only** `iris_doc` diagnoses this: a class that reaches IRIS through a disk write plus the VS Code
sync and `iris_compile` gets the bare `#5559` with no hint at all. The **generated** `Storage
Default` block that a VS Code / Atelier export brings back into the file *after* a successful
compile is expected and is **not** a defect — do not chase it out of the file.

**One statement per line.** ObjectScript is line-oriented: there is no line-continuation character.
Splitting `Do $$$AssertTrue(<expr>,` across two lines yields `MPP5612: Referenced macro missing
right paren`, which again names the wrong thing. Compute into a variable first, then assert on it.

## Reserved package names

Some package names are reserved for cross-cutting concerns. Do not put domain classes in them.

| Package | Purpose | Special handling |
|---|---|---|
| `Alt` | System classes that had to be patched | Re-test on every IRIS/Ensemble upgrade — the patched version may need to be reapplied. |
| `<Customer>NoExport` | Production class + site-config table | MUST NEVER be deployed across sites — name signals "stays in the source environment". |
| `INFRAESTRUCTURA` | System management classes | |
| `SOAPENC` | Auto-generated SOAP encoding side classes | Do not edit; regenerated on WSDL re-import. |

## Namespace discipline — resolve once, pass on EVERY call

Architecture (when to split an estate) is below; this is the **operational** rule, and it is
non-negotiable:

1. **Determine the target namespace from the task, ONCE, up front.** The task statement, the
   production name, or the user names it. If genuinely absent, ask — don't assume.
2. **Pass `namespace=` explicitly on EVERY MCP call.** Never rely on a tool schema's default:
   **`USER` is almost never the interop namespace**, and the failure mode is the worst kind —
   a run can complete *perfectly* in the wrong namespace, tests green, zero errors, deliverable
   absent. (Observed verbatim: 21/21 calls with the schema default `USER`, 8/8 tests green,
   nothing in the required namespace.) A PreToolUse gate blocks *some* tools when `namespace`
   is missing, but `iris_doc` / `iris_compile` / `iris_query` / `iris_execute` / `iris_test`
   pass through — the discipline is yours on every call.
3. **Sanity-check before building**: `check_config` lists the namespaces on the connection —
   confirm the target exists and is interop-enabled *before* the first write, not when a compile
   dies with `<CLASS DOES NOT EXIST> Ens.Director`. (The tdd skill's `CheckEnvironment` catches
   this at compile time — too late for calls already aimed at the wrong namespace.)
4. **On IRIS for Health / Health Connect, the namespace must be a FOUNDATION namespace.** See
   below — this is the step that is missing when a namespace "exists and looks interop-enabled"
   and half the library still isn't there.

### Foundation namespaces — IRIS for Health only, and required

> **"Every interoperability-enabled production needs a special interoperability-enabled namespace
> called a *foundation namespace*."** — *Foundation Namespaces* (AFNS), opening line.

This is not a FHIR detail and not a recommendation. On **IRIS for Health** and **Health Connect**
it is how an interop namespace is initialised: a Foundation namespace carries the healthcare
interoperability configurations and the `HS.*` mappings. A plain namespace is missing all of it.

**On plain IRIS — generic, non-healthcare integration — there is no such thing.** There is no
`HS.*` and no Foundation concept; an interop-enabled namespace is all there is, and none of this
section applies. Know which product you are on before acting on it.

**Why the failure is hard to read.** Without the mapping, `HS.FHIRServer.*`, `HS.SDA3.*` and the
rest simply *do not exist*, so every reference looks like a misspelling and the instinct is to hunt
for the right class name. There isn't one — the namespace is wrong. `Ens.Director` resolves fine
either way, so `check_config` saying "interop-enabled" does **not** tell you the namespace is a
Foundation namespace.

**Check it — the table's existence is the discriminator** (AFNS: *"you can check the
`HS_Util_Installer.ConfigItem` table"*). Verified on 2026.1 with both controls:

```
iris_query(namespace="<NS>", query="SELECT Name, Type, Activated FROM HS_Util_Installer.ConfigItem")
  Foundation namespace  -> a row, Type='Foundation', Activated=1
  plain namespace       -> SQLCODE -30, Table 'HS_UTIL_INSTALLER.CONFIGITEM' not found
```

`-30` here means "not a Foundation namespace", not "you guessed the table name" — see
§"Resolving real names" for why that distinction matters.

**Create one, or convert one — same call** (AFNS sections 2 and 3):

```
iris_execute(namespace="HSLIB", code="Do ##class(HS.Util.Installer.Foundation).Install(""<NS>"")")
```

Run against an existing non-Foundation namespace, that **converts it in place** — AFNS section 3
is explicit that conversion is what you must do if you want IRIS for Health interoperability in a
namespace that was not created as one. Note it also creates a `<NS>PKG.FoundationProduction`, so
`iris_production(action=status)` afterwards will report a production you did not write.

## When to split into multiple namespaces / productions

Drivers for splitting an estate (vs. a single `INTEROP` namespace with categories per integration):

1. **Ownership / RBAC** — different teams own different productions.
2. **Tech-stack churn** — FHIR in its own namespace as STU3 → R4 evolves; OAuth wizard regeneration isolated.
3. **Security boundary** — external integrations isolated from internal ones for tighter access control.
4. **Regulatory boundary** — data-residency or differential-audit requirements.

Both shapes (split or consolidated) are valid. Consolidation simplifies deployment at the cost of weaker access boundaries. Do **not** split for cosmetic reasons — every split adds its own monitor, alert circuit, settings, source-control branch, and deploy pipeline.

Detailed migration patterns, the deployment tool, and the multi-environment configuration strategy live in `production-lifecycle`.

## Configuration source precedence — the four levels

Production component settings can come from four levels. Pick the level deliberately:

| Order (low → high) | Portal colour | Source | Use for |
|---|---|---|---|
| 1 | green | Class property `InitialExpression` | Sensible defaults that almost never change (`Timeout = 10`) |
| 2 | black | Production XML `<Setting>` | Values identical across all environments (travel with the export) |
| 3 | blue | System Default Settings | Values that **differ** per environment (URLs, hostnames, credentials) |
| (advanced) | — | Registry | Rarely used |

**Visual cue at deploy time**: verify each per-environment setting shows **blue** in the portal after deploy. Black means hard-coded in the production XML and the same in every environment.

System Default Settings are the **only** layer that does NOT migrate via a production XML deploy. Mis-classify a setting and a deploy clobbers production with the source environment's value.

## Resolving real names — no class, table, or column name is known until a tool returned it

Before the first SQL statement (or class reference) against anything not created in this session,
resolve the real names with tools — never from the prompt, the class name, or memory.

**Step 0 — first ask whether it is a table at all.** Part of the interop configuration surface is
not projected to SQL anywhere. For those names no amount of introspection finds anything: the
answer is a typed tool, and the `-30` is final rather than a cue to guess again.

| What you were about to `SELECT` from | Reality | Call this instead |
|---|---|---|
| `Ens_Config.Item`, `Ens_Config.Setting` | **Not a queryable table** (`SQLCODE -30`). The item list and its settings are embedded objects inside the production definition, declared in the production class's XData block. | `iris_production(action=status, namespace=…)` for the item list; `iris_production_item(action=get_settings, item="<Item>", namespace=…)` for one item's settings. From ObjectScript: `##class(Ens.Config.Production).%OpenId("<Pkg>.Production")`, then iterate `tProd.Items`. |
| `Ens_Util.Queue` | **Not a table** (`SQLCODE -30`). | `iris_interop_query(what=queues, namespace=…)` |
| `%Library.SQLConnection`, `Config.SQLConnections` | **Not those names.** The SQL-Gateway connection list is the table `%Library.sys_SQLConnection`, in `%SYS` (BSQG §2). | `business-operations` §"Diagnose a named SQL Gateway connection without the Portal"; `check_config` for the MCP's own connection. |
| `%SYS.Namespace`, `Config.Namespaces` | Not a SQL table. | `check_config` |

**These four ARE real tables — the steps below apply to them unchanged.** A failure on one of them
is a **column** error (`-29`), not a missing table (`-30`): introspect the columns, don't abandon
the table.

| Real table | What it is, and when the typed tool is fewer calls |
|---|---|
| `Ens_Config.Production` | The **registered production definitions**. It does **not** carry run state — for that, `iris_production(action=status, namespace=…)`. |
| `Ens_Rule.RuleDefinition` | Real. `iris_business_rule_info` returns the rule set and its rules without guessing column names, which is where the `-29` came from. |
| `Ens_Util.Log` | Real. `iris_interop_query(what=logs, component=…, since_id=…)` adds the filters and the watermark in one call. |
| `Ens.MessageHeader` | Real, and it keeps its dot — `Ens.MessageHeader`, not `Ens_MessageHeader`. `iris_interop_query(what=messages\|trace, session_id=…)`. |

Once you know it IS a table, the sequence:

1. `iris_symbols(query="Pkg.*")` → the real class names in the package.
2. `docs_introspect(class_name=...)` → that class's properties.
3. `iris_table_info(table="Pkg_Sub.Table")` → the projected table and its columns
   (`table=` is the only parameter — there is no `schema=`. To list a package, pass the package
   to `table=`: a miss answers with the tables that DO exist there.)
4. Catalog fallback: `SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES` and
   `INFORMATION_SCHEMA.COLUMNS`. There is no `%INFORMATION_SCHEMA` — that name itself returns
   `-30`; the working name is `INFORMATION_SCHEMA`.

Dots-to-underscores is **not** enough: `SqlTableName` and `SqlFieldName` override the projection.
A class `Demo.Enc.Encounter` carrying `SqlTableName = "PatEncounter"` projects as table
`Demo_Enc.PatEncounter`, and a property `DeptCode` can project as column `UnitCode` — none of it
derivable from the class definition's names alone. Derive nothing; confirm with `iris_table_info`.
On `SQLCODE -30` (Table not found), the next call is introspection — never another guessed name.

### Headless bootstrap — running the calls `iris_execute` cannot

Some setup APIs do not survive `iris_execute`. The symptom is never an error: the call reports
success, returns nothing, and the artefact you asked for is absent or half-made. **Wrap the call in a
`[SqlProc]` class method and invoke it with `SELECT`** — that is the canonical headless path, and it
is the same pattern whatever the API. Three independent failure modes converge on it:

| Failure mode | What you see | Where it bites |
|---|---|---|
| **Class-generating calls are no-ops.** `iris_execute`'s CodeMode does not run an objectgenerator. | Call succeeds, no class generated. A later compile is green, and the method is missing at *runtime*: `<METHOD DOES NOT EXIST>GetObject`. | `EnsLib.RecordMap.Generator.GenerateObject` |
| **Only device output comes back.** In HTTP CodeMode a `Quit`/`Return` value is not captured — only what you `Write` to the current device. | "Success" with an empty result; the `%Status` you returned is lost, so a failure is indistinguishable from a success. | any call whose answer is a return value |
| **`&sql` breaks `SQLCODE`.** The MCP rewrites `&sql(...)` into a `%SQL.Statement` and binds status to a generated local, never to bare `SQLCODE`. | `<UNDEFINED>` on `If SQLCODE<0` — *after* the write already succeeded, so it reads like a failed insert and invites you to retry a load that worked. (intersystems-ib/iris-interop-dev#145) | direct SQL against `Ens_Util.LookupTable` etc. |

The `[IIS-SILENT]` guard fires on the second one automatically, but it can only speak *after* the
call — recognise the shape and start from the SqlProc instead.

The skeleton, identical for every case — take a parameter, return a **string** that says what
happened, never a bare `%Status`:

```objectscript
/// Host class for headless bootstrap procedures. Shown WITH its class wrapper deliberately: as a
/// bare `ClassMethod` this snippet had no compilation unit, so no tier could compile it and the
/// one thing a reader most needs to get right — the `[SqlProc]` keyword surviving a real compile —
/// was gated by nothing.
Class MyApp.Bootstrap Extends %RegisteredObject
{

/// The shape is identical for every API in the table below: take a parameter, and return a
/// **string** that says what happened — never a bare `%Status`. In HTTP CodeMode a returned status
/// is not captured, so a failure is indistinguishable from a success.
/// Invoke via: SELECT MyApp.Bootstrap_GenerateRecordMap('MyApp.RecordMap.Censo')
ClassMethod GenerateRecordMap(pMap As %String = "") As %String [ SqlProc ]
{
    // the object-generator call iris_execute would silently swallow
    Set sc = ##class(EnsLib.RecordMap.Generator).GenerateObject(pMap)
    Quit $Select($$$ISOK(sc): "ok", 1: "FAIL: " _ $system.Status.GetErrorText(sc))
}

}
```

**Idempotency is the shared caveat.** These APIs are create-only: re-running one after editing the
source fails or silently keeps the stale artefact. Delete first, then regenerate — and put the
delete in its own SqlProc so the pair is repeatable.

| API | What it makes | Re-run behaviour |
|---|---|---|
| `EnsLib.RecordMap.Generator.GenerateObject(map)` | the `.Record` class + the `GetObject`/`PutObject` bodies | `#5768 Class already exists` — delete the `.Record` first (`business-services`) |
| `EnsLib.HL7.SchemaXML.Import(file, .cat)` | a custom HL7 schema category | overwrites, but a renamed/removed segment lingers — remove the category first (`hl7-schemas`) |
| direct SQL into `Ens_Util.LookupTable` | lookup-table rows | make it idempotent with a `DELETE WHERE TableName=…` inside the same transaction (`lookup-tables`) |

**Whatever the SqlProc generated in the namespace still has to reach disk.** These artefacts are the
documented exception to write-file-first: generate → `iris_doc(mode=get)` → `Write` to `src/`. A
`.Record` that exists only in the namespace is a CR-12 finding like any other.

### Calling a `[SqlProc]` — the name is not the class name

A `[SqlProc]` class method projects as **`<package, dots→underscores>.<Class>_<Method>`**: everything
up to the *last* dot becomes the SQL schema, then the final class name and the method name join with
an underscore. Measured against `INFORMATION_SCHEMA.ROUTINES` on IRIS 2026.1:

| class :: method | schema | function | call as |
|---|---|---|---|
| `Demo.Bootstrap` :: `Ping` | `Demo` | `Bootstrap_Ping` | `SELECT Demo.Bootstrap_Ping(…)` |
| `ImgLink.HL7.SchemaImport` :: `ImportSchema` | `ImgLink_HL7` | `SchemaImport_ImportSchema` | `SELECT ImgLink_HL7.SchemaImport_ImportSchema(…)` |

The three forms that feel right and are not:

```sql
SELECT Demo_Bootstrap_Ping('x')        -- -359 'SQLUSER.DEMO_BOOTSTRAP_PING' does not exist
SELECT Demo.Bootstrap.Ping('x')        -- -359 'DEMO.BOOTSTRAP.PING' does not exist
SELECT Demo.UTL.Bootstrap_ImportSchema()
                                       -- -359 'DEMO.UTL.BOOTSTRAP_IMPORTSCHEMA' does not exist
                                       -- The WHOLE package goes to underscores, not just the tail.
                                       -- Class Demo.UTL.Bootstrap -> schema Demo_UTL, never Demo.UTL.
                                       -- Correct: SELECT Demo_UTL.Bootstrap_ImportSchema()
```

All-underscores carries no schema qualifier at all, so IRIS resolves it against the default schema
`SQLUSER` and never finds it. The **third** is what a half-read of the rule produces: the underscore
gets applied to `Class_Method` but not to the package. A SQL function reference in IRIS carries at
most one dot, so **two or more dots in the name is always this mistake** — compare the
`ImgLink_HL7.SchemaImport_ImportSchema` row above, the same three-segment package spelled right.

Don't derive the name — read it:

```sql
SELECT ROUTINE_SCHEMA, ROUTINE_NAME FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME LIKE 'Bootstrap%'
SELECT parent, Name FROM %Dictionary.CompiledMethod WHERE SqlProc = 1 AND parent %STARTSWITH 'MyApp'
```

**`-149 <PRIVATE METHOD>` is a different failure and does not look like one.** It means the name
resolved but the method has no `[SqlProc]` keyword — the fix is on the class, not in the query.

SQL-BO worked flow (child-table projections, invented system catalogs): see `business-operations`
(section "Resolve real table names BEFORE the first query").

## Sibling skill index

> **Invoke skills by their plugin-qualified id `iris-interop-skills:<name>`.** A bare name like
> `Skill("interop")` or `Skill("messages")` errors with "Unknown skill" — the `Skill` tool resolves
> only plugin-qualified leaf names.
>
> **Plugin AGENTS are not skills and do not go through `Skill()`.** An agent is invoked with
> `Agent(subagent_type="iris-interop-skills:<name>")`; `Skill()` on an agent id errors with
> "Unknown skill". `introspect-dont-guess` and `conformance-reviewer` are **agents**;
> `conformance-review` (skill) and `conformance-reviewer` (agent) differ by two letters, so read
> the suffix before you call. With no agent tool available, every agent has a documented fallback —
> follow the section the entry points at instead.

| If the user is doing… | Load this skill (call now) |
|---|---|
| **Starting a build / unsure which component or adapter fits a task** | `iris-interop-skills:component-map` (task→component quick-reference; load right after this router) |
| Designing the message class itself (HL7, persistent, SOAP) | `iris-interop-skills:messages` |
| Building a Business Service (inbound: file/TCP/SOAP/REST/CSV) | `iris-interop-skills:business-services` |
| Writing a DTL or transforming HL7/CDA/XML | `iris-interop-skills:transformations` |
| Building a non-SOAP Business Operation (TCP, SQL, file, REST) | `iris-interop-skills:business-operations` |
| Building a SOAP Business Operation (wizard, WSDL gotchas, %Persistent payloads, CDA) | `iris-interop-skills:soap-bo` |
| Writing a BPL Business Process or routing rules | `iris-interop-skills:bpl` |
| Production class structure, start/stop, settings, deployment, migration | `iris-interop-skills:production-lifecycle` |
| Custom HL7 schemas, Z-segments, schema editor | `iris-interop-skills:hl7-schemas` |
| Lookup tables (creating, loading, using in DTL) | `iris-interop-skills:lookup-tables` |
| **Looking at a RUNNING production for any reason** — did it arrive, how many rows landed, what did session N do, resend a message, queue depth, Visual Trace, Event Log, testing live components, SOAP tracing, purge. **Verifying a run that worked counts — not just debugging one that didn't.** | **`iris-interop-skills:message-search-debug`** — load it *before* writing any query against `Ens.MessageHeader` / `Ens_Util.Log` |
| **Writing SQL against any class/table not created this session** — resolving real class, table, and column names | §"Resolving real names" above (universal recipe); `iris-interop-skills:business-operations` for the SQL-BO worked flow |
| **FHIR work** — Façade vs Repository, OAuth2 PKCE, FHIR R4 Bundles, FHIR SQL Builder | `iris-interop-skills:fhir` |
| **Securing endpoints** — SAML 2.0 / 1.1, OAuth 2.0 server + LDAP, SSL/TLS chain, internal account hygiene | `iris-interop-skills:security` |
| **Alert circuit** — `Ens.Alert` router, dedup function set, ProductionMonitorService, per-BO alert settings | `iris-interop-skills:alerting` |
| **About to build *anything* (DTL, rule, BO method, BPL) — TDD workflow** | **`iris-interop-skills:tdd`** (entry point; non-negotiable) |
| **Built it and TDD-green — is it idiomatic / per best practices?** (run before declaring done) | **`iris-interop-skills:conformance-review`** (criteria CR-1…CR-14; the `conformance-reviewer` plugin agent — an agent, not a skill — runs it). **Mechanically: FIRST open `skills/conformance-review/SKILL.md`** — via the Skill tool where available, else read the file — before writing any review output. |
| %UnitTest framework toolbox (storage, runner flags, ^UnitTest.Result) | `iris-interop-skills:unit-tests` (lower-level reference; the TDD skill calls into it) |
| Anything DICOM (C-STORE, C-FIND, C-MOVE, MWL, STOW-RS, imaging modalities, PACS — but NOT a local `.dcm` file batch with no network protocol and no IRIS) | `iris-interop-skills:dicom` (architecture + wiring patterns; defers byte-level work to docs + vendored sample at `${CLAUDE_PLUGIN_ROOT}/BestPractices/external/workshop-iris-dicom-interop/`) |

## Exact routing — call these now (don't just describe them)

Loading this router is **not** enough: you must issue the actual `Skill(...)` calls for the components
in play, as soon as you recognise the work — not after you start coding. When several components are
involved, issue several `Skill(...)` calls in the same turn.

- Unsure which component/adapter a task needs, or starting a fresh build → `Skill(iris-interop-skills:component-map)` to pick the component, then hand off to its depth skill below.
- Building/modifying **ANY** component (BS/BP/BO/DTL/Rule/Message class) → also call
  `Skill(iris-interop-skills:tdd)` in the same turn (TDD is the default workflow, not opt-in).
- Creating, starting, stopping, updating, or otherwise touching a **production** (anything that will
  call `iris_production` — status/start/stop/update — or that wires components into the production XML)
  → **force-load** `Skill(iris-interop-skills:production-lifecycle)` in the same turn. Do NOT wait until
  you "decide" you need it: lifecycle semantics (one production per namespace, UpdateProduction vs
  restart, settings precedence) are exactly what weak models fumble. Treat it like `tdd` — non-opt-in
  the moment a production is in play.
- Designing a message → `Skill(iris-interop-skills:messages)` **first** (messages-first principle).
- Business Service / inbound (file, CSV/RecordMap, TCP, REST, SOAP) → `Skill(iris-interop-skills:business-services)`.
- DTL / transformation → `Skill(iris-interop-skills:transformations)`.
- Routing rule / MessageRouter / BPL → `Skill(iris-interop-skills:bpl)`.
- Non-SOAP Business Operation → `Skill(iris-interop-skills:business-operations)`; SOAP BO → `Skill(iris-interop-skills:soap-bo)`.
- Production class / start-stop / settings / deploy → `Skill(iris-interop-skills:production-lifecycle)`.
- Custom HL7 schema → `Skill(iris-interop-skills:hl7-schemas)`; lookup tables → `Skill(iris-interop-skills:lookup-tables)`.
- **Any look at a running production** — verifying a run landed, searching messages, tracing a session,
  resending → `Skill(iris-interop-skills:message-search-debug)`. Checking your own work counts.
- **Any review / audit / conformance or best-practices check** of built interop work →
  `Skill(iris-interop-skills:conformance-review)` — and in an environment without the Skill tool,
  **FIRST read `skills/conformance-review/SKILL.md`**. The criteria live in that file only; a review
  run from this router or the build skills alone is incomplete by construction.
- FHIR → `Skill(iris-interop-skills:fhir)`; endpoint security → `Skill(iris-interop-skills:security)`;
  alert circuit → `Skill(iris-interop-skills:alerting)`; DICOM → `Skill(iris-interop-skills:dicom)`.
- About to write the **first** SQL statement against a table you did not create in this session, or
  to reference a class whose exact name you have not seen a tool return →
  `Agent(subagent_type="iris-interop-skills:introspect-dont-guess")` — **an agent, not a skill.**
  With no agent tool, follow §"Resolving real names" above instead: `iris_table_info(table=…)` for
  the table, `docs_introspect(class_name=…)` for the members. A guessed name costs a round-trip and
  an `SQLCODE -30`; the lookup costs one call.

## Delegating to a subagent

A subagent you spawn starts with the plugin installed but **nothing loaded**: the SessionStart
bootstrap and any context injected into *this* conversation do not reach it.

- **Use `Skill(...)` when the Skill tool exists.** Reading `skills/<name>/SKILL.md` with `Read` or
  `Grep` is the documented fallback for an environment *without* the Skill tool — not the normal
  path. A file read gives you the text without registering the skill, so nothing downstream knows
  it was loaded.
- **When you hand interop work to a subagent** (`Explore`, `interop-builder`, or any other), name
  the skills in the subagent's own prompt: *"Start by calling `Skill(iris-interop-skills:interop)`
  and `Skill(iris-interop-skills:tdd)`, plus `Skill(iris-interop-skills:<topic>)` for the component
  in play."*
- **Never let a subagent's summary of a SKILL.md stand in for the skill in the main agent.** If the
  build happens in the main agent, the skills must be loaded in the main agent.

## Stop on repeated failure — do not loop, do not switch mechanism

If the same class won't compile or the same test won't run, read the error and fix the source rather
than retrying blindly. After **3 consecutive failed attempts at the same goal**, stop and report the
blocker: what was tried, the exact error, and the current hypothesis. Changing the namespace, package,
or superclass to make an error disappear is **not** a fix — it relocates the deliverable out of the
place the user asked for. A failing `iris_compile` / `iris_test` is never a cue to drop to the terminal
or `$SYSTEM.OBJ.Load`/`Compile` — that bypasses the MCP without fixing the error. There is no Docker on
native Windows IRIS (never probe for it), and never mix bash `&&`/syntax in the PowerShell tool.

## Scaffold the build on local disk BEFORE implementing

Before writing any logic, turn the component plan (from `component-map`) into a **local-disk scaffold** so
compiles never hit missing-dependency errors and `iris_test` is always called with exact, compiled names.
This is disk-only work; **execution stays MCP-only**. See `component-map` for the full recipe. In short:
write a build-order manifest (topological: messages -> DTs -> BO/BP -> rules -> production) plus typed
class skeletons and `%UnitTest.TestProduction` test stubs wired to the exact class names, all under local
`src/`, then fill in logic and push via the MCP. A component is delivered only when it is compiled in the
target namespace and its tests run GREEN via `iris_test` — local files are a scaffold, not a deliverable.
Mechanism: see `tdd` (section "The non-negotiable workflow").

## Recommended build order

For a typical end-to-end interface, work in this order — it minimises rework because later artefacts depend on earlier ones:

1. **Messages** (`messages`)
2. **Custom schemas** if needed (`hl7-schemas`)
3. **TDD workflow** (`tdd`) — every component below has its test written BEFORE the implementation. Non-negotiable.
4. **Business Service** (`business-services`) — entry point; testable only from outside IRIS
5. **Transformations** (`transformations`) — DTL test → DTL impl
6. **Business Process / routing rules** (`bpl`) — rule test → rule impl; BPL via Testing Service
7. **Business Operation** — `business-operations` (generic) or `soap-bo` (SOAP) — BO method test → BO impl
8. **Alert circuit** (`alerting`) — wire `Ens.Alert` router + sink BO + dedup function set; audit per-BO alert settings
9. **Production wiring + settings** (`production-lifecycle`) — add `TestingEnabled="true"` for dev productions; choose deployment tool early
10. **Security** (`security`) — only after components exist; SAML/OAuth/SSL added where the endpoints actually call out
11. **Test, search, debug** (`message-search-debug`) — Visual Trace + Event Log for verifying end-to-end runs; purge task added
12. **Conformance review** (`conformance-review`) — once built and TDD-green, review against the best-practice criteria (CR-1…CR-14) before declaring done; spawn the `conformance-reviewer` plugin agent (an agent, not a skill), or where no agent/Skill tool exists, FIRST read `skills/conformance-review/SKILL.md` and follow it. It re-verifies tests via the real `iris_test` tool (never a self-graded `[SqlProc]`), reports findings with the canonical fix, and proposes a scoped remediation plan.

For FHIR-specific work, replace steps 4–7 with the `fhir` decision tree (Façade vs Repository, OAuth2 PKCE setup, FHIR R4 Bundle shape).

## MCP dependency

The skills assume an IRIS MCP server is enabled — either `iris-agentic-dev` (the original) or the streamlined `iris-interop-dev` fork; tool names are identical, so either works. It provides the actions for compiling classes, inspecting productions, listing messages. If MCP tools are not available in the current session, tell the user explicitly and ask them to enable one (or perform the action manually in the IRIS Management Portal).

## Out of scope for this router

This router does no actual implementation work. Always hand off to a sibling. If the request is ambiguous, ask the user one targeted question to disambiguate which sibling to use.
