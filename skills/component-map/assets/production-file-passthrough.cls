/// Rule: BestPractices_Interop_IRIS.md §6.10 "File passthrough relay — Ens.StreamContainer, and the read that only works once"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: Medium (the wiring); the silent part is in the consumer, see bo-stream-container-consumer.cls.
///
/// Pattern: the commonest relay in the field — move a file from A to B, unchanged. Before this
/// example, `Ens.StreamContainer` had ZERO hits across all 20 skills and the whole bank, while
/// `production-lifecycle` already wired `EnsLib.File.PassthroughOperation` as the canonical alert
/// sink. The commonest shape in production was the least documented here.
///
/// NO CUSTOM CLASSES AT ALL, and that is the lesson. Both halves are prebuilt:
///   EnsLib.File.PassthroughService    polls, reads the file, wraps it in Ens.StreamContainer
///   EnsLib.File.PassthroughOperation  receives the container and writes it out
/// Verified: PassthroughOperation's `OnMessage(pRequest As Ens.StreamContainer, ...)` — the message
/// body travelling between them is an Ens.StreamContainer, not a project message class and not a
/// raw stream.
///
/// `Ens.StreamContainer` IS NOT AN `Ens.Request`. Verified superclass list:
/// `(%Library.Persistent, Ens.Util.MessageBodyMethods, %XML.Adaptor)`. Two consequences people trip
/// on: a DTL over a relay operates on the CONTAINER (and its `Stream`), not on properties; and
/// `%Persistent` is leftmost here, exactly as §5.10 requires of your own message classes — the
/// platform follows its own rule.
///
/// NO ROUTER, DELIBERATELY. A relay makes no routing decision, so `TargetConfigNames` goes straight
/// to the operation. Inserting a MessageRouter whose rule always sends to one target adds a queue,
/// a session hop and a rule class to maintain, and decides nothing. Add the router when there is an
/// actual decision — a second destination, a content test — not before.
///
/// ARCHIVEPATH IS SET FOR THE SAME REASON AS EVERYWHERE ELSE IN THIS BANK: without it the input
/// file's fate depends on `DeleteFromServer`, and a failed run can leave you with no sample to
/// re-run. During development, archiving makes every run repeatable (EFIL's six-scenario table).
Class Example.Productions.FileRelay Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.FileRelay" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>File passthrough relay: read a file, hand it on unchanged as an Ens.StreamContainer.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BS.Relay" Category="Example" ClassName="EnsLib.File.PassthroughService"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="TargetConfigNames">BO.Relay</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="FilePath">/data/relay/in/</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.dat</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/data/relay/archive/</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>

  <!-- Filename is a HOST setting on the operation; FilePath is an ADAPTER setting. The Portal
       lists both in one panel, and a setting on the wrong target is accepted and never read.
       %f substitutes the container's OriginalFilename, which is the only reason the output
       keeps the input's name. -->
  <Item Name="BO.Relay" Category="Example" ClassName="EnsLib.File.PassthroughOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="Filename">%f</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="FilePath">/data/relay/out/</Setting>
  </Item>

  <!-- NO Ens.Alert ITEM HERE, DELIBERATELY. This production carried one until v1.33.0, with
       AlertOnError=0 and no BusinessRuleName — and an Ens.Alert router with no rule is WORSE than
       no Ens.Alert item at all: the framework routes every Ens.AlertRequest to it and the rule that
       would forward them does not exist, so the alerts are captured and dropped in silence. Found
       by Example.UTL.PreflightValidator on its first real run (§1.15).
       The alert circuit is a production of its own — see ch07_alerting/production-alert-circuit.cls
       (§7.1), which wires Ens.Alert to a rule and a sink. The AlertOnError=1 settings on the items
       above are what FEED that circuit; they do not need a local router to be correct. -->

</Production>
}

}
