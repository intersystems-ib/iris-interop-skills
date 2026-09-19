/// Rule: BestPractices_Interop_IRIS.md §12.6 "Resend and edit-and-resend: two APIs, and the shared body row that rewrites history"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, started, and messages delivered through it.
/// Severity: Low on its own (it is a fixture); High for what it makes testable.
///
/// Pattern: the smallest production a resend test can run against — two queued sinks and nothing else.
///
/// TWO ITEMS, NOT ONE, AND THAT IS THE WHOLE DESIGN. `ResendDuplicatedMessage`'s third argument is
/// `pNewTarget`, and "resend somewhere else" is the case operators actually use: a message failed at
/// one operation and is redirected to another. With a single item, a test could not tell a resend that
/// honoured `pNewTarget` from one that ignored it — both would deliver to the same place.
///
/// NO ADAPTERS, NO PORTS, NO FILESYSTEM. A fixture production that listens on a port fails in CI for
/// reasons that have nothing to do with what is being tested, and a fixture that writes files leaves
/// state behind. Both items are adapter-less operations reachable only by queue.
///
/// AND NOTHING SENDS INTO IT. There is no Business Service: the tests create headers directly, which
/// is the situation a resend is in anyway — the original message already exists and the question is
/// what a resend does with it.
Class Example.Productions.ResendFixture Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.ResendFixture" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Fixture for the resend / edit-and-resend tests: two queued sinks, no adapters.</Description>
  <ActorPoolSize>1</ActorPoolSize>

  <Item Name="BO.Sink" Category="Example" ClassName="Example.BO.MessageSink"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BO.Reprocess" Category="Example" ClassName="Example.BO.MessageSink"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

</Production>
}

}
