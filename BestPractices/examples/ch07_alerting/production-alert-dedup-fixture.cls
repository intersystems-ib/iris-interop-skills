/// Rule: BestPractices_Interop_IRIS.md §7.4 "Testing the alert circuit without an SMTP server"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, started, and alerts delivered through it.
/// Severity: High for what it makes testable.
///
/// Pattern: the alert circuit of §7.1, made startable and assertable — no SMTP server, no mailbox,
/// no adapters, no ports.
///
/// WHY `Example.Alerting.Production` COULD NOT BE USED. Its ordinary host is an
/// `EnsLib.HL7.Operation.TCPOperation` pointed at `hl7.example.org:5000`, and its sink is
/// `EnsLib.EMail.AlertOperation` pointed at `smtp.example.org`. That is the right shape for a
/// document — every value is the one an operator recognises — and it cannot be started in a test
/// without a network. This production is the same circuit with both ends replaced by classes that
/// keep a receipt, so §7.1's claims become assertions instead of illustrations.
///
/// THE THREE `AlertOnError` VALUES ARE THE WHOLE CIRCUIT, and two of them are 0 on purpose:
///   BO.Failing         1   the ordinary host. This is the ONLY reason the circuit ever fires.
///   Ens.Alert          0   the router must never alert on itself -- that is an alert loop.
///   BO.AlertRecorder   0   nor must the sink, or a failed send alerts about the failed send.
///
/// `FailureTimeout` IS 2 SECONDS, WHICH WOULD BE WRONG IN PRODUCTION. §1.8 and §7.3 both say finite
/// and never `-1`; 2 is finite and absurd, chosen so a test finishes. It is called out here because a
/// value copied out of a fixture into a real production is a recognised way for a bad default to
/// travel, and 2 seconds of retry on a transient outage means giving up almost immediately.
Class Example.Productions.AlertDedupFixture Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.AlertDedupFixture" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>The §7.1 alert circuit with both ends replaced by recorders, so it can be tested.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BO.Failing" Category="Example" ClassName="Example.BO.FailOnDemand"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">2</Setting>
    <Setting Target="Host" Name="RetryInterval">1</Setting>
  </Item>

  <Item Name="Ens.Alert" Category="Example" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
    <Setting Target="Host" Name="BusinessRuleName">Example.RUL.AlertDedupFixture</Setting>
  </Item>

  <Item Name="BO.AlertRecorder" Category="Example" ClassName="Example.BO.AlertRecorder"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>

</Production>
}

}
