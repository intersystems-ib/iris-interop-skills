---
name: conformance-review
description: Review an already-built IRIS Interoperability production against the iris-interop best-practice criteria AFTER implementation + TDD, and report what does not conform with the canonical fix. Use after building/modifying components, before declaring done, or whenever the user asks "is this implemented correctly / per best practices / conforme". This skill is the single source of truth for the conformance criteria (CR-1…CR-12); the `conformance-reviewer` agent and the `conformance-prescan` hook both check against it. Triggers EN: review, conformance, best practices, is this correct, code review, ready to ship. Triggers ES: revisar, conformidad, buenas prácticas, está bien implementado, cumple, revisión.
---

# IRIS Interoperability — Conformance Review

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
3. **Check every criterion below** (CR-1…CR-12) against the actual code. Cite `file:line` and the exact
   best-practice it meets or breaks.
4. **Re-verify tests for real** (CR-7): run `iris_test` on the test class; record the genuine result.
4b. **Compare the namespace against the source tree** (CR-12). This is the one check that cannot be
   done by reading code — it needs both sides:

   ```
   iris_symbols(query="<Pkg>.*", namespace="<NS>", limit=500)   ← default limit is 20; raise it
   Glob("**/src/**/*.cls")                                       ← the tree
   ```

   Normalise both to class names (`src/Pkg/BO/Name.cls` → `Pkg.BO.Name`) and diff **in both
   directions**. Report anything present in one and not the other.
5. **Emit the report** (severity-tagged) → **a scoped remediation plan** → offer to **apply the safe
   fixes** (P0/P1 with an unambiguous canonical fix) only after the user confirms. Leave defensible
   choices as notes, not edits.

## Severity

- **P0** — breaks the integration or hides failure (e.g. tests not actually verified; component won't run).
- **P1** — clear anti-pattern with a canonical built-in alternative (hand-rolled where a built-in exists).
- **P2** — idiomatic gap that works but loses tooling/robustness (declarative vs procedural; missing alerts).
- **P3** — cosmetic / naming / hardcoded paths.

## Criteria (CR-1 … CR-12)

Items marked **⚙ pre-scannable** are also detected mechanically by the `conformance-prescan` hook from a
single file's text; the rest need the agent's cross-file/semantic judgment.

| ID | Sev | Anti-pattern (what to flag) | Canonical fix | Skill |
|---|---|---|---|---|
| **CR-1** ⚙ | P1 | A pass-through `Ens.BusinessProcess` whose `OnRequest` only calls a DTL `.Transform()` then `SendRequestAsync()` — routing logic coded as a BP instead of declared. | Put the `transform` on the **MessageRouter rule's `<send>`** and target the BO directly; delete the intermediate BP. *(interop: "MessageRouter + rule, never a hand BP with `OnRequest`")* | `bpl`, `interop` |
| **CR-2** ⚙ | P1 | A `Ens.BusinessService` + `EnsLib.File.InboundAdapter` that parses rows with `$Piece`/`ReadLine` in `OnProcessInput` — and sends **all rows in one session** instead of one per record. | Use **`EnsLib.RecordMap.Service.*` + a RecordMap** (delimited/fixed-width); one session per record. *(interop: "RecordMap, never a hand-rolled parser")* | `business-services` |
| **CR-3** | P2 | Alert circuit present structurally but **not fed**: BOs without `AlertOnError`, Router without `AlertOnBadMessage`/`BadMessageHandler`, no `Ens.AlertRequest` on real failures. | `AlertOnError=1` on BOs; `AlertOnBadMessage=1` + `BadMessageHandler` on the RoutingEngine; emit `Ens.AlertRequest` on error paths. | `alerting` |
| **CR-4** ⚙ | P2 | A DTL (`Ens.DataTransformDTL`) implemented as imperative `<code>` loops (`SetValueAt`/`GetValueAt`) with **no `<assign>`** — loses visual-editor round-trippability. | Express field/segment moves as `<assign property='target.{…}'>`; reserve `<code>` for genuinely procedural steps (Z-segments, lookups). | `transformations` |
| **CR-5** ⚙ | P2 | An HL7 routing rule matching on raw `MSH:9.1`/`9.2` string equality with **no `docCategory`/`docName`/`source`** constraints. | Constrain by `docCategory`/`docName` (+ `source`) instead of positional `MSH:9.x` matches. | `bpl`, `hl7-schemas` |
| **CR-6** | P2 | A **generic** `EnsLib.MsgRouter.RoutingEngine` production item hosting an **HL7** rule (rule uses `EnsLib.HL7.MsgRouter.RuleAssist`). | Use the HL7-specific `EnsLib.HL7.MsgRouter.RoutingEngine` engine to match the HL7 rule. | `bpl` |
| **CR-7** ⚙ | **P0** | "Tests pass" claimed from a **self-authored `[SqlProc]` runner** read via `iris_query`, not from `%UnitTest`. `iris_test` never returned green (or wasn't run). | **Re-run `iris_test`** against the `%UnitTest.TestProduction` class; require real asserts to pass. Treat a `[SqlProc]`-returned `"PASS"` as unverified. | `tdd`, `unit-tests` |
| **CR-8** | P2 | HL7/REST message fields typed as non-`%String` (forced by `EnsLib.HL7`/REST string semantics), except genuinely typed synthetic fields. | Type HL7/REST-sourced message properties `As %String`. | `messages` |
| **CR-9** | P3 | Naming: classes not `<Pkg>.<Tipo>.<Nombre>` (`.BS`/`.BP`/`.BO`/`.DT`/`.RUL`/`.MSG`), or production **Item Name** not `<Tipo>.<Nombre>`; Category ≠ package root. | Apply the interop naming convention; Category = package root; fixed `Ens.Alerts`. | `interop` |
| **CR-10** ⚙ | P3 | A `.cls` with a **hardcoded absolute path** (`C:\…`, `/tmp/…`) instead of resolving relative to the install/source dir. | Parametrize via a Setting, or resolve with `##class(%Library.File).TempFilename`/`InstallDirectory`. | `production-lifecycle` |
| **CR-11** ⚙ | P2 | An **object property of a message resolved to a `%Persistent` class with no delete cascade** — no `Trigger [ Event = DELETE ]` and no `%OnDelete` on the referencing message, no `OnDelete = Cascade` on the link. `Ens.Util.Tasks.Purge` then deletes the message and orphans the child rows, silently, forever. | Make it `%SerialObject` in `<Pkg>.DAT.<Name>` if it's a value object owned by the message (the default); if it must be `%Persistent` (shared / queried on its own / recursive / large), add the delete cascade to the **referencing** message class. | `messages` |
| **CR-12** | **P1** | **A class exists in the IRIS namespace but not in `src/`** (or the reverse). The namespace is not version-controlled, not reviewable, and does not survive the instance — so work that lives only there is already lost, it just hasn't been noticed yet. Check both directions: a class only on disk was never compiled, or was deleted from the namespace, and the running production does not contain what the tree says it does. | `iris_doc(mode=get)` the namespace-only classes and write them to `src/` in the Atelier nested layout; compile or delete the disk-only ones so the two agree. Then fix the cause: hand-written classes go **`Write` → `iris_doc(mode=put)`** (a PreToolUse gate enforces it), wizard/generator output goes **generate → `iris_doc(mode=get)` → `Write`** (`soap-bo`, `messages`, `business-services`). | `production-lifecycle`, `soap-bo` |

## Output template

```
## Conformance review — <production/scope>
Tests (real iris_test): <PASS n/n | FAIL | NOT-RUN/ERROR ⇒ CR-7>

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
