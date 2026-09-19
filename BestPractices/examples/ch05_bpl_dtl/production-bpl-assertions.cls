/// Rule: BestPractices_Interop_IRIS.md §5.23 "Asserting a BPL ran: `$IsObject(resp)` passes on a process that failed every call"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and started.
/// Severity: Medium (the fixture).
///
/// Pattern: both BPL shapes in one production, so the oracle can send the SAME failing input to each and
/// assert the difference rather than one behaviour in isolation.
///
///     BP.SwallowedFault   catchall records, does NOT propagate   -> caller sees $$$OK
///     BP.ScopedOrder      catchall records AND propagates        -> caller sees an error
///
/// `TestingEnabled="true"` is required for `%UnitTest.TestProduction.SendRequest()` to reach these items
/// at all — see `tdd`'s section on enabling the Testing Service.
Class Example.Productions.BplAssertions Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.BplAssertions" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Fixture for §5.23: the swallowing and propagating BPLs side by side.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <!-- The defect, on purpose. See bpl-scope-swallow-fixture.cls. -->
  <Item Name="BP.SwallowedFault" Category="Example" ClassName="Example.BP.SwallowedFault"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>

  <!-- The honest shape, shipped by §5.21, here purely as the contrast. -->
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
