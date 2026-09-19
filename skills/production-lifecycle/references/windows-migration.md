# Windows gotchas, HL7 schema export, and migration

Git on a shared dev IRIS, the ZPM install paradox, manual HL7 schema export, migrating a production between instances, `Ens.<X>` package shadowing, service accounts for UNC paths, Ensemble-vs-IRIS ports, and the `irissession` stdin gotcha. Read the part that applies; none of it is needed to build.

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

Failure to export is a silent loss-of-work risk on the next namespace refresh. See `hl7-schemas` §"Schemas are NOT auto-exported to source control" for the full risk discussion.

## Migration of interop productions

When migrating a production between IRIS instances (version upgrade, hardware refresh, container rebuild), these patterns prevent silent failures.

### Never auto-start a migrated production

Set `EnsembleAutoStart = 0` (or its IRIS equivalent) on the freshly migrated instance. The restored productions point at **real** endpoints — auto-starting them injects test traffic (or real traffic from yesterday's queue) into production systems. Validate each component's settings manually before enabling.

### Credentials migration

`Ens.Config.Credentials` records contain passwords encrypted with the **instance key** of the source system. Standard backup-restore preserves the records but renders the passwords unreadable in the target instance.

Pattern: write an ObjectScript utility that walks all `Ens.Config.Credentials` rows in the source, exports `(name, username, password)` to a file (treating the file as a secret), then re-imports them on the target. Worked example: `../assets/credentials-export-reimport.cls`.

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
| SuperServer | 1972 | 1972 |
| Web (Apache) | 57772 | 52773 |

The **SuperServer default did not change** — it is `1972` on both, and the authoritative value on any instance is the CPF `[Startup] DefaultPort` key (`##class(Config.Startup).Get()`, or read `iris.cpf` directly). Only the web port moved. Read the CPF rather than assuming: a container publishes the SuperServer on a *host* port (`0.0.0.0:43972->1972/tcp`, say), and that host-side number is not the instance's default.

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

