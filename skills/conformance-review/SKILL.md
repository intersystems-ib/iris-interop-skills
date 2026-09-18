---
name: conformance-review
description: Review an already-built IRIS Interoperability production against the iris-interop best-practice criteria AFTER implementation + TDD, and report what does not conform with the canonical fix. For ANY review, audit, or quality/conformance check of interop work, read THIS skill FIRST — the criteria (CR-1…CR-14) live here, not in the router or the build skills, and a review run without them is graded incomplete. Use after building/modifying components, before declaring done, or whenever the user asks whether the implementation is correct, idiomatic, or per best practices. The `conformance-reviewer` plugin agent (an agent, not a skill — with no agent tool, reading this file IS the review) and the `conformance-prescan` hook both check against this file. Triggers EN: review, audit, conformance, best practices, is this correct, is this idiomatic, code review, quality check, check my production, validate the implementation, ready to ship. Triggers ES: revisar, auditar, auditoría, conformidad, buenas prácticas, está bien implementado, es correcto, cumple, revisión, control de calidad.
---

# IRIS Interoperability — Conformance Review

> **This file is the review.** However you arrived here — the Skill tool, a native-skill search,
> or reading `skills/conformance-review/SKILL.md` directly — this document is self-contained:
> follow its workflow and check its criteria. Do NOT run an interop review from the router or the
> build skills alone; they do not carry the criteria, and a review without CR-1…CR-14 misses the
> checks this plugin exists to make.

> **A Stop hook enforces this pass.** When a session has written classes into IRIS, it blocks
> once at the moment the model would stop: hard on **CR-12** (any class put into IRIS with no
> file on disk — mechanical, no judgement involved), and once on "the conformance pass never
> ran". Answer it and stop again; the same unresolved condition is never raised twice. It speaks
> again only if you put NEW classes into IRIS and stop without reviewing them. It exists because this
> instruction previously had *no* enforcement point — measured over 206 runs that produced
> authored `.cls`, the `conformance-reviewer` agent was spawned **0 times**, while
> `interop-builder`, whose instruction lives in the SessionStart hook, was spawned 79. The two
> differed only in where they lived (#96).

A built production can **compile and "pass tests"** and still be non-idiomatic. This skill defines the
criteria a finished interop build is checked against, and the **review workflow**: surface findings →
propose a scoped remediation plan → apply only the unambiguous fixes, with the user's OK. It does **not**
re-plan from scratch and it never rewrites silently.

> **The number-one rule, learned the hard way: verify tests for real.** A build can self-author a
> `[SqlProc]` runner that returns `"PASS"` and call it via `iris_query` — that is **self-graded green**,
> not a `%UnitTest` result. The review MUST re-run the real `iris_test` tool against the
> `%UnitTest.TestProduction` class and confirm genuine asserts pass before trusting any "tests green"
> claim (see CR-7). If `iris_test` itself errors, that is a finding, not a pass.
>
> This is stronger than "don't mark your own homework": such a runner has a failure mode it **cannot
> detect by construction**. A test method that raises before its first `$$$Assert*` writes **zero assert
> rows**, so any "did any assert fail?" scan finds nothing and counts the method as passed. Measured on
> IRIS for Health 2026.1: on a class where `%UnitTest` printed `**FAILED**` and `iris_test` reported red,
> an assert-scanning wrapper reported `passed=2 failed=0`. See `unit-tests` for the fix if you must keep
> such a wrapper — read the **method node's** own flag, never its assert children.

## How to run a review

1. **Scope.** Identify the classes built/changed this session (production XML, `.BS`/`.BP`/`.BO`/`.DT`/
   `.RUL`/`.MSG`/Tests). Read them from disk and/or via the IRIS MCP (`iris_doc`, `iris_production_item`).
2. **Load the relevant skills** so you judge against their guidance, not memory: `iris-interop-skills:interop`
   (router/naming), plus the component skills in play (`:bpl`, `:business-services`, `:transformations`,
   `:alerting`, `:hl7-schemas`, `:messages`, `:tdd`).
3. **Check every criterion below** (CR-1…CR-14) against the actual code. Cite `file:line` and the exact
   best-practice it meets or breaks.
3b. **Re-check the criteria that depend on WIRING, not just on the classes you changed.** Some
   violations are created by an edit to a *different* component than the one that ends up wrong —
   CR-6 above is the worked example: adding an HL7 service to an existing generic router makes the
   **router** non-conformant without touching it. So when this session added or re-pointed an input,
   re-evaluate the **targets**, not only the item you edited. Conformance is not a per-component
   "build it, review it once" gate.
4. **Re-verify tests for real** (CR-7): run `iris_test` on the test class; record the genuine result.
4b. **Compare the namespace against the source tree** (CR-12). This is the one check that cannot be
   done by reading code — it needs both sides:

   ```
   iris_symbols(query="<Pkg>.*", namespace="<NS>", limit=500)   ← default limit is 20; raise it
   Glob("**/src/**/*.cls")                                       ← the tree
   ```

   Normalise both to class names (`src/Pkg/BO/Name.cls` → `Pkg.BO.Name`) and diff **in both
   directions**. Report anything present in one and not the other.

   Then compare **content**, not only names: `iris_doc(mode=get)` each class in scope and
   byte-compare it against the disk file. Presence is not agreement, and a stale file is the
   likelier finding — a session that edits a class inline several times leaves the tree behind
   without ever removing it. Whitespace and the generated `Storage` block are not findings;
   a different property list is.

   **The generated `Storage Default` block is NOT a finding at any severity — not even P3.** Check
   what it NAMES, not whether it is there: if the globals are the class's own extent
   (`^Pkg.MSG.NameD`/`^Pkg.MSG.NameI` for `Pkg.MSG.Name`), it is the generated default that a
   disk-first export legitimately brings back into the file, and reporting it sends the user into a
   remove→re-export→re-flag loop on the most common artefact there is — a `%Persistent` message.
   Only a **custom global map** — globals that are not this class's own extent — is reportable.
4c. **Name the destination** (CR-13). Before trusting a green `iris_test`, write down in one line
   which external destination the tests actually wrote to — DSN / `database.schema.table`, file
   path, or endpoint — and where each of those values came from: the BO's production settings and
   the test class's own setup, **read, not assumed**. Compare it against the destination the task
   names. If the review cannot name it, that is a CR-13 finding, not a pass. A destination the
   session **created** during this build is a CR-13 finding regardless of the test result. Skip this
   step only when the tests touch no external system at all.

   **Read it with the gated helper rather than by hand** —
   `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/tdd-destination-assert.cls`:

   ```
   SELECT Example_Tests.DestinationAssert_NameDestination('<Pkg>.Production','BO.AdtOut','FilePath')
   -> BO.AdtOut.FilePath = /data/hl7/out/  (Target=Adapter, class=EnsLib.HL7.Operation.FileOperation)
   ```

   Three things that make the difference between performing CR-13 and appearing to:

   - **`Target` is half the destination.** A setting is `Host` or `Adapter`, the Portal shows both in
     one panel, and a value on the wrong target is accepted and never read. "FilePath = /data/hl7/out/"
     is not an answer; "FilePath on the **Adapter**" is.
   - **Absent and empty read identically.** A setting that is not configured returns `""`, exactly like
     one configured to empty. The helper reports `NOT CONFIGURED: … a CR-13 finding, not an empty
     destination`, because CR-13 says an unnameable destination is a finding rather than a pass.
   - **The read needs a REGISTERED production.** `%OpenId` and `Ens_Config.Item` both read the
     registered definition, not the class file's XData, so a production that merely compiles reads as
     **zero items**. Zero items is not "no destinations configured" — it is "I read nothing".

   And `Ens_Config.Item` **is** a queryable table: `interop` said otherwise until v1.24.0, and that
   claim is why this step had no worked example for as long as it did.
5. **Emit the report** (severity-tagged) → **a scoped remediation plan** → offer to **apply the safe
   fixes** (P0/P1 with an unambiguous canonical fix) only after the user confirms. Leave defensible
   choices as notes, not edits.
6. **For *confirmed* P0/P1 findings, offer to file them** — load
   `Skill(iris-interop-skills:report-issue)`, which dedups against existing issues and asks before
   creating anything. Do this even when the review was asked for in its own words ("review this",
   "is this idiomatic") and nobody mentioned an issue: filing is the *consequence* of a review, so
   the prompt that started it will not name it. Never auto-file; `report-issue` always confirms
   first. Skip it for P2/P3 and for anything you are not sure reproduces.

## Severity

- **P0** — breaks the integration or hides failure (e.g. tests not actually verified; component won't run).
- **P1** — clear anti-pattern with a canonical built-in alternative (hand-rolled where a built-in exists).
- **P2** — idiomatic gap that works but loses tooling/robustness (declarative vs procedural; missing alerts).
- **P3** — cosmetic / naming / hardcoded paths.

## Criteria (CR-1 … CR-14)

Items marked **⚙ pre-scannable** are also detected mechanically by the `conformance-prescan` hook from a
single file's text; the rest need the agent's cross-file/semantic judgment.

| ID | Sev | Anti-pattern (what to flag) | Canonical fix | Skill |
|---|---|---|---|---|
| **CR-1** ⚙ | P1 | A pass-through `Ens.BusinessProcess` whose `OnRequest` only calls a DTL `.Transform()` then `SendRequestAsync()` — routing logic coded as a BP instead of declared. | Put the `transform` on the **MessageRouter rule's `<send>`** and target the BO directly; delete the intermediate BP. *(interop: "MessageRouter + rule, never a hand BP with `OnRequest`")* | `bpl`, `interop` |
| **CR-2** ⚙ | P1 | A `Ens.BusinessService` + `EnsLib.File.InboundAdapter` that parses rows with `$Piece`/`ReadLine` in `OnProcessInput` — and sends **all rows in one session** instead of one per record. | Use **`EnsLib.RecordMap.Service.*` + a RecordMap** (delimited/fixed-width); one session per record. *(interop: "RecordMap, never a hand-rolled parser")* | `business-services` |
| **CR-3** | P2 | Alert circuit present structurally but **not fed**: BOs without `AlertOnError`, Router without `AlertOnBadMessage`/`BadMessageHandler`, no `Ens.AlertRequest` on real failures. | `AlertOnError=1` on BOs; `AlertOnBadMessage=1` + `BadMessageHandler` on the RoutingEngine; emit `Ens.AlertRequest` on error paths. | `alerting` |
| **CR-4** ⚙ | P2 | A DTL (`Ens.DataTransformDTL`) implemented as imperative `<code>` loops (`SetValueAt`/`GetValueAt`) with **no `<assign>`** — loses visual-editor round-trippability. | Express field/segment moves as `<assign property='target.{…}'>`; reserve `<code>` for genuinely procedural steps (Z-segments, lookups). | `transformations` |
| **CR-5** ⚙ | P2 | An HL7 routing rule matching on raw `MSH:9.1`/`9.2` string equality with **no `docCategory`/`docName`/`source`** constraints. | Constrain by `docCategory`/`docName` (+ `source`) instead of positional `MSH:9.x` matches. | `bpl`, `hl7-schemas` |
| **CR-6** ⚙ | P2 | A **generic** `EnsLib.MsgRouter.RoutingEngine` production item with **HL7 flowing into it** — any `EnsLib.HL7.*` service/process naming it in `TargetConfigNames`, or a rule using `EnsLib.HL7.MsgRouter.RuleAssist`. Key off the **production wiring**, not only the rule: the router is correct when built for a non-HL7 input and becomes a violation the moment an HL7 input is pointed at it, which is a *different* edit to a *different* component. A green end-to-end test cannot see it — the generic engine transports `EnsLib.HL7.Message` fine, it just loses schema validation in the rule editor and the `{MSH:9.1}` paths. | Use the HL7-specific `EnsLib.HL7.MsgRouter.RoutingEngine`. If the router must serve both HL7 and custom messages, split it — one router per message shape. | `bpl` |
| **CR-7** ⚙ | **P0** | "Tests pass" claimed from a **self-authored `[SqlProc]` runner** read via `iris_query`, not from `%UnitTest`. `iris_test` never returned green (or wasn't run). | **Re-run `iris_test`** against the `%UnitTest.TestProduction` class; require real asserts to pass. Treat a `[SqlProc]`-returned `"PASS"` as unverified. | `tdd`, `unit-tests` |
| **CR-8** | P2 | HL7/REST message fields typed as non-`%String` (forced by `EnsLib.HL7`/REST string semantics), except genuinely typed synthetic fields. | Type HL7/REST-sourced message properties `As %String`. | `messages` |
| **CR-9** | P3 | Naming: classes not `<Pkg>.<Tipo>.<Nombre>`, or production **Item Name** not `<Tipo>.<Nombre>`; Category ≠ package root. The Tipo set is `interop`'s table, not a shorter list: `.BS`/`.BP`/`.BO`/`.DT`/`.DTS`/`.MSG`/`.RUL`/`.DAT`/`.ADP`/`.UTL`/`.HL7` — `.UTL` (Utility / FunctionSet) and `.DAT` (internal `%SerialObject` data classes, see CR-11) are conformant, do **not** flag them. Wizard-generated SOAP/XSD code is exempt: it follows `interop`'s separate `WSC`/`WS` sub-package table. | Apply the interop naming convention; Category = package root; fixed `Ens.Alert`. | `interop` |
| **CR-10** ⚙ | P3 | A **runtime component** (an `Ens.BusinessService`/`BusinessOperation`/`BusinessProcess`/`Ens.DataTransformDTL` subclass) with a **hardcoded absolute path** (`C:\…`, `/tmp/…`). | Move the path to the item's **Setting** (`FilePath`, `Filename`, `JDBCClasspath` — adapter settings, ESQL §3.1), or resolve it at run time with `##class(%Library.File).ManagerDirectory()` / `##class(%Library.File).TempFilename("csv")` / `$SYSTEM.Util.InstallDirectory()` (note: `InstallDirectory` is on `%SYSTEM.Util`, **not** on `%Library.File`). **Not a finding** in a `%UnitTest` fixture (which must name a real file on the IRIS server), in a provisioning/bootstrap helper, or in a `Parameter` default: there is no production item to carry a Setting. Flag those only if the same literal is also duplicated in a component. | `production-lifecycle` |
| **CR-11** ⚙ | P2 | An **object property of a message resolved to a `%Persistent` class with no delete cascade** — no `Trigger [ Event = DELETE ]` and no `%OnDelete` on the referencing message, no `OnDelete = Cascade` on the link. `Ens.Util.Tasks.Purge` then deletes the message and orphans the child rows, silently, forever. | Make it `%SerialObject` in `<Pkg>.DAT.<Name>` if it's a value object owned by the message (the default); if it must be `%Persistent` (shared / queried on its own / recursive / large), add the delete cascade to the **referencing** message class. | `messages` |
| **CR-12** | **P1** | **A class exists in the IRIS namespace but not in `src/`, or exists in both with DIFFERENT CONTENT.** Compare bytes, not just presence, and in both directions — the common case in a long session is not an absent file but a *stale* one, because `iris_doc(mode=put, content=…)` and `iris_production_item` change the namespace only. The namespace is not version-controlled, not reviewable, and does not survive the instance — so work that lives only there is already lost, it just hasn't been noticed yet. Check both directions: a class only on disk was never compiled, or was deleted from the namespace, and the running production does not contain what the tree says it does. | `iris_doc(mode=get)` the namespace-only classes and write them to `src/` in the Atelier nested layout; compile or delete the disk-only ones so the two agree. Then fix the cause: hand-written classes go **`Write` → `iris_doc(mode=put)`** (a PreToolUse gate enforces it), wizard/generator output goes **generate → `iris_doc(mode=get)` → `Write`** (`soap-bo`, `messages`, `business-services`). | `production-lifecycle`, `soap-bo` |

| **CR-13** | **P0** | **The test went green against a destination the session fabricated, not the one the task named.** A green `iris_test` proves the code ran; it does not prove it ran against the right thing. The test, or the BO it exercises, points at a database, schema, table, file path or endpoint the session **created** rather than the one the requirement fixed. Three hard signals: (a) a `CREATE DATABASE`/`CREATE TABLE`/`mkdir` issued during the build to make the test runnable, against a name the task never mentions; (b) DDL executed with a credential **stronger** than the one the task granted (task says the app login is CRUD-without-DDL; the session used a superuser); (c) the message class or DTL contract reshaped to fit the fabricated destination instead of the specified one. Applies whenever the tests touch an external system. Verify by reading the BO's `DSN`/`FilePath`/`Credentials` from its production settings and the test class's own setup — read, not assumed — and comparing both against the task statement. | Point the BO and the test back at the destination named in the requirement and re-run `iris_test`. Isolate **inside** that destination (`tdd` §"Test data isolation" — prefix first; a separate database is the top rung, not the default). A genuine name collision is fixed by renaming the **test artefact**, never the destination. If the task's credentials cannot do what the test needs, that is a finding to report, not a licence to escalate. | `tdd`, `business-operations` |
| **CR-14** ⚙ | **P1** | A subclass of a **prebuilt** `EnsLib.*.Service.*` / `EnsLib.*.Operation.*` whose `OnInit()` override never calls `##super()`. The base `OnInit` is the only place the host's parser state is initialised (`..recordMapFull`, `..%Parser`); without it the component starts green, consumes and **deletes** its input, and emits no message and no Event Log entry — a green run that proves nothing happened. Mechanical: the class extends `EnsLib\..*\.(Service\|Operation)\.` **and** the file contains no `##super`. Does **not** apply to a direct `Ens.BusinessService`/`Ens.BusinessOperation` subclass with `Parameter ADAPTER` — its inherited `OnInit()` does nothing by default (ESQL). | Make `Set tSC = ##super()  Quit:$$$ISERR(tSC) tSC` the first statement of the override, then validate. | `business-services` |

## Output template

```
## Conformance review — <production/scope>
Tests (real iris_test): <PASS n/n | FAIL | NOT-RUN/ERROR ⇒ CR-7>
Destination (CR-13): <db.schema.table | path | endpoint the tests wrote to> — <matches the task | MISMATCH>

### Findings
- [CR-x][Pn] <title> — <file:line>
  best-practice: <one line>  ·  fix: <canonical fix>
… (one per finding; "none" if clean)

### Remediation plan (scoped, ordered by severity)
1. <P0/P1 item> — <concrete change>
…

### Safe to auto-apply (with your OK): <list of P0/P1 with unambiguous fixes>
### Left as a note (defensible): <P2/P3 judgment calls>
```

A clean build returns "no findings" plus the verified `iris_test` result — that confirmation is itself
valuable. The reviewer reports; it does not silently rewrite. Full rationale for each criterion lives in
the sibling skill named in the table and in `${CLAUDE_PLUGIN_ROOT}/BestPractices/BestPractices_Interop_IRIS.md`.
