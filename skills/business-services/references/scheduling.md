# Scheduled and order-sensitive Business Services

Wall-clock schedules versus polling intervals, `PoolSize` and the concurrency trap, and the
synchronous-chain pattern for sources whose ordering must be preserved. Genuinely optional:
no part of the standard file / HL7 / REST intake needs any of it.

## Scheduled BS — wall-clock vs interval

Default Ensemble inbound adapters do **interval** scheduling ("every X seconds"). For **wall-clock** schedules (daily 08:30, weekdays 08:00–18:00 only, etc.) two options:

- **Custom scheduler adapter** with a cron-style format `min hour day month dayOfWeek`. Most legacy
  customer projects built one of these. **Gated example:**
  `assets/adp-scheduler-inbound-adapter.cls`,
  with its service `bs-scheduled-cron.cls` and dispatch test `tdd-inbound-adapter-dispatch.cls`.
  Until 1.18.0 nothing in this plugin showed the shape — `Ens.InboundAdapter` had **zero** hits
  across all 20 skills and the whole bank — while §5.2 named a class for it.
  The one line that matters is `..BusinessHost.ProcessInput()`. An `OnTask()` that checks its
  schedule and returns `$$$OK` without it leaves the service **green and ticking for ever,
  producing nothing**, with an empty Event Log. Measured: broken that way, `OnTask` still returns
  `$$$OK` — so the status can never be the signal, only the dispatch count.
- **IRIS native task framework** — subclass **`%SYS.Task.Definition`**, override `OnTask`, and have it trigger a passive BS via `Ens.Director.CreateBusinessService`. Preferred for new work. (Not `%SYS.TaskSuper`: that class also exists, so the mistake survives an existence check, but it is the internal persistent superclass of the stored `%SYS.Task` schedule record — *"for internal use only"* — and has no `OnTask` to override. Every shipped task on an instance, `PurgeJournal` / `IntegrityCheck` / `PurgeErrorsAndLogs` …, subclasses `%SYS.Task.Definition`.)

### Scheduled BS concurrency — `PoolSize=1` alone is not enough

To prevent concurrent execution of a scheduled Business Service, **both** are required:

(a) Set `Pool Size = 1` on the BS item.
(b) Make **all calls from the BS synchronous** (`SendRequestSync`).

Async calls let the BS return before the work downstream finishes. The scheduler's next tick fires while the first execution is still in-flight → two concurrent BS instances racing.

Also: any **manual** entry path (a Studio test, a non-scheduled inbound message sent by a different BS) bypasses the scheduler entirely and is not subject to the lock. If concurrency matters for correctness, defend in code (a global lock / semaphore inside the BS).

## Synchronous chain for source-system ordering dependencies

When the source system has row-ordering dependencies (e.g. an UPDATE that depends on its prior INSERT, a "Reprogramacion" that depends on its "Programacion"), prefer a synchronous BS → BP → BO chain over async messaging. Async queues are free to reorder; sync chains preserve order at the cost of throughput.

Document the trade-off explicitly in the production. See `bpl` for the BP-side pattern.
