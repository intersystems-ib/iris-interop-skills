---
name: component-map
description: Quick-reference map from a plain-English integration task to the exact IRIS component type, superclass, prebuilt adapter, and the key methods/settings. Routed from interop — load it at the START of a build to pick the right component before diving into the per-component skill. Triggers: which component, what class do I use, qué componente, qué adaptador, BS or BO, superclass, adapter for, scaffold, cómo empiezo, task to component.
---

# Task → Component map

A lookup table that turns "I need to do X" into the **exact** IRIS Interop component type, its
superclass, the prebuilt adapter, and the 2–3 settings/methods that matter. It exists to stop the most
expensive failure mode observed in agent-driven builds: **picking the wrong component or adapter and
hand-rolling ObjectScript to compensate** (wrong adapter → 25-minute connection spirals; guessed APIs →
`<METHOD DOES NOT EXIST>`; hand-rolled SQL → `<SYNTAX>errdone+2^%qaqqt`).

## How to use this skill

Load it **once, at the start of a build**, right after `interop` and before you write any class. Find the
row for each task in play, note the component + superclass + adapter, then hand off to the per-component
skill named in the last column for the full pattern, settings checklist, and pitfalls. This skill is the
index from *intent* to *component*; the sibling skills are the depth. It does not replace them — design the
message first (`messages`) and write the test first (`tdd`) as always.

## The map

| Task (intent) | Component | Superclass | Prebuilt adapter | Key methods / settings | Depth skill |
|---|---|---|---|---|---|
| Read CSV / flat file from a folder | BS | `EnsLib.RecordMap.Service.FileService` | `EnsLib.File.InboundAdapter` | `RecordMap`,`TargetConfigNames`,`HeaderCount` (Host); `FilePath`,`FileSpec`,`Charset=UTF-8` (Adapter). **Generate the `.Record`+`GetObject` — compiling alone does NOT.** | `business-services`, `lookup-tables` |
| Receive HL7 v2.x from files | BS | `EnsLib.HL7.Service.FileService` | `EnsLib.File.InboundAdapter` | `MessageSchemaCategory="<ver>:<msgtype>"` (e.g. `2.5:ADT_A01`) — mandatory for symbolic paths; `TargetConfigNames` | `business-services`, `hl7-schemas` |
| Receive HL7 over MLLP/TCP | BS | `EnsLib.HL7.Service.TCPService` | built-in TCP | `Port`,`MessageSchemaCategory`,`ReplyCodeActions` | `business-services` |
| Expose a REST endpoint (JSON in) | BS | `EnsLib.REST.Service` (is both `%CSP.REST`+`Ens.BusinessService`) | `EnsLib.HTTP.InboundAdapter` (own port) or adapterless via CSP web app | `XData UrlMap` `<Route>`; handler is an **instance** method → `..SendRequestSync(target,req,.resp)`; write to the **passed-in** `pOutput`. Web app `AutheEnabled=96` for Basic. | `business-services`, `security` |
| Expose an inbound SOAP web service | BS | `EnsLib.SOAP.Service` | adapterless (`ADAPTER=""`) | `[WebMethod]` methods; `SERVICENAME`/`NAMESPACE`; **production item Name = class FQCN** or the WSDL won't resolve; Basic Auth in `OnPreWebMethod()` | `business-services`, `soap-bo`, `security` |
| Receive from a source that already dispatches (CSP/queue) | BS | `Ens.BusinessService` | none (`PoolSize="0"`, passive) | created on demand via `Ens.Director.CreateBusinessService(...)`; `..ProcessInput(req,.resp)` | `business-services` |
| Route HL7 to multiple targets by type | Router | `Ens.Rule.Definition` (runtime `EnsLib.HL7.MsgRouter.RoutingEngine`) | — | `RuleAssistClass=EnsLib.HL7.MsgRouter.RuleAssist`; `Document.{MSH:9.1}="ADT"`; `<send transform=… target=…/>`; item setting `BusinessRuleName` | `bpl` |
| Orchestrate multi-step (lookup → decision → fan-out) | BP | `Ens.BusinessProcessBPL` | — | `XData BPL`; `<call async='0'>` sync for lookups, `'1'` fire-and-forget; `<if>`,`<context>` | `bpl` |
| Transform HL7→HL7 (same/diff version) | DTL | `Ens.DataTransformDTL` | — | `Create=Copy` (same ver) / `New` (cross-ver); `target.SetValueAt(v,"MSH:8")` | `transformations` |
| Transform repeating HL7 segments (AL1/NK1/OBX) into a collection | DTL + subtransform | `Ens.DataTransformDTL` (sub: src `EnsLib.HL7.Segment`, tgt `Ens.StringContainer`) | — | iterate `1:source.SegCount`, filter `seg.Name="AL1"`, call sub-DTL, `target.List.Insert(...)`. Grouped segments only by **index**, not `GetSegmentAt("NK1(N)")` | `transformations`, `hl7-schemas` |
| Write rows to an **external** SQL DB (PostgreSQL/Oracle/foreign IRIS) | BO | `Ens.BusinessOperation` | `EnsLib.SQL.OutboundAdapter` (JDBC) | `MessageMap`; `..Adapter.ExecuteUpdate(.rows,sql,p1,p2,…)` with `?` — **one bind per `?`**. Use a **direct `jdbc:` URL** in `DSN`, not a pre-created ODBC DSN. | `business-operations` |
| Read rows from an external/foreign DB | BO | `Ens.BusinessOperation` | `EnsLib.SQL.OutboundAdapter` | `..Adapter.ExecuteQuery(.rs,sql,p1)` → `rs.Next()`/`rs.Get("Col")`; if `<SUBSCRIPT>%QParms` use `ExecuteQueryParmArray` with `$$$SqlVarchar`/`$$$SqlInteger` types | `business-operations` |
| Persist to a `%Persistent` table in **this** namespace | BO | `Ens.BusinessOperation` | **none** | `Set o=##class(X).%New()` … `o.%Save()`. Don't use the SQL adapter for local tables. | `business-operations` |
| Call an external REST endpoint (JSON out) | BO | `Ens.BusinessOperation` | `EnsLib.REST.OutboundAdapter` / `EnsLib.HTTP.OutboundAdapter` | `..Adapter.Post(.resp,url,body)`; `Credentials`,`SSLConfig`, finite `FailureTimeout`; `resp.StatusCode` is multidim → wrap in `Try{}` | `business-operations` |
| Call an external SOAP web service | BO | SOAP-wizard client / `Ens.BusinessOperation` | SOAP client **or** `EnsLib.HTTP.OutboundAdapter` (manual envelope) | `SOAPAction` header from WSDL; `ArrayOf<X>` wraps items in `<itemsItem>` | `soap-bo`, `business-operations` |
| Write HL7 to a file | BO | `EnsLib.HL7.Operation.FileOperation` | built-in file | `Filename`,`FilePath` | `business-operations` |
| Write plain text / JSON lines to a file | BO | `Ens.BusinessOperation` | `EnsLib.File.OutboundAdapter` | `..Adapter.PutLine(file,line)`; `Overwrite=0` ⇒ append | `business-operations` |
| Map codes (M→1, planta→edificio, clinic names) | Lookup table + `Lookup()` | imported via Portal / API | — | DTL `Lookup("GeneroSOAP",src.Genero,"")`; code `##class(Ens.Util.LookupTable).%GetValue(tbl,v)`. **Always pass the 3rd default arg.** | `lookup-tables`, `transformations` |
| Capture production errors to a sink | Alert router + sink BO | `Ens.Rule.Definition` named **`Ens.Alert`** + `Ens.BusinessOperation` | `EnsLib.File.OutboundAdapter` | router **must** be named `Ens.Alert`; BO `MessageMap` on `Ens.AlertRequest`; per-item `Send Alert on Error=true` | `alerting` |
| Make HL7 searchable in Message Viewer | Search Table | `EnsLib.HL7.SearchTable` | — | `XData SearchSpec` `<Item PropName="..">[PID:5()]</Item>` | `hl7-schemas`, `message-search-debug` |
| Unit-test any interop component | Test | `%UnitTest.TestProduction` (**never** `%UnitTest.TestCase` for productions) | — | `Parameter PRODUCTION` (compile-time mandatory — missing/empty = `#5001`); `TestControl()`→no-op; seed `BaseLogId`; `..SendRequest(...)`; assert the **side-effect**, not just the Event Log | `tdd`, `unit-tests` |

## The two rules that prevent most wasted round-trips

1. **Pick the adapter from this table, don't improvise.** The single most expensive build failure is the
   wrong outbound DB path: choosing an **ODBC SQL-Gateway DSN** instead of a direct JDBC URL produces
   `ERROR #6022: Gateway failed: SQLConnect … SQLState (IM002) Data source name not found` and a long,
   un-winnable connection spiral. For an external DB, `EnsLib.SQL.OutboundAdapter` with a `jdbc:` URL in
   `DSN` is the answer — see the JDBC wiring checklist in `business-operations`.
2. **Don't hand-roll introspection or SQL via `iris_execute`.** Asking "what's the production status / which
   items exist / what columns does this table have" by writing ObjectScript or SQL leads to guessed,
   non-existent APIs (`<METHOD/CLASS DOES NOT EXIST>`) and malformed queries (`<SYNTAX>errdone+2^%qaqqt`).
   Use the typed MCP tools — the cheat-sheet lives in `message-search-debug` and the `introspect-dont-guess`
   agent resolves real names before you reference them.

## Scaffold on disk before you implement (cuts compile-order and `NO_TESTS_FOUND` thrash)

Once you have picked the components above, **do not start writing logic class-by-class and discovering the
compile order by trial and error.** That is the single biggest source of wasted cycles in agent builds:
classes referenced before their dependency exists (`COMPILE_MISSING_CLASS` / `ENS_COMPILE_ERR`), and tests
invoked before they compile (`NO_TESTS_FOUND`). Instead, from the component plan, scaffold the whole build
**on local disk first** — this is plain file-writing, NOT an MCP action:

1. **Build-order manifest.** Write the topological compile order to a local file
   (e.g. `src/BUILD-ORDER.md` or a comment block): **messages -> custom schemas -> DTs -> BO/BP -> rules
   -> production**. Every later artefact depends on earlier ones, so compiling in this order means
   `iris_doc(compile)` / `iris_compile` never hits a missing-dependency error.
2. **Class-skeleton stubs in that order.** Write empty/typed `.cls` stubs under local `src/` in the
   Atelier-nested layout, with the correct `<Package>.<Tipo>.<Name>` names, superclasses, and adapters
   from the table above. Stubs only — signatures and `Extends`, no logic yet — so the dependency graph is
   real on disk before any push.
3. **TestProduction skeletons wired to exact names.** Write `%UnitTest.TestProduction` stubs whose
   `Parameter PRODUCTION` and `##class(...)` references use the **exact** class names from step 2, so when
   you later run `iris_test` you pass a name that exists and is compiled (no `NO_TESTS_FOUND`).

Then fill in logic and push each class via the MCP **in manifest order**. Source of truth stays in local
`src/`; **execution (compile/run/test) stays MCP-only** — scaffolding never reaches IRIS except through
`iris_doc`/`iris_compile`/`iris_test`.

## See also

- `interop` — the router; load this map right after it, before any per-component skill
- `messages` — design the message class first (the foundational building block)
- `tdd` — write the component's test before the implementation (non-negotiable)
- `business-operations` / `business-services` / `bpl` / `transformations` — the depth behind each row
- `message-search-debug` + `introspect-dont-guess` agent — typed-tool cheat-sheet (rule 2 above)
