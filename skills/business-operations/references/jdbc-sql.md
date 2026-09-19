# JDBC and SQL outbound

The whole SQL/JDBC outbound path: `DSN` forms, diagnosing a named SQL Gateway connection without the Portal, prerequisites, the settings quartet, `Credentials`/`BusinessPartner`, a worked PostgreSQL example, type marshalling, and typed parameters via `ExecuteUpdateParmArray`. Read this only when the outbound is SQL.

## Contents

- JDBC outbound — wiring checklist
- `DSN` takes EITHER a direct `jdbc:` URL OR a named SQL Gateway connection
- Diagnose a named SQL Gateway connection without the Portal
- NOT a pre-created ODBC DSN
- Prerequisites (one-time per host)
- BO settings — the quartet
- `Credentials` + `BusinessPartner` linkage
- Worked example — PostgreSQL outbound
- JDBC type marshalling — gotchas
- Typed SQL parameters — `ExecuteUpdateParmArray` / `ExecuteQueryParmArray`

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

The worked, **compile-gated** version is
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/sql-bo-typed-parmarray.cls`
(`Example.Adapters.BO.SqlTypedParmArray`) — use it rather than the sketch that used to sit here. That
file carries `Include EnsSQLTypes` and uses `$$$SqlInteger`, `$$$SqlVarchar`, `$$$SqlJDate` and
`$$$SqlDouble` in real code, so tier 2 **compiles the macro names** on every release. The sketch here
was a loose fragment that no tier could compile, and it named `$$$SqlDate` — a spelling nothing had
ever checked. For a macro, "it compiles" is the whole question, so prefer the gated file.

The four things that decide whether the call binds anything, all of them silent when wrong:

| | |
|---|---|
| `Kill parms` | **Before every call.** A subscript left from the previous message binds silently. |
| `parms(1,"SqlType")` | Parameter **1** must carry a type, or none of the other descriptors are honoured. |
| `Set parms = <n>` | The **top level is the parameter count**. Omit it and the call binds nothing. |
| `Include EnsSQLTypes` | The `$$$Sql*` macros are not automatic in a BO. `%occODBC` offers the same values under UPPERCASE names. |

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

