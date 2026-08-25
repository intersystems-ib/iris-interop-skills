---
name: production-lifecycle
description: Production class, start/stop/update, deploy, settings. Routed from interop. Triggers: production, producción, Ens.Production, start/stop, arrancar/parar, deploy, despliegue, System Default Settings, UpdateProduction, namespace.
---

# Production lifecycle — the container of everything

The Production is the runtime container. It's a class extending `Ens.Production` whose `XData ProductionDefinition` lists every component (BS/BP/BO) and its settings. At runtime exactly **one production per namespace** is active.

## Disk-first: source code is the source of truth

**Code lives on disk and gets pushed to IRIS, not the other way around.** A workshop is shipped over git; the `.cls` files in `src/` are canonical. IRIS is a runtime mirror — reinstall it tomorrow and you should be able to reload everything from disk.

> **Enforced, not merely advised.** A PreToolUse gate **denies** `iris_doc(mode=put)` when the
> class has no file under the project: write `src/<Pkg>/<Tipo>/<Name>.cls` first, then put the
> same content. Classes generated *by* IRIS — RecordMap `.Record`, SOAP-wizard `WSC.*` — are
> exempt, and their rule is the mirror image: `iris_doc(mode=get)` them into `src/` immediately
> after generating.

### Drift is silent — check it before calling the work done

Nothing in the toolchain compares the namespace against the source tree, so the two diverge with
no symptom at all. Audited on one real VM at the end of a workshop:

```
28 classes on disk · 29 in IRIS · only 22 in common
```

**Seven existed only in the namespace** — and not scratch work: an entire HL7 canonical flow
(`DT.HL7ToCanonico` → `MSG.PacienteCanonico` → `DT.CanonicoToMenu` / `DT.CanonicoToSOAP`, plus
`DT.AL1ToString` and its test), written straight to IRIS in the closing hours and never exported.
**Six existed only on disk** — written but never compiled, or compiled and later deleted from the
namespace. Both directions had happened, and nothing made it visible.

The check is cheap:

```objectscript
ClassMethod DriftReport(pPkg As %String, pSrcDir As %String) As %String [ SqlProc ]
{
    Set onlyIris = "", n = $Length(pPkg) + 1, k = ""
    For {
        Set k = $Order(^oddCOM(k))  Quit:k=""
        Continue:$Extract(k, 1, n) '= (pPkg _ ".")
        Set f = pSrcDir _ "/" _ $Replace(k, ".", "/") _ ".cls"
        If '##class(%Library.File).Exists(f) {
            Set onlyIris = onlyIris _ $Select(onlyIris="":"", 1:", ") _ k
        }
    }
    Quit $Select(onlyIris="":"in sync", 1:"ONLY IN IRIS: " _ onlyIris)
}
```

Run it before declaring a production done, and after any session that used the Management Portal
or a wizard — those write straight into the namespace and never touch disk.

Layout (VS Code ObjectScript plugin convention — **Atelier-style nested**, NOT flat dotted filenames):

```
src/
└── MyApp/                       ← namespace's top-level package
    ├── BO/
    │   ├── CocinaREST.cls       ← class: MyApp.BO.CocinaREST
    │   └── CocinaSOAP.cls
    ├── DT/
    │   ├── Censo2Menus.cls
    │   └── HL7ADT2MenuRich.cls
    ├── Production.cls           ← class: MyApp.Production
    └── Tests/
        └── DT/
            └── Censo2Menus.cls
```

**Wrong** (legacy flat — the VS Code plugin doesn't recognize): `src/MyApp.BO.CocinaREST.cls`. Bash convert: `PKG_PATH=$(echo "${file%.cls}" | tr '.' '/')`.

`.code-workspace` settings to wire VS Code ↔ IRIS:

```json
"objectscript.conn": { "active": true, "server": "<server>", "ns": "<namespace>" },
"objectscript.export": { "folder": "src", "atelier": true, ... }
```

When you must drive IRIS from MCP (`iris_doc put`), **immediately** `iris_doc get` the result and `Write` to disk in the Atelier layout. Don't let in-IRIS-only classes accumulate — that's silent debt the workshop alumno can't recover.

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

Use `UpdateProduction` after **production XML** changes only. Use `RestartProduction` after **class code** changes. Treat the two as distinct lifecycle events.

## Pre-flight validation before restart

Before `RestartProduction`, run a validator that catches references to classes / items that don't exist (typo in transform name, target BO renamed, helper class deleted). It's a SqlProc that iterates `Ens_Config.Item` and parses the Router's `XData RuleDefinition` to verify every `<send transform="X" target="Y"/>` resolves. Returns `OK` or `ISSUES: <list>`. The `bpl` skill has a worked example.

This catches the entire class of "BP terminated with `<CLASS DOES NOT EXIST>`" bugs at edit time — without it, the first signal is the first message that hits the router after the broken edit.

## Probing for an existing credential — `IDKeyExists()` does not exist

Bootstrap code that checks for an existing credential with
`##class(Ens.Config.Credentials).IDKeyExists(name)` fails at **runtime** (not compile time) with
`<METHOD DOES NOT EXIST>` — the method simply isn't there, even though it's exactly what one
reaches for by analogy with other `%Persistent` classes. The working probe is `%OpenId()` plus
`$IsObject()`:

```objectscript
Set cred = ##class(Ens.Config.Credentials).%OpenId(pName)
If '$IsObject(cred) { /* not there — create it */ }
```

Through the MCP, prefer `iris_credential_list` / `iris_credential_manage`, which handle the
exists-then-create dance for you.

## Recovering from a wedged IRIS web stack

After many rapid production restarts in tight loops, the IRIS private web server / CSP gateway can enter a sostained-503 state — port 80 returns `503 Server Unavailable` for every request even though `irisdb` is running. MCP tools (which talk via Atelier REST on the same port) start failing with `HTTP 503 Service Unavailable` and don't self-recover.

Recovery: `Restart-Service` the IRIS daemon at the OS level:

```powershell
Restart-Service -Name 'IRIS_<instance>' -Force
```

The state is in-memory web-stack only; persistent data is untouched. After service comes back, `Ens.Director.StartProduction("MyApp.Production")` to bring the production back up.

## When to use this skill

The user is wiring components together, changing settings, deploying between DEV/TEST/PROD, or troubleshooting startup issues.

## Production class skeleton

```objectscript
Class MyApp.Productions.MainProduction Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="MyApp.Productions.MainProduction" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Main interop production for MyApp</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BS.Census" Category="MyApp" ClassName="MyApp.BS.PatientCensusFromCSV"
        PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="FilePath">/data/in</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Router.Census</Setting>
  </Item>

  <Item Name="Router.Census" Category="MyApp" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">MyApp.Rule.RoutingCensus</Setting>
  </Item>

  <Item Name="BO.SQL" Category="MyApp" ClassName="MyApp.BO.WriteCensusToSQL"
        PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="JGService">Util.JDBCGateway</Setting>
  </Item>

  <Item Name="Util.JDBCGateway" Category="MyApp" ClassName="EnsLib.JavaGateway.Service"
        PoolSize="1" Enabled="true" Comment="Points at the %JDBC Server External Language Server">
    <Setting Target="Host" Name="%gatewayName">%JDBC Server</Setting>
  </Item>

  <!-- Default scaffold: alerts router + file logger. Wired even before any rule exists. -->
  <Item Name="Ens.Alerts" Category="MyApp" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">MyApp.Rule.Alerts</Setting>
  </Item>
  <Item Name="BO.AlertLogger" Category="MyApp" ClassName="EnsLib.File.PassthroughOperation"
        PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="FilePath">/var/log/iris/alerts</Setting>
  </Item>

</Production>
}
}
```

Naming and category conventions (apply to every item):
- **`Item Name="Tipo.Nombre"`** — `BS.X`, `BO.X`, `Router.X`, `Util.X`, fixed `Ens.Alerts`. Don't break the pattern (`Java.Gateway` looks like `Tipo.Nombre` but `Java` isn't a component type → rename to `Util.JavaGateway` or similar).
- **`Category="<Package>"`** on every item. Groups items in the portal and enables category-level filtering. Use the project package (`MyApp`, `Hospital`) or a finer-grained label if it helps the UI.
- **Omit noise attributes** like `Schedule=""` and `LogTraceEvents="false"`. They duplicate defaults and clutter the XML — leave them off unless the value is non-default and meaningful.

Components are added by editing the XML directly or, more usually, via the Management Portal (or via the MCP server).

## Defaults that are correct — don't audit them away

These are the right defaults for a newly-scaffolded production. They look "unconfigured" but they aren't — they're the documented baseline:

| Attribute / setting | Default | When to change |
|---|---|---|
| `PoolSize="1"` on every item | Correct everywhere. | Raise only with measured evidence of a bottleneck (queue depth, end-to-end latency). Don't preemptively scale. |
| `TestingEnabled="true"` on `<Production>` | Correct in dev/workshop. Enables `EnsLib.Testing.Service.SendTestRequest` and the portal Test page. | Strip (or override per-environment) when there's a real deploy-to-prod pipeline. In a workshop or single-environment project, leave it on. |
| `LogTraceEvents="false"` on items | Correct (off by default). | Set per-item to `true` in dev when actively debugging that component. Don't set it to `"false"` explicitly — that's just noise. |
| Empty `Schedule` | Correct (item is always-on). | Set a cron expression only for scheduled BSes/BOs. |

If your audit pass says "PoolSize=1 is a defect" or "TestingEnabled=true needs a guardrail" without environment context, you are second-guessing a correct default. Stop.

### Skeleton / future-flow items: comment, don't register broken stubs

When a production is built one flow at a time but you want the **full set of circuits visible**, do NOT add `<Item>` elements that reference classes that don't exist yet — the production fails to load (`<CLASS DOES NOT EXIST>`). Two valid options:
- **XML comments** describing the pending items (B–E flows, their classes and adapters) inside the `XData ProductionDefinition`. Zero runtime cost, documents intent.
- **`Enabled="false"`** items — only once the referenced class actually exists and compiles. A disabled item whose class is missing still breaks load. Also use `Enabled="false"` for a real-but-not-yet-runnable component (e.g. an FTPS service when no FTPS server exists this iteration) — but provide placeholder adapter settings so it validates.

Don't confuse "registered but disabled" (class exists, `Enabled="false"`) with "documented for later" (no class yet → comment only).

## Default scaffolds the skill should produce

Beyond BS/Router/BO, every production should ship with:

- **`Ens.Alerts` router** (`EnsLib.MsgRouter.RoutingEngine`) wired as the alert target. Without it, exceptions land in the Event Log but don't fan out.
- **Alert sink BO** — at minimum a file logger (`EnsLib.File.PassthroughOperation` writing to a dedicated alerts directory). Optional email BO (`EnsLib.EMail.OutboundAdapter`) for prod.
- **`Ens.Util.Tasks.Purge` task** scheduled daily. Persistent messages accumulate forever otherwise; the message-class table grows unbounded. Set `NumDaysToKeep` per retention policy (typically 30–90).
- **External Language Server reference** when JDBC is in use — the BO's `JGService` setting points to an item whose `%gatewayName` is the ELS name (`%JDBC Server` is the IRIS-shipped default). `EnsLib.JavaGateway.Service` works but is **deprecated in IRIS 2026.1** — the gateway class is being phased out in favour of ELS-direct references.

When auditing an existing production, **flag missing alert router or purge task as gaps**; flag missing items only if the production's purpose requires them.

## Settings: precedence order (lowest → highest)

1. Class-level defaults (`Property` declaration with default).
2. Production-level setting on the `<Item>` (in the production XML).
3. **Default Site Settings** (set per-environment, override imported production XML).

Default Site Settings are the deployment escape hatch: when you export DEV's production XML to TEST, the DEV file paths and IPs come along — but the TEST environment's Default Site Settings override them at runtime.

Wildcards (`*`) work in Default Site Settings — apply a value to all File-adapter components, or all BOs of a class.

## Starting / stopping / updating

| Action | What it does | When to use |
|---|---|---|
| **Start** | Production goes from Stopped → Running. All `Enabled=true` items start. | Initial start, after major changes. |
| **Stop** | All items shut down cleanly. | Maintenance, breaking change deploy. |
| **Update** | Live re-read of the production class. Items with changed config restart in-place. | After editing settings in dev. Preferred over full Stop/Start. |
| **Restart item** | Single component restart. | Targeted setting change without disturbing the rest. |

`Update` is the workflow — it's almost always what you want during dev. Full Stop/Start is heavier and slower.

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

`ErrProductionSuspendedMismatch` is the nastiest: because the message names the *old* production
(`Production 'Cocina.Production' was suspended, a new production of a different name can not be
started`), the reflex is to edit the production name you just passed and retry — which returns the
identical error, indefinitely. The name in the message is the thing to **clear**, not the thing to
type. Typical in shared/workshop namespaces where a previous exercise's production was left
suspended.

This ladder is about starts that are **refused outright**. The complementary trap — a start/restart
that *succeeds* but returns before the production is actually `Running` — is covered by the
wait-for-Running loop in the RestartProduction pattern above.

## Deployment: export → import

1. **Production → Actions → Export.** Generates a single bundle XML containing: production definition, all BS/BP/BO classes (XML projections), HL7 message definitions, routing rules, lookup tables, custom schemas, DTLs.
2. **Custom dependencies not auto-detected** (utility classes, helper methods) → add them manually via the export interface's "Add additional element" buttons.
3. **Import on target environment**: Interoperability → Manage → Deployment Changes → Deploy. The deploy step automatically writes a **rollback file** before importing — you can revert if the import goes bad.
4. **Always test deploy in TEST first.** Production deploy is the wrong place to discover a missing dependency.

## Default Site Settings — the deploy escape hatch

Define environment-specific values **outside** the production XML, at the namespace level. When the production runs, Default Site Settings are applied on top of whatever the production XML says. This is how you keep one production XML across DEV/TEST/PROD without hand-editing on each deploy.

**When to introduce Default Site Settings**: ask the user explicitly. The trigger is "does this value differ between PRE and PROD?" — paths, hostnames, credentials, ports often do; constants and shared paths often don't. Hardcoding is the right default when the value is the same everywhere; Default Site Settings are the right tool **only when** the value actually varies. Don't move every setting into `Ens.Config.DefaultSettings` preemptively.

```
DEV exports with:    <Setting Target="Adapter" Name="FilePath">C:\dev\in</Setting>
TEST overrides via Default Site Settings:  Component="*", Name="FilePath", Value="/srv/test/in"
PROD overrides via Default Site Settings:  Component="*", Name="FilePath", Value="/srv/prod/in"
```

## OnInit / OnTearDown

Productions have lifecycle callbacks too — most of the time, the per-component `OnInit`/`OnTearDown` are what you want. Only override the production-level callback for cross-component setup (rare).

## When to split into multiple namespaces / productions

Drivers to split a single integration estate across multiple productions (or namespaces):

| Driver | Example |
|---|---|
| Ownership / RBAC | Lab vendor maintains "their" production; hospital staff maintain "theirs". Separate productions enforce the boundary. |
| Tech-stack churn | FHIR in its own production — DSTU2 → STU3 → R4 evolution, OAuth wizard regeneration, all isolated. |
| Security boundary | External integrations isolated from internal ones for tighter access control. |
| Regulatory boundary | Anything subject to differential audit or data-residency rules. |

Do **not** split for cosmetic reasons. Every split adds operational burden: its own production monitor, alert circuit, settings, source-control branch, deploy pipeline.

The opposite extreme — a single `INTEROP` namespace with **categories** per integration and a shared deployment tool — is also acceptable for cohesive estates. Both shapes work; the consolidation makes deployment simpler at the cost of weaker access boundaries.

## Capture per-environment values BEFORE deploy day

When a developer introduces a new System Default Setting on DEV, populate the value for **all** environments in your site-config mirror table immediately. Don't wait for migration day to remember which settings need per-environment values.

A pragmatic pattern is a single configuration table per customer (e.g. `CustomerNoExport.CFG.ConfiguracioSites` with rows `[ItemName, SettingName, ValueDEV, ValueTEST, ValuePRE, ValuePROD]`) that you fill at the moment the setting is added in DEV. Deploy tools (next section) consume this table.

## The IRIS Interop Deployment tool — concept

Out of the box, IRIS keeps System Default Settings **separate per environment** — they don't travel with the production XML export. So a DEV → PROD deploy preserves the production structure but loses the per-environment configuration (file paths, hostnames, credentials).

Either document those settings by hand for every deploy, or use a deployment tool. The reference open-source tool is `https://github.com/PYDuquesnoy/IRIS-Interop-Deployment` (community-maintained, **not** InterSystems-supported).

Key behaviours of any production-aware deploy tool:

- Stores per-environment values in a configuration table (typical columns: `ValueDEV / ValueDEVLOCAL / ValueTEST / ValuePRE / ValuePROD`).
- Triggers on `Ens.Config.DefaultSettings` keep that table in sync — usually requires `ENSLIB` RW during install.
- Export produces a small set of files: classes, production cfg, site cfg, virtual docs.
- Import auto-backups before overwriting, recompiles, restarts the production, prints a rollback command.
- A `DEVLOCAL` site flag (or equivalent) means "sync configuration values but DON'T overwrite local class changes" — so a developer working on uncommitted code isn't blown away by an incoming deploy.

Pick a tool early. Manual per-env maintenance scales poorly past three integrations × three environments.

## Git source control on a shared dev IRIS — Windows gotchas

When using `git-source-control` (or `objectscript-git-source-control` via ZPM) on Windows where IRIS runs as a service, two issues recur:

### CVE-2022-24765 — `fatal: unsafe repository`

Git 2.35+ verifies the repository owner matches the running user. IRIS running as `LocalSystem` hits this when the repo is owned by a developer account. Three fixes, pick one:

1. Run the IRIS service as a service account (`Intersystems` user or a domain account) instead of `LocalSystem`.
2. Change the Windows owner of the repo to match the IRIS service account.
3. `git config --global --add safe.directory <path>` for whichever account runs IRIS. **Note**: some Git versions need a trailing `/` on the path; some don't. If the error persists after adding the rule, try both forms.

### ZPM install paradox

`zpm install` works only when IRIS is started as `LocalSystem` (it uses `$ZU(-1)` which fails for non-`LocalSystem` users). After installing the source-control packages, switch the service account to your service user. Document this dance — it's non-obvious and a fresh environment setup will hit it.

## HL7 schemas — manual export required (HIGH severity)

Custom HL7 schemas edited via the Management Portal are stored **in the namespace**, not on disk. They are not auto-exported by source-control integration. After every schema edit, manually `Export` to the SCM root and commit alongside related class changes.

Failure to export is a silent loss-of-work risk on the next namespace refresh. See `iris-interop-hl7-schemas §2.2` for the full risk discussion.

## Migration of interop productions

When migrating a production between IRIS instances (version upgrade, hardware refresh, container rebuild), these patterns prevent silent failures.

### Never auto-start a migrated production

Set `EnsembleAutoStart = 0` (or its IRIS equivalent) on the freshly migrated instance. The restored productions point at **real** endpoints — auto-starting them injects test traffic (or real traffic from yesterday's queue) into production systems. Validate each component's settings manually before enabling.

### Credentials migration

`Ens.Config.Credentials` records contain passwords encrypted with the **instance key** of the source system. Standard backup-restore preserves the records but renders the passwords unreadable in the target instance.

Pattern: write an ObjectScript utility that walks all `Ens.Config.Credentials` rows in the source, exports `(name, username, password)` to a file (treating the file as a secret), then re-imports them on the target. Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch13_migration/credentials-export-reimport.cls`.

### `Ens.<X>` package shadowing

If a customer-written class lives in package `Ens.<something>` (e.g. `Ens.Util.MyHelper`), the ENSLIB-to-namespace mapping returns the system version (or fails to resolve), **shadowing** the customer class. Symptoms: `<PROTECT>` runtime errors, classes appearing in the dictionary but not callable.

Fix: export the affected classes, rename the package to a customer-owned namespace (e.g. `CustomerUtil.MyHelper`), re-import.

**Side effect**: the storage definition changes when the class is renamed; old persistent instances of the renamed class become unreadable. Migrate or archive the data before renaming.

### IRIS Windows service account for UNC paths

Default Windows installs of IRIS run the service as `LocalSystem`, which has no rights to UNC paths. Any `FileService` / `FileOperation` / FTP-mount adapter that points at `\\server\share\...` will **fail silently** after migration. Fix: change the IRIS Windows service to run as a domain user with read/write to the UNC paths.

### Production startup protocol

A migration with 30+ steps cannot be done from memory; one missed step ships a non-functional production. Build a documented, line-by-line startup protocol covering: disable user logins, restore each `.bck`, restore the CPF, reconfigure environment globals, modify routines for new file paths, register license / credentials, configure ODBC for new DSN, configure terminal connections, **explicitly do NOT auto-start** the production.

### Ensemble vs IRIS default ports

| Default | Ensemble (≤2017) | IRIS (2018+) |
|---|---|---|
| SuperServer | 1972 | 52772 |
| Web (Apache) | 57772 | 52773 |

Watch for hardcoded port references in client code and firewall rules during migration.

## Bootstrap scripts on Windows — `irissession` stdin gotcha

When writing a bootstrap script (`install.ps1`, environment-prep helper) that pipes ObjectScript into `irissession`, the **shell `<` redirect form does NOT work in PowerShell 5.1 or 7**:

```powershell
# FAILS — parser error: "The '<' operator is reserved for future use"
& $irisSession $instance -U %SYS < $tmpScript.FullName
```

Use one of these portable alternatives:

```powershell
# Option A — pipe via Get-Content (preferred; works in 5.1 and 7)
Get-Content $tmpScript.FullName | & $irisSession $instance -U %SYS

# Option B — drop to cmd.exe for the redirect
cmd.exe /c "`"$irisSession`" $instance -U %SYS < `"$($tmpScript.FullName)`""
```

The `<` redirect is a `cmd.exe` / bash builtin; PowerShell parses it as a reserved operator and fails before executing the command. Any bootstrap script that crosses PowerShell hits this — and since PowerShell 5.1 is the Windows default, the failure surfaces on every fresh student environment.

If the installer must run identically on Linux and Windows, prefer driving it from ObjectScript via MCP (`iris_execute` or a `SqlProc` wrapper) and skip the shell layer entirely.

## Common pitfalls

- **Editing settings in the production XML directly** in TEST/PROD instead of using Default Site Settings → values get blown away on next deploy.
- **Stop/Start when Update would do** → unnecessary downtime.
- **Restart-then-act without waiting for Running** → poll `Ens.Director.IsProductionRunning()` after every restart — see §"Hot-swap vs. restart" above.
- **Re-issuing an identical `start` after a refusal** → the refusal never clears on retry; the state must change first. See §"When the production will NOT start — the recovery ladder".
- **Probing credentials with `IDKeyExists()`** → the method does not exist; use `%OpenId()` + `$IsObject()` — see §"Probing for an existing credential" above.
- **Ignoring the rollback file** after a botched import → manual recovery is much harder.
- **Items disabled in DEV that get re-enabled by import** because the export captured them as `Enabled=true`.
- **Auditing `PoolSize=1` as a defect** → it's the correct default everywhere. Raise only with measured evidence.
- **Production XML edited by two people simultaneously** → merge conflicts in XML; coordinate via source control.
- **Forgetting custom utility classes** in the export bundle → import succeeds, runtime breaks.
- **Using `EnsLib.JavaGateway.Service` as a production item for JDBC** → deprecated in IRIS 2026.1; reference the ELS from the BO's `JGService` setting — see §"Default scaffolds" above.
- **Item name that breaks `Tipo.Nombre`** (`Java.Gateway`, `Censo`, `myBS`) → rename to fit the pattern (`Util.JavaGateway`, `BS.Censo`). Cosmetic but it affects portal grouping and search.
- **Missing `Ens.Alerts` router** → exceptions die in the Event Log with no fan-out — scaffold rule in §"Default scaffolds" above.
- **No purge task scheduled** → message tables grow forever; add `Ens.Util.Tasks.Purge` at creation time — see §"Default scaffolds" above.
- **Adding `Schedule=""` and `LogTraceEvents="false"` to every item** → those are defaults; setting them explicitly to the default value adds noise to the XML and to diffs. Leave them off.

## Testing / how to verify

1. After any production change, **Update** the production. Watch the Event Log for item-restart entries.
2. Confirm component status: each item should be green (running). Red = failed start; check the Event Log message and `OnInit()` validations.
3. After a deploy: smoke test by sending one canonical message through and using `message-search-debug` to confirm Visual Trace looks correct end-to-end.
4. After a deploy with Default Site Settings: confirm the runtime settings (Management Portal → Component → "Settings as currently applied") show the *target environment* values, not the source-environment values.

## When NOT to use this skill — fall back to docs

- Multi-namespace orchestration (cross-namespace messaging, cross-namespace deployments) — namespace-level patterns, not production-class patterns.
- HSMOD / HealthShare Modular deployments — different deploy machinery.

## See also

- `business-services` — adding a BS to the production
- `business-operations` — adding a BO to the production
- `bpl` — adding a BP / Message Router
- `message-search-debug` — verifying live behaviour after a change; purge task lives in the production
- `alerting` — alert circuit baseline (alert router + sink BO + monitor service)
- `hl7-schemas` — schema export discipline (NOT auto-exported)
- `security` — credentials, instance keys, namespace-level security boundaries
- `iris-interop` — naming convention (§1.1) and reserved packages (§1.2)
