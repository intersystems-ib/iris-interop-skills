# When the production will not start

The recovery ladder, in order. Read it when `StartProduction` fails or the production reports running with dead items.

## When the production will NOT start — the recovery ladder

A `start` can be **refused because of leftover state**, and every one of these refusals is
recoverable — but not by retrying. The cardinal rule:

> **Never re-issue an identical `start` after a refusal. The state must change first.**
> Measured over a workshop cohort: 105 start refusals across 18/18 students, dominated by the
> same `iris_production(action="start", ...)` call repeated unchanged against a namespace that
> could never accept it.

Always begin with `iris_production(action=status, namespace=...)` — never start blind. Then match
the error:

| Refusal | What it actually means | Recovery |
|---|---|---|
| `<Ens>ErrInvalidProduction` | The production class is missing, not compiled, or the name doesn't resolve | Verify the class exists in that namespace and compiles clean (`iris_compile`), and that the name is the exact FQCN. Then start. |
| `<Ens>ErrProductionSuspendedMismatch` | A **different** production was left suspended in this namespace; nothing else can start until it is cleared | **The error names the OLD production, not yours** — do not "fix" the name you typed. Stop/clear the suspended one (it is the namespace's registered production, so `Ens.Director.StopProduction(30, 1)` targets it), then start yours. |
| `<Ens>ErrProductionNotShutdownCleanly` | The previous run died without a clean shutdown | Run the recovery path — `##class(Ens.Director).RecoverProduction()` — then start. A plain retry hits the same refusal forever. |
| `<Ens>ErrProductionSuspendedMismatch` **and the named class does not exist** | The namespace holds an orphan RUNTIME registration, not a production — a leftover from a stale image or a deleted exercise. `recover` is a **no-op** here (the production is Suspended, not Troubled — EGDV §12.3), and `stop force=true` leaves it `Stopped` without clearing the registration, so the next `start` under any other name refuses again. | 1. `iris_production(action=status, namespace="<NS>")` — note the production name it returns. 2. `iris_doc(mode=head, name="<that name>.cls", namespace="<NS>")`. 3. `exists:false` → `iris_execute(namespace="<NS>", code="Do ##class(Ens.Director).CleanProduction()")`, then start yours. 4. `exists:true` → a real suspended production: `iris_production(action=stop, force=true)` on **that** name, then start yours. |

**Step 2 is the one that must not be skipped** — it is what separates a real suspended production
from a registration with nothing behind it. `iris_doc(mode=head)` answers
`{"success":true,"name":…,"exists":…}`; **any other envelope means the call could not look** (wrong
namespace, wrong web prefix) and is **not** evidence of a ghost.

`iris_production` has **no `clean` action** — its enum is `status, start, stop, restart (item), update,
check, recover, get_autostart, set_autostart` — so this remedy necessarily goes through
`iris_execute`. Write it in the documented form, `Do ##class(Ens.Director).CleanProduction()`: the
docs publish no return value, so do not wrap it in `Set sc=`.

> **CAUTION** — Never use this procedure on a live, deployed production. The `CleanProduction()`
> method removes all messages from queues and removes all current information about the production.
> Use this procedure only on a production that is still under development.
>
> — *Developing Productions* §13.1.3, "Resetting Productions in a Namespace"

If there are messages still needed, export or resend them **before** running it.

`ErrProductionSuspendedMismatch` is the nastiest: because the message names the *old* production
(`Production 'Cocina.Production' was suspended, a new production of a different name can not be
started`), the reflex is to edit the production name you just passed and retry — which returns the
identical error, indefinitely. The name in the message is the thing to **clear**, not the thing to
type. Typical in shared/workshop namespaces where a previous exercise's production was left
suspended.

This ladder is about starts that are **refused outright**. The complementary trap — a start/restart
that *succeeds* but returns before the production is actually `Running` — is covered by the
wait-for-Running loop in the RestartProduction pattern above.

