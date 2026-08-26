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
├── SOAP web service → use iris-interop-soap-bo (SOAP wizard from WSDL)
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
| `DSN` (SQL) | JDBC URL (`jdbc:postgresql://...`) **or** named SQL Gateway connection. |
| `JGService` (SQL/JDBC) | Name of the Java Gateway item the adapter routes through. Should reference an **External Language Server** (`%JDBC Server` or your custom ELS), not the deprecated `EnsLib.JavaGateway.Service` class. |
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

A BO's `Response Timeout` and `Failure Timeout` MUST be strictly smaller than the calling BP's wait timeout — whoever times out first owns the error context, and only a BO-first timeout carries diagnostic detail up the chain. Set BO timeouts last, after the calling BP's timeout is fixed. Mechanism and the BP-side view: see `bpl` §"Timeouts".

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
| **Multiple rows per message** (batch) | `..Adapter.StartTransaction()` → loop `ExecuteUpdate` → `..Adapter.Commit()` on success, `..Adapter.Rollback()` on any failure. Set `AutoCommit=false` on the adapter so intermediate INSERTs don't commit independently. |
| **Oracle JDBC** | Set `AutoCommit=true` on the adapter even for single-row work. Oracle treats SELECT as transactional by default and connections can hang on idle transactions otherwise. |

## Idempotency — let the remote constraint do the work

A BO that does `INSERT INTO Menus VALUES (?)` with `paciente_id` as PK is **not idempotent**: re-running the same input violates the unique constraint and fails. That is **the correct behaviour by default** — re-runs surface as alerts to the operator, which is exactly what you want for "did we accidentally re-process yesterday's CSV?".

Switch to UPSERT (`INSERT ... ON CONFLICT (paciente_id) DO NOTHING` / `DO UPDATE SET ...`) **only when** re-runs are part of the normal flow (retry-safe ingestion pipelines, eventually-consistent feeds). Don't add UPSERT preemptively "for safety" — it hides the re-run signal.

## Common pitfalls

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

## Resolve real table names BEFORE the first query — introspect, don't guess

Any SQL a BO (or its verification step) touches goes through this gate: **before the first
`iris_query` / SQL statement against a table you did not create in this session, resolve the real
name** — `iris_table_info` on the schema, or spawn the `introspect-dont-guess` plugin agent (an
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
- **Invented system catalogs.** `%Library.SQLConnection`, `Config.config`, `Ens_Config.Setting` —
  these do not exist as SQL tables. The typed tools (`check_config`, `iris_production_item`,
  `iris_interop_query`) are the path; `message-search-debug` has the full table.

**On `-30 Table not found`, the NEXT call is introspection — never another guessed name.**

## JDBC outbound — wiring checklist

A JDBC-backed BO needs more than just a `DSN` setting; the full path from class to database touches the JVM, the External Language Server, and four BO settings that must align. Missing one piece produces opaque errors ("Java gateway not started", "no driver found", "no suitable driver"). Validate the checklist before debugging code.

### Use a direct `jdbc:` URL — NOT a pre-created ODBC DSN

The adapter's `DSN` setting takes a **direct JDBC URL** (`jdbc:postgresql://host:5432/db`, `jdbc:IRIS://localhost:1972/USER`). Do **not** route an external-DB BO through an ODBC System DSN — that path produces an un-winnable spiral:

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
| **ELS port reachable** | `%JDBC Server` ELS arrancado (default port `53772`). Smoke test on Windows: `netstat -ano \| findstr :53772` after starting the ELS. |
| **JDBC driver JAR** | Driver JAR copied to a stable filesystem path the IRIS service account can read (e.g. `C:\jdbc\postgresql-42.x.jar`). |

### BO settings — the quartet

| Setting (`Target="Adapter"`) | Value | Notes |
|---|---|---|
| `DSN` | `jdbc:postgresql://host:5432/dbname` | Direct JDBC URL — **no pre-created SQL Gateway connection needed**. |
| `JGService` | Name of the ELS-backed gateway item in the production (e.g. `Util.JDBCGateway` whose `%gatewayName="%JDBC Server"`) | Adapter routes through this gateway. |
| `JDBCDriver` | `org.postgresql.Driver` (or vendor equivalent) | Fully-qualified Java class name. |
| `JDBCClasspath` | `C:\jdbc\postgresql-42.x.jar` | The exact JAR file path. Multiple JARs: separate with `;` (Windows) or `:` (Unix). |
| `Credentials` | Name of an `Ens.Config.Credentials` record | Reference, not inline. Credential record points at a `BusinessPartner` for documentation. |

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

`EnsLib.JavaGateway.Service` is **deprecated in IRIS 2026.1** — the item can be kept as a thin wrapper pointing at `%JDBC Server`, but the long-term direction is to reference the ELS directly from the BO. See `iris-interop-production-lifecycle §Default scaffolds`.

## JDBC type marshalling — gotchas

When binding parameters to `EnsLib.SQL.OutboundAdapter.ExecuteUpdate()` (or any JDBC outbound), the driver translates the ObjectScript value to the column's SQL type. A few translations fail silently or with cryptic messages:

| ObjectScript value | Bound to column type | Result |
|---|---|---|
| `%Date` integer (e.g. `52798`) | `DATE` (PostgreSQL/Oracle) | `StringIndexOutOfBoundsException: begin 0, end 10, length 5` — the driver tries to parse the integer as `YYYY-MM-DD`. **Fix**: convert in the BO with `Set bound = $ZDATE(req.FechaNacim, 3)` before passing to `ExecuteUpdate`. |
| `%TimeStamp` `"2026-05-13 07:13:59"` | `TIMESTAMP` | Usually works; JDBC accepts space separator. Use `T` separator (`$TRANSLATE(...,"  ","T")`) if the column is `xs:dateTime` schema-bound. |
| Empty string `""` | nullable column | Driver inserts empty string, not NULL. **Fix** if you want NULL: pass `$S(val="":"", 1:val)` is **wrong** — that still passes `""`. Use the adapter's `ExecuteUpdateNull` variant or explicit `NULL` in the SQL with conditional binding. |
| Boolean `1` / `0` | `BOOLEAN` (PostgreSQL) | Usually OK; if not, cast to `'t'`/`'f'` strings. |
| ObjectScript collection | array column | Not directly supported by JDBC adapter — iterate and INSERT child rows, or serialize to a string. |

## SQL Inbound / Outbound — typed parameters

When the adapter is a SQL one, two cosmetic gotchas show up with long-running customer projects:

- **`<SUBSCRIPT>` error at `^CacheTemp.EnsRuntimeAppData(...,"%QParms")`** — switch from `..Adapter.ExecuteQuery(...)` to `..Adapter.ExecuteQueryParmArray(...)` and pass parameters with **explicit SQL types**:

  ```objectscript
  Set parametros(1) = pId
  Set parametros(1, "SqlType") = $$$SqlVarchar
  Set parametros(2) = pCount
  Set parametros(2, "SqlType") = $$$SqlInteger
  Set tSC = ..Adapter.ExecuteQueryParmArray(.rs, sql, .parametros)
  ```

- **`<SUBSCRIPT>` error at `...,"%QCols"`** — caused by a BO class name too long for the runtime global subscript. Shorten the BO class name (long-package long-name combinations like `MyApp.LongDomain.Outbound.SQL.WriteSomethingComplicated` hit the limit).

Verify against current IRIS — these were Caché 2016.2 / 2017 issues and are likely improved, but the `ExecuteQueryParmArray` pattern is the robust choice regardless.

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

In 2025+, prefer **External Language Server** references over `EnsLib.JavaGateway.Service` (deprecated in IRIS 2026.1 — deprecation policy in `production-lifecycle` §"Default scaffolds"). Use sparingly: most legacy use cases now have native ObjectScript alternatives (e.g. SAML via `intersystems-ib/SAML-COS`).

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/javagateway-bo.cls`.

## Lab device integration — DT in both directions

When integrating with a lab analyzer / device vendor (any modality where HL7 v2 flows in both directions), even directions that look like passthrough usually need a DT. Common reasons:

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
