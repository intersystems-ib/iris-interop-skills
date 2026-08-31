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

## Runtime queries from Claude — use the typed MCP tool, never guess SQL

When inspecting a running production through the IRIS MCP, reach for `iris_interop_query` / `iris_production` / `iris_production_item`. Do **not** hand-write SQL against `Ens_Util.Log` / `Ens.MessageHeader`, and never guess `%SYS.*` / `Config.*` / `Ens_Config.*` catalog tables — those guesses fail ~⅔ of the time. One typed call replaces the multi-query reconstruction (and the `SELECT MAX(ID)` watermark dance).

> **The `<SYNTAX>errdone+2^%qaqqt` signature = you hand-rolled SQL through `iris_execute`.** `%qaqqt` is the SQL query compiler; it chokes on malformed/dynamic SQL (invalid predicates like `%STARTSWITH`/`%LIKE`, or `SELECT … FROM` a table that doesn't exist — `Ens_Config.Setting`, `Config.config`, `%SYS.*ELS*`). Two fixes: (1) a read-only SELECT → use `iris_query` (it goes through a real result-set path and returns a structured failure envelope — branch on its `error_code`; a `hint` naming the right typed tool is usually included but is not guaranteed); (2) anything that runs ObjectScript or **generates classes** → wrap it in a `[SqlProc]` class method and call it via `iris_query`, never embed `&sql`/`%SQL.Statement` inside an `iris_execute` snippet.

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
| Only new log entries since last check | `iris_interop_query(what=logs, since_id=<lastID>)` — no `SELECT MAX(ID)` first |
| Events of one session | `iris_interop_query(what=logs, session_id=<n>)` |
| Messages of one session | `iris_interop_query(what=messages, session_id=<n>)` |
| **Everything one initial message triggered** (header chain + events) | `iris_interop_query(what=trace, session_id=<n>)` |
| Message archive (by source/target/class) | `iris_interop_query(what=messages, source=…, target=…)` |
| Queue depths | `iris_interop_query(what=queues)` |
| Production state | `iris_production(action=status)` |
| One item's settings | `iris_production_item(action=get_settings, item="<Item>")` |
| Change a setting **and apply live** | `iris_production_item(action=set_settings, item=…, settings={…})` — applies via `Ens.Director.UpdateProduction`; pass `apply=false` to batch and apply once |
| Restart **one** component | `iris_production(action=restart, item="<Item>")` |
| Apply pending config to the whole production | `iris_production(action=update)` |
| Business partners | `iris_interop_query(what=partners)` |
| SQL-Gateway connections | `introspect-dont-guess` plugin agent (an agent, not a skill; no agent tool → `interop` §"Resolving real names") / `iris_table_info` (no SQL catalog table) |
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

### Authoring a Search Table

Everything above assumes someone already declared the fields. Authoring one is a single subclass
plus one production setting:

```objectscript
Class MyApp.Search.HL7 Extends EnsLib.HL7.SearchTable
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
- **A search table indexes nothing until it is assigned**: set `SearchTableClass` on the BS/BO
  item, target **`Host`** — and only messages received from that point on are indexed. Nothing
  back-indexes existing messages (same caveat as in the query section above).

Once compiled and assigned, the rows land in the shared base extent `EnsLib_HL7.SearchTable` and
are queried by `PropId` exactly as shown in Join 2 — the subclass never gets a table of its own.

## Searching by message body content

Searchable when:
- The message class is `%Persistent` with the right indexes (see `messages`).
- Or the message is HL7 — built-in indexed fields (MSH:10 control ID, sender, etc.) are searchable.

Not efficiently searchable when:
- The message body is in `Ens.MessageBodyD` without a typed class (full-table-scan territory).
- Hence the importance of `%Persistent` + indexes during message design.

## Resending

From the Message Viewer, a message can be **resent** to its original target or to a new target. Useful after a fix on a downstream system. Resend creates a new session — the old session stays as an audit trail.

### Headless resend — there is no MCP tool for this

`iris_interop_query` has no resend mode (`what` accepts only `logs`, `queues`, `messages`, `trace`,
`partners`). Without the Portal, resend one message by header ID with:

```objectscript
Set newId = "", sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(<headerId>, .newId)
// sc = %Status; newId = the header ID of the new message
```

Run it through `iris_execute`; it persists (this is a runtime side effect, not class generation, so
it does not hit the objectgenerator no-op trap). Verified on IRIS 2026.1: resending header `102`
returned `$$$OK` and `newId = 171`, and the new session appeared in `Ens.MessageHeader` immediately.

**`docs_introspect` will not help you find this method** — asking for
`Ens.MessageHeader::ResendDuplicatedMessage` returns `{"methods":[],"properties":[],"success":true}`,
an empty result that reads as "no such method". It exists; the introspection just doesn't surface it.

Confirm the resend landed by header ID, not by re-listing everything:
`iris_query("SELECT ID, SessionId, TargetConfigName, Status FROM Ens.MessageHeader WHERE ID >= <newId>")`.

For bulk resends (a batch failed during an outage), filter Message Viewer to the affected window + status `Error`, select all, resend. Before bulk-resending: verify **idempotency** on the downstream BO. A non-idempotent BO will create duplicates — fix that first or use a manual loop with deduplication logic in the BP.

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
- **Bulk-resending without dedup** — a 200-row failure window resent against a non-idempotent BO creates 200 duplicates downstream.
- **Leaving `^ISCSOAP("Log")` enabled namespace-wide** — log file grows fast, mixes all BO traffic, disk fills. Per-BO `SoapLogFile` only.
- **No purge task** → tables grow forever; eventually the namespace becomes slow and large backups become unwieldy.

## See also

- `messages` — design messages so search and trace work well later
- `production-lifecycle` — Production Status page is part of the lifecycle UI; purge task lives there too
- `unit-tests` — for automated, repeatable test coverage (vs ad-hoc Test pages)
- `alerting` — `Ens.Util.Tasks.Purge` is part of the baseline production checklist
- `soap-bo` — generated SOAP client patches and customisation
