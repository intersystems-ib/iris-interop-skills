---
name: message-search-debug
description: Verify a run end-to-end, search messages, Visual Trace, Event Log, resend. Routed from interop. Load it whenever you are about to LOOK AT a running production — confirming a run worked counts, not only diagnosing a failure. Triggers EN: did it arrive, how many rows landed, verify end-to-end, check the run, Message Viewer, Visual Trace, Event Log, message search, resend, troubleshoot, queue depth. Triggers ES: verificar, comprobar, ha llegado, cuántos mensajes, ha funcionado, buscar mensaje, reenviar, depurar, traza, cola.
---

# Message Search & Debug

Everything you do **after** a message enters a running production: confirming it arrived, following where it went, and resending it. Four tools cover 95% of the work (Message Viewer, Visual Trace, Event Log, Production Status); the remaining 5% is per-BO SOAP tracing, retention/purge tuning, and bulk-resend recipes.

## When to use this skill

**Not only when something is broken.** The most common use is verifying a run that went *fine*: "did the 13 rows land", "how many messages did the BS send", "show me what session 103 did". If you are about to query a production's runtime state for any reason, this is the skill.

Also: the user is troubleshooting (a message didn't arrive, a transform produced wrong output, a BO is red), or wants to manually test a single component live (Management Portal "Test" link on a BS/BO/BP) without writing automated tests. For automated unit tests, see `unit-tests` instead.

> **Why the framing matters.** Measured over one workshop cohort day: 18 students ran **295
> hand-written SQL queries** against `Ens.MessageHeader` / `Ens_Util.Log` versus 113 typed
> `iris_interop_query` calls, producing 57 `%qaqqt` errors on the way. **56% of that SQL was
> counting/verifying** and 41% plain listing. They were not debugging — they were checking their
> own work, so nobody thought to load a skill called "debug". Zero loads across the cohort.

## The four tools (and when to use which)

| Tool | Best for |
|---|---|
| **Message Viewer** | Find a specific message by ID, time, source, target, or property. Filter by status (completed/error). Browse the message body. |
| **Visual Trace** | See the full path of a single message: which BS received it, which BP routed it, which BO sent it, with timestamps and the body at each step. Best for "where did it go wrong" diagnosis. |
| **Event Log** | Component-level events (start/stop/error/warning/info). Best for "is the BS even running" and seeing OnInit failures. |
| **Production Status page** | Per-component live status (queue depth, last-error, last-activity). Quick health check. |

Heuristic: start at the Production Status page (red items?). Follow up in Event Log for component-level errors. Use Visual Trace once you've narrowed to a specific message.

Headless, the same four map onto `iris_interop_query` (`what=messages` / `trace` / `logs` / `queues`)
plus `iris_message_body` for the payload — see §"Worked example — triage a failed message" for the
order to call them in.

## Runtime queries from Claude — use the typed MCP tool, never guess SQL

When inspecting a running production through the IRIS MCP, reach for `iris_interop_query` / `iris_production` / `iris_production_item`. Do **not** hand-write SQL against `Ens_Util.Log` / `Ens.MessageHeader`, and never guess `%SYS.*` / `Config.*` / `Ens_Config.*` catalog tables — those guesses fail ~⅔ of the time. One typed call replaces the multi-query reconstruction (and the `SELECT MAX(ID)` watermark dance).

> **The `<SYNTAX>errdone+2^%qaqqt` signature = you hand-rolled SQL through `iris_execute`.** `%qaqqt` is the SQL query compiler; it chokes on malformed/dynamic SQL (invalid predicates like `%STARTSWITH`/`%LIKE`, or `SELECT … FROM` a table that doesn't exist — `Ens_Config.Setting`, `Config.config`, `%SYS.*ELS*`). Two fixes: (1) a read-only SELECT → use `iris_query` (it goes through a real result-set path and returns a structured failure envelope — branch on its `error_code`; a `hint` naming the right typed tool is usually included but is not guaranteed); (2) anything that runs ObjectScript or **generates classes** → wrap it in a `[SqlProc]` class method and call it via `iris_query`, never embed `&sql`/`%SQL.Statement` inside an `iris_execute` snippet.

> **`<PROPERTY DOES NOT EXIST>` naming a method you know exists = you wrapped the call in `$GET()`.**
> `$G()` takes a variable or property reference, so `$G(seg.GetValueAt("1"))` makes IRIS resolve
> `GetValueAt` as a *property* and fail — while `seg.GetValueAt("1")` on the line above works. The
> error is anti-diagnostic: it sends you hunting for a method name that was already right. **Guard
> the object, not the call.**
>
> ```objectscript
> Set tVal = ""
> If $IsObject(seg) { Set tVal = seg.GetValueAt("1") }   // not $G(seg.GetValueAt("1"))
> ```
>
> With a by-reference argument (`$G(m.GetValueAt(p,m.Separators,.sc))`) the same mistake surfaces as
> `<SYNTAX>` instead, which looks like a typo rather than a category error.

> **`<METHOD DOES NOT EXIST>` on a stream = you reached for the `%File` API.** `%Stream.FileCharacter`
> has **no `Open()` and no `Save()`** — those are `%File` and `%Save` respectively. Verified on IRIS
> 2026.1: `.Open()` and `.Save()` both abort; `.LinkToFile()` and `.%Save()` are the real members.
> The class instantiates fine with `%New()`, so the failure lands on the second line, not the first.

> **Always pass `namespace`.** It is documented as optional on these tools and it is not: it
> resolves `Ens.Director` / `Ens_Config.*` in whatever namespace the connection defaults to, and if
> that one is not interop-enabled the call dies with an error that never names the cause —
> `<CLASS DOES NOT EXIST> Ens.Director`, or `Table 'ENS_CONFIG.CREDENTIALS' not found`. Measured over
> a workshop cohort: **omitting it failed 37 of 39 times (95%)**, against 16% when it was passed
> (`iris_credential_list` 14/14, `iris_production_item` 7/7, `iris_production` 15/17). The PreToolUse
> gate now blocks these calls when `namespace` is missing. Exceptions, verified: `check_config` and
> `iris_get_log` work fine without it.

| You want… | Call this (one round-trip) |
|---|---|
| Event Log of a component | `iris_interop_query(what=logs, component="<Item>")` |
| Wait for an inbound file to be picked up | watermark with `limit=1`, copy the file ONCE, then poll `since_id=<that ID>` — never a blind `sleep`; see `business-services` §"Waiting for a file BS to pick the file up" |
| Only new log entries since last check | `iris_interop_query(what=logs, since_id=<lastID>)` — no `SELECT MAX(ID)` first |
| Events of one session | `iris_interop_query(what=logs, session_id=<n>)` |
| Messages of one session | `iris_interop_query(what=messages, session_id=<n>)` |
| **Everything one initial message triggered** (header chain + events) | `iris_interop_query(what=trace, session_id=<n>)` |
| Message archive (by source/target/class) | `iris_interop_query(what=messages, source=…, target=…)` |
| Queue depths | `iris_interop_query(what=queues)` |
| Production state | `iris_production(action=status)` |
| One item's settings | `iris_production_item(action=get_settings, item="<Item>")` |
| Change a setting **and apply live** | `iris_production_item(action=set_settings, item=…, settings={…})` — applies via `Ens.Director.UpdateProduction`; pass `apply=false` to batch and apply once |
| Restart **one** component (a setting change **or a recompiled class**) | `iris_production(action=restart, item="<Item>")` |
| Apply pending config to the whole production | `iris_production(action=update)` |
| Business partners | `iris_interop_query(what=partners)` |
| SQL-Gateway connections | `iris_query(namespace="%SYS", query="SELECT * FROM %Library.sys_SQLConnection")` — a real table, in `%SYS`, not named after the class (BSQG §2). Test one with `$SYSTEM.SQLGateway.TestConnection(name)`. Full recipe: `business-operations` §"Diagnose a named SQL Gateway connection without the Portal". |
| Namespaces | `check_config` (not a SQL table) |

If you do fall back to raw `iris_query` and hit a table-not-found failure, **branch on the `error_code`** — it and `error` are the only fields guaranteed on a failure envelope. A `hint` naming the typed tool is *usually* there and worth reading when it is, but its wording is not stable across server releases and one of the two supported MCP servers may not send one at all. If there is no hint, go to the typed-tool table above rather than waiting for the server to name it.

### Where raw SQL IS the right answer

`iris_interop_query` returns **rows of headers and log entries**. It does not aggregate and it does
not join to the message body. For these, a plain `iris_query` is correct — not a fallback:

| Need | Why the typed tool can't |
|---|---|
| `SELECT COUNT(*) … GROUP BY TargetConfigName, Status` — how many landed where | no aggregation |
| Join `Ens.MessageHeader` to the message-body class to see business fields (`PacienteId`, …) | returns headers only |
| `COUNT(*) FROM Ens_Util.Log WHERE Type = 2` — how many errors, by component | no aggregation |

Everything else — listing a session's messages, tailing the Event Log, following one message end to
end, queue depths — has a typed call, and the typed call is one round trip against a table name you
would otherwise guess. Use the table above; drop to SQL only for the three cases here.

## Worked example — triage a failed message (session → trace → body)

The reusable shape for *"find the message that errored yesterday; I need the session, the patient
and their allergies"*. Four calls, all through the MCP, no Portal and no hand-written SQL.

**1. Find the failing header.** Filter rather than listing everything — `target` / `source` /
`message_class` / `session_id` / `since_id` all narrow it:

```
iris_interop_query(what="messages", target="BO.Cocina", limit=10, namespace="APP")
```

```
ID 16  Verify.MSG.PingReq  session 15  Status=8   <- error
ID 11  Verify.MSG.PingReq  session 10  Status=9   <- completed
```

`Status` is the quickest discriminator on the way past: **9 = Completed, 8 = Error**. The per-message
`IsError` flag marks the *error reply* headers within a session.

**2. Read the whole session — this is the step that stops you getting lost.**

```
iris_interop_query(what="trace", session_id=15, namespace="APP")
```

One call returns **both** halves of the story: the header chain (who sent what to whom, with each
`Status`/`IsError`) *and* that session's Event Log entries, in order. For the case above it lands
directly on the cause:

```
BO.Echo                  Rechazado: valor no valido en Texto = BAD-...
BO.Echo                  ERROR #5001: Datatype validation failed for Texto: BAD-...
EnsLib.Testing.Process   ERROR <Ens>ErrBPTerminated: Terminating BP ... due to error: #5001
```

`session_id` is **required** for `what=trace`; that is the whole point of starting at step 1.

**3. `what=logs` only when the trace is not enough.** The trace already carries the session's events,
so this step is usually redundant — reach for it when you want a **severity filter**
(`log_type="error,warning"`, the default), a **component-wide** view across sessions
(`component="BO.Cocina"`), or to **tail** with `since_id`:

```
iris_interop_query(what="logs", session_id=15, namespace="APP")
```

**4. Read the body — and know the PHI gate is on by default.** `iris_message_body` takes the
**header** ID from step 1 or 2:

```
iris_message_body(message_id="16", namespace="APP")
→ PHI_POLICY_BLOCKED: "blocked while dataPolicy=block — message bodies may contain PHI"
```

That refusal is the designed default, not a misconfiguration. Choose deliberately:

| `data_policy` | Effect |
|---|---|
| `block` *(default)* | refuses to read the body at all |
| `redact` | returns it with known HL7 v2 PHI fields blanked — PID-3/5/7/8/11/18 and MSH-3 |
| `allow` | returns it as-is; **additionally requires `acknowledge_phi=true`** |

Use `redact` unless you actually need the identifying values — for "why did this fail" you usually
do not. For "which patient and what allergies", `allow` + `acknowledge_phi=true`, then read `PID-5`
and the `AL1` segments.

It is not HL7-only: a custom `%Persistent` message body comes back as JSON
(`{"Texto":"BAD-datatype-value"}`, `content_type: "JSON"`). `max_bytes` caps the read (default
65536, hard cap 1048576) and the response reports `actual_size` and `truncated`.

**Why this order.** Step 1 narrows to one session; step 2 explains it in a single call; the body is
read last because it is the only step that touches PHI, and by then you often no longer need it.
Going body-first means opening patient data to answer a question the trace would have answered.

## Searching by message content — the two joins

`Ens.MessageHeader` holds no business data: it carries `MessageBodyClassName` (which class) and
`MessageBodyId` (which row). To search on what the message *says*, join to the body.

### Join 1 — header to a custom message class

The join key is always `h.MessageBodyId = <BodyClass>.ID`. The SQL name of the body class is its
package with dots turned into underscores **except the last** — `Ejercicio3.MSG.MenuReq` becomes
`Ejercicio3_MSG.MenuReq`:

```sql
SELECT TOP 5 h.ID, h.SessionId, h.SourceConfigName, h.Status, r.PacienteId, r.FechaNacimiento
FROM   Ens.MessageHeader h
JOIN   Ejercicio3_MSG.MenuReq r ON h.MessageBodyId = r.ID
WHERE  h.SourceConfigName = 'Router.Censo'
ORDER  BY h.ID DESC
```

Filter on a body property to find every message about one entity —
`WHERE h.TargetConfigName='BO.Menus' AND r.PacienteId='4003'`. **Read `MessageBodyClassName` first**:
one production carries several body classes, and each needs its own join. Alerts are
`Ens.AlertRequest` (`a.AlertText`) — `LEFT JOIN` it, since non-alert rows have no match. There is no
`EnsLib_Messaging.AlertRequest`; guessing it costs a round trip.

Only worth doing when the body class is `%Persistent` with the property indexed — see `messages`.
A body sitting in `Ens.MessageBodyD` without a typed class is a full-table scan.

### Join 2 — header to a Search Table (HL7 and other virtual documents)

An HL7 body has no columns to join to, so **Search Tables** are the indexed path. A developer writes
**one subclass per use case** (`Hospital.Search.HL7 Extends EnsLib.HL7.SearchTable`, with an
`XData SearchSpec` naming the fields), but — this is the part that surprises people — **the subclass
gets no table of its own**. Every HL7 search table in the namespace stores its rows in the shared
base extent `EnsLib_HL7.SearchTable`:

| Table | Columns |
|---|---|
| `EnsLib_HL7.SearchTable` | `ID`, `DocId`, `PropId`, `PropValue` — `DocId` **is** `Ens.MessageHeader.MessageBodyId` |
| `Ens_Config.SearchTableProp` | `ID`, `Name`, `PropId`, `ClassExtent`, `ClassDerivation`, `PropType`, `IndexType`, … |

So you select a search table's fields by **`PropId`**, never by table name:

```sql
SELECT TOP 10 h.ID, h.SessionId, h.SourceConfigName, p.Name, st.PropValue
FROM   Ens.MessageHeader h
JOIN   EnsLib_HL7.SearchTable st ON st.DocId = h.MessageBodyId
JOIN   Ens_Config.SearchTableProp p
       ON p.PropId = st.PropId AND p.ClassExtent = 'EnsLib.HL7.SearchTable'
WHERE  p.Name = 'PatientID' AND st.PropValue = '16284718'
```

- **Join the catalogue on `PropId`, not on `ID`.** `Ens_Config.SearchTableProp.ID` is composite —
  `EnsLib.HL7.SearchTable||Medication` — so `ON p.ID = st.PropId` compiles, returns zero rows, and
  looks like "no data".
- **`PropId` is unique only within a `ClassExtent`.** Without the `ClassExtent` predicate you match
  X12/EDIFACT/ASTM/XML props that share the number.
- **`ClassDerivation` tells you which subclass declared a prop** — `Hospital.Search.HL7~EnsLib.HL7.SearchTable`.
  Filter `p.ClassDerivation LIKE 'Hospital.Search.HL7~%'` to scope to one use case.
- Built-in HL7 props occupy the low ids (`MSHControlID`=1, `MSHTypeName`=2, `PatientAcct`=3,
  `PatientID`=4, `PatientName`=5); custom ones are appended (`Medication`=12).
- A field only becomes searchable **after** `SearchTableClass` is set on the BS/BO item, target
  `Host` — and only for messages received from that point on. Existing messages are not back-indexed.

Non-HL7 virtual documents follow the same shape with their own base extent
(`EnsLib_EDI_X12.SearchTable`, `EnsLib_EDI_XML.SearchTable`, …). Custom non-VDoc search tables
extend `Ens.CustomSearchTable`, whose own extent is `Ens.CustomSearchTable` with the same
`DocId` key.

### Why this one is hand-written SQL, when the rest of this skill says never to

The rule at the top of this skill — reach for `iris_interop_query`, do not hand-write SQL against
`Ens.MessageHeader` — has exactly one standing exception, and this is it.

`iris_interop_query(what="messages")` advertises a `search_table={prop, value|value_like, class?,
extent?}` filter. **On MCP `iris-interop-dev` 0.19.0 that parameter is silently ignored**: the call
succeeds, `success: true`, and returns the *unfiltered* message list. Verified against a live
instance carrying exactly one indexed HL7 message:

| Call | Rows |
|---|---|
| no filter at all | 2 |
| `search_table={prop:"PatientID", value:"16284718"}` (a real match) | 2 |
| `search_table={prop:"PatientID", value:"NO-SUCH-PATIENT-ZZZ"}` | **2** |
| `search_table={prop:"ThisPropDoesNotExist", value:"x"}` | **2** |
| `search_table={prop:"PatientID"}` (missing the required value) | **2** |
| control: `target="BO.AdtOut"` | **1** ✅ |

The control matters: other filters on the same tool work, so this is specific to `search_table`,
not a broken call. The last row of the group is the diagnostic one — a `search_table` with no
`value` is supposed to be rejected outright, so getting results back proves the filter never
reached the query logic at all.

**A filter that cannot return zero is not a filter.** Treat a `search_table` result as unfiltered
until you have re-run the impossible-value probe above on your own MCP version and seen it return
nothing. Until then, use the `PropId` join below — it is longer, and it is the one that answers the
question you asked.

Tracked upstream as **intersystems-ib/iris-interop-dev#202** — the parameter is parsed with a
`.ok()` that discards a deserialisation failure instead of erroring, so a rejected filter degrades
into no filter. When that closes, re-run the probe and delete this section.

### Authoring a Search Table

Everything above assumes someone already declared the fields. Authoring one is a single subclass
plus one production setting:

```objectscript
Class MyApp.Search.Hl7Adt Extends EnsLib.HL7.SearchTable
{
XData SearchSpec [ XMLNamespace = "http://www.intersystems.com/EnsSearchTable" ]
{
<Items>
  <Item DocType="" PropName="PatientFirstName">[PID:5().2]</Item>
</Items>
}
}
```

- **The XData namespace is `EnsSearchTable`** — literally
  `http://www.intersystems.com/EnsSearchTable`. `EnsHL7SearchTable`, the form you'd guess by
  analogy with the class name, does not work.
- **`PropType`**: the only values observed in a live catalogue
  (`Ens_Config.SearchTableProp.PropType` on a namespace carrying 257 real search-table rows) are
  `String:CaseSensitive` and `String:CaseInsensitive`. Both `PropType="String"` and
  `PropType="String:25"` fail with `ErrDatatypeValidationFailed`. **Omitting the attribute
  entirely also works and is the safe default.** (`DateTime` / `Numeric` are unverified against
  that catalogue — don't reach for them without checking.)
- **A search table indexes nothing until it is assigned** — and only messages received from that
  point on are indexed. Nothing back-indexes existing messages (same caveat as in the query section
  above).

#### Assigning it — `SearchTableClass` is a `Host` setting on the service and the operation

This is the step that is easy to read past, because the class compiles happily without it and the
search table simply stays empty. `SearchTableClass` is declared on `EnsLib.HL7.Service.Standard`
and `EnsLib.HL7.Operation.Standard`, so **every** HL7 service and operation carries it, always with
`Target="Host"`:

```xml
<Item Name="BS.AdtIn" ClassName="EnsLib.HL7.Service.FileService" Enabled="true">
  <Setting Target="Adapter" Name="FilePath">/data/hl7in</Setting>
  <Setting Target="Host"    Name="MessageSchemaCategory">2.5</Setting>
  <Setting Target="Host"    Name="SearchTableClass">MyApp.Search.Hl7Adt</Setting>
  <Setting Target="Host"    Name="TargetConfigNames">BO.AdtOut</Setting>
</Item>
```

Or on a running production, without editing the class:

```
iris_production_item(action="set_settings", item="BS.AdtIn", production="MyApp.Production",
                     settings={"SearchTableClass": "MyApp.Search.Hl7Adt"}, namespace="APP")
```

(That changes the namespace only — pull the production class back to `src/` afterwards, see
`production-lifecycle`.)

**Routers do not carry `SearchTableClass`.** `EnsLib.HL7.MsgRouter.RoutingEngine` has no such
property, so assigning it there is not an option you have missed — index at the **service** (and/or
the operation) instead. The one exception is `EnsLib.MsgRouter.RoutingEngineST`, a routing engine
whose whole purpose is to carry one.

Once compiled and assigned, the rows land in the shared base extent `EnsLib_HL7.SearchTable` and
are queried by `PropId` exactly as shown in Join 2 — the subclass never gets a table of its own.
Verified end to end: an `ADT_A01` through a `FileService` with the above settings produced six rows
for one message — four built-in (`MSHControlID`, `MSHTypeName`, `PatientID`, `PatientName`) and two
from the custom subclass, the latter carrying
`ClassDerivation = MyApp.Search.Hl7Adt~EnsLib.HL7.SearchTable`. A built-in prop whose field is empty
in the message simply gets no row (`PatientAcct` was absent because PID-18 was).

#### `PropValue` is stored LOWERCASED under the default `PropType`

The default (and the `String:CaseInsensitive` setting) normalises on the way in. Measured on the
message above:

| Message field | Stored `PropValue` |
|---|---|
| `ADT^A01` | `adt_a01` |
| `GARCIA^MARIA` | `garcia^maria` |
| `HOUSE` | `house` |
| `I` | `i` |

So `WHERE st.PropValue = 'GARCIA^MARIA'` returns **nothing** and reads as "that patient was never
here". Lowercase the literal, or use `%STARTSWITH`/`LIKE` against a lowercased pattern. The
`PatientID` example in Join 2 dodges this only because it is numeric.

## Searching by message body content

Searchable when:
- The message class is `%Persistent` with the right indexes (see `messages`).
- Or the message is HL7 — built-in indexed fields (MSH:10 control ID, sender, etc.) are searchable.

Not efficiently searchable when:
- The message body is in `Ens.MessageBodyD` without a typed class (full-table-scan territory).
- Hence the importance of `%Persistent` + indexes during message design.

## Resending

From the Message Viewer, a message can be **resent** to its original target or to a new target.
Useful after a fix on a downstream system.

**A resend stays in the ORIGINAL session.** This is the point of using the supported API rather
than re-sending the body yourself: the new header carries the original `SessionId`, so the resend
appears in the original message's trace and the whole story stays in one place. Measured on IRIS for
Health 2026.1 — one original delivery plus two resends, all in session `2`:

```
what=trace session_id=2
  ID 3  Verify.MSG.PingReq  -> BO.Echo     the original
  ID 6  Verify.MSG.PingReq  -> BO.Echo     plain resend        (same session)
  ID 8  Verify.MSG.PingReq  -> BO.Echo     edited resend       (same session)
```

### Headless resend — there is no MCP tool for this

`iris_interop_query` has no resend mode (`what` accepts only `logs`, `queues`, `messages`, `trace`,
`partners`). Without the Portal, resend one message by header ID with:

```objectscript
Set newId = "", sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(<headerId>, .newId)
// sc = %Status; newId = the header ID of the new message
```

The full signature — read off `%Dictionary.CompiledMethod`, since `docs_introspect` does not surface
it (below):

```
ResendDuplicatedMessage(pOriginalHeaderId, *pNewHeaderId, pNewTarget, pNewBody, pNewSource, pHeadOfQueue) As %Status
```

`pNewTarget` re-routes the resend; `pNewBody` replaces the payload (see edit & resend); all four
trailing arguments are optional.

Run it through `iris_execute`; it persists (this is a runtime side effect, not class generation, so
it does not hit the objectgenerator no-op trap). Verified on IRIS 2026.1: resending header `102`
returned `$$$OK` and `newId = 171`, and the new session appeared in `Ens.MessageHeader` immediately.

**`docs_introspect` will not help you find this method** — asking for
`Ens.MessageHeader::ResendDuplicatedMessage` returns `{"methods":[],"properties":[],"success":true}`,
an empty result that reads as "no such method". It exists; the introspection just doesn't surface it.

Confirm the resend landed by header ID, not by re-listing everything:
`iris_query("SELECT ID, SessionId, TargetConfigName, Status FROM Ens.MessageHeader WHERE ID >= <newId>")`.

### Edit & resend — change the payload without breaking the trail

Resending a message you first had to *fix* (a bad code, a missing field) is the common case, and the
obvious route is the wrong one. **A plain resend SHARES the original body** — verified: original
header `3` and resent header `6` both point at `MessageBodyId=1`. So editing that body in place to
"fix" it rewrites what the original message said, and the audit trail now lies.

Clone the body, edit the clone, and hand it to the resend as `pNewBody`:

```objectscript
Set hdr   = ##class(Ens.MessageHeader).%OpenId(origHeaderId)
Set body  = $classmethod(hdr.MessageBodyClassName, "%OpenId", hdr.MessageBodyId)
Set clone = body.%ConstructClone(1)          ; 1 = deep clone
Set clone.Texto = "corrected value"          ; or SetValueAt(...) on an EnsLib.HL7.Message
Do  clone.%Save()

Set newId = "", sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(origHeaderId, .newId, "", clone)
```

Verified outcome: the new header keeps `SessionId` and `TargetConfigName` of the original, points at
the **new** body, and the original body still reads what it always did.

**Anti-pattern — do NOT re-inject the edited body through `EnsLib.Testing.Service`.** It is the
reflex move, it reports success, and it quietly does the wrong thing: measured, the same clone sent
via `SendTestRequest` landed in **session 10** while the original was session `2`. The resend is then
absent from the original trace, nothing marks it as a resend of anything, and the connection between
the failure and its fix exists only in your memory. The Testing Service is for injecting *new* test
traffic, not for re-driving a real message.

**Check idempotency before you resend anything.** A resend re-executes whatever the message already
did downstream. If the first attempt got far enough to INSERT a row or ACK a partner, the resend does
it again — the reported symptom was `duplicate key value violates unique constraint` from inserting
the same patient twice. A message that *errored* is not necessarily a message that did *nothing*:
check where in the session it stopped (`what=trace`) before assuming it is safe to replay.

### Bulk resend

From the Portal: filter Message Viewer to the affected window + status `Error`, select all, resend.
Headless, there are dedicated APIs — the documentation calls them "more efficient than the Message
Viewer page for resending large numbers of messages":

```objectscript
Set filter("SourceConfigName") = "HttpService"
Set filter("Status") = "Error"
Set sc = ##class(Ens.MessageHeader).ResendMessageBatch(.filter, 0, 0, .count)
```

```
ResendMessageBatch(&filter, resubmit=0, headOfQueue=0, *resentCount) As %Status
ResendMessageBatchAsync(*queueToken, &filter, resubmit=0, headOfQueue=0) As %Status
```

`ResubmitMessage(pHeaderId, pNewTarget, pNewBody, pHeadOfQueue)` and its
`PrepareResubmitMessage(...)` companion also exist for the resubmit (rather than duplicate) flavour.

Before bulk-resending: verify **idempotency** on the downstream BO. A non-idempotent BO will create
duplicates — fix that first or use a manual loop with deduplication logic in the BP. The blast radius
here is the whole filter, so the idempotency question above is not optional at this scale.

## Per-BO SOAP tracing

The global `^ISCSOAP("Log")` toggle traces all SOAP traffic for the namespace, mixing every BO's calls into one log file. Useless on a production with multiple SOAP integrations.

**Better:** per-BO SOAP tracing via a customer-internal copy of `%SOAP.WebClient`:

1. Copy `%SOAP.WebClient` to a customer namespace (e.g. `Alt.SOAP.WebClient`) — `Alt` is the canonical reserved package for patched system classes (xref `interop` §"Reserved package names").
2. Change the generated SOAP proxy's superclass from `%SOAP.WebClient` to `Alt.SOAP.WebClient`.
3. Add a `SoapLogFile` setting on each BO; toggle the global only inside that BO's `OnMessage`:

```objectscript
Property SoapLogFile As %String(MAXLEN="512") [ InitialExpression = "" ];
Parameter SETTINGS = "<...>,SoapLogFile";

Method OnMessage(...) {
    If (..SoapLogFile'="") {
        set ^ISCSOAP("Log")="ios"
        set ^ISCSOAP("LogFile")=..SoapLogFile
    }
    // invoke proxy...
    If (..SoapLogFile'="") { set ^ISCSOAP("Log")="" }
}
```

Each BO writes to its own log file path, settable from the Portal at runtime — no recompile to turn tracing on/off.

**Caveat:** `^ISCSOAP` is process-scoped, so heavy multi-process scenarios can still cross-pollute. Treat as a debug aid, not always-on tracing. Disable the SoapLogFile setting once the issue is diagnosed.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/alt-soap-webclient-tracing.cls`.

## Retention and purge

Persistent messages and message-body tables grow unbounded. Without a purge task scheduled, `Ens.MessageHeader` and every custom-message-class table accumulate forever.

Add `Ens.Util.Tasks.Purge` to the production at creation time, scheduled daily. Set `NumDaysToKeep` per the customer's retention policy:

- **30 days** — typical default for development environments and low-criticality flows.
- **90 days** — common for production where operational lookback is the only requirement.
- **Longer** — only if a regulatory or contractual retention requirement applies, in which case the messages probably belong in a separate audit store, not in `Ens.MessageHeader`.

The purge task removes both `Ens.MessageHeader` rows and the corresponding message-body table rows. Auditing an existing production, flag the absence of the purge task as a gap (xref `alerting` baseline checklist).

Verify purge actually runs: Management Portal → Interoperability → Manage → System Tasks → check the last-run timestamp and any errors.

## What this skill does NOT yet do

- Auto-correlate a stack of related messages across multiple sessions.
- Generate Message Viewer queries from a plain-English search description.
- Customer-specific retention policy advice (depends on contract; the policy values above are starting defaults).

## Pitfalls to surface

- Searching by body content on a message that's not `%Persistent` → very slow.
- Confusing **Session ID** with **Message ID** — a session is the whole flow, a message is one hop.
- Resending a message that mutates external state without the destination expecting a duplicate → check idempotency first.
- **Re-sending a message body through `EnsLib.Testing.Service` instead of resending the message.**
  Starts a NEW session, so the resend never appears in the original's trace and nothing records that
  it was a resend. Use `Ens.MessageHeader::ResendDuplicatedMessage`.
- **Editing the original message body in place before a resend** → a plain resend shares that body,
  so you have rewritten history. Clone it and pass the clone as `pNewBody`.
- **Trusting a `search_table=` result on MCP 0.19.0** → the filter is silently dropped and you get
  every message back, with `success: true`. Probe it with an impossible value before believing it.
- **Searching `PropValue` with an upper-case literal** → search-table values are stored lowercased
  under the default `PropType`, so `= 'SMITH'` matches nothing while `= 'smith'` works.
- **Expecting a search table to index retroactively, or to be assignable on a router** →
  `SearchTableClass` is a `Host` setting on the service/operation, and only messages received after
  it is set are indexed.
- **Bulk-resending without dedup** — a 200-row failure window resent against a non-idempotent BO creates 200 duplicates downstream.
- **Leaving `^ISCSOAP("Log")` enabled namespace-wide** — log file grows fast, mixes all BO traffic, disk fills. Per-BO `SoapLogFile` only.
- **No purge task** → tables grow forever; eventually the namespace becomes slow and large backups become unwieldy.

## See also

- `messages` — design messages so search and trace work well later
- `production-lifecycle` — Production Status page is part of the lifecycle UI; purge task lives there too
- `unit-tests` — for automated, repeatable test coverage (vs ad-hoc Test pages)
- `alerting` — `Ens.Util.Tasks.Purge` is part of the baseline production checklist
- `soap-bo` — generated SOAP client patches and customisation
