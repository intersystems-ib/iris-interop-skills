---
name: tdd
description: TDD-first workflow for IRIS Interoperability — the non-negotiable order is spec, then tests, then implementation. Test classes ALWAYS extend `%UnitTest.TestProduction` (the Interop-specific superclass), never `%UnitTest.TestCase` directly. Covers what's testable (DTL, routing rules, BO methods, BPL via Testing Service) and what isn't (Business Services, tested externally). Triggers when the user proposes building or modifying any Interop component, or asks how to test/validate one. Triggers ES: TDD, test driven, pruebas, validar, probar, antes de implementar, spec first, primero el test. Triggers EN: TDD, test driven, unit test, %UnitTest, validate before code, testing service.
---

# IRIS Interoperability — TDD-first workflow

**This skill is non-negotiable.** Every Interop component (DTL, routing rule, custom BO method, BPL, message class with logic) is built **spec → test → red → implement → green → refactor**. If the user asks to write a transformation, a routing rule, or a BO method *and you don't see a test for it yet*, stop and write the test first. Push back politely if the user pushes you past this step.

## Baseline class — `%UnitTest.TestProduction` (NOT `%UnitTest.TestCase`)

**Test classes for Interop ALWAYS extend `%UnitTest.TestProduction`**, never plain `%UnitTest.TestCase`. The TestProduction superclass provides everything you'd otherwise reinvent:

- **`Run()` / `Debug()` class methods**: invoke a single test class directly — `do ##class(My.Tests.X).Run()`. No `/noload` gymnastics, no custom helper — but **no bypass of the manager either**: `Run()` is a four-line wrapper over `%UnitTest.Manager.DebugRunTestCase`, so **`^UnitTestRoot` must still point at a directory that exists on the IRIS server**. If it doesn't, the run *appears to complete* having discovered **zero test cases** — the `#5007` directory error is buried in the log, so the symptom looks like "no tests found", not like a path problem. See `unit-tests` for the workaround (point it at any existing server-side dir; the MCP's `iris_test` sets it for you).
- **`SendRequest(name, req, .resp, getReply, timeout)`**: wrapper over `EnsLib.Testing.Service.SendTestRequest`. One line instead of manual `$$$EnsRuntimeAppData` polling.
- **`GetEventLog(type, configName, baseId, .Log, .new)`**: pulls `Ens_Util.Log` entries into an array, incremental. Type can be `info`, `error`, `warning`, `infouser`, `trace`, `alert`, `assert`, `startstop`, `other`. Replaces hand-written SQL embedded.
- **`ChangeSetting(production, configName, setting, value)`** / **`GetSetting(...)`**: read/modify production item settings with validation.
- **`CreateCredentials(id, user, pwd)`**: provision `Ens.Config.Credentials` (overwrites if exists).
- **`CopyFile`, `CompareFiles`, `CleanUpDirectory`, `CreateMainDirTree`**: file plumbing for HL7-style tests.
- **Auto-properties**: `MainDir`, `HL7InputDir`, `HL7OutputDir`, `HL7WorkDir`, `HL7ArchiveDir`, `MachineName`, `InstanceName`, `DSNToSamples`, `DSNToUser`, `BaseLogId`, `LastLogId`.
- **`CheckEnvironment`**: refuses to compile if the namespace is not Interop/HealthShare-enabled (catches setup errors early).

### Required parameters — `PRODUCTION` is COMPILE-TIME mandatory

```objectscript
Class My.Tests.X Extends %UnitTest.TestProduction
{
Parameter PRODUCTION = "My.Production";   // compile fails without it — see below
}
```

The superclass enforces this with a method generator (`CheckParameterPRODUCTION`): a subclass
whose `PRODUCTION` is **missing or empty (`= ""`)** does not compile:

```
ERROR #5001: Parameter PRODUCTION must be specified
  > ERROR #5490: Error running generator for method 'CheckParameterPRODUCTION:...'
```

Two consequences that are easy to get wrong (verified on IRIS 2026.1):

- **A class that hit `#5001` never compiled, so to the test runner it does not exist** — a later
  `NO_TESTS_FOUND` is a correct answer about a missing class, not a discovery bug. Measured across
  an eval campaign, this single omission accounted for **every** zero-tests-run failure. Diagnosis
  path: the `NO_TESTS_FOUND` recovery recipe in
  [references/no-tests-found.md](references/no-tests-found.md).
- The value must be **non-empty**, but it need not name an *existing* production to compile —
  existence is asserted at runtime when the lifecycle starts the production. Name the real
  production anyway; a wrong name just moves the failure to run time.

### When the production is managed externally

The superclass's auto-lifecycle (start → run for MINRUN seconds → CheckResults → stop) is opt-in. When the production is already running externally (typical in dev sessions and shared CI), **override `TestControl()` to a no-op** and seed `BaseLogId` manually:

```objectscript
Method TestControl() As %Status
{
    Quit $$$OK
}

Method OnBeforeAllTests() As %Status
{
    // Capture log baseline because we skipped StartProduction
    &sql(SELECT NVL(MAX(ID),0) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = tMax + 1
    Set ..LastLogId = ..BaseLogId
    Quit $$$OK
}
```

Without this override, every `Run()` would restart the production — slow and disruptive.

## When to invoke this skill

- The user says "vamos a hacer un DTL / routing rule / BO / BPL".
- The user asks "cómo pruebo esto" / "cómo valido".
- A new Interop component is being proposed or modified.
- A bug fix on existing Interop logic — even more important: write the regression test first.

If the conversation is purely about wiring components into a production (production XML edits, settings), this skill doesn't apply — see `production-lifecycle`.

## The non-negotiable workflow

```
0. NAMESPACE      Resolve the target namespace from the task and verify it with `check_config`
                  (exists + interop-enabled) BEFORE writing the first test. Pass `namespace=` on
                  every MCP call from here on — never the tool default (`USER` is almost never
                  the interop namespace, and a green suite in the wrong namespace is a lost task).
1. SPEC           Write the spec in one or two sentences in the conversation.
2. TEST           Author Test* methods in a `%UnitTest.TestProduction` subclass, one per spec clause.
                  Each Test* method must have a /// comment describing what spec clause it verifies.
3. RED            Run each test class:
                      iris_test(pattern="MyApp.Tests.DT.Csv2Menus", namespace="<NS>")
                  ONE COMPILED CLASS PER CALL. `pattern` does NOT expand a package: "MyApp.Tests"
                  comes back NO_TESTS_FOUND with a did_you_mean list of the real names. Fully
                  qualified, case-correct, and compiled first. Confirm the failures.
4. IMPLEMENT      Write the minimum DTL/rule/BO method to satisfy the tests.
5. GREEN          Re-run iris_test for EVERY test class, all of them after the last compile.
                  All pass. Then print the %UnitTest.Portal.Home URL so the user can inspect
                  individual asserts.
6. REFACTOR       Simplify with green tests as the safety net. Re-run.
```

**Definition of done.** A component is delivered only when (a) its source is compiled in the target
namespace and the compiler result was read, and (b) its `%UnitTest.TestProduction` suite runs GREEN
via `iris_test`. Files on local disk are a scaffold, not a deliverable. Do not write a completion
summary unless both happened in this session; if either is missing, say plainly which one and stop.

Two rules about the numbers you quote for (b):

- **They come from the final pass, made after the last edit.** The final pass is ONE `iris_test`
  call **per test class**, all of them after the last recompile — a suite of N test classes is N
  calls, and adding those N results up is correct. What is forbidden is mixing **generations**: a
  green captured before you recompiled measured a class that no longer exists. Touch any source
  after the pass and you re-run **all** N, not just the class you touched.
- **Record the baseline first, then hold at zero NEW failures.** Where the namespace already has red
  tests, capture which ones fail *before* you start, verbatim. Green then means *no new failure*,
  not an empty list — and repairing an unrelated pre-existing failure is scope creep: surface it,
  don't quietly fix it.

Stepping over 1-2-3 ("just write the DTL first") is the most common anti-pattern. Refuse it:

> "I'll write the test first. It defines what 'done' means, and we'll know we're done when it passes."

### Loop budget — stop at the third red

The existing cap covers a test that **will not run** (`NO_TESTS_FOUND`, a compile error). It says
nothing about a test that runs and **stays red**, which is the longer loop: the model edits, re-runs,
edits, re-runs, and each iteration costs a compile plus a production restart.

**Read the failure before editing anything — and a red test has two shapes.** An **assert failure**
has an assertion and two compared values. An **abort** has neither: `<PROPERTY DOES NOT EXIST>`,
`<METHOD DOES NOT EXIST>` and friends kill the test before the assert runs, so there is nothing to
compare and the symbol named in the error *is* the finding. Looking for an assertion in an abort is
the commonest way to read a red wrongly.

`iris_test` returns `failure_message` and `failure_location` inline in `failed_tests` — read those
first. Call `iris_get_log(log_id=…)` only when they come back **empty**, which is today's abort case,
or when `failed_tests_truncated` is true. Do not expect a `.cls` line number from
`failure_location`: it is a raw `.INT` frame (`Method+offset^Pkg.Class.1`), nothing maps it back on
IRIS 2026.1, and it is worth reading only when it names a class of yours rather than library code.

Two edits that leave the failure mode unchanged mean the hypothesis is wrong — not that the fix was
too small — and the next edit will be the third guess in a row.

**At the third red that told you nothing new, stop and report the blocker**: the class, the assertion,
and what you have ruled out. That is more useful than a fourth variation.

The budget is deliberately **advisory, not a hard stop.** Measured over a workshop cohort: of the six
red streaks of three or more in 120 steps, **five went green with no intervention**. A gate that
blocked at three would have aborted five runs that were about to succeed. A `PostToolUse` hook says so
once, at the third consecutive red on the same target, and then keeps quiet.

One specific cause to rule out first, because it makes a correct fix look wrong: **a test still red
immediately after `iris_compile` may be running the old code.** A running host job does not reload a
recompiled class, and `UpdateProduction` does not restart jobs. Recycle that one item —
`iris_production(action=restart, item="<Item>")` — and re-run before editing again. See
`production-lifecycle` §"Hot-swap vs. restart".

### Step 3 is the load-bearing one — a test that never went red proves nothing

**If the first run of a test class is green, TDD did not happen.** The test was written against
code that already existed, so its assertions describe what the code *does* rather than what the
spec *requires* — and a bug in the code gets faithfully encoded as the expected result. No count
of assertions can detect this.

Measured over a workshop cohort: **67 of 103 test classes (65%) were green on their first ever
run**, while assertion density looked perfectly healthy — 5.3 `Test*` methods per class, 2.8
asserts per method. The tests were plentiful and shallow at the same time. "Write more
assertions" would not have fixed one of them.

Recovery when you find a green-on-first-run test is not to delete it: add one case that **fails
right now**, against the implementation as it stands. If you cannot write one, you are not yet
testing the spec.

## How much test is enough — the completeness checklist

A component is covered when, for its spec, the test class has:

| | What | Why it is not optional |
|---|---|---|
| 1 | **The happy path, asserting on values** — not merely on `$$$ISOK` | A green `%Status` says the code ran, not that it was right |
| 2 | **One rejection case per validation rule in the spec** | Each rule is a claim; an untested rule is a guess |
| 3 | **Boundary values** — empty, maximum length, zero, first and last valid item | `MAXLEN` truncation and off-by-one live exactly here, and both fail *silently* |
| 4 | **The malformed inputs the spec says to reject**, asserting the *rejection* | "Rejected cleanly" and "blew up" are different outcomes; only one is correct |
| 5 | **One case per branch you wrote** — each `if`, each `switch` case, each `<when>` of a rule | An unexercised branch is untested code under a passing suite |

The fixtures usually *are* the checklist in disguise. A CSV censo flow whose spec says *dates are
`DD/MM/YYYY`*, *allergies are `|`-separated and empty means SQL NULL*, *a quoted comma is one
field*, *`ñ` and accents are preserved* has **four** edge cases named in the spec itself — and a
date like `32/13/1990` sitting in the sample data is not a nuisance, it is test case 4 handed to
you.

Anti-pattern worth naming: a `Test*` method whose only assertion is `$$$AssertStatusOK(sc)`. That
asserts the component did not error. It does not assert it did the right thing, and it passes
against an implementation that silently drops every field.

Write assertions only with macros that exist — there is no `$$$AssertNotNull` or `$$$AssertGreater`,
and inventing one fails the compile with `MPP5610`. Mechanism: see `unit-tests` (section "Assertion
macros — the inventory").

### The checklist says what to write — one mutation says whether it worked

A class can satisfy all five rows and still assert nothing that matters, and no amount of *reading*
it tells you which. The detector is to break the implementation on purpose and watch the suite go
red — **once per component, after the whole suite is green**, never inside the per-behaviour loop:

1. Pick the logic carrying the most weight in what you just wrote.
2. Introduce ONE plausible bug in the source file — flip a comparison, delete an `<assign>` from
   the DTL, remove a `<when>` from the rule, return a constant from the BO method.
3. **Push it with `iris_doc(mode=put, compile=true)`.** Editing `src/` does nothing on its own:
   `iris_compile` takes a class NAME and recompiles what is already in the namespace, so a mutant
   that was never `put` leaves the original class standing and the suite stays green.
4. `iris_test` the same class. **It must fail** — and read *which* `Test*` method failed. A mutant
   killed by an unrelated test says nothing about the behaviour you meant to check.
5. Restore the source, `iris_doc(mode=put, compile=true)`, `iris_test`: green before you continue.

**How many is decided by whether you watched RED, not by taste.** A mutation and an observed RED are
the same proof at two different times — a test you saw fail before the code existed has already
proven it can fail. So: **one** mutant by default, spot-checking logic that arrived during
GREEN/REFACTOR with no test driving it. **Three to five** where the class was green on its first
run, because there the RED proof was never taken and this is the only detector left.

Budget it honestly: with `compile=true` a mutant is two MCP calls and the restore two more — four
for the default pass, twelve for the full one.

A survivor is a missing assertion — but **confirm the mutant actually landed before calling it
one.** `iris_doc(mode=get)` and look at the mutated line. A green suite over a `put` that did not
happen is a result for a mutant that never ran, and on screen it is indistinguishable from a
genuinely vacuous test — you would then add a test to kill a bug that was never there. Never skip
the restore either: an unrestored mutant sitting compiled in the namespace looks exactly like a
component that was never built.

## What's testable in IRIS Interop — decision table

| Component | Test approach |
|---|---|
| **Persistent message class** | TestProduction class with Test* methods that instantiate, set properties, `%Save()`, query back, assert on serialization. |
| **Data Transform (DTL)** | Test* methods that call `##class(My.DT.X).Transform(srcObj, .tgtObj)` directly and assert on `tgtObj`. No production lifecycle needed — but still extend TestProduction (free `Run()`/helpers). |
| **Routing rule (`Ens.Rule.Definition`)** | Two valid styles: **(a) Integration** — drive the actual Router config item via `..SendRequest("Router.Censo", msg, .resp, 0)` and assert via `..GetEventLog(...)` for downstream config-name dispatch. **(b) Unit** — construct `EnsLib.MsgRouter.RoutingEngine.Context`, call `Ens.Rule.Definition.EvaluateRules(...)`, assert on returned actions. (a) catches more real bugs (DTL chain, BO availability), (b) is faster but more brittle to API drift. |
| **Custom BO method** | Drive the BO **with its real adapter** against a real test endpoint (test DB schema, test file dir, test TCP listener). Two modes: **(a)** `..SendRequest("BO.Cocina", req, .resp, 1)` against the running production, assert via `..GetEventLog` or direct SQL on the side-effect store. **(b)** Drive the BO's **adapter** directly — the BO itself does not instantiate (see the pitfall below); the adapter does, and `##class(EnsLib.SQL.OutboundAdapter).%New()` is the supported way to exercise it headlessly. Set the same settings the production item carries, call `OnInit()`, invoke `ExecuteQuery`/`ExecuteUpdate`, then `Disconnect()`. Valid **without a running production only for a BO with no adapter, or with a File/TCP adapter**. With a `jdbc:` DSN it is not: the production must be **started** and must contain an `EnsLib.JavaGateway.Service` item whose name matches `JGService` character for character — `JGService` is required for all JDBC data sources and the adapter reuses that item's settings (ESQL §3.1). Otherwise `<INVALID OREF> 192 initAdapterJG+2^EnsLib.JavaGateway.Common.1`, a frame naming neither your BO nor the adapter: read it as "I cannot find the JGService item", never as "the gateway is broken". Recipe: `business-operations` §"Headless verification". Never stub the adapter — see pitfall below. |
| **BO `OnInit`/settings validation** | Test* method invokes `..OnInit()` on a manually-wired **adapter** instance whose settings match the production item's XML. A BO *instance* is not available — `%New()` on a BO subclass returns `""`. For a `jdbc:` DSN, the `JGService` precondition in the row above applies here too. |
| **BPL Business Process** | `..SendRequest("BP.MyProcess", req, .resp, 1)` against the running production (with `TestingEnabled="true"`). Inspect side-effects via `..GetEventLog` or `Ens.MessageHeader`. |
| **End-to-end inside production (BS→BP→BO chain)** | Same: `..SendRequest` to the entry point (BP, BO, or Router), assert on side-effects. |
| **Custom HL7 schema** | Two tests, not one. **(a)** the category registered — `EnsLib.HL7.Schema.ResolveSegNameToStructure` / `ResolveSchemaTypeToDocType`. **(b)** the structure is right — drive a real message through an `EnsLib.HL7.MsgRouter.RoutingEngine` whose **`Validation="dm"`** and assert it routes, plus a malformed one that must land on the `BadMessageHandler`. Parsing alone (`ImportFromString`+`DocTypeSet`+`GetValueAt`) reads fields and **never checks segment order**, so a wrong `MessageStructure` passes. See `hl7-schemas`. |
| **RecordMap** | Two levels. **(a)** the `.Record` was generated — assert the class exists (a plain compile does not generate it). **(b)** the parser works — push a line through `GetObject` on the **RecordMap class** (not `.Record`), asserting an accented field and a quoted-comma field. Give the test stream the **same `CharEncoding` as the map**, or pass a filename and let `GetObject` open it; a default `%IO.StringStream` is `Native` and silently corrupts accents with a `$$$OK` status. See `business-services`. |
| **Business Service (entry point)** | **Not testable from inside IRIS.** Test from *outside*: copy a file into the BS's `FilePath`, send TCP to its port, POST to its REST URL. Use `pytest`, `curl`, or equivalent external clients. The BS adapter is the contract; it must be exercised via its actual transport. |
| **Custom inbound adapter** | Same as BS — exercise from outside. |

> **Before you name a test class or a Test\* method:** identifiers are letters and digits only —
> `_` is the concatenation operator, and `Method TestADT_A01ContainsZdi()` aborts the parser with
> `#5559 … non-matching {} or () characters`. HL7 work is where this bites, because the message
> type is `ADT_A01`. See `interop` §"Invariants when writing ANY ObjectScript class".

> **A compiled, mutation-checked worked example** lives at
> `assets/tdd-testproduction-dtl.cls`. It tests the DTL that ships beside it, and its
> header records the mutation result: breaking the transform leaves `$$$AssertStatusOK` and
> `$$$AssertTrue($IsObject(...))` **both passing** while only the assertion on a written field
> fails. The vacuous green, demonstrated rather than asserted.

## Where to store the tests

`MyApp.Tests.*` package, compiled in the namespace alongside `MyApp.*`. Source-controlled in Git (VS Code ObjectScript export or `$system.OBJ.Export`). With `%UnitTest.TestProduction.Run()` you don't need `/noload` gymnastics — invoke directly by class name. You **do** still need `^UnitTestRoot` → an existing server-side directory (silent zero-test run otherwise — see the `Run()` bullet above and `unit-tests`).

## Canonical skeletons

Copy the skeleton for what you are testing — DTL, HL7 fixtures, routing rule, BO method, or BPL
via the Testing Service, plus how to enable the Testing Service:
see [references/skeletons.md](references/skeletons.md).

## Running the tests

Primary: directly on the class via the inherited `Run()`.

```objectscript
do ##class(MyApp.Tests.DT.Censo2Menus).Run()
do ##class(MyApp.Tests.Rule.RoutingCenso).Run()
do ##class(MyApp.Tests.BO.Menus2Cocina).Run()
```

For runner mechanics — the `^UnitTestRoot` directory requirement, `DebugRunTestCase` qualifier syntax (boolean flags only), the MCP-friendly SqlProc wrapper that returns `passed=N failed=M`, how to read `^UnitTest.Result`, and the `Try / Catch + Quit` pitfall — see **`unit-tests`**. That skill is the framework toolbox; this one is the workflow.

### `NO_TESTS_FOUND` — do NOT re-run blindly

`iris_test` reporting no tests has a specific recovery order, and re-running first wastes the
cheapest signal you get: see [references/no-tests-found.md](references/no-tests-found.md).

### After running — show the portal URL (ALWAYS)

After every test run, **print the `%UnitTest.Portal.Home` URL** as the last line of output so the user can click through to drill into individual assert details. The portal provides navigable drill-down that is NOT visible from the terminal output alone.

```objectscript
// After Run(), always print this:
Write !,"Test results: http://localhost:80/csp/sys/%25UnitTest.Portal.Home.cls?$NAMESPACE="_$NAMESPACE,!
```

Adjust the host/port/prefix per the instance. The `%25` is `%` URL-encoded. URL pattern and navigation chain details are in `unit-tests`.

## Error-handling idiom inside test helpers

When test setup / teardown / fixture-builder code drops to ObjectScript, use the standard try/catch idiom — same pattern used in production code so failures surface uniformly. Pattern (and the `Quit` inside `Try` pitfall) is documented once in `unit-tests`.

## Timeout precedence when testing flows end-to-end

When a test calls a BP that calls a BO, the **timeouts must be ordered correctly** for diagnostics to come back. If the BP times out before its downstream BO, the test sees a generic timeout with no chain. If the BO times out first, the BP gets the failure with full diagnostic detail.

When writing the test:

- Set the BO `Response Timeout` to the realistic upper bound of the work it does.
- Set the calling BP timeout strictly higher than the sum of downstream BO timeouts plus margin.
- Set the test's `..SendRequest(..., timeout)` higher than the BP timeout.

If a test fails with "timeout" but the visual trace shows the BO never failed, the BP timed out first — increase the BP timeout, not the test's.

See `business-operations` and `bpl` for the runtime side of the same rule.

## Pitfalls specific to Interop TDD

- **Extending `%UnitTest.TestCase` instead of `%UnitTest.TestProduction`** — you lose everything the superclass provides and reinvent it by hand. Nor is `%UnitTest.TestCase` an escape hatch for a compile error: `Extends %UnitTest.TestProduction` and `Parameter PRODUCTION` are fixed points — fix the error, never remove the parameter or change the superclass to silence it. See §"Baseline class" above.
- **Omitting `Parameter PRODUCTION` (or leaving it `= ""`)** — `#5001` at compile time; the class never exists to any runner. See §"Required parameters" above.
- **`%New()`-ing a Business Service or Operation to test it directly — it does not instantiate.** The cheap move from conventional software is to new the host up and call `OnMessage()` with a request. It cannot work: `Ens.BusinessOperation` and `Ens.BusinessService` do not declare `%New`, and a concrete subclass returns `""` rather than erroring — so the failure arrives a line later, as `<INVALID OREF>` that never mentions the host. Measured on IRIS 2026.1:

  | `##class(…).%New()` | result |
  |---|---|
  | `Ens.BusinessOperation`, `Ens.BusinessService` | `<METHOD DOES NOT EXIST>` |
  | `Ens.BusinessProcess` | returns `""` — `$IsObject` = 0, no error |
  | `EnsLib.File.OutboundAdapter` and other adapters | a real object, `$IsObject` = 1 |

  **The adapter instantiating is the trap.** `ad=1` printed beside `bo=0` reads as "objects work here, so my class is broken", and sends you to re-inspect the one thing that was fine. A BS/BO is exercised only by the production framework: run it through `%UnitTest.TestProduction` + `iris_test`, or send it a message with the `deploy-smoke-test` agent. If you want to unit-test logic in isolation, put that logic in a plain `%RegisteredObject` helper the host delegates to, and test the helper.
  **The adapter instantiating is also not a licence to use it anywhere.** `##class(EnsLib.SQL.OutboundAdapter).%New()` is fine, and is how headless verification is written — but with a `jdbc:` DSN, `OnInit()` only initialises when the production is **running** and contains an `EnsLib.JavaGateway.Service` item named exactly like the `JGService` you set (ESQL §3.1). Otherwise: `<INVALID OREF> 192 initAdapterJG+2^EnsLib.JavaGateway.Common.1` — a frame that names neither the adapter nor the BO, so it reads as a broken gateway and sends you rebuilding one that was never broken. Filling `..BusinessHost` by hand does not fix it: `##class(EnsLib.Testing.Service).%New()` is a Business Service and returns `""` (see above).
- **Stubbing the adapter in BO tests.** In conventional software you'd unit-test the BO method with a mocked adapter — in IRIS Interop that's an anti-pattern. The adapter boundary is exactly where the defects you care about live (auth, classpath, type marshalling, encoding, timeouts). Stubs make the test green while the real thing breaks. Use a real adapter against a real test endpoint.
- **Forgetting to override `TestControl()`** — TestProduction will start/stop your production every time you `Run()`. Override to no-op when the production is managed externally.
- **Quoting `TestControl` as evidence that the rest of the class is sound.** The no-op override has no assertion in it — it passes whenever the class compiled and the runner reached it. That makes it a **liveness** signal and never a **correctness** one. Green `TestControl` beside failures tells you the failures are real verdicts rather than a harness fault, and nothing else: a class whose every substantive method is broken, mis-specified, or asserting on the wrong thing still shows it green. Anything shaped `Quit $$$OK` is in this category whatever it is named. Cite the methods that actually assert something.
- **`ErrBusinessDispatchNameNotRegistered` on the first `..SendRequest`** → the production is
  missing `TestingEnabled="true"`, not a config item. The error names `EnsLib.Testing.Service` (and,
  once you add that, `EnsLib.Testing.Process`), which points at the wrong fix. See "Enabling the Testing Service" in
  [references/skeletons.md](references/skeletons.md).
- **A `%UnitTest` that builds a stream in the wrong encoding.** A RecordMap declares its
  `char_encoding`, and `GetObject` applies it — so a test stream whose `CharEncoding` differs
  (the `%IO.StringStream` default is `Native`) hands the parser bytes it decodes as something
  else. Accents come back as `?`, the status is `$$$OK`, and the RecordMap looks broken when the
  test is. Match the encoding, or pass a filename. Reaching for `$ZCVT` instead papers over it
  and double-encodes on a real file — see `business-services`.
- **Forgetting to seed `..BaseLogId`** — `GetEventLog` returns nothing if `BaseLogId` is empty. Seed it in `OnBeforeAllTests` from `MAX(ID) FROM Ens_Util.Log`.
- **Asserting on internal state** instead of public contract. Assert on what the next consumer (DTL, BO, downstream system) actually sees.
- **No fixture strategy** — paste-in literals everywhere. Centralize sample inputs in a fixtures class (`MyApp.Tests.Fixtures.Censo`).
- **File fixtures on a path only the agent can see.** A test that reads sample data from a file (`CopyFile`, an HL7 drop, a CSV) runs **inside IRIS** — and when IRIS is in a container, your working directory does not exist there. The red assert says "file not found" against a path that plainly exists on *your* side, and the fix is never to retry the path. Put server-read fixtures on a **server-visible path**: the container's mounted data directory, or ferry the content in via the MCP (`iris_execute` writing a temp file server-side, or inline the fixture as a string in the test class — the most portable option).
- **Testing a custom HL7 schema by parsing it.** `ImportFromString` + `DocTypeSet` + `GetValueAt`
  returns field values without validating the message structure, so a schema whose `MessageStructure`
  has the segments in the wrong order passes every assertion and fails later in the routing engine
  with `<EnsEDI>ErrMapSegUnrecog`. Worse, routing it through an HL7 router proves nothing either
  *unless that router's `Validation` setting is non-empty* — it defaults to empty, meaning "route
  everything unchecked". See `hl7-schemas` §"Verification part 2".
- **Reading "the message reached the target" as "the routing is correct".** An end-to-end assert
  that a message arrived proves transport, not conformance. A **generic**
  `EnsLib.MsgRouter.RoutingEngine` carries `EnsLib.HL7.Message` perfectly well, so a test that drops
  an HL7 file and asserts it reached the target passes while the router has silently lost HL7 schema
  validation and the `{MSH:9.1}` paths (CR-6). No test written this way can see it — the check is
  "is the engine right for what now flows through this router", and it must be re-made whenever an
  input is added to an existing router. See `bpl`.
- **Trusting a green suite to tell you the tree is current.** Tests run against the **namespace**,
  so `iris_doc(put, content=…)` and `iris_production_item` keep them green while the `.cls` on
  disk falls behind — there is no signal anywhere in the loop. Write the file alongside every
  inline put, and `iris_doc(mode=get)` the production class after every item change. See
  `production-lifecycle`.
- **`TestingEnabled="true"` left in a deployed production** — treat it like a debug flag. See "Enabling the Testing Service" in [references/skeletons.md](references/skeletons.md) (security note).
- **Asserting only on `$$$LOGINFO` presence in the event log** ("INSERT OK paciente_id=...") instead of on the row's actual contents → the log proves the BO method ran, not that the destination has the right values. Add at least one assert that reads the side-effect back: a `SELECT` via psql/`Adapter` in `OnAfterAllTests`, or a small **verifier BO** callable via `..SendRequest(verifier, query, .resp, 1)` that returns the row for property-by-property asserts. The log is necessary but insufficient.
- **A test still red immediately after `iris_compile` may be measuring the OLD code.** A running host
  job does not reload a class because you recompiled it — `UpdateProduction` does not restart jobs
  either. Recycle that one item with `iris_production(action=restart, item="<Item>")` before concluding
  the implementation is wrong; the platform call underneath is `TempStopConfigItem`, and a wrong item
  name says so (`<Ens>ErrConfigItemNotFound: Item X not found in Production Y`). See
  `production-lifecycle` §"Hot-swap vs. restart".
- **Test methods without a description comment** — When a test fails, the first thing the user sees is the method name in the portal. A `///` comment on the method clarifies *what spec clause* the test verifies, not just *what code it exercises*. One line is enough: `/// Verifies that empty Alergias is marshalled to SQL NULL`.

## Test data isolation — spectrum, not all-or-nothing

For shared destinations (one PostgreSQL `Cocina.Menus` table used by both prod and tests), pick the **lightest** isolation that meets your blast-radius budget:

| Approach | When |
|---|---|
| **Per-run key suffix** (`TST-<runid>-*` on every value that lands on a unique column) + cleanup in `OnAfterAllTests` | Workshop, dev, single-developer sessions. Lowest infra. **A fixed literal is not enough:** a second run of the same suite collides with the first run's rows even when the first exited cleanly — `ERROR #5808: Key not unique` in IRIS, `duplicate key value violates unique constraint` in PostgreSQL — and `OnAfterAllTests` is by definition the callback a mid-run crash skips. Fixed keys are right only for an UPSERT/MERGE destination, or when the duplicate path **is** the subject under test. |
| **Separate schema** in the same DB (`MenusTest`) with its own credentials | CI on shared infra, multiple devs running tests concurrently. |
| **Separate DB / credentials / BO item** (`CocinaTest`, `BO.CocinaTest`) | Production-grade CI with isolation requirements (e.g. test data must never bleed into prod backups). |

Default to **a per-run suffix inside the shared destination** unless you have a concrete reason to escalate. Auditing a workshop production for "weak isolation" because it isolates by key rather than by database is misreading the spectrum. The suffix does not replace cleanup — it makes the suite **re-runnable when cleanup did not run**, and it lets cleanup target exactly this run's rows (`LIKE 'TST-'_..RunId_'-%'`).

One run id, one place, and every key built from it — the base class that allocates a `RunId` in
`OnBeforeAllTests` and a `Key()` helper every insert and assert goes through. See the per-run key base
class in [references/skeletons.md](references/skeletons.md), which the gate compiles rather than
quoting here.

## See also

- `messages` — design the contract before the tests
- `transformations` — DTL implementation reference (after the test exists)
- `business-operations` — keep BO methods thin so they're testable
- `bpl` — BPL Business Processes (test via Testing Service)
- `message-search-debug` — for inspecting Visual Trace after a Testing Service dispatch
- `unit-tests` — runner mechanics (`Run()`, `DebugRunTestCase`, SqlProc wrapper, qualifier syntax), `^UnitTest.Result` global, the `%UnitTest.Portal` URL, where to store tests so they survive. **This skill is the workflow; that one is the toolbox.**

## TL;DR

```
Test classes:   extend %UnitTest.TestProduction (never plain TestCase).
Parameter:      PRODUCTION = "MyApp.Production"   — COMPILE-TIME mandatory; missing/empty = #5001, class never exists
Lifecycle:      override TestControl() to no-op if production runs externally; seed ..BaseLogId in OnBeforeAllTests.
Dispatch:       ..SendRequest(configName, req, .resp, getReply, timeout)
Inspect:        ..GetEventLog(type, configName, baseId, .Log, .new)
Run:            iris_test(pattern="MyApp.Tests.DT.Csv2Menus", namespace="<NS>")  — ONE class per call
                do ##class(MyApp.Tests.X).Run()  — the same thing the tool runs internally, but via
                iris_execute you lose the parsed result envelope and the log_id iris_get_log needs;
                still needs ^UnitTestRoot → an existing server dir (unit-tests)

Spec → Test → Red → Implement → Green → Refactor.
Done = compiled in the target namespace + GREEN via iris_test; local files are a scaffold.
BS: from outside IRIS only (file drop, TCP, curl).
TestingEnabled="true" on production for dev; strip before deploy.
```
