# Operating a production over time — per-BO SOAP tracing, retention and purge

Housekeeping and deep-diagnostic depth. Neither is needed to find, resend or triage a message:
read this when tuning an installation that has been running for a while, or when a SOAP BO needs
envelope-level tracing.

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

Worked example: `assets/alt-soap-webclient-tracing.cls`.

## Retention and purge

Persistent messages and message-body tables grow unbounded. Without a purge task scheduled, `Ens.MessageHeader` and every custom-message-class table accumulate forever.

Add `Ens.Util.Tasks.Purge` to the production at creation time, scheduled daily. Set `NumDaysToKeep` per the customer's retention policy:

- **30 days** — typical default for development environments and low-criticality flows.
- **90 days** — common for production where operational lookback is the only requirement.
- **Longer** — only if a regulatory or contractual retention requirement applies, in which case the messages probably belong in a separate audit store, not in `Ens.MessageHeader`.

The purge task removes both `Ens.MessageHeader` rows and the corresponding message-body table rows. Auditing an existing production, flag the absence of the purge task as a gap (xref `alerting` baseline checklist).

Verify purge actually runs: Management Portal → Interoperability → Manage → System Tasks → check the last-run timestamp and any errors.
