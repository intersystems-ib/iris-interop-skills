/// Rule: BestPractices_Interop_IRIS.md §5.21 "BPL <scope>: the fault handler that completes the process green"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, started, and messages driven through it.
/// Severity: Low on its own (a fixture); High for what it makes assertable.
///
/// Pattern: the smallest production that can exercise a `<scope>`'s fault handler — the BPL under
/// test and a target that fails on demand.
///
/// IT REUSES `Example.BO.FailOnDemand` FROM ch07 rather than adding another failing operation. That
/// BO already exists, is gated, and does exactly this: `OnMessage` returns `$$$ERROR` when the payload
/// says so. A second copy would be a second thing to keep in step.
///
/// `FailureTimeout` IS 2 SECONDS, WHICH WOULD BE WRONG IN PRODUCTION (§1.8, §7.3: finite, never -1).
/// 2 is finite and absurd, chosen so the fault reaches the scope quickly. Called out because a value
/// copied out of a fixture is a recognised way for a bad default to travel.
Class Example.Productions.BplScope Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.BplScope" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Fixture for the BPL &lt;scope&gt; fault-handler tests.</Description>
  <ActorPoolSize>1</ActorPoolSize>

  <Item Name="BP.ScopedOrder" Category="Example" ClassName="Example.BP.ScopedOrder"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>

  <Item Name="BO.Failing" Category="Example" ClassName="Example.BO.FailOnDemand"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="FailureTimeout">2</Setting>
    <Setting Target="Host" Name="RetryInterval">1</Setting>
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>

</Production>
}

}
