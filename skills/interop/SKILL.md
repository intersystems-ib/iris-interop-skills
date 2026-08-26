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
resolve the real names with tools — never from the prompt, the class name, or memory. The sequence:

1. `iris_symbols(query="Pkg.*")` → the real class names in the package.
2. `docs_introspect(class_name=...)` → that class's properties.
3. `iris_table_info(table="Pkg_Sub.Table")` → the projected table and its columns
   (`iris_table_info(schema="Pkg_Sub")` lists a whole schema).
4. Catalog fallback: `SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES` and
   `INFORMATION_SCHEMA.COLUMNS`. There is no `%INFORMATION_SCHEMA` — that name itself returns
   `-30`; the working name is `INFORMATION_SCHEMA`.

Dots-to-underscores is **not** enough: `SqlTableName` and `SqlFieldName` override the projection.
A class `Demo.Enc.Encounter` carrying `SqlTableName = "PatEncounter"` projects as table
`Demo_Enc.PatEncounter`, and a property `DeptCode` can project as column `UnitCode` — none of it
derivable from the class definition's names alone. Derive nothing; confirm with `iris_table_info`.
On `SQLCODE -30` (Table not found), the next call is introspection — never another guessed name.

SQL-BO worked flow (child-table projections, invented system catalogs): see `business-operations`
(section "Resolve real table names BEFORE the first query").

## Sibling skill index

> **Invoke skills by their plugin-qualified id `iris-interop-skills:<name>`.** A bare name like
> `Skill("interop")` or `Skill("messages")` errors with "Unknown skill" — the `Skill` tool resolves
> only plugin-qualified leaf names.

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
| **Built it and TDD-green — is it idiomatic / per best practices?** (run before declaring done) | **`iris-interop-skills:conformance-review`** (criteria CR-1…CR-12; the `conformance-reviewer` agent runs it). **Mechanically: FIRST open `skills/conformance-review/SKILL.md`** — via the Skill tool where available, else read the file — before writing any review output. |
| %UnitTest framework toolbox (storage, runner flags, ^UnitTest.Result) | `iris-interop-skills:unit-tests` (lower-level reference; the TDD skill calls into it) |
| Anything DICOM (C-STORE, C-FIND, C-MOVE, MWL, STOW-RS, modalities, PACS) | `iris-interop-skills:dicom` (architecture + wiring patterns; defers byte-level work to docs + vendored sample at `${CLAUDE_PLUGIN_ROOT}/BestPractices/external/workshop-iris-dicom-interop/`) |

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

## Stop on repeated failure — do not loop, do not switch mechanism

If the same class won't compile or the same test won't run after a few attempts, **stop and report the
blocker** — read the error and fix the source rather than retrying blindly. A failing `iris_compile` /
`iris_test` is never a cue to drop to the terminal or `$SYSTEM.OBJ.Load`/`Compile` — that bypasses the
MCP without fixing the error. There is no Docker on native Windows IRIS (never probe for it), and never
mix bash `&&`/syntax in the PowerShell tool. The full iteration cap and self-abort rule lives in the
`interop-builder` agent.

## Scaffold the build on local disk BEFORE implementing

Before writing any logic, turn the component plan (from `component-map`) into a **local-disk scaffold** so
compiles never hit missing-dependency errors and `iris_test` is always called with exact, compiled names.
This is disk-only work; **execution stays MCP-only**. See `component-map` for the full recipe. In short:
write a build-order manifest (topological: messages -> DTs -> BO/BP -> rules -> production) plus typed
class skeletons and `%UnitTest.TestProduction` test stubs wired to the exact class names, all under local
`src/`, then fill in logic and push via the MCP.

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
12. **Conformance review** (`conformance-review`) — once built and TDD-green, review against the best-practice criteria (CR-1…CR-12) before declaring done; spawn the `conformance-reviewer` agent, or where no agent/Skill tool exists, FIRST read `skills/conformance-review/SKILL.md` and follow it. It re-verifies tests via the real `iris_test` tool (never a self-graded `[SqlProc]`), reports findings with the canonical fix, and proposes a scoped remediation plan.

For FHIR-specific work, replace steps 4–7 with the `fhir` decision tree (Façade vs Repository, OAuth2 PKCE setup, FHIR R4 Bundle shape).

## MCP dependency

The skills assume an IRIS MCP server is enabled — either `iris-agentic-dev` (the original) or the streamlined `iris-interop-dev` fork; tool names are identical, so either works. It provides the actions for compiling classes, inspecting productions, listing messages. If MCP tools are not available in the current session, tell the user explicitly and ask them to enable one (or perform the action manually in the IRIS Management Portal).

## Out of scope for this router

This router does no actual implementation work. Always hand off to a sibling. If the request is ambiguous, ask the user one targeted question to disambiguate which sibling to use.
