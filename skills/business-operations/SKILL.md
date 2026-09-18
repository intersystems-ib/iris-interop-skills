---
name: business-operations
description: BO outbound - SQL/JDBC, TCP, HTTP, REST, file. Routed from interop. Triggers: Business Operation, BO, outbound, salida, SQL/JDBC, TCP, HTTP, REST, file, OutboundAdapter, enviar datos.
---

# Business Operations — outbound endpoints

A Business Operation is the boundary where data leaves the production. One BO = one destination (one IP/port, one FTP server, one directory, one SQL gateway). Routing decisions happen *before* the BO; the BO just sends.

## When to use this skill

The user wants to send data out: write files, push HL7 over TCP/MLLP, call a SOAP/REST endpoint, insert/update a SQL row, post to a queue.

## Decision tree

```
What's the destination?
├── A %Persistent table IN THIS namespace → custom BO, NO adapter, just %New()/%Save()
├── An EXTERNAL/foreign database → EnsLib.SQL.OutboundAdapter or JDBC variant
│       BO method calls the gateway and runs parameterized SQL
├── HL7 v2.x over TCP/MLLP → EnsLib.HL7.Operation.TCPOperation
├── HL7 v2.x to file → EnsLib.HL7.Operation.FileOperation
├── SOAP web service → use the soap-bo skill (SOAP wizard from WSDL)
├── REST endpoint → custom BO + EnsLib.REST.OutboundAdapter (or HTTP.OutboundAdapter)
├── Plain file → EnsLib.File.OutboundAdapter
└── Custom protocol → custom BO extending Ens.BusinessOperation
```

### Persisting locally: object `%Save()` vs the SQL adapter

When the destination is a `%Persistent` class **in the same namespace as the production**, the cleanest BO has **no adapter at all** — its MessageMap method just does `Set obj = ##class(App.Data.X).%New()`, copies fields, `Set sc = obj.%Save()`. Fewer moving parts, directly unit-testable (`EnsLib.Testing.Service.SendTestRequest` → BO → assert the row), no JDBC/ELS plumbing.

Reach for `EnsLib.SQL.OutboundAdapter` (JDBC) **only when the table lives in a foreign/external database** (PostgreSQL, Oracle, a different IRIS namespace reached as a DSN). The adapter exists to cross a process/DB boundary; using it to write a table you could open as an object in-process is needless complexity. (Flow A of a hub persists `Order` locally via object save; Flows that sync to an external PostgreSQL use the SQL adapter — same project, different choice driven by where the table lives.)

## Canonical pattern — custom BO for a typed request

```objectscript
Class MyApp.BO.WriteCensusToSQL Extends Ens.BusinessOperation
{
Parameter ADAPTER = "EnsLib.SQL.OutboundAdapter";
Parameter INVOCATION = "Queue";

/// Re-declare Adapter with the concrete type so `..Adapter.<method>` resolves to the
/// adapter's own API instead of the generic Ens.OutboundAdapter.
Property Adapter As EnsLib.SQL.OutboundAdapter;

XData MessageMap
{
<MapItems>
  <MapItem MessageType="MyApp.Msg.PatientCensusRequest">
    <Method>InsertCensus</Method>
  </MapItem>
</MapItems>
}

Method InsertCensus(pRequest As MyApp.Msg.PatientCensusRequest, Output pResponse As Ens.Response) As %Status
{
    Set tSQL = "INSERT INTO Menus (PatientId, AdmissionDate, Department) VALUES (?, ?, ?)"
    Set tSC = ..Adapter.ExecuteUpdate(.tRows, tSQL, pRequest.PatientId, pRequest.AdmissionDate, pRequest.Department)
    If $$$ISERR(tSC) Quit tSC
    Set pResponse = ##class(Ens.Response).%New()
    Quit $$$OK
}
}
```

Key elements:
- **`INVOCATION` on a BO is `"Queue"` — not the BP's `"Queued"`.** The parameter is valid on a
  Business Operation; the *value vocabulary* differs from `Ens.BusinessProcess` (`InProc` /
  `Queued`). Copying a BP template verbatim yields `<Ens>ErrParameterInvocationInvalid`, which
  reads as "this parameter doesn't belong here" and sends you to delete the line — when the fix
  is one letter.
- `MessageMap` dispatches the right method per incoming request type.
- `Adapter.*` calls do the protocol work; the method does the message-shape work.
- Always parameterize SQL — never concatenate values.
- **One bind argument per `?`, in order.** Pass each field as its own argument — `ExecuteUpdate(.rows, sql, f1, f2, f3)`, not the whole record as one string. Binding a delimited row (`"1|Yu,Sophia|977-…"`) into a single `?` makes the driver try to coerce the entire blob to the first column's type and fails with e.g. `NumberFormatException: For input string "1|Yu,Sophia|…"`. If the request is a RecordMap record, bind its **properties**, not the raw line.
- Return a typed response if the BP cares; otherwise plain `Ens.Response`.

## SOAP BOs — see the dedicated skill

If the destination is a SOAP web service, **stop and use `soap-bo`** instead. It covers the SOAP Wizard, %SerialObject vs %Persistent payload decision, the delete trigger, and the recursive-CDA pattern. This skill stays focused on non-SOAP BOs.

## Adapter settings worth knowing

| Setting | Effect |
|---|---|
| `PoolSize` | Concurrent BO instances. **Default `1` is correct** — only raise with evidence of a bottleneck (queue depth, latency). >1 means messages out of order; only acceptable if the destination tolerates it. |
| `Credentials` | Reference to a credential record (don't put passwords in settings directly). |
| `ReplyCodeActions` | For HL7 ACK handling — what to do on AE/AR/CE/CR. |
| `DSN` (SQL) | JDBC URL (`jdbc:postgresql://...`) **or** the name of a SQL Gateway connection — see §"JDBC outbound" for how each is wired. |
| `JGService` (SQL/JDBC) | Name of the `EnsLib.JavaGateway.Service` item the adapter routes through, whose `%gatewayName` names an **External Language Server** (`%JDBC Server` or a custom one). **Required for any `jdbc:` DSN** — the BO terminates at startup without it. |
| `LogTraceEvents` | Per-item toggle for `$$$TRACE` calls. Default off in prod, on in dev. `$$$LOGINFO`/`$$$LOGWARNING` are not gated by this. |
| Stay-alive / reconnect | TCP/SOAP — controls whether the BO holds the connection open. |

## File output — two `%File` API traps

When creating the directory a file BO writes into (or checking its output from a test):

- Use `##class(%File).CreateDirectoryChain(dir)` for any path whose parents may not exist.
  `CreateDirectory` creates **one** level only, and on failure returns a bare `0` — not a
  `%Status`, so there is no error text to read; a missing intermediate directory fails silently.
- The existence tests are `##class(%File).Exists(file)` and `##class(%File).DirectoryExists(dir)`.
  There is no `%File.FileExists` — calling it fails as `<METHOD DOES NOT EXIST>`, easy to misread
  as a read-only filesystem when it is just a wrong method name.

## Error handling and retry policy

`If $$$ISERR(tSC) Quit tSC` propagates every error the same way. That's almost never what you want — transient errors (timeout, connection drop) should retry; permanent errors (constraint violation, schema mismatch, auth failure) should suspend and alert.

The BO item exposes a **`RetryInterval`** / **`FailureTimeout`** pair plus the `OnError`/`OnFailureTimeout` callbacks. For finer control, configure per-error-number actions in the item settings (Management Portal → Settings → "Reply Code Actions" for HL7, or override `OnError` for custom mapping):

```
Transient (retry):           timeout, connection-lost, gateway-down
Permanent (suspend + alert): constraint violation, schema mismatch, bad credentials, type marshalling
Skip-and-log:                genuinely-bad input that the upstream BS should have rejected
```

A poison message under "retry on anything" will spin forever and block the queue. Default to **suspend on unknown errors** and graduate to retry only for codes you have classified.

### `Failure Timeout = -1` means infinite retries — never ship this

Some HL7 BO classes default `Failure Timeout` to `-1`, which means **retry indefinitely**. Always override to a finite value before deploying.

Without a finite timeout, in-flight retries against an unreachable target accumulate forever. They consume queue slots, block downstream processing, and the only signal is "the queue is growing." A finite timeout (`60` seconds for fast-cycle integrations, up to a few hours for batch flows) causes the BO to give up and suspend, which surfaces as an alert and lets operations decide.

### Timeout precedence — BO timeouts MUST be smaller than calling BP

A BO's `Response Timeout` and `Failure Timeout` MUST be strictly smaller than the calling BP's wait timeout — whoever times out first owns the error context, and only a BO-first timeout carries diagnostic detail up the chain. Set BO timeouts last, after the calling BP's timeout is fixed. Mechanism and the BP-side view: see `bpl` §"Timeout precedence".

### `ReplyCodeActions` defaults can swallow application errors (HL7 BO)

The default HL7 BO `ReplyCodeActions` (`:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C`) leaves application-level errors as **Suspended** messages — so an integration that intentionally returns negative ACKs drowns operators in suspended messages. For HL7 BOs whose calling BP wants to inspect the ACK/NACK itself, override to:

```
:?R=C,:?E=C,:~=C,:?A=C,:*=C,:I?=C
```

This **Completes** the message regardless of reply code; the BP receives the response and decides. Symbol meanings + full decision matrix: see `alerting`.

## Transactions — single row vs batch

| Scenario | Pattern |
|---|---|
| **One row per message** (typical) | No explicit transaction. `..Adapter.ExecuteUpdate(...)` commits under the driver's autocommit; if it fails, the message is suspended and can be resent. |
| **Multiple rows per message** (batch) | **`..Adapter.SetAutoCommit(0)`** → loop `ExecuteUpdate` → `..Adapter.Commit()` on success, `..Adapter.Rollback()` on any failure → `SetAutoCommit(1)` to restore. **Turning autocommit off IS the transaction start — there is no `StartTransaction()`.** Verified on 2026.1: the adapter's whole transaction API is `SetAutoCommit` / `Commit` / `Rollback` (`%Dictionary.CompiledMethod`, parent `EnsLib.SQL.OutboundAdapter`). `..Adapter.StartTransaction()` fails at runtime with `<METHOD DOES NOT EXIST>`; an earlier revision of this skill prescribed it. `SetAutoCommit` connects first if the adapter is cold, so it is safe to call in `OnMessage`. |

> **There is no `Finally` in ObjectScript.** The block after `Catch` is the pseudo-finally and it
> only runs if the `Catch` does not `Quit` early — a `Quit` there leaves the transaction **open on
> a connection that outlives the message** (`StayConnected`), and the next message inherits it.
> Restore autocommit in that block, guard it with a flag set only after `SetAutoCommit(0)`
> succeeded, and do not overwrite your `%Status` with the rollback's own.

> **`ConnectionAttributes` has two syntaxes and the wrong one fails silently.** ODBC takes
> `attr:val,attr:val` (e.g. `AutoCommit:1`); **JDBC takes `attr=val;attr=val`** (e.g.
> `TransactionIsolationLevel=TRANSACTION_READ_COMMITTED`). The `:`/`,` parsing loop in
> `EnsLib.SQL.Common` sits inside `If '..%Connection.%Extends("EnsLib.SQL.CommonJ")` — **ODBC
> only**. On JDBC the string is passed through unparsed to `connectWithPropString`, so ODBC syntax
> on a JDBC connection becomes an unrecognised driver property and is **ignored**. Field-observed:
> `ConnectionAttributes=AutoCommit:1` sat on dozens of production items running an Oracle JDBC
> driver for years, doing nothing — harmless only because it asked for the default the driver
> already had.
| **Oracle JDBC** | Set `AutoCommit=true` on the adapter even for single-row work. Oracle treats SELECT as transactional by default and connections can hang on idle transactions otherwise. |

## Idempotency — let the remote constraint do the work

A BO that does `INSERT INTO Menus VALUES (?)` with `paciente_id` as PK is **not idempotent**: re-running the same input violates the unique constraint and fails. That is **the correct behaviour by default** — re-runs surface as alerts to the operator, which is exactly what you want for "did we accidentally re-process yesterday's CSV?".

Switch to UPSERT (`INSERT ... ON CONFLICT (paciente_id) DO NOTHING` / `DO UPDATE SET ...`) **only when** re-runs are part of the normal flow (retry-safe ingestion pipelines, eventually-consistent feeds). Don't add UPSERT preemptively "for safety" — it hides the re-run signal.

## Common pitfalls

- **`##class(Pkg.BO.X).%New()` to test the operation directly** → a BO does not instantiate. `Ens.BusinessOperation` declares no `%New`; a subclass returns `""`, and the error surfaces a line later as `<INVALID OREF>`. The adapter beside it *does* instantiate, which makes the BO look like the broken one. See `tdd` §"Pitfalls specific to Interop TDD".
- **Concatenating values into SQL strings** instead of parameterizing → injection + escaping bugs.
- **Writing SQL from an assumed table name, then guessing again on `-30`** → see §"Resolve real table names BEFORE the first query" above.
- **Forgetting `MessageMap`** → every request hits the default `OnMessage` method which then has to dispatch by type manually.
- **PoolSize > 1 with order-sensitive HL7 receivers** → out-of-order delivery breaks downstream state.
- **Hardcoding URLs/credentials** instead of using settings + credentials records → environment-specific deploys fail.
- **No timeout on HTTP/REST outbound** → a hung remote endpoint blocks the BO pool indefinitely.
- **Auditing a non-idempotent BO as a defect** when the remote table has a PK preventing duplicates → see "Idempotency" above; the constraint is the contract, not the bug.
- **Stripping `$$$LOGINFO(...)` from the BO method because it's "noisy in prod"** → keep the log calls; toggle them off via the item's `LogTraceEvents` setting (or by environment) instead of editing the code. Verbosity is an operator decision, not a source-code one.
- **`$ZDATE`/`$ZTIME` reformatting in the BO** when the DTL already produced a typed `%Date`/`%TimeStamp` → bind the typed property directly; the SQL adapter handles the ODBC representation conversion to the driver type. Re-formatting in the BO is redundant work and creates a second place for date logic to drift.

## Testing / how to verify

1. Compile via the MCP server.
2. Add to production. Configure adapter settings (DSN, URL, credentials).
3. From the Management Portal "Test" link on the BO, send a sample message. Or invoke from a Message Router.
4. Use `message-search-debug` Visual Trace — confirm the BO received, attempted, and got an ACK/response from the destination.
5. Negative test: stop the destination. Confirm the BO retries per its configured retry policy and surfaces a clear error.

### Headless verification — no Portal, no Test link

Step 3 above needs the Portal, which an agent does not have. Drive the **adapter** instead: the BO
itself does not instantiate (`%New()` on a BO subclass returns `""` — see `tdd`), but
`##class(EnsLib.SQL.OutboundAdapter).%New()` is the supported way to exercise the same settings
headlessly.

**Precondition for a `jdbc:` DSN, and it is the one that bites:** the production must be **running**
and must contain an `EnsLib.JavaGateway.Service` item whose name matches `JGService` character for
character. `JGService` is required for all JDBC data sources, and the adapter *reuses that item's
settings* to reach the JVM (ESQL §3.1). Without it:

```
<INVALID OREF> 192 initAdapterJG+2^EnsLib.JavaGateway.Common.1
```

That frame names neither your BO nor the adapter, so it reads as "the gateway is broken" and sends
you rebuilding the gateway. Read it as **"I cannot find the JGService item"**. Filling `..BusinessHost`
by hand does not help: `##class(EnsLib.Testing.Service).%New()` is a Business Service and returns `""`.

Wrap the probe in a `[SqlProc]` and invoke it with `iris_query` (for the SQL function name see
`interop` §"Calling a `[SqlProc]` — the name is not the class name"):

```objectscript
/// Headless probe of the SAME adapter settings BO.WriteCensus uses.
/// Requires the production RUNNING with an EnsLib.JavaGateway.Service item named
/// exactly as JGService below (ESQL §3.1).
ClassMethod ProbeMenus() As %String [ SqlProc ]
{
    Set ada = ##class(EnsLib.SQL.OutboundAdapter).%New()
    Set ada.DSN           = "jdbc:postgresql://localhost:5432/Cocina"
    Set ada.JDBCDriver    = "org.postgresql.Driver"
    Set ada.JDBCClasspath = "C:\jdbc\postgresql-42.7.4.jar"
    Set ada.Credentials   = "CocinaAppCredentials"      // Ens.Config.Credentials record
    Set ada.JGService     = "Util.JDBCGateway"          // the production ITEM name, not "%JDBC Server"
    Set tSC = ada.OnInit()
    Quit:$$$ISERR(tSC) "OnInit: "_$SYSTEM.Status.GetErrorText(tSC)
    Set tSC = ada.ExecuteQuery(.rs, "SELECT COUNT(*) AS n FROM public.menus")
    If $$$ISERR(tSC) {
        Do ada.Disconnect()
        Quit "ExecuteQuery: "_$SYSTEM.Status.GetErrorText(tSC)
    }
    Set n = $Select(rs.Next(.tSC): rs.Get("n"), 1: "?")   // EnsLib.SQL.GatewayResultSet, ESQL §9.3-9.4
    Do ada.Disconnect()
    Quit "rows="_n
}
```

Same shape with `ExecuteUpdate(.rows, "DELETE FROM …")` for fixture cleanup between test runs.
`Disconnect()` is the documented adapter method for closing the connection — call it on both paths.

## Resolve real table names BEFORE the first query — introspect, don't guess

Any SQL a BO (or its verification step) touches goes through this gate: **before the first
`iris_query` / SQL statement against a table you did not create in this session, resolve the real
name** — `iris_table_info(table=…)`, or spawn `Agent(subagent_type="iris-interop-skills:introspect-dont-guess")` (an
agent, not a skill; with no agent tool, this section plus `interop` §"Resolving real names" is the
recipe). Never write the query from an assumed name.

Measured over a workshop cohort: `iris_query` returned `SQL_ERROR` **127 times across 17/18
students**, dominated by invented object names — and the recovery pattern made it worse: guess →
`SQLCODE -30 Table not found` → guess a *different* name → `-30` again (or `-12`, malformed SQL
written from the same guess), without ever calling the catalog. One introspection call would have
answered each of these.

The two most-guessed-wrong families:

- **Projected child tables.** A collection property (`Property Alergias As list Of %String` on
  `COCINA.MSG.MenuRecibido`) projects to a child table **in the parent's schema**:
  `COCINA_MSG.MenuRecibido_Alergias`. Guessing `COCINA.MenuRecibido_Alergias` (wrong schema) cost
  one cohort 12 straight failures. The scheme is predictable — which is exactly why
  `iris_table_info` answers it in one call. See `messages` (Collections) for the projection rule.
- **Names that are not the table you want.** `%Library.SQLConnection`, `Config.config`,
  `Ens_Config.Setting` — querying these fails. Two different reasons, and the difference matters:
  `Config.config` and `Ens_Config.Setting` are not tables at all (typed tools instead —
  `check_config`, `iris_production_item`, `iris_interop_query`; `message-search-debug` has the full
  table). `%Library.SQLConnection` **is a real class**, and its definitions **are** a real table —
  just not under the class name and not in this namespace: `%Library.sys_SQLConnection`, in `%SYS`.
  See §"Diagnose a named SQL Gateway connection without the Portal" below.

**On `-30 Table not found`, the NEXT call is introspection — never another guessed name.**

> **Compiled worked examples**: typed parameters and NULLs via `ExecuteUpdateParmArray` at
> `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/sql-bo-typed-parmarray.cls`; the inbound side, with the mandatory
> `EnsLib.JavaGateway.Service` item wired, at `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/production-sql-poll.cls`.

## JDBC outbound — wiring checklist

A JDBC-backed BO needs more than just a `DSN` setting; the full path from class to database touches the JVM, the External Language Server, and four BO settings that must align. Missing one piece produces opaque errors ("Java gateway not started", "no driver found", "no suitable driver"). Validate the checklist before debugging code.

### `DSN` takes EITHER a direct `jdbc:` URL OR a named SQL Gateway connection

**Default to the direct `jdbc:` URL in `DSN`.** The whole connection then lives in the production
XML, under source control, with nothing to configure per-environment by hand and nothing to
pre-create. Reach for a **named connection** only when several BOs share one database, or when the
credentials/classpath are managed centrally by an administrator.

Both work, so pick one deliberately — the failure mode of mixing them is a connection error that
names your connection and then shows an empty URL:

| `DSN` value | What it means | Verified |
|---|---|---|
| `jdbc:postgresql://host:5432/db` | a **direct JDBC URL**. Nothing to pre-create; pair it with `JDBCDriver` + `JDBCClasspath` on the BO. | ✅ works |
| `MyConnection` | the **name of a SQL Gateway connection** (`%Library.SQLConnection`, Portal → System Administration → Configuration → Connectivity → SQL Gateway Connections), which carries the URL, driver and classpath centrally. | ✅ works |

**If you use a named connection, the `jdbc:` URL goes in its `URL` property — NOT in its `DSN`
property.** A JDBC gateway connection is shaped:

```
isJDBC    = 1
URL       = "jdbc:postgresql://host:5432/db"    <- the URL lives HERE
DSN       = ""                                   <- empty for JDBC
driver    = "org.postgresql.Driver"
classpath = "/opt/jdbc/postgresql-42.x.jar"
Usr / pwd = credentials
```

Put the URL in the connection's `DSN` and leave `URL` empty and the BO fails with the URL missing
from its own error message — the giveaway is the empty `jdbc://`:

```
ERROR <Ens>ErrOutConnectFailed: JDBC Connect failed for 'MyConnection' (jdbc://) / 'MyCreds'
  with error ERROR #5023: Remote Gateway Error: JDBC Gateway connection failed for jdbc://
```

Read `(jdbc://)` as "the connection I found has no URL", not as "the URL is wrong".

### Diagnose a named SQL Gateway connection without the Portal

**Hard rule first: when a call dies with `<CLASS DOES NOT EXIST>` / `<METHOD DOES NOT EXIST>` /
`<PROPERTY DOES NOT EXIST>`, the NEXT call is
`docs_introspect(class_name="<Class>", namespace="%SYS")` — never another guessed name.**
Everything below is documented (BSQG §2 and §2.1; Technical Reference, "%SQLConnection class");
anything about SQL Gateway connections that is *not* below is a guess. This section exists because
the vacuum where it used to be produced 101 blind probe calls across 11 of 14 people in one day —
`%Library.SQLGatewayConnection`, `%SYSTEM.SQL.Gateway.CreateConnection`, `SYS.SQLGateway`,
`Config.SQLGatewayConnections`, `Config.Gateways.Classpath`, and finally `$query` over `^%SYS`.

The definitions ARE a table — but not under the class name, and only in `%SYS`:

```
iris_query(namespace="%SYS", query="SELECT * FROM %Library.sys_SQLConnection")
```

`%SQLConnection` (full name `%Library.SQLConnection`) is the CLASS; `%Library.sys_SQLConnection` is
the TABLE — BSQG §2: *"These connections are stored in the table `%Library.sys_SQLConnection`."*
`SELECT … FROM %Library.SQLConnection` is the query that returns `SQLCODE -30`. The column list is
not published: read it off the first row, or
`iris_table_info(table="%Library.sys_SQLConnection", namespace="%SYS")`.

From ObjectScript (`iris_execute`, `namespace="%SYS"`):

```objectscript
// Does a connection with this logical name exist?  (%SQLConnection — Technical Reference)
Write ##class(%SQLConnection).ConnExists("<ConnName>"), !

// Test it. Writes the driver's own diagnostics to the current device. (BSQG §2.1)
Do $SYSTEM.SQLGateway.TestConnection("<ConnName>")

// Drop a stale open connection before re-testing. (BSQG §2.1)
Do $SYSTEM.SQLGateway.DropConnection("<ConnName>")
```

Connection names are **case-sensitive** (BSQG §2.1). `%SQLConnection` also publishes the class
queries `ByName()` and `ByConnection()`; their call spelling and arguments are not published, so
resolve them with `docs_introspect(class_name="%SQLConnection", namespace="%SYS")` against the
running version before calling them.

**Creating one from code is deliberately not published here.** The documented creation path is the
Portal (BSQG §2, §5.1 "Defining a Logical Connection in the Management Portal"). The
`isJDBC`/`URL`/`driver`/`classpath` block above describes the object; it is **not** a verified
`%New()`/`%Save()` contract, and hand-rolling one is how the spiral starts. With no Portal, use the
direct `jdbc:` URL form — it needs nothing pre-created.

### NOT a pre-created ODBC DSN

Do **not** route an external-DB BO through an ODBC System DSN — that path produces an un-winnable spiral:

```
ERROR #6022: Gateway failed: SQLConnect ... SQLState (IM002)
             Data source name not found and no default driver specified
```

`IM002` means the OS has no ODBC DSN by that name (and configuring one is host-specific, fragile, and invisible to source control). The JDBC adapter does not need it: point `DSN` at the `jdbc:` URL, set `JDBCDriver` + `JDBCClasspath` (the quartet below), and the gateway connects directly. If you ever see `#6022 (IM002)`, stop — you're on the ODBC path; switch to the JDBC URL rather than trying to create the DSN.

### Prerequisites (one-time per host)

| Item | Verify |
|---|---|
| **JDK installed** | JDK 8 / 11 / 17 / 21 (matching the IRIS-supported list for your version). `java -version` on the host. |
| **`JAVA_HOME` or `Config.Gateways.FilePath`** | Either `$env:JAVA_HOME` set, or the `%JDBC Server` ELS configured with `FilePath` pointing at the JDK install (Management Portal → System Administration → Configuration → Connectivity → External Language Servers). |
| **ELS running** | `%JDBC Server` (default port `53772`). **A `EnsLib.JavaGateway.Service` item in the production starts it for you** — verified: `IsGatewayRunning("%JDBC Server")` goes 0 → 1 on production start, and the BO then connects without anyone calling `StartGateway`. That is **necessary, not sufficient**: the adapter still has to resolve that item by the exact `JGService` name, in a **running** production (ESQL §3.1) — see §"Headless verification" below for what it looks like when it cannot. You only start it by hand (`##class(%Net.Remote.Service).StartGateway("%JDBC Server",.pid)`) when there is no such item. Check with `##class(%Net.Remote.Service).IsGatewayRunning("%JDBC Server")`; smoke test on Windows: `netstat -ano \| findstr :53772`. |
| **JDBC driver JAR** | Driver JAR copied to a stable filesystem path the IRIS service account can read (e.g. `C:\jdbc\postgresql-42.x.jar`). |

### BO settings — the quartet

| Setting (`Target="Adapter"`) | Value | Notes |
|---|---|---|
| `DSN` | `jdbc:postgresql://host:5432/dbname`, **or** the name of a SQL Gateway connection | Direct JDBC URL needs no pre-created connection. For the named form, see the section above — the URL goes in the connection's `URL`, not its `DSN`. |
| `JGService` | Name of a **`EnsLib.JavaGateway.Service` item in the same production** (e.g. `Util.JDBCGateway`, whose `%gatewayName="%JDBC Server"`) | **Mandatory, not optional.** Without it the BO does not merely fail to connect — it *terminates at startup*: `ERROR <Ens>ErrGeneral: The JGService setting must be configured in order for this Adapter to work with a JDBC DSN : jdbc:…`. The item also starts the ELS. |
| `JDBCDriver` | `org.postgresql.Driver` (or vendor equivalent) | Fully-qualified Java class name. |
| `JDBCClasspath` | `C:\jdbc\postgresql-42.x.jar` | The exact JAR file path. Multiple JARs: separate with `;` (Windows) or `:` (Unix). |
| `Credentials` | Name of an `Ens.Config.Credentials` record | Reference, not inline. Credential record points at a `BusinessPartner` for documentation. |

> **The path goes in the Setting, not in the `.cls`.** `FilePath`, `Filename` and `JDBCClasspath`
> are adapter settings of the **production item** (ESQL §3.1), so a literal `C:\…` or `/tmp/…`
> inside a BS/BO/BP/DTL class is a CR-10 finding. Bootstrap/`UTL` helpers and `%UnitTest` fixtures
> are exempt — they have no production item, hence no Setting, and a fixture must name a real file
> on the server.

### `Credentials` + `BusinessPartner` linkage

Don't create a `Credentials` record in isolation. The expected order is:

1. **Check if `Ens.Config.Credentials` for this endpoint already exists** — duplicates are silent footguns.
2. **Create `Ens.Config.BusinessPartner`** with `Description` (which BO/endpoint this serves) and `PrimaryContact`. Documentation lives **here**, not on `Credentials`.
3. **Create `Ens.Config.Credentials`** with `BusinessPartner` pointing at the BP from step 2, plus `Username` / `Password`.

The BP is the documentation anchor; `Credentials` is just the secret holder. Auditing a project: missing `BusinessPartner` references on `Credentials` rows is a code-quality flag.

### Worked example — PostgreSQL outbound

```xml
<Item Name="BO.WriteCensus" Category="MyApp" ClassName="MyApp.BO.WriteCensusToSQL"
      PoolSize="1" Enabled="true">
  <Setting Target="Adapter" Name="DSN">jdbc:postgresql://localhost:5432/Cocina</Setting>
  <Setting Target="Adapter" Name="JGService">Util.JDBCGateway</Setting>
  <Setting Target="Adapter" Name="JDBCDriver">org.postgresql.Driver</Setting>
  <Setting Target="Adapter" Name="JDBCClasspath">C:\jdbc\postgresql-42.7.4.jar</Setting>
  <Setting Target="Adapter" Name="Credentials">CocinaAppCredentials</Setting>
</Item>

<Item Name="Util.JDBCGateway" Category="MyApp" ClassName="EnsLib.JavaGateway.Service"
      PoolSize="1" Enabled="true">
  <Setting Target="Host" Name="%gatewayName">%JDBC Server</Setting>
</Item>
```

That item is **required, not a legacy wrapper.** ESQL §2.1 *"Adding the Java Gateway Service (for JDBC)"* prescribes adding it to the production, and ESQL §3.1 marks `JGService` **IMPORTANT** — *"required for all JDBC data sources, even if you are using a working SQL gateway connection with JDBC. For JDBC connections to work, a business service of type `EnsLib.JavaGateway.Service` must be present."* Its `%gatewayName` is what points it at the ELS; the BO reaches the ELS **through** the item, not instead of it.

## JDBC type marshalling — gotchas

When binding parameters to `EnsLib.SQL.OutboundAdapter.ExecuteUpdate()` (or any JDBC outbound), the driver translates the ObjectScript value to the column's SQL type. A few translations fail silently or with cryptic messages:

| ObjectScript value | Bound to column type | Result |
|---|---|---|
| `%Date` integer (e.g. `52798`) | `DATE` (PostgreSQL/Oracle) | `StringIndexOutOfBoundsException: begin 0, end 10, length 5` — the driver tries to parse the integer as `YYYY-MM-DD`. **Fix**: convert in the BO with `Set bound = $ZDATE(req.FechaNacim, 3)` before passing to `ExecuteUpdate`. |
| `%TimeStamp` `"2026-05-13 07:13:59"` | `TIMESTAMP` | Usually works; JDBC accepts space separator. Use `T` separator (`$TRANSLATE(...,"  ","T")`) if the column is `xs:dateTime` schema-bound. |
| Empty string `""` | nullable column | Driver inserts an empty string, not NULL — and `$S(val="":"", 1:val)` does **not** help, it still passes `""`. **Fix: bind with an explicit SQL type** via `ExecuteUpdateParmArray`, so the driver is told the column is a `DATE`/`NUMERIC` and an empty value lands as a typed NULL instead of a VARCHAR it must coerce. See §"Typed SQL parameters" below. (There is **no** `ExecuteUpdateNull` method — verified against `%Dictionary.CompiledMethod` on 2026.1, the adapter declares exactly six `Execute*` methods: `ExecuteQuery`, `ExecuteUpdate`, `ExecuteProcedure` and their three `ParmArray` counterparts. An earlier revision of this skill named `ExecuteUpdateNull`; it does not exist.) |
| Boolean `1` / `0` | `BOOLEAN` (PostgreSQL) | Usually OK; if not, cast to `'t'`/`'f'` strings. |
| ObjectScript collection | array column | Not directly supported by JDBC adapter — iterate and INSERT child rows, or serialize to a string. |

## Typed SQL parameters — `ExecuteUpdateParmArray` / `ExecuteQueryParmArray`

**This is the idiomatic way to write an outbound SQL BO, and it is a data-correctness rule, not a
style one.** `ExecuteUpdate(sql, p1, p2, …)` carries no type information, so the adapter asks the
driver via ODBC `SQLDescribeParam`. Several JDBC drivers cannot answer, and IRIS then falls back
to **SQL type 12, VARCHAR** (ESQL §8.2.2.1, scenario 3). Everything becomes a string: an empty
value binds as an empty VARCHAR instead of a typed NULL, and a `%Date` binds as its internal day
count. The workaround people reach for — concatenating values into the statement text with `NULL`
spliced in by hand — is an injection surface and is exactly what these methods remove.

```objectscript
Include EnsSQLTypes       // REQUIRED — the $$$Sql* macros are not automatic in a BO

    Kill parms                                             // ALWAYS, before every call
    Set parms(1) = pId,     parms(1, "SqlType") = $$$SqlInteger
    Set parms(2) = pName,   parms(2, "SqlType") = $$$SqlVarchar
    Set parms(3) = pBirth,  parms(3, "SqlType") = $$$SqlDate       // "" -> typed NULL
    Set parms = 3                                          // TOP LEVEL = PARAMETER COUNT
    Set tSC = ..Adapter.ExecuteUpdateParmArray(.tRows, sql, .parms)
```

Three rules, each of which silently does nothing when broken:

- **Type parameter 1, or type nothing.** The adapter decides whether to honour your descriptors by
  testing `$D(pParms(1,"SqlType"))||$D(pParms(1,"CType"))` — either subscript counts, **parameter 1 only**
  (`EnsLib.SQL.OutboundAdapter::privPrepare`, and ESQL §8.2.2 says the same). Leave parameter 1
  untyped and every other descriptor is ignored; the statement silently reverts to
  `SQLDescribeParam`. Partial typing is worse than none, because it looks done.
- **The top level of the array is the parameter COUNT**, not a value: `Set parms = 3`.
- **`Kill` the array before every call.** ESQL §8.2.2: *"If you execute multiple queries that use
  the parameter array, kill and recreate the parameter array before each query."* A subscript left
  over from the previous message is bound without complaint.

**The macros need an `Include`, and there are TWO spellings — both real.** Neither is available
to an `Ens.BusinessOperation` by default: without the `Include` you get `MPP5610 Referenced macro
not defined`, which reads like a typo in the macro name and sends you renaming it. Verified by
compiling both against IRIS for Health 2026.1:

| `Include` | spelling | values |
|---|---|---|
| **`EnsSQLTypes`** ← use this in interop code | `$$$SqlVarchar` 12, `$$$SqlInteger` 4, `$$$SqlNumeric` 2, `$$$SqlDecimal` 3, `$$$SqlDouble` 8, `$$$SqlChar` 1 — date/time in the table below | |
| `%occODBC` | the same values under UPPERCASE names — `$$$SQLVARCHAR`, `$$$SQLINTEGER`, … | |

Prefer `EnsSQLTypes`: it is the Ensemble include, and the mixed-case spelling is what existing
field code uses.

**Date/time has FOUR families in `EnsSQLTypes.inc`, and picking the wrong one is silent.** All
values below were obtained by compiling them and printing the expansions on IRIS for Health 2026.1,
not by reading the file:

| family | macros | values |
|---|---|---|
| legacy (SQLEXT.H) | `$$$SqlDate` `$$$SqlTime` `$$$SqlTimestamp` | **9 / 10 / 11** |
| ODBC 3.x | `$$$SqlTypeDate` `$$$SqlTypeTime` `$$$SqlTypeTimestamp` | **91 / 92 / 93** |
| **JDBC aliases** | `$$$SqlJDate` `$$$SqlJTime` `$$$SqlJTimeStamp` | **91 / 92 / 93** (aliases of the ODBC 3.x set) |
| C-type aliases | `$$$SqlCDate` `$$$SqlCTimeStamp` | aliases of the legacy set (9 / 11) |

`EnsLib.SQL.OutboundAdapter` runs **JDBC** whenever `JDBCDriver` is set, so **`$$$SqlJDate` /
`$$$SqlJTimeStamp` are the semantically correct choice there** — they say "JDBC date" rather than
leaving the reader to work out which numbering is in play.

**That is a preference, not a bug report.** `$$$SqlDate` (9) is field-proven: it has bound Oracle
`DATE` columns over the Oracle JDBC driver in production, across dozens of SQL BO items, for years.
Do not go rewriting working code — prefer the `SqlJ*` spelling in new code for legibility.

**Two collisions that make a wrong constant look plausible**, both verified:
`$$$SqlDate` = `$$$SqlDateTime` = 9, and `$$$SqlTime` = `$$$SqlInterval` = 10. A misremembered name
in either pair still compiles and still binds — it just may not mean what you think.

**`"SqlType"` and `"CType"` are both honoured.** `EnsLib.SQL.OutboundAdapter::privPrepare` carries,
verbatim: `Set:""=tSqlType tSqlType=tCType, tCType="" ; for back compatibility we support CType
used as SqlType`. `"SqlType"` is the primary name and the one ESQL documents, but a great deal of
production code uses `"CType"` — **do not "fix" it, it works.**

Worked example, compiled against live IRIS as part of the example-bank gate:
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/sql-bo-typed-parmarray.cls`

Two historical `<SUBSCRIPT>` gotchas from the same family, kept for recognition only — both Caché
2016.2 / 2017 era and not reproduced on 2026.1:

- `<SUBSCRIPT>` at `^CacheTemp.EnsRuntimeAppData(...,"%QParms")` — moving to the ParmArray form
  also fixed this.
- `<SUBSCRIPT>` at `...,"%QCols"` — a BO class name too long for the runtime global subscript;
  shorten it.

## DIME protocol (legacy — do NOT use for new integrations)

Some legacy SOAP services return PDF attachments via the obsolete **DIME** protocol (the predecessor of MTOM, obsolete since 2002). IRIS has no native DIME support.

If you must integrate with a DIME-emitting service, the historic pattern is to copy `%SOAP.WebClient` to a customer class (e.g. `Alt.DIMEWebClient`) and extend it to recognise `Content-Type: application/dime` in responses. The generated proxy class extends both `%SOAP.WebClient` and `Alt.DIMEWebClient` (multi-inheritance with `Inheritance = right`).

**For any new integration, require MTOM instead.** DIME support exists only as a maintenance burden for legacy contracts that cannot be renegotiated.

## Java Gateway BO (sparingly in 2025+)

When a third-party library is only available as Java (legacy SAML modules, customer JAR with no equivalent ObjectScript impl), call it via the Java Gateway:

1. Deploy the JAR to a fixed directory on the IRIS host.
2. Use Studio → Tools → Java Gateway Wizard to generate ObjectScript proxy classes from the JAR.
3. Write a BO that extends `EnsLib.JavaGateway.AbstractOperation` and calls the proxy via `obj.<javaMethod>(...)`.
4. Add the JAR to the JavaGateway classpath via the production component's "Additional parameters" setting.

The `EnsLib.JavaGateway.Service` item is how a production reaches an **External Language Server**: its `%gatewayName` names the ELS (`%JDBC Server` is the IRIS-shipped default). The two are not alternatives and the item is not deprecated — see §"JDBC outbound — wiring checklist". Use a custom Java gateway BO sparingly all the same: most legacy use cases now have native ObjectScript alternatives (e.g. SAML via `intersystems-ib/SAML-COS`).

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/javagateway-bo.cls`.

## Lab device integration — DT in both directions

When integrating with a lab analyzer / device vendor (any instrument where HL7 v2 flows in both directions), even directions that look like passthrough usually need a DT. Common reasons:

- Field truncation requirements (the receiver's parser is stricter than the sender's emitter).
- Segment re-ordering (the receiver keys on segment position).
- Field copying between segments (the receiver's primary key lives in a non-standard field).

Do not assume "vendor A → vendor B" is passthrough without inspecting the actual payloads. Document the DT per direction; mechanism and concrete cases: `transformations` §"Lab device integration".

Also: document the port pairs per environment in a single integration table, not just in BS/BO settings. Lab integrations are notoriously asymmetric (different ports for PRE vs PRO, different ports for inbound vs outbound) — discovery without a table is painful.

## BO settings checklist

Audit on every Business Operation (and the BS equivalent for adapters that can fail):

| Setting | Recommended | Why |
|---|---|---|
| `Send Alert on Error` | ✔ (except `Ens.Alert` and the alert sink BO) | Without it, exceptions land in the Event Log only. |
| `Alert on Queue Wait` (`QueueWaitAlert`) | `30` (seconds) | Catches messages piling up when the downstream is slow but not erroring. |
| `Failure Timeout` | **Finite — never `-1`** | Infinite retries pile up forever. |
| `Reply Code Actions` (HL7 BO) | Review per-host | Defaults may swallow application-level NACKs. |
| Response Timeout vs calling BP | Strictly smaller than BP wait | Whoever times out first owns the diagnostic context. |
| `Credentials` | Reference a credential record | Don't hardcode passwords in settings. |

See `alerting` for the full picture; this is the per-BO subset.

## HTTP outbound — manual SOAP / REST envelope pattern

When you need to call a SOAP service but **don't have access** to the IRIS SOAP Wizard (MCP-only workflow, headless deployment, version mismatch), skip the Wizard and use `EnsLib.HTTP.OutboundAdapter` + a hand-crafted envelope:

```objectscript
Method CallRemote(pReq As MyApp.Msg.MyRequest, Output pResp As Ens.Response) As %Status
{
    Set pResp = ##class(Ens.Response).%New()
    Set xml = "<?xml version=""1.0"" encoding=""UTF-8""?>"
    Set xml = xml _ "<soap:Envelope xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:m=""http://remote.ns/svc"">"
    Set xml = xml _ "<soap:Body><m:DoStuff>"
    Set xml = xml _ "<m:field1>" _ $ZCONVERT(pReq.Field1, "O", "XML") _ "</m:field1>"
    // collection -> Array wrapper with Item children (NOT repeating top-level elements):
    Set xml = xml _ "<m:items>"
    For i = 1:1:pReq.Items.Count() { Set xml = xml _ "<m:itemsItem>" _ $ZCONVERT(pReq.Items.GetAt(i),"O","XML") _ "</m:itemsItem>" }
    Set xml = xml _ "</m:items>"
    Set xml = xml _ "</m:DoStuff></soap:Body></soap:Envelope>"

    Set httpReq = ##class(%Net.HttpRequest).%New()
    Set httpReq.ContentType = "text/xml; charset=utf-8"
    Do httpReq.SetHeader("SOAPAction", "http://remote.ns/svc/MyClass.DoStuff")  ; from the WSDL
    Do httpReq.EntityBody.Write(xml)

    Set tSC = ..Adapter.SendFormDataArray(.response, "POST", httpReq)
    If $$$ISERR(tSC) Quit tSC

    Set body = ""
    If $IsObject($G(response)) && $IsObject(response.Data) {
      Do response.Data.Rewind()  Set body = response.Data.Read(32000)
    }
    Set httpStatus = ""
    Try { Set httpStatus = response.StatusCode } Catch {}  ; see pitfall below
    // ... parse body for the response fields ...
    Quit $$$OK
}
```

Key points:
- **`SOAPAction` header is required**. Get the exact value from `<soap:operation soapAction="..."/>` in the WSDL. IRIS-generated SOAP services typically use `<namespace>/<FullClassName>.<MethodName>`.
- **`ArrayOf<X>` types in WSDL wrap their items in `<itemsItem>` (or whatever the WSDL declares)**, not repeating top-level elements. Inspect the WSDL `<s:complexType name="ArrayOf...">` to know the wrapper/item names.
- **`xs:date` format is `YYYY-MM-DD`** (use `$ZDATE(d, 3)`), `xs:dateTime` is `YYYY-MM-DDTHH:MM:SS` (use `$TRANSLATE($ZDATETIME($H,3), " ", "T")`).
- For empty fields, send `<m:field xsi:nil="true"/>` (with the `xmlns:xsi` namespace declared on the envelope) or simply `<m:field/>`.

This pattern bypasses `%SOAP.WebClient` entirely. `%SOAP.WebClient` is convenient when the Wizard generated matching client classes, but it's opaque (`<ZSOAP> 64` errors with no detail). The HTTP-manual approach gives you full control of headers, response inspection, retries — and you can see the exact bytes on the wire with `EnsLib.HTTP.OutboundAdapter` tracing.

## `%Net.HttpResponse.StatusCode` is multidimensional

When reading the HTTP response, this throws `<OBJECT DISPATCH> Property 'StatusCode' must be MultiDimensional`:

```objectscript
$$$LOGINFO("status="_$G(response.StatusCode))   ; FAILS
```

`StatusCode` is a MultiDim property — direct access works, but `$G()` doesn't. Wrap in `Try`:

```objectscript
Set httpStatus = ""
Try { Set httpStatus = response.StatusCode } Catch {}
$$$LOGINFO("status="_httpStatus)                ; works
```

## When NOT to use this skill — fall back to docs

- **SOAP** outbound → `soap-bo` (wizard + storage decisions for the generated classes).
- DICOM C-STORE outbound — see `dicom` (stub).
- Email outbound (`EnsLib.EMail.OutboundAdapter`) — covered by docs.
- Message-broker integrations (Kafka, RabbitMQ) — adapter-specific, not yet in the workshop's validated set.

## See also

- `soap-bo` — SOAP-specific BO (wizard, %Persistent payloads, CDA, WSDL gotchas)
- `messages` — design the request type the BO consumes
- `transformations` — DTL upstream produces the message shape the BO expects; lab device DT both directions
- `production-lifecycle` — wiring the BO into the production
- `unit-tests` — refactor BO methods to be testable
- `message-search-debug` — confirm outbound delivery
- `alerting` — per-BO settings checklist (Send Alert on Error, QueueWaitAlert, Failure Timeout, ReplyCodeActions matrix)
- `bpl` — timeout precedence (BO < BP)
