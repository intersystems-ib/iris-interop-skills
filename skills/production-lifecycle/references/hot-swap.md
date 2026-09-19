# Hot-swap vs restart

Why a code change does not take effect, and what actually has to be restarted. Read this when a change is in IRIS and the behaviour has not moved.

## Hot-swap vs. restart — when code changes don't take effect

`Ens.Director.UpdateProduction(timeout)` is for **production XML changes** — adding/removing items, modifying settings. It does **NOT** recompile class code and does **NOT** restart the OS jobs running BO/BP/BS instances.

When you edit and recompile a component class (BO method body, DTL, Rule XData), the running job still executes the **old** code. Symptoms: `<NOLINE>^MyClass.1` errors (line numbers from old/new code don't match), `<CLASS DOES NOT EXIST>` when a new helper class was added but the BO process didn't reload, behaviour matching the pre-edit code.

The right pattern after **code** changes:

```objectscript
ClassMethod RestartProduction(pName As %String) As %String [ SqlProc ]
{
    Set running = ##class(Ens.Director).IsProductionRunning(.current)
    If running = 1 {
        Set sc = ##class(Ens.Director).StopProduction(30, 1)   ; force=1
        If $$$ISERR(sc) Quit "Stop err: "_$SYSTEM.Status.GetErrorText(sc)
    }
    Hang 1
    Set sc = ##class(Ens.Director).StartProduction(pName)
    If $$$ISERR(sc) Quit "Start err: "_$SYSTEM.Status.GetErrorText(sc)
    // StartProduction returns BEFORE the production is up — wait for Running
    For i = 1:1:30 {
        Quit:##class(Ens.Director).IsProductionRunning()
        Hang 1
    }
    If '##class(Ens.Director).IsProductionRunning() Quit "Started but NOT Running after 30s"
    Quit "Restarted"
}
```

**Do not drop the wait-for-Running loop.** The start call returns before the production has come
back up; a restart without the wait leaves the production observably **Stopped** for the next few
seconds. Code that restarts and immediately continues — starts a component, sends a test message,
queries status — sees a stopped production and reports a confusing *downstream* failure that looks
nothing like "the restart wasn't finished". Same family of trap as "recompile doesn't reload the
running job" above: the lifecycle call succeeded, the state you assumed from it wasn't there yet.

It is a **three-way** choice, not two. Bouncing the whole production to re-test one Business
Operation is the most common way to waste a minute per iteration:

| What changed | Do this |
|---|---|
| production XML, or a Setting | `Ens.Director.UpdateProduction(timeout)` — or `iris_production(action=update)` |
| **one host's class code** | recycle **that job only**: `iris_production(action=restart, item="<Item>")` |
| several hosts, or the `Ens.Production` class itself | the full bounce — the `RestartProduction` pattern above |

**The platform API behind the one-item recycle is `TempStopConfigItem`, not a "restart" method.** There
is no `Ens.Director.RestartConfigItem` — measured, `##class(Ens.Director).RestartConfigItem(...)` raises
`<METHOD DOES NOT EXIST>`. What exists is:

```objectscript
Class MyApp.UTL.RecycleItem Extends %RegisteredObject
{

/// Recycle ONE host's job, leaving the rest of the production running. Use after recompiling that
/// host's class: neither a compile nor UpdateProduction restarts a running job.
ClassMethod One(pItem As %String) As %Status
{
    // TempStopConfigItem(item, stop, doUpdate). There is no RestartConfigItem -- see above.
    Set tSC = ##class(Ens.Director).TempStopConfigItem(pItem, 1, 1)
    // A bad item name is reported, not swallowed: <Ens>ErrConfigItemNotFound names item AND production.
    Quit:$$$ISERR(tSC) tSC
    Quit ##class(Ens.Director).TempStopConfigItem(pItem, 0, 1)
}

/// The disable/enable equivalent, for taking an item out of service rather than recycling it.
ClassMethod SetEnabled(pItem As %String, pEnabled As %Boolean) As %Status
{
    Quit ##class(Ens.Director).EnableConfigItem(pItem, pEnabled, 1)
}

}
```

Measured on 2026.1: both calls return `$$$OK` against a running production, and the rest of the
production keeps running throughout.

**A wrong item name fails clearly, so do not go hunting.** Measured:

```
EnableConfigItem("NoSuchItem", 1, 0)
  -> ERROR <Ens>ErrConfigItemNotFound: Item NoSuchItem not found in Production Example.Productions.ResendFixture
```

— it names the item *and* the production. `TempStopConfigItem` with a bad name gives the same. So if a
one-item recycle fails, read the status: it tells you whether the name matched.

One exception, and it is narrower than it looks: the per-item stop is blocked for a **Business Process**
with `PoolSize=0`, which runs in the shared actor pool rather than its own job. That restriction is
host-type-specific — `PoolSize=0` on an adapterless *Service* is a legitimate configuration this
codebase uses deliberately, and is not affected. A `PoolSize=0` BP needs the full bounce.

