---
name: production-lifecycle
description: Production class, start/stop/update, deploy, settings. Triggers: production, producción, Ens.Production, start/stop, arrancar/parar, deploy, despliegue, System Default Settings, UpdateProduction, namespace.
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

The check is cheap, and it has to report **both** directions to earn the words "in sync":

**Gated, compiled and RUN:**
`assets/drift-report-disk-vs-namespace.cls`
(`Example.UTL.DriftReport`). It lived here as two **bare `ClassMethod`s**, so no tier compiled it —
which mattered more than usual, because its earlier form did not compile at all (see the first trap
below) and this is the one snippet this skill tells you to run at the end of every build.

Invoke it headlessly:

```
SELECT Example_UTL.DriftReport_DriftReport('<Pkg>', '<src dir as IRIS sees it>')
```

Both failure modes below were executed against the gated class: an unmounted `src` returned
`ONLY IN IRIS: <class>`, and a wrong package prefix returned **`in sync`** having compared nothing.


Run it before declaring a production done, and after any session that used the Management Portal
or a wizard — those write straight into the namespace and never touch disk.

**Two traps this snippet is written around, both measured on 2026.1 (#118):**

- **ObjectScript postconditionals end at the first space.** The earlier form of this helper wrote
  `Continue:$Extract(k, 1, n) '= (pPkg _ ".")` and did not compile —
  `#1012: Expected EOL or spaces : 'n) '='`. A postconditional argument must be unbroken:
  `Continue:$Extract(k,1,n)'=(pPkg_".")`. It is the one snippet this skill tells you to run at the
  end of every build, so it is the worst possible place for a parse error.
- **`%File` sees the IRIS host's filesystem, not yours.** When IRIS runs in a container,
  `pSrcDir` is a path *inside* the container. A source tree that is not mounted there reads as
  entirely missing, and the report says every class is `ONLY IN IRIS` — the alarming answer, for
  an environment reason. Check the mount before believing the output.

Verified end to end: `in sync` when the tree matches, `ONLY ON DISK: <pkg>.BO.Ghost` for a `.cls`
that was never compiled, and `ONLY IN IRIS: ...` when `pSrcDir` does not exist.

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


## `iris_doc(put)` and `iris_production_item` change the NAMESPACE only

Two of the most-used MCP calls write to IRIS and to nothing else:

| Call | Changes | Does **not** change |
|---|---|---|
| `iris_doc(mode=put, content=…)` | the class in the namespace | the `.cls` on disk |
| `iris_production_item(add/remove/enable/disable/set_settings)` | the production in the namespace | `Production.cls` on disk |

Neither is wrong — they are the right tools. What is wrong is stopping there, and **the feedback
loop will not tell you**, because the tests run against the namespace. The suite stays green while
the repo quietly stops reproducing what is running, and the divergence surfaces much later as a
CR-12 finding (#181 reported it twice in one session: the disk DTL was two assigns behind, and disk
`Production.cls` was still the single-router version).

So pair every one of them:

- **Authoring a class** → `Write` the file first, then `iris_doc(put)` the *same* content. The
  `src-before-iris` PreToolUse gate enforces that a file exists; the `src-drift-guard` PostToolUse
  guard warns when the content you put differs from it.
- **Changing the production** → after the item change, `iris_doc(mode=get)` the production class
  and `Write` it back to `src/`. Same for anything edited in the Portal.
- **Generated artefacts** (RecordMap `.Record`, SOAP `WSC.*`) → generate, then `iris_doc(mode=get)`
  → `Write`. This is the documented exception to file-first, not an exemption from disk.

Disk is the deliverable: the namespace is not version-controlled, not reviewable, and does not
survive the instance.


> **Compiled worked examples** of a production class, showing the Host-vs-Adapter setting split
> that causes most "the setting had no effect" reports: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch01_production/production-censo-intake.cls`
> (RecordMap file intake), `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch02_hl7v2/production-hl7-intake.cls` (HL7 + the HL7-specific
> router, CR-6), `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/production-sql-poll.cls` (JDBC poll + the mandatory
> `JGService` item). All three gated by `validate_examples --compile`.

## Creating the namespace — on IRIS for Health it is a FOUNDATION namespace

Before any of the lifecycle below applies, the namespace has to be the right KIND of namespace.
AFNS, opening line: *"Every interoperability-enabled production needs a special
interoperability-enabled namespace called a foundation namespace."*

```
# is it one? the table's EXISTENCE is the discriminator (AFNS section 1)
iris_query(namespace="<NS>", query="SELECT Name, Type, Activated FROM HS_Util_Installer.ConfigItem")
    Foundation -> a row, Type='Foundation', Activated=1
    plain      -> SQLCODE -30, Table 'HS_UTIL_INSTALLER.CONFIGITEM' not found

# create it, or CONVERT an existing one — the same call does both (AFNS sections 2 and 3)
iris_execute(namespace="HSLIB", code="Do ##class(HS.Util.Installer.Foundation).Install(""<NS>"")")
```

Three consequences for this skill specifically:

- **`Install()` creates a production** — `<NS>PKG.FoundationProduction`. So on a freshly created
  Foundation namespace `iris_production(action=status)` reports a production nobody wrote, and a
  `start` of *your* production can hit `<Ens>ErrProductionSuspendedMismatch` naming that one. It is
  a real production with a real class, so it is the `exists:true` branch of the recovery ladder —
  stop it by name, do not reach for `CleanProduction()`.
- **Conversion is in place and is the documented fix** for "we already have a namespace". You do
  not have to recreate it or move code.
- **Plain IRIS has none of this.** No `HS.*`, no Foundation concept — an interop-enabled namespace
  is all there is. Check which product you are on before applying any of it.

## Hot-swap vs. restart — when code changes don't take effect

A compiled change that has not taken effect is a hot-swap question, not a compile question:
see [references/hot-swap.md](references/hot-swap.md).

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
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="Router.Census" Category="MyApp" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">MyApp.RUL.RoutingCensus</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BO.SQL" Category="MyApp" ClassName="MyApp.BO.WriteCensusToSQL"
        PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="JGService">Util.JDBCGateway</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="Util.JDBCGateway" Category="MyApp" ClassName="EnsLib.JavaGateway.Service"
        PoolSize="1" Enabled="true" Comment="Points at the %JDBC Server External Language Server">
    <Setting Target="Host" Name="%gatewayName">%JDBC Server</Setting>
  </Item>

  <!-- Default scaffold: alerts router + file logger. Wired even before any rule exists. -->
  <Item Name="Ens.Alert" Category="MyApp" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">MyApp.RUL.Alerts</Setting>
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
- **`Item Name="Tipo.Nombre"`** — `BS.X`, `BO.X`, `Router.X`, `Util.X`, fixed `Ens.Alert`. Don't break the pattern (`Java.Gateway` looks like `Tipo.Nombre` but `Java` isn't a component type → rename to `Util.JavaGateway` or similar).
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

- **`Ens.Alert` router** (`EnsLib.MsgRouter.RoutingEngine`) wired as the alert target. Without it, exceptions land in the Event Log but don't fan out.
- **Alert sink BO** — at minimum a file logger (`EnsLib.File.PassthroughOperation` writing to a dedicated alerts directory). Optional email BO (`EnsLib.EMail.OutboundAdapter`) for prod.
- **`Ens.Util.Tasks.Purge` task** scheduled daily. Persistent messages accumulate forever otherwise; the message-class table grows unbounded. Set `NumDaysToKeep` per retention policy (typically 30–90).
- **External Language Server reference** when JDBC is in use — the BO's `JGService` setting points to an `EnsLib.JavaGateway.Service` **item in the same production**, whose `%gatewayName` is the ELS name (`%JDBC Server` is the IRIS-shipped default). That item is **required, not optional and not deprecated**: ESQL §2.1 *"Adding the Java Gateway Service (for JDBC)"* prescribes it, and ESQL §3.1 marks `JGService` **IMPORTANT** — *"required for all JDBC data sources, even if you are using a working SQL gateway connection with JDBC. For JDBC connections to work, a business service of type `EnsLib.JavaGateway.Service` must be present."* The scaffold above ships exactly that item; keep it.

  > **A JDBC BO needs `JGService` pointing at a Java Gateway item in the same production.** Without
  > it the BO terminates at startup, and the error is an `<INVALID OREF>` inside
  > `EnsLib.JavaGateway.Common` that never mentions the gateway, the item, or `JGService` — so it
  > reads as a broken gateway and sends you rebuilding one that was never broken. 22 gateway
  > failures across 9 of 14 students in one day, 19 of them in sessions where the plugin was
  > loaded and working. See `business-operations` §"Headless verification".

  *(An earlier release of this skill called the item "deprecated in IRIS 2026.1". That claim was
  unsourced, contradicted `business-operations`, and contradicted the scaffold in this same file.
  Checked against the IRIS for Health documentation corpus: "deprecat*" appears 249 times across
  47 files and **none** of it attaches to the Java Gateway, while ESQL still flags the item
  IMPORTANT and required. Removed — #225.)*

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
| **Restart item** | Single component restart — `iris_production(action=restart, item="<Item>")`; `item` is required. | Targeted setting change, **or a recompile of that one host's class**, without disturbing the rest. |

`Update` is the workflow — it's almost always what you want during dev. Full Stop/Start is heavier and slower.

## When the production will NOT start

There is a recovery ladder and the order matters:
see [references/wont-start.md](references/wont-start.md).

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

## Windows, HL7 schema export, and migration

Git on a shared dev IRIS, the ZPM paradox, manual HL7 schema export (HIGH severity), migrating a
production, `Ens.<X>` shadowing, UNC service accounts, Ensemble-vs-IRIS ports, and the
`irissession` stdin gotcha: see [references/windows-migration.md](references/windows-migration.md).

## Common pitfalls

- **Editing settings in the production XML directly** in TEST/PROD instead of using Default Site Settings → values get blown away on next deploy.
- **Stop/Start when Update would do** → unnecessary downtime.
- **Restart-then-act without waiting for Running** → poll `Ens.Director.IsProductionRunning()` after every restart — see §"Hot-swap vs. restart" above.
- **Re-issuing an identical `start` after a refusal** → the refusal never clears on retry; the state must change first. See [references/wont-start.md](references/wont-start.md).
- **Answering `ErrProductionSuspendedMismatch` with `recover`** → `recover` is for `ErrProductionNotShutdownCleanly`. On a **suspended** production it reports success and changes nothing — EGDV §12.3: *"If the production is not Troubled, the method simply returns."* Watch for the giveaway: `action=recover` answering `{"state":"Running","success":true}` on a production that `action=status` reports `Suspended` seconds later. That is the documented no-op, not a fixed production.
- **Probing credentials with `IDKeyExists()`** → the method does not exist; use `%OpenId()` + `$IsObject()` — see §"Probing for an existing credential" above.
- **Ignoring the rollback file** after a botched import → manual recovery is much harder.
- **Items disabled in DEV that get re-enabled by import** because the export captured them as `Enabled=true`.
- **Auditing `PoolSize=1` as a defect** → it's the correct default everywhere. Raise only with measured evidence.
- **Production XML edited by two people simultaneously** → merge conflicts in XML; coordinate via source control.
- **Forgetting custom utility classes** in the export bundle → import succeeds, runtime breaks.
- **OMITTING the `EnsLib.JavaGateway.Service` item when a BO uses a `jdbc:` DSN** → the BO does not merely fail to connect, it terminates at startup with an `<INVALID OREF>` inside `EnsLib.JavaGateway.Common` that names neither the gateway nor `JGService`. The item is required (ESQL §2.1, §3.1) and `JGService` must match its name character for character — see §"Default scaffolds" above.
- **Item name that breaks `Tipo.Nombre`** (`Java.Gateway`, `Censo`, `myBS`) → rename to fit the pattern (`Util.JavaGateway`, `BS.Censo`). Cosmetic but it affects portal grouping and search.
- **Missing `Ens.Alert` router** → exceptions die in the Event Log with no fan-out — scaffold rule in §"Default scaffolds" above.
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
- `interop` — §"Naming convention" and §"Reserved package names"
