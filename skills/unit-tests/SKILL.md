---
name: unit-tests
description: %UnitTest framework - runner, storage, results. Routed from interop. Triggers: %UnitTest, unit test, prueba unitaria, test runner, %UnitTest.TestProduction, ^UnitTest.Result, RunTest, qualifiers.
---

# %UnitTest framework — toolbox reference

> **Workflow note**: for the *order of work* (spec → test → red → implement → green → refactor) and for **the baseline class you must extend** (`%UnitTest.TestProduction`, not `%UnitTest.TestCase`), see **`tdd`**. That's the entry point when you're starting a new Interop component. This skill is the lower-level reference for **how the framework itself works**: where tests live on disk, how to invoke runners, where results land, how to inspect them.

IRIS ships a built-in unit-test framework with two relevant classes:
- **`%UnitTest.TestProduction`** — the Interop-flavoured superclass. **Use this for any Interop test.** Provides `Run()`, `SendRequest`, `GetEventLog`, `ChangeSetting`, `CreateCredentials`, file helpers, auto-properties (`BaseLogId`, `HL7InputDir`, etc.). Detail in `tdd`.
- **`%UnitTest.TestCase`** — the generic base. **Only use directly for tests of pure utility code that has nothing to do with Interop** (and even then, extending TestProduction is fine if the namespace is Interop-enabled).

## When to use this skill

You're already extending `%UnitTest.TestProduction` (per `tdd`) and need to understand the underlying framework — where to store tests so the runner doesn't delete them, how to invoke `Run()` / `DebugRunTestCase` / the MCP-friendly wrapper, what the qualifier flags mean, how to read `^UnitTest.Result`, what URL surfaces the portal.

## Where to store tests so they survive

**The trap**: `%UnitTest.Manager`'s `RunTest` with the default qualifiers **loads classes from disk via `^UnitTestRoot`** and **deletes them from the namespace after the run**. If you put your tests directly in source-controlled `.cls` files under `^UnitTestRoot`, every run wipes them.

**The fix**: store unit tests in a separate package, **compiled into the namespace ahead of time**, and run with qualifiers that skip the load/delete cycle.

Two patterns:

1. **In-namespace package** (recommended). Create `MyApp.Tests.*`, compile the classes once via your normal source-control flow (VS Code ObjectScript export, `iris_compile`, etc.). Run with `RunTest("MyApp.Tests", "/noload/nodelete")`. The runner walks the namespace, finds compiled tests, runs them in place.

2. **Use `TestProduction.Run()` / `Debug()`** (the canonical Interop path). The inherited methods invoke a single test class by name with `/noload/nodelete` semantics — they don't load test source from disk or delete classes after the run. **But they do still call the manager's "Finding directories" step**, so `^UnitTestRoot` must point at an existing directory (see below).

   ```objectscript
   do ##class(MyApp.Tests.DT.X).Run()      ; same-process, prints to terminal
   do ##class(MyApp.Tests.DT.X).Debug()    ; same-process, stops on failure for inspection
   ```

   **`Run()` still requires `^UnitTestRoot` to point at an existing directory** — even though we're not loading from it, the manager calls "Finding directories" early and fails with `ERROR #5007` if the path is invalid. Workaround:

   ```objectscript
   set ^UnitTestRoot = "C:\Temp\unittest_fake"
   ```

   Pre-create the (empty) folder; the runner reads no files from it but checks for existence.

   **`^UnitTestRoot` — like every file path a test touches — is resolved by the IRIS *server*,
   not by you.** When IRIS runs in a container, your working directory does not exist there:
   `set ^UnitTestRoot = "/home/me/project/tests"` fails with `#5007` even though the directory
   plainly exists on your side, and a fixture file at an agent-side path reads as "file not
   found" inside the test. Use a path *inside* the container (or the mounted data directory),
   or ferry fixture content in via the MCP / inline it in the test class — see `tdd` (pitfalls).

Avoid the documentation-default `RunTest` invocation that loads from `^UnitTestRoot` and deletes after run — that's the failure mode you want to prevent.

## Running tests — three options

| How | When |
|---|---|
| **`do ##class(MyApp.Tests.X).Run()`** | Default for Interop work. Same-process, returns a status, no docker exec required. No load/delete of test source — but still requires `^UnitTestRoot` set to an existing dir (see above). |
| **`do ##class(%UnitTest.Manager).DebugRunTestCase("", "MyApp.Tests.X", "/noload/norecursive/nodelete")`** | When you need the manager's full lifecycle (suite tracking, log granularity) but not its load-and-delete behaviour. Use **boolean qualifiers** only (see pitfall below). |
| **SqlProc wrapper around `DebugRunTestCase` invoked via `iris_query`** | **Legacy fallback only** — see the warning below. `iris_test` runs over HTTP and needs no container; prefer it whenever the MCP is present. |
| **`%UnitTest.Portal` UI** | Visual, navigable; for inspecting results, not driving runs. |

### The SqlProc wrapper — legacy fallback, and how it silently lies

> **Prefer `iris_test`.** This wrapper existed because `iris_test` used to require `IRIS_CONTAINER` /
> docker exec. It no longer does — it works over HTTP against a Windows-host IRIS. `conformance-review`
> **CR-7 flags a `[SqlProc]`-returned "PASS" as unverified**, and the reason is below.

**A runner that counts assert rows cannot detect a test that crashed.** If a method raises before its
first `$$$Assert*` — an `<UNDEFINED>` on an uninitialised variable is the common case — it writes **zero
assert rows**. A loop that scans the asserts looking for a failure finds none, and counts the method as
**passed**. Verified on IRIS for Health 2026.1:

```
LogStateStatus:0:TestRevienta: ERROR #5002: <UNDEFINED>… <<==== **FAILED**
TestRevienta failed
…
passed=2 failed=0          ← what an assert-counting wrapper reported for that same run
```

The framework itself is right — `%UnitTest` records the method as failed and `iris_test` reports it red.
Only the hand-rolled summary is wrong.

**The fix is to read the method node's own verdict**, not its assert children. `$LISTGET(node,1)` is the
framework's own pass/fail flag and it is already correct for both failure modes:

```objectscript
ClassMethod RunTestClass(pClassName As %String) As %String [ SqlProc ]
{
    Set sc = ##class(%UnitTest.Manager).DebugRunTestCase("", pClassName, "/noload/norecursive/nodelete")
    If $$$ISERR(sc) Quit "err: "_$SYSTEM.Status.GetErrorText(sc)
    Set resultId = $G(^UnitTest.Result, 0)
    Set passed = 0, failed = 0, failedList = ""
    Set suite = ""
    For {
        Set suite = $O(^UnitTest.Result(resultId, suite))  Quit:suite=""
        If '$D(^UnitTest.Result(resultId, suite, pClassName)) Continue
        Set m = ""
        For {
            Set m = $O(^UnitTest.Result(resultId, suite, pClassName, m))  Quit:m=""
            // The METHOD node carries the framework's own verdict. Do NOT scan the assert
            // children: a method that crashed before its first assert has none, and an
            // "any child failed?" loop then reports it as passed.
            Set ok = +$LISTGET($G(^UnitTest.Result(resultId, suite, pClassName, m)), 1)
            If ok { Set passed = passed + 1 }
            Else  { Set failed = failed + 1, failedList = failedList _ $S(failedList="":"", 1:", ") _ m }
        }
    }
    Quit "passed="_passed_" failed="_failed_$S(failed>0:" | failures: "_failedList, 1:"")_" | rid="_resultId
}
```

Verified on IRIS for Health 2026.1 against a class with one passing method, one failing assert and one
`<UNDEFINED>` crash: `passed=1 failed=2 | failures: TestAssertFalla, TestRevienta`. The previous
assert-scanning form reported `passed=2 failed=0` on the same class.

Invoke from MCP:

```sql
SELECT MyApp_Bootstrap_RunTestClass('MyApp.Tests.DT.Censo2Menus')
```

### Qualifier syntax pitfall — booleans only

The `DebugRunTestCase` qualifier flags are **boolean** — write `/noload/norecursive/nodelete`. Do NOT write `/noload=0` or `/recursive=1`. The `=value` form throws `ERROR #5001: can not mix negated form with value`. The qualifier is either present (true) or absent (default false).

### `Try / Catch + Quit` pitfall inside runners

`Quit <arg>` is illegal inside a `Try` block — IRIS reports `#1043: QUIT argument not allowed`. The runner pattern:

```objectscript
Set tSC = $$$OK
Try {
    ; ... possibly-raising work ...
} Catch ex {
    Set tSC = ex.AsStatus()
}
If $$$ISERR(tSC) Quit tSC
```

Set the status inside the Try; exit the Try; then act on it. Same idiom applies in test method bodies (see "Error handling" below).

## Inspecting results — the `%UnitTest.Portal` web pages

After running tests, **always direct the user to the portal** for navigable drill-down through asserts. The portal class chain is:

```
%UnitTest.Portal.Home  →  Indices  →  TestSuite  →  TestCase  →  TestMethod (per-assert detail)
```

**Canonical URL** (substitute host/port/prefix per the instance):

```
http(s)://<host>:<port>/<prefix?>/csp/sys/%25UnitTest.Portal.Home.cls?$NAMESPACE=<NamespaceDelTest>
```

`%25` is `%` URL-encoded. `$NAMESPACE=` filters to the namespace where the tests ran.

Concrete example (IRIS on port 80, namespace `MyApp`):

```
http://localhost:80/csp/sys/%25UnitTest.Portal.Home.cls?$NAMESPACE=MyApp
```

**Test runners that ship with skills (SqlProc wrappers, MCP commands, scripted invocations) MUST print this URL as the last line of their output** so the user can click straight through to drill-down detail. The portal isn't obvious — most students go read `^UnitTest.Result` by hand because the doc doesn't surface it.

## The `^UnitTest.Result` global

Results land in:

```
^UnitTest.Result(resultId, suite, case, method, assertSeq) = $LB(success, action, description, ...)
```

- `resultId` increments per run; current is `^UnitTest.Result` (no subscripts).
- `success` is `1` for pass, `0` for fail.
- `description` is the assert message.

The SqlProc wrapper above traverses this global to compute the pass/fail summary — reading each
**method node's** own flag, not its assert children, for the reason given in that section. The portal
renders the same data graphically.

## Error handling inside test methods

When a test method drops to ObjectScript that may raise, use the standard try/catch idiom:

```objectscript
Method TestSomething()
{
    #DIM tSC As %Status = $$$OK
    #DIM errObj As %Exception.AbstractException
    Try {
        Set tSC = ##class(MyApp.X).DoStuff()
        $$$ThrowOnError(tSC)
    } Catch errObj {
        Set tSC = errObj.AsStatus()
    }
    Do $$$AssertStatusOK(tSC, "DoStuff should succeed")
}
```

This is the same pattern used in production code (see `transformations` and `bpl`). Consistent error handling between tests and code means the framework's assertion message includes the real diagnostic chain — not "tSC was 0" with no further context.

Inside a `Try` block, `Quit <value>` is illegal (`#1043: QUIT argument not allowed`). Set the status, exit the Try, then act on it after — same as the runner-side rule above.

## Canonical pattern — unit-testing a DTL

```objectscript
Class MyApp.Tests.DTL.PatientCensusToHL7 Extends %UnitTest.TestProduction
{
Parameter PRODUCTION = "MyApp.Production";
Method TestControl() As %Status { Quit $$$OK }

Method TestHappyPath()
{
    Set tSrc = ##class(MyApp.Msg.PatientCensusRequest).%New()
    Set tSrc.PatientId = "P12345"
    Set tSrc.AdmissionDate = "2026-05-06 10:00:00"
    Set tSrc.Department = "ICU"

    Set tSC = ##class(MyApp.DT.PatientCensusToADT).Transform(tSrc, .tTarget)
    Do $$$AssertStatusOK(tSC, "Transform should succeed")
    Do $$$AssertEquals(tTarget.GetValueAt("PID:3"), "P12345", "PID:3 should be PatientId")
    Do $$$AssertEquals(tTarget.GetValueAt("PV1:3"), "ICU", "PV1:3 should be Department")
}

Method TestEmptyDepartment()
{
    Set tSrc = ##class(MyApp.Msg.PatientCensusRequest).%New()
    Set tSrc.PatientId = "P12345"
    Set tSC = ##class(MyApp.DT.PatientCensusToADT).Transform(tSrc, .tTarget)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tTarget.GetValueAt("PV1:3"), "", "Empty department should map to empty PV1:3")
}
}
```

For Interop-specific test skeletons (DTL / routing rule / BO method / BPL), see `tdd`.

## Common pitfalls

- **Tests stored where the runner deletes them after run** — pick a storage pattern that doesn't get cleaned up (see "Where to store" above).
- **`Run()` failing with `ERROR #5007: Finding directories`** — `^UnitTestRoot` not set or points at a non-existent path. Set it to any existing directory; runner reads no files from it.
- **Qualifier syntax `/noload=0`** → `#5001: can not mix negated form with value`. Boolean qualifiers are presence-only.
- **`Quit <value>` inside `Try`** → `#1043`. Set tSC; exit Try; quit after.
- **Asserting on internal state instead of public contract** — tests get brittle. Assert on what the next consumer (DTL, BO, downstream system) will actually see.
- **Real adapter calls in unit tests** → flaky, slow, environment-dependent. That's an integration test, not a unit test.
- **Missing `$$$AssertStatusOK` on every `Set tSC = ...`** — silent failures pass the test.
- **Tests that depend on each other** — each test method should be runnable in any order, in isolation.
- **No fixture data strategy** — paste-in literals everywhere. Centralize sample messages/inputs in a fixtures class.
- **Forgetting the portal URL in runner output** — students go straight to `^UnitTest.Result` by hand because they don't know the portal exists.

## Testing / how to verify (this skill itself)

For a smoke test of the unit-test setup:

1. Compile a trivial `MyApp.Tests.Smoke` extending `%UnitTest.TestProduction` with one passing assertion.
2. Run via `do ##class(MyApp.Tests.Smoke).Run()`.
3. Confirm the test class is still in the namespace after the run (didn't get deleted).
4. Open the portal URL (see above), confirm the result shows green.
5. Add a deliberate failure; re-run; confirm it surfaces clearly with line numbers in both the terminal output and the portal.

## When NOT to use this skill — fall back to docs

- Performance / load testing — use a different harness; `%UnitTest` isn't designed for it.
- UI testing of the Management Portal — out of scope.
- End-to-end production tests where you want to assert across multiple components — use `message-search-debug` patterns (Visual Trace inspection from a test-driven sample injection) rather than `%UnitTest` alone.

## See also

- `tdd` — the workflow (spec → test → red → green → refactor), the `TestProduction` baseline class, and the canonical Interop test skeletons (DTL, routing rule, BO method, BPL).
- `messages` — define the contract before writing tests.
- `transformations` — DTL classes are first-class unit-test targets.
- `business-operations` — refactor BO methods to be testable.
- `message-search-debug` — for end-to-end / integration verification beyond what `%UnitTest` covers.
