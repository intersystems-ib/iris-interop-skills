---
name: alerting
description: Ens.Alert router, alert dedup, production monitor, per-BO alert settings in IRIS Interoperability. Routed from interop. Triggers: Ens.Alert, Ens.AlertRequest, Send Alert on Error, alert on error, IRIS alert routing, alert dedup FunctionSet, AlertOperation, ProductionMonitorService, alerta de producción, ruta de alertas.
---

# Alert circuit for IRIS Interop productions

Every production needs an alert path. The default behaviour — exceptions land in the Event Log and stop there — is not operational; nobody is paging the Event Log at 02:00. This skill is the canonical wiring of the **alert circuit**, the **dedup function set** that keeps it from flooding, and the per-host settings that make alerts fire when they should.

## When to use this skill

The user is wiring `Ens.Alert`, adding an `EnsLib.EMail.AlertOperation`, asking why their mailbox is flooded with duplicate alerts, configuring `Send Alert on Error` per host, or scoping a production-monitor baseline.

## Baseline production checklist

Every production must include at minimum:

- **`Ens.ProductionMonitorService`** — the conventional *item* name; runs every 30 s (default) and surfaces per-component state to the production monitor screen. Two **different** real classes exist here and are easy to conflate — IRIS's own descriptions: `Ens.MonitorService` *"checks all hosts for inactivity"* (the `ClassName` wired below), and `Ens.ProductionMonitorService` *"monitor service for the production status … calls UpdateProduction once it notices the production is not up-to-date"*. Both are real, so a wrong pick fails silently rather than at load.
- **`Ens.Alert`** — an `EnsLib.MsgRouter.RoutingEngine` configured to handle `Ens.AlertRequest` messages.
- **At least one alert sink BO** — typically `EnsLib.EMail.AlertOperation` for email; can be SMS, file, a paging system. Multiple sinks fan out through the router.

Without these, exceptions die silently. Add the three at production creation time; auditing an existing production, flag their absence as a gap.

## Alert circuit — canonical wiring

Set **`Send Alert on Error = ✔`** on every Business Host in the production, **with two mandatory exceptions**:

- `Ens.Alert` itself — the router that handles alerts.
- The alert sink BO (e.g. the email AlertOperation).

If those two have `Send Alert on Error` enabled, a failure inside the alert circuit triggers a new alert that re-enters the circuit — **infinite alert loop**. The portal will accept the misconfiguration without warning; the consequence is only visible at runtime.

Production XML excerpt for the alert circuit:

```xml
<Item Name="Ens.Alert" Category="..." ClassName="EnsLib.MsgRouter.RoutingEngine"
      PoolSize="1" Enabled="true">
  <Setting Target="Host" Name="BusinessRuleName">MyApp.RUL.AlertRouting</Setting>
  <!-- deliberately NO AlertOnError here — this item IS the alert circuit -->
</Item>

<Item Name="BO.AlertEmail" Category="..." ClassName="EnsLib.EMail.AlertOperation"
      PoolSize="1" Enabled="true">
  <Setting Target="Host" Name="Recipient">oncall@example.org</Setting>
  <!-- deliberately NO AlertOnError here — this item IS the alert sink -->
</Item>

<Item Name="Ens.ProductionMonitorService" Category="..."
      ClassName="Ens.MonitorService" PoolSize="1" Enabled="true"/>
```

A complete production XML with this wiring lives in `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch07_alerting/alert-circuit-production.xml`.

## Alert deduplication — `Ens.Alert` routing-rule guards

Two real, repeatedly observed failure modes flood the alert mailbox:

1. **Cascading alerts in the same session** — a BP catches an error and raises an alert; the BO downstream also catches the same error and raises another. One operational incident → multiple emails.
2. **Retry storms** — a failing BO retries every `RetryInterval` seconds and emits `Ens.AlertRequest` on each retry. A 5-minute outage with a 10-second retry interval is 30 alerts.

Defend with a portable function set (`Ens.Rule.FunctionSet` extension) called from the `Ens.Alert` routing rule:

```objectscript
Class MyApp.UTL.AlertFilterFunctions Extends Ens.Rule.FunctionSet [ LegacyInstanceContext, Not ProcedureBlock ]
{

/// True if (SourceConfigName, ErrorMessage) was already reported within Interval seconds today.
ClassMethod AlreadyReportedErr(SourceConfigName, ErrorMessage, Interval = 60) As %Boolean
{
    set datetime=$H, day=+datetime, seconds=$p(datetime,",",2)
    kill ^FilterAlerts("Err",day-1)  // Purge previous day
    if $data(^FilterAlerts("Err",day,seconds\Interval,$extract(ErrorMessage,1,200))) {
        quit 1
    } else {
        set ^FilterAlerts("Err",day,seconds\Interval,$extract(ErrorMessage,1,200))=""
    }
    quit 0
}

/// True if any alert was already produced for this Ensemble session today.
ClassMethod AlreadyReportedPerSession() As %Boolean
{
    set SessionId=%Ensemble("SessionId"), day=+$H
    kill ^FilterAlerts("Session",day-1)
    if ($data(^FilterAlerts("Session",day,SessionId))) {
        quit 1
    } else {
        set ^FilterAlerts("Session",day,SessionId)=""
    }
    quit 0
}

}
```

Wire it in the `Ens.Alert` routing rule as a guard:

```
when AlreadyReportedErr(Document.SourceConfigName, Document.AlertText, 60) → skip
```

Both halves of that expression are load-bearing, and getting either wrong fails in a way the error
does not name (#113):

- **Call the FunctionSet method by BARE NAME — never qualify it with its package.** The rule
  expression parser resolves methods across every `Ens.Rule.FunctionSet` subclass in the namespace,
  which is what the FunctionSet pattern is for. A qualified call does not parse:
  `<Ens>ErrInvalidToken` at the offset of the `.`, surfacing as `#5490` running the generator for
  `evaluateRuleDefinition` and `#5030` compiling the rule class — none of which says "drop the
  package".
- **Reach message fields through `Document.`.** With `context="EnsLib.MsgRouter.RoutingEngine"` the
  bare form `AlreadyReportedErr(SourceConfigName, AlertText, 60)` **compiles** and is still wrong:
  the engine context has `Document` and does not have `SourceConfigName` or `AlertText` — those are
  properties of the `Ens.AlertRequest` message. The rule then builds and silently guards nothing,
  which is the worse of the two failures.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch07_alerting/alert-dedup-functionset.cls`.

Notes on the dedup design:

- Truncates the error message to 200 chars so per-occurrence variation (stack frames, transient values) doesn't defeat the dedup.
- Bucket key is `seconds \ Interval` — coarse time bins, so concurrent failures in the same bin dedup correctly.
- Stores in `^FilterAlerts` (a regular global, not `^IRISTemp.*`) so dedup survives a process restart. The kill of `day-1` keeps the global from growing unbounded.

## Per-BO settings checklist

Audit these on every Business Operation (and the file equivalent for File BSes that can fail):

| Setting | Recommended | Why |
|---|---|---|
| `Send Alert on Error` | ✔ — except `Ens.Alert` and the alert sink BO | Without it, exceptions land in the Event Log only. |
| `Alert on Queue Wait` (`QueueWaitAlert`) | `30` (seconds) | Catches messages piling up when the downstream is slow but not erroring. |
| `Failure Timeout` | Finite — **never `-1`** | `-1` means retry indefinitely. Pile-up against an unreachable target consumes queue slots forever. |
| `Reply Code Actions` (HL7 BO) | Review per-host | Defaults may swallow application-level NACKs as suspended messages. See decision matrix below. |

### `ReplyCodeActions` defaults can mask application errors

The default HL7 BO `ReplyCodeActions` (`:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C`) leaves application-level errors as **Suspended** messages. For integrations that **legitimately** return negative ACKs (rejected admissions, rejected orders, business-rule denials), this turns every business rejection into a suspended message that operations has to deal with manually.

For a BO whose calling BP wants to inspect the ACK/NACK itself, override to:

```
:?R=C,:?E=C,:~=C,:?A=C,:*=C,:I?=C
```

This **Completes** the message regardless of reply code; the BP gets the response and decides what to do.

| Symbol | Meaning |
|---|---|
| `C` | Complete the message — no retry, no alert. |
| `S` | Suspend — manual operator action required. |
| `R` | Retry. |
| `F` | Fatal — kill the production session. |
| `W` | Warning — log but continue. |

Default behaviour is right when the BO's ACK is a true error signal. Override when the partner uses NACKs for business outcomes.

## When alerts should NOT fire

Some failure modes are expected and shouldn't page anyone:

- **Lookup-table misses** (handled in DTL) — usually a DTL test should produce a routing-rule decision, not an alert.
- **Validation rejections at the BS edge** — return an error response or send to a dead-letter folder; don't alert per-rejection.
- **Scheduled-task "no work to do"** results — silence by checking for the well-known empty-input status before raising.

Tune by adding routing-rule guards in `Ens.Alert` rather than disabling `Send Alert on Error` on the source host. Disabling at the source means the alert can't be re-enabled retroactively when you change your mind; filtering at the router preserves the alert stream as a recoverable resource.

## ProductionMonitorService — what it actually does

Keep the item and the class apart, as in the wiring above: the production **item** is conventionally named `Ens.ProductionMonitorService`, and the `ClassName` it runs is **`Ens.MonitorService`**. It is that class which *"checks all hosts for inactivity"* — polling every interval (default 30 s) and feeding the production monitor screen.

The class that happens to share the item's name, `Ens.ProductionMonitorService`, is a **different** real class doing a different job: it watches production *status* and calls `UpdateProduction` once it notices the production is not up-to-date. Wiring that class where `Ens.MonitorService` belongs fails silently — both names resolve.

Neither class sends an alert by itself — that's the role of `Ens.Alert`. Without the monitor service, the portal monitor screen stops updating; alerts still fire.

Run the monitor service even on small productions; the cost is one process, the benefit is the portal screen actually shows current state.

## Public FHIR Façade operational requirements

If the production is a public FHIR Façade, four monitoring concerns are mandatory beyond the standard alert circuit:

1. Listing of registered users (enrolment trail).
2. Listing of users + data they submitted.
3. Errors in observation reception.
4. OAuth login error log.

These don't replace the alert circuit — they sit alongside it. See `fhir`.

## Common pitfalls

- **`Send Alert on Error` enabled on `Ens.Alert` itself or on the alert sink BO** → infinite alert loop. The portal won't warn.
- **No dedup function set in `Ens.Alert`** → cascading alerts and retry storms flood the mailbox; oncall starts ignoring the channel.
- **`Failure Timeout = -1`** → infinite retries; always finite — see the per-BO settings checklist above.
- **No `Ens.ProductionMonitorService`** → portal monitor screen stops updating; status feels real-time but is stale.
- **Disabling `Send Alert on Error` on a "noisy" host** instead of filtering in the router → loses recoverability if the noise was actually a real condition you started ignoring.
- **Storing the dedup state in `^IRISTemp.*`** → dedup resets on process restart. Use a regular global (see the dedup function notes above).
- **Per-occurrence variation in the error message** (PIDs, timestamps, stack frames) defeats simple dedup keys → truncate to first 200 chars or hash the constant prefix.

## Testing the alert circuit

1. Build a tiny test BO that fails on demand (raise a `%Status` error in its `OnMessage`).
2. Wire it to the production; send one test message.
3. Verify the alert email arrives.
4. Send the same test message N times in quick succession.
5. Verify dedup: with `Interval=60`, exactly **one** email for all N.
6. Wait `Interval+10` seconds, send again — should produce a new email.

If step 5 produces N emails, the dedup wiring is wrong (rule not triggering, function set not loaded, or guard logic inverted).

## When NOT to use this skill — fall back to docs

- IAM / Kong rate-limit-based alerting — separate product; see InterSystems IAM docs.
- SAM (System Alerting and Monitoring) for platform-level metrics (CPU, journal, license) — that's a Prometheus/Grafana topic on the IRIS instance, orthogonal to interop alerting.
- Application-specific business alerting (e.g. "patient census above threshold") — that's domain logic in a BP, not the `Ens.Alert` circuit.

## See also

- `production-lifecycle` — production XML structure, where the alert items sit.
- `bpl` — `Ens.Alert` routing-rule structure, including how to call the dedup function set from a rule.
- `business-operations` — per-BO settings (`Failure Timeout`, `ReplyCodeActions`) in the broader BO context.
- `message-search-debug` — searching for `Ens.AlertRequest` messages, resending after a fix.
- `fhir` — FHIR Façade operational monitoring requirements.
