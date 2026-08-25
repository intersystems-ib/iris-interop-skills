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
Parameter PRODUCTION = "My.Production";   ; compile fails without it — see below
}
```

The superclass enforces this with a method generator (`CheckParameterPRODUCTION`): a subclass
whose `PRODUCTION` is **missing or empty (`= ""`)** does not compile:

```
ERROR #5001: Parameter PRODUCTION must be specified
  > ERROR #5490: Error running generator for method 'CheckParameterPRODUCTION:...'
```

Two consequences that are easy to get wrong (verified on IRIS 2026.1):

- **A class that hit `#5001` never compiled, so to the test runner it does not exist.** If you
  miss the compile error, the *next* thing you see is `iris_test` answering `NO_TESTS_FOUND` —
  which is a **correct answer about a class that was never created**, not a discovery or naming
  problem. `%Dictionary.CompiledClass` can still list the class name, which is exactly why this
  masquerades as a discovery bug. Never diagnose `NO_TESTS_FOUND` without re-reading the last
  compile result first.
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
3. RED            Run the runner via `do ##class(My.Tests.X).Run()`. Confirm failures.
4. IMPLEMENT      Write the minimum DTL/rule/BO method to satisfy the tests.
5. GREEN          Run the runner. All tests pass.
                  After GREEN, print the %UnitTest.Portal.Home URL so the user can inspect individual asserts.
6. REFACTOR       Simplify with green tests as the safety net. Re-run.
```

Stepping over 1-2-3 ("just write the DTL first") is the most common anti-pattern. Refuse it:

> "I'll write the test first. It defines what 'done' means, and we'll know we're done when it passes."

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

## What's testable in IRIS Interop — decision table

| Component | Test approach |
|---|---|
| **Persistent message class** | TestProduction class with Test* methods that instantiate, set properties, `%Save()`, query back, assert on serialization. |
| **Data Transform (DTL)** | Test* methods that call `##class(My.DT.X).Transform(srcObj, .tgtObj)` directly and assert on `tgtObj`. No production lifecycle needed — but still extend TestProduction (free `Run()`/helpers). |
| **Routing rule (`Ens.Rule.Definition`)** | Two valid styles: **(a) Integration** — drive the actual Router config item via `..SendRequest("Router.Censo", msg, .resp, 0)` and assert via `..GetEventLog(...)` for downstream config-name dispatch. **(b) Unit** — construct `EnsLib.MsgRouter.RoutingEngine.Context`, call `Ens.Rule.Definition.EvaluateRules(...)`, assert on returned actions. (a) catches more real bugs (DTL chain, BO availability), (b) is faster but more brittle to API drift. |
| **Custom BO method** | Drive the BO **with its real adapter** against a real test endpoint (test DB schema, test file dir, test TCP listener). Two modes: **(a)** `..SendRequest("BO.Cocina", req, .resp, 1)` against the running production, assert via `..GetEventLog` or direct SQL on the side-effect store. **(b)** Instantiate the BO with explicit settings + call its real `OnInit()` + invoke the method directly (more setup, but works without a running production). Never stub the adapter — see pitfall below. |
| **BO `OnInit`/settings validation** | Test* method invokes `..OnInit()` on a manually-wired BO instance with adapter settings matching production XML. |
| **BPL Business Process** | `..SendRequest("BP.MyProcess", req, .resp, 1)` against the running production (with `TestingEnabled="true"`). Inspect side-effects via `..GetEventLog` or `Ens.MessageHeader`. |
| **End-to-end inside production (BS→BP→BO chain)** | Same: `..SendRequest` to the entry point (BP, BO, or Router), assert on side-effects. |
| **Business Service (entry point)** | **Not testable from inside IRIS.** Test from *outside*: copy a file into the BS's `FilePath`, send TCP to its port, POST to its REST URL. Use `pytest`, `curl`, or equivalent external clients. The BS adapter is the contract; it must be exercised via its actual transport. |
| **Custom inbound adapter** | Same as BS — exercise from outside. |

## Where to store the tests

`MyApp.Tests.*` package, compiled in the namespace alongside `MyApp.*`. Source-controlled in Git (VS Code ObjectScript export or `$system.OBJ.Export`). With `%UnitTest.TestProduction.Run()` you don't need `/noload` gymnastics — invoke directly by class name. You **do** still need `^UnitTestRoot` pointing at an existing server-side directory: the manager's "Finding directories" step runs regardless, and an invalid path yields a **silent zero-test run** (see `unit-tests`). The MCP's `iris_test` sets `^UnitTestRoot` itself; the trap bites direct `Run()` / `DebugRunTestCase` invocations.

## Canonical skeletons (USE THESE AS TEMPLATES)

### DTL test

```objectscript
Class MyApp.Tests.DT.Censo2Menus Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }   ; production managed externally

/// Verifies that Apellido1 + Apellido2 are concatenated with a single space separator
Method TestApellidosConcat()
{
    Set src = ##class(MyApp.RecordMap.Censo.Record).%New()
    Set src.Apellido1 = "Pérez"
    Set src.Apellido2 = "López"
    Set src.Nombre = "Carlos"  Set src.Dieta = "Basal"  Set src.FechaNacimiento = "01/01/1970"
    Set tSC = ##class(MyApp.DT.Censo2Menus).Transform(src, .tgt)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tgt.Apellidos, "Pérez López", "Apellidos with single space")
}

/// Verifies that an invalid date (32/13/1990) is rejected with an error status
Method TestFechaInvalidaSeAisla()
{
    Set src = ##class(MyApp.RecordMap.Censo.Record).%New()
    Set src.FechaNacimiento = "32/13/1990"
    Set src.Nombre = "X"  Set src.Apellido1 = "Y"  Set src.Dieta = "Basal"
    Set tSC = ##class(MyApp.DT.Censo2Menus).Transform(src, .tgt)
    Do $$$AssertStatusNotOK(tSC, "Bad date must error out")
}

}
```

Run: `do ##class(MyApp.Tests.DT.Censo2Menus).Run()`.

### Routing rule test (integration style — preferred)

```objectscript
Class MyApp.Tests.Rule.RoutingCenso Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }

Method OnBeforeAllTests() As %Status
{
    &sql(SELECT NVL(MAX(ID),0) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = tMax + 1, ..LastLogId = ..BaseLogId
    Quit $$$OK
}

/// Verifies that the Router.Censo dispatches a census record to BO.Cocina
Method TestRouterDispatchaACocina()
{
    Set rec = ##class(MyApp.RecordMap.Censo.Record).%New()
    Set rec.ID = "TEST-RULE-1"  ; prefix for cleanup
    ; ... fill the rest of the record fields ...
    Do $$$AssertStatusOK(rec.%Save())

    Set baseId = ..LastLogId
    Do $$$AssertStatusOK(..SendRequest("Router.Censo", rec, .resp, 0))
    Hang 2  ; async settle

    Kill Log
    Do ..GetEventLog("info", "BO.Cocina", baseId, .Log, .new)
    Set tFound = 0
    For i=1:1:$G(Log) { If Log(i,"Text") [ "TEST-RULE-1" Set tFound = 1 Quit }
    Do $$$AssertTrue(tFound, "TEST-RULE-1 dispatched to BO.Cocina")
}

}
```

### BO method test (integration with real adapter)

```objectscript
Class MyApp.Tests.BO.Menus2Cocina Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }

Method OnBeforeAllTests() As %Status
{
    &sql(SELECT NVL(MAX(ID),0) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = tMax + 1, ..LastLogId = ..BaseLogId
    Quit $$$OK
}

Method ExpectInsertLogged(pBaseId, pPacienteId, pDesc)
{
    Kill Log
    Do ..GetEventLog("info", "BO.Cocina", pBaseId, .Log, .new)
    Set tFound = 0
    For i=1:1:$G(Log) {
        If Log(i,"Text") [ ("INSERT OK paciente_id="_pPacienteId) Set tFound = 1 Quit
    }
    Do $$$AssertTrue(tFound, pDesc)
}

/// Verifies that empty Alergias ("") is marshalled correctly to SQL NULL by the JDBC adapter
Method TestEmptyAlergiasToNull()
{
    ; Catches marshalling bugs that no stub would: does the real JDBC driver
    ; translate "" to SQL NULL, or to empty string?
    Set req = ##class(MyApp.Msg.MenuRequest).%New()
    Set req.PacienteId = "TEST-EMPTY"
    Set req.Nombre = "X"  Set req.Apellidos = "Y"  Set req.TipoDieta = "Basal"
    Set req.Alergias = ""
    Do $$$AssertStatusOK(req.%Save())

    Set baseId = ..LastLogId
    Do $$$AssertStatusOK(..SendRequest("BO.Cocina", req, .resp, 0))
    Hang 2

    Do ..ExpectInsertLogged(baseId, "TEST-EMPTY", "INSERT OK logged for TEST-EMPTY")
}

}
```

### BPL via Testing Service

```objectscript
Class MyApp.Tests.BPL.MyProcess Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }

Method OnBeforeAllTests() As %Status
{
    &sql(SELECT NVL(MAX(ID),0) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = tMax + 1, ..LastLogId = ..BaseLogId
    Quit $$$OK
}

/// Verifies that BP.MyProcess receives a request and returns a response object
Method TestProcessReceivesAndForwards()
{
    Set req = ##class(MyApp.Msg.SomeRequest).%New()
    Set req.Field = "value"
    Do $$$AssertStatusOK(..SendRequest("BP.MyProcess", req, .resp, 1, 30))
    ; SendRequest with GetReply=1 waits for the response. Resp is now populated.
    Do $$$AssertEquals($IsObject(resp), 1, "Got a response back")
}

}
```

## Enabling the Testing Service on a production

Add `TestingEnabled="true"` to the `<Production>` opening tag in the `XData ProductionDefinition`:

```xml
XData ProductionDefinition
{
<Production Name="MyApp.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  ...
</Production>
}
```

Effect:
- The IRIS Management Portal exposes a "Testing Service" page (under Interoperability) for manual dispatch of test messages to any BP or BO. Requires `%Ens_TestingService:USE` resource.
- Programmatic: `..SendRequest(...)` and `EnsLib.Testing.Service.SendTestRequest(...)` both work when the production is running with this flag.
- Internally: a hidden `EnsLib.Testing.Process` is registered and dispatches the wrapped `EnsLib.Testing.Request` to the target via `SendRequestAsync`.

**Important — security**: `TestingEnabled="true"` is a development setting. **Never deploy a production to prod with this flag on** — anyone with the Testing resource can fabricate messages into running BPs/BOs. Strip it (or guard via a deployment-time setting) before promoting.

## Running the tests

Primary: directly on the class via the inherited `Run()`.

```objectscript
do ##class(MyApp.Tests.DT.Censo2Menus).Run()
do ##class(MyApp.Tests.Rule.RoutingCenso).Run()
do ##class(MyApp.Tests.BO.Menus2Cocina).Run()
```

For runner mechanics — the `^UnitTestRoot` directory requirement, `DebugRunTestCase` qualifier syntax (boolean flags only), the MCP-friendly SqlProc wrapper that returns `passed=N failed=M`, how to read `^UnitTest.Result`, and the `Try / Catch + Quit` pitfall — see **`unit-tests`**. That skill is the framework toolbox; this one is the workflow.

### `NO_TESTS_FOUND` recovery recipe — do NOT re-run blindly

`iris_test` returning `NO_TESTS_FOUND` almost never means "no tests" — it means the runner could not find
a compiled test class under the name you passed. Re-running the identical call will return the identical
error. Work the cause instead, in this exact order:

1. **Re-read the last compile result, then compile the test class and confirm it is CLEAN.** The class
   must be compiled before `iris_test` can see it. Push it with `iris_doc(mode=put, compile=true)` (or
   `iris_compile`) and **read the compiler output — do not assume**: a test class that failed to compile
   does not exist to the runner, even though `%Dictionary.CompiledClass` may still list its name. The
   most common compile failure on a `TestProduction` subclass is
   `ERROR #5001: Parameter PRODUCTION must be specified` — see "Required parameters" above.
2. **Run `iris_test` with the EXACT compiled class name** — fully qualified, case-correct
   (`MyApp.Tests.DT.Censo2Menus`, not `Censo2Menus`, not `myapp.tests...`). An unqualified or
   mis-cased name is the most common cause.
3. **Act on the tool's `hint` / `candidates`.** `iris_test` returns these on a miss — they list the
   names it *can* see. Pick the matching candidate and re-run with that exact name; do not guess a third
   variant or fall back to running `Run()` from the terminal.
4. **Verify the superclass.** The class must extend `%UnitTest.TestProduction` (or `%UnitTest.TestCase`)
   and have at least one `Test*` method. A class that extends the wrong base, or whose methods are not
   prefixed `Test`, compiles but exposes zero tests.
5. Only after 1–4 — if it still reports `NO_TESTS_FOUND` — STOP and report the blocker (see the agent's
   iteration cap). Do not loop, and do not switch routes to "work around" it — not `$SYSTEM.OBJ.Load` /
   the terminal, not `Run()` via `iris_execute`, not `RunTest(..., "/noload")`, not querying
   `^UnitTest.Result` by hand hoping to find a result. Every one of those gives the same (correct)
   answer about a class that never compiled; the only fix is upstream, at step 1.

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

- **Extending `%UnitTest.TestCase` instead of `%UnitTest.TestProduction`** — you lose `Run()`, `SendRequest`, `GetEventLog`, etc., and end up reinventing them with `$$$EnsRuntimeAppData` polling and embedded SQL. Don't.
- **Omitting `Parameter PRODUCTION` (or leaving it `= ""`)** — the class fails to compile with `#5001`, and everything downstream (`iris_test` → `NO_TESTS_FOUND`, empty `^UnitTest.Result`) is a correct report about a class that doesn't exist. Measured across an eval campaign, this single omission accounted for **every** zero-tests-run failure while the class *looked* complete. Non-empty is the compile-time requirement; naming the real production is the runtime one.
- **Stubbing the adapter in BO tests.** In conventional software you'd unit-test the BO method with a mocked adapter — in IRIS Interop that's an anti-pattern. The adapter boundary is exactly where the defects you care about live (auth, classpath, type marshalling, encoding, timeouts). Stubs make the test green while the real thing breaks. Use a real adapter against a real test endpoint.
- **Forgetting to override `TestControl()`** — TestProduction will start/stop your production every time you `Run()`. Override to no-op when the production is managed externally.
- **Forgetting to seed `..BaseLogId`** — `GetEventLog` returns nothing if `BaseLogId` is empty. Seed it in `OnBeforeAllTests` from `MAX(ID) FROM Ens_Util.Log`.
- **Asserting on internal state** instead of public contract. Assert on what the next consumer (DTL, BO, downstream system) actually sees.
- **No fixture strategy** — paste-in literals everywhere. Centralize sample inputs in a fixtures class (`MyApp.Tests.Fixtures.Censo`).
- **File fixtures on a path only the agent can see.** A test that reads sample data from a file (`CopyFile`, an HL7 drop, a CSV) runs **inside IRIS** — and when IRIS is in a container, your working directory does not exist there. The red assert says "file not found" against a path that plainly exists on *your* side, and the fix is never to retry the path. Put server-read fixtures on a **server-visible path**: the container's mounted data directory, or ferry the content in via the MCP (`iris_execute` writing a temp file server-side, or inline the fixture as a string in the test class — the most portable option).
- **`TestingEnabled="true"` left in a deployed production** — security/integrity risk. Treat it like a debug flag. (Note: `TestingEnabled="true"` is the **correct default** in dev/workshop productions — only flagged here for environments with deploy-to-prod automation.)
- **Asserting only on `$$$LOGINFO` presence in the event log** ("INSERT OK paciente_id=...") instead of on the row's actual contents → the log proves the BO method ran, not that the destination has the right values. Add at least one assert that reads the side-effect back: a `SELECT` via psql/`Adapter` in `OnAfterAllTests`, or a small **verifier BO** callable via `..SendRequest(verifier, query, .resp, 1)` that returns the row for property-by-property asserts. The log is necessary but insufficient.
- **Test methods without a description comment** — When a test fails, the first thing the user sees is the method name in the portal. A `///` comment on the method clarifies *what spec clause* the test verifies, not just *what code it exercises*. One line is enough: `/// Verifies that empty Alergias is marshalled to SQL NULL`.

## Test data isolation — spectrum, not all-or-nothing

For shared destinations (one PostgreSQL `Cocina.Menus` table used by both prod and tests), pick the **lightest** isolation that meets your blast-radius budget:

| Approach | When |
|---|---|
| **Prefix discipline** (`TEST-*` on PK fields) + cleanup in `OnAfterAllTests` | Workshop, dev, single-developer sessions. Lowest infra, low blast radius if tests crash mid-run. |
| **Separate schema** in the same DB (`MenusTest`) with its own credentials | CI on shared infra, multiple devs running tests concurrently. |
| **Separate DB / credentials / BO item** (`CocinaTest`, `BO.CocinaTest`) | Production-grade CI with isolation requirements (e.g. test data must never bleed into prod backups). |

Default to **prefix** unless you have a concrete reason to escalate. Auditing a workshop production for "weak isolation" because it uses prefix-only is misreading the spectrum.

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
Run:            do ##class(MyApp.Tests.X).Run()   — still needs ^UnitTestRoot → existing server dir (unit-tests)

Spec → Test → Red → Implement → Green → Refactor.
BS: from outside IRIS only (file drop, TCP, curl).
TestingEnabled="true" on production for dev; strip before deploy.
```
