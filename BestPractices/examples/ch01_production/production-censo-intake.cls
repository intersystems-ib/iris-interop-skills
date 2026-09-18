/// Rule: BestPractices_Interop_IRIS.md §1.12 "Production class — the wiring IS the deliverable"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: Medium.
///
/// Pattern: a complete production for a delimited-file intake — CSV in, RecordMap, router,
/// outbound. Read this next to §1.11's RecordMap definition (examples/ch01_production/recordmap-censo.cls).
///
/// THE POINT OF THE EXAMPLE: there is NO custom Business Service here, and that is correct.
/// EnsLib.RecordMap.Service.FileService supplies the file adapter, the poll loop and the
/// per-record dispatch. Writing an Ens.BusinessService subclass for a RecordMap flow is always
/// wrong, and subclassing the FileService to reshape records does not work either —
/// FileService.OnProcessInput receives the whole file as a %Stream.Object and has no per-record
/// hook, so the override replaces the loop it was meant to use (§1.11). Reshaping belongs in a
/// DTL on the router.
///
/// TARGET="Host" vs TARGET="Adapter" IS THE THING TO GET RIGHT. The Portal lists both in one
/// panel, which hides the distinction, and a setting on the wrong target is accepted silently
/// and simply never read:
///   Host    — RecordMap, TargetConfigNames, HeaderCount, AlertOnError, PoolSize
///   Adapter — FilePath, FileSpec, Charset, ArchivePath, WorkPath, CallInterval
///
/// CallInterval is an ADAPTER setting and it is the answer to "how long before the file is
/// picked up" — default 5s, minimum 0.1 (EFIL). It is why a blind `sleep` is never the way to
/// test an inbound; see business-services §"Waiting for a file BS to pick the file up".
///
/// ArchivePath is set deliberately. Without it the adapter's disposal of the input file depends
/// on the Delete From Server setting, and a run that fails leaves you without the sample to
/// re-run (EFIL's six-scenario table). During development, archiving makes every run repeatable.
///
/// AlertOnError=1 on every runtime item, and NOT on the alert path itself — Ens.Alert and the
/// operation that sends the alert must have it OFF or a failing alert loops forever (§7.1).
///
/// Category equals the package root, and item names follow <Tipo>.<Nombre>. Both are load-bearing:
/// Category drives deployment tooling and the Portal filter, and the item name is what
/// TargetConfigNames and JGService resolve against, character for character.
Class Example.Productions.CensoIntake Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.CensoIntake" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>CSV census intake: file in, RecordMap, router, outbound.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BS.Censo" Category="Example" ClassName="EnsLib.RecordMap.Service.FileService"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="RecordMap">Example.RecordMap.Censo</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Router.Censo</Setting>
    <Setting Target="Host" Name="HeaderCount">1</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="FilePath">/data/censo/in/</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.csv</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/data/censo/archive/</Setting>
    <Setting Target="Adapter" Name="Charset">UTF-8</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>

  <Item Name="Router.Censo" Category="Example" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="BusinessRuleName">Example.RUL.CensoRouting</Setting>
    <Setting Target="Host" Name="AlertOnBadMessage">1</Setting>
    <Setting Target="Host" Name="BadMessageHandler">BO.CensoBad</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BO.Census" Category="Example" ClassName="EnsLib.File.PassthroughOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="FilePath">/data/censo/out/</Setting>
  </Item>

  <!-- The bad-message sink, and it must be a DIFFERENT item from the rule's target. Until
       v1.25.0 BadMessageHandler above named BO.Census, which is exactly where the routing rule
       sends accepted records, so a rejected one was written to the normal output directory
       beside the good ones and nothing could tell them apart. Found by tier-1 C11, which was
       written for the same collision in the §2.10 HL7 production and caught this one too. -->
  <Item Name="BO.CensoBad" Category="Example" ClassName="EnsLib.File.PassthroughOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="FilePath">/data/censo/bad/</Setting>
  </Item>

  <!-- The alert circuit itself must NOT alert on its own errors, or a failing alert loops. -->
  <Item Name="Ens.Alert" Category="Example" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>

</Production>
}

}
