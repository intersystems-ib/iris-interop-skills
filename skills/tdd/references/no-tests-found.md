# `NO_TESTS_FOUND` recovery

The recipe for when `iris_test` reports no tests. Read it when that happens, not before — and do not re-run blindly first.

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
3. **Branch on `error_code`, not on the prose.** `error_code` and `error` are the only fields
   guaranteed on every failure envelope. `hint`, `candidates`, `did_you_mean` and `cause` are
   **optional enrichment** — use them when present, never depend on them. Hint *wording* is not
   stable across server releases, and one of the two supported MCP servers returns no `candidates`
   at all, so a step that waits for them strands you.

   ```
   NO_TESTS_FOUND      the pattern matched no test class.
                       If `candidates` is present and non-empty, pick the match and re-run with
                       that exact name.
                       An EMPTY `candidates` is a DIFFERENT FACT, not a missing field: it means
                       the namespace holds no compiled test classes at all — go back to step 1,
                       the compile is what failed.
                       If `candidates` is absent entirely, the server does not send them. Do not
                       wait for it; go to step 4.

   NO_RUNNABLE_TESTS   the class exists and exposes nothing runnable. Here — and only here —
                       `cause` is present and says which:
                         NOT_A_TEST_CLASS            wrong superclass          -> step 4
                         NO_TEST_METHODS             no Test* method           -> step 4
                         PRODUCTION_PARAMETER_EMPTY  missing Parameter PRODUCTION -> step 1 (#5001)
                         UNKNOWN, or anything not listed above
                                                     -> report `cause` verbatim and stop
                       `cause` values change between releases too; never assume the list is closed.

   anything else       report `error_code` and `error` verbatim and STOP. There are ~88 codes and
                       new ones ship; a ladder that recognises a few and silently does nothing on
                       the rest is the bug this step exists to prevent. Do not guess a third name
                       variant, and do not fall back to running `Run()` from the terminal.
   ```
4. **Verify the superclass.** The class must extend `%UnitTest.TestProduction` — never
   `%UnitTest.TestCase`, which is not an escape hatch from a `#5001` here any more than anywhere
   else (see §"Baseline class" and the fixed-points rule below) — and have at least one `Test*`
   method. A class that extends the wrong base, or whose methods are not prefixed `Test`, compiles
   but exposes zero tests.
5. Only after 1–4 — if it still reports `NO_TESTS_FOUND` — STOP and report the blocker: 3 consecutive
   failed attempts at the same goal is the cap — and a test that RUNS but stays red has its own budget:
   see §"Loop budget — stop at the third red" above. Mechanism: see `interop` (section "Stop on repeated
   failure"). Do not loop, and do not switch routes to "work around" it — not `$SYSTEM.OBJ.Load` /
   the terminal, not `Run()` via `iris_execute`, not `RunTest(..., "/noload")`, not querying
   `^UnitTest.Result` by hand hoping to find a result. Every one of those gives the same (correct)
   answer about a class that never compiled; the only fix is upstream, at step 1.

