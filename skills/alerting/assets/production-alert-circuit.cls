/// Rule: BestPractices_Interop_IRIS.md §7.1 "Alert circuit — the canonical pattern"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (every break in this circuit is silent).
///
/// Pattern: the canonical Ens.Alert circuit, as a COMPILED class. It replaces
/// alert-circuit-production.xml, which tier 2 skipped because it is not a `.cls` — and which was
/// shipping a rule that **cannot compile**. See "What the conversion found" below.
///
/// THE FOUR LINKS, and not one of them produces a diagnostic when wrong:
///   1. the router item must be named literally `Ens.Alert`. The framework routes Ens.AlertRequest
///      to that name and to nothing else; rename it and alerts vanish with no error.
///   2. its rule must actually match. A rule that matches nothing consumes alerts and drops them.
///   3. `AlertOnError` must be **1** on ordinary hosts — that is what FEEDS the circuit — and **0**
///      on `Ens.Alert` and on the sink operation, or a failing alert alerts about itself, forever.
///   4. a finite `FailureTimeout` on the ordinary host, or a retrying operation never gives up and
///      therefore never raises the alert at all.
/// A system that has never alerted and a system whose circuit is broken look identical from
/// outside. That is the whole argument for compiling this rather than describing it.
///
/// BO.DemoOutbound IS NOT DECORATION. A circuit wired but never fed is conformance finding CR-3:
/// it is structurally present and cannot fire. This ordinary HL7 operation carries AlertOnError=1
/// and is what makes the file show a FED circuit. Every host in a real production looks like this
/// one except `Ens.Alert` and the sink.
///
/// WHAT THE CONVERSION FOUND, and it is the reason this file exists rather than a tidy-up. The XML
/// this replaces carried its dedup conditions in the PACKAGE-QUALIFIED form:
///     ##class(Demo.FilterAlerts.FunctionSet).AlreadyReportedPerSession()=1
/// Compiled on 2026.1, both spellings, in the rule context:
///     AlreadyReportedPerSession()=1                            -> COMPILES
///     ##class(Demo.FilterAlerts.FunctionSet).AlreadyReported…  -> FAILS
///         ERROR <Ens>ErrParsingExpression … <Ens>ErrInvalidToken
/// So the shipped XML could not be loaded at all, while its own header instructed the reader to
/// `$system.OBJ.Load()` it. No tier compiled it, so it shipped broken across many releases. The
/// rule expression parser resolves FunctionSet methods across every `Ens.Rule.FunctionSet` subclass
/// in the namespace — that is what the pattern is for — and qualifying the call defeats it.
///
/// Adapter vs Host, verified against the dictionary rather than assumed: `SMTPServer`, `Recipient`
/// and `From` live on `EnsLib.EMail.OutboundAdapter` (Target="Adapter"); `AlertOnError`,
/// `FailureTimeout` and `QueueWaitAlert` are Host settings. A setting on the wrong target is
/// accepted silently and never read.
Class Example.Alerting.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Alerting.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <Description>Canonical alert circuit (§7.1), fed by an ordinary business host.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <!-- Heartbeat for production health (§1.6 baseline). -->
  <Item Name="Ens.ProductionMonitorService" Category="Alerting" ClassName="Ens.MonitorService"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
  </Item>

  <!-- MUST be named exactly Ens.Alert. AlertOnError=0: this item must never alert on itself. -->
  <Item Name="Ens.Alert" Category="Alerting" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
    <Setting Target="Host" Name="BusinessRuleName">Example.Alerting.RUL.AlertRouter</Setting>
  </Item>

  <!-- The sink. AlertOnError=0 here too, or a failed send alerts about the failed send. -->
  <Item Name="BO.AlertEmail" Category="Alerting" ClassName="EnsLib.EMail.AlertOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
    <Setting Target="Adapter" Name="SMTPServer">smtp.example.org</Setting>
    <Setting Target="Adapter" Name="Recipient">interop-alerts@example.org</Setting>
    <Setting Target="Adapter" Name="From">iris-interop@example.org</Setting>
  </Item>

  <!-- An ORDINARY host, and the only reason the circuit above ever fires (CR-3). -->
  <Item Name="BO.DemoOutbound" Category="Demo" ClassName="EnsLib.HL7.Operation.TCPOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="QueueWaitAlert">30</Setting>
    <Setting Target="Host" Name="FailureTimeout">30</Setting>
    <Setting Target="Adapter" Name="IPAddress">hl7.example.org</Setting>
    <Setting Target="Adapter" Name="Port">5000</Setting>
  </Item>

</Production>
}

}
