/// Rule: BestPractices_Interop_IRIS.md §2.10 "HL7 file intake — the prebuilt HL7 service and the HL7-SPECIFIC router"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (a generic router silently loses schema validation).
///
/// Pattern: HL7 v2 file intake. As with RecordMap, no custom Business Service is written —
/// EnsLib.HL7.Service.FileService is configured, not subclassed.
///
/// THE ONE CHOICE THAT MATTERS, and it is CR-6: the router is
/// EnsLib.HL7.MsgRouter.RoutingEngine, NOT the generic EnsLib.MsgRouter.RoutingEngine. The
/// generic engine transports an EnsLib.HL7.Message perfectly well, so an end-to-end test passes
/// either way — what it loses is schema validation in the rule editor and the {MSH:9.1} path
/// syntax in rules. The failure is therefore invisible until someone tries to write a rule.
///
/// MessageSchemaCategory on the service is what gives every parsed message its DocType. Without
/// it the message arrives with no schema, and symbolic field names stop resolving everywhere
/// downstream — a segment obtained from a message INHERITS the message's DocType, so an unset
/// category silently degrades every DTL to numeric paths (transformations §"Path resolution").
///
/// Validation="dm" on the router means "validate DocType and message structure". It is what
/// makes a malformed message land on the BadMessageHandler instead of flowing on as if it were
/// fine. A custom schema is NOT tested by parsing alone — only a router with validation on
/// checks segment ORDER (hl7-schemas §"Verification part 2").
Class Example.Productions.Hl7Intake Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.Hl7Intake" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>HL7 v2 file intake: ADT in, HL7-specific router, file out.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BS.Adt" Category="Example" ClassName="EnsLib.HL7.Service.FileService"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Router.Adt</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="FilePath">/data/hl7/in/</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/data/hl7/archive/</Setting>
    <Setting Target="Adapter" Name="Charset">UTF-8</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>

  <!-- HL7-SPECIFIC router. The generic EnsLib.MsgRouter.RoutingEngine would transport the
       message fine and lose schema validation + {MSH:9.1} paths in the rule editor: CR-6. -->
  <Item Name="Router.Adt" Category="Example" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="BusinessRuleName">Example.RUL.AdtRouting</Setting>
    <Setting Target="Host" Name="Validation">dm</Setting>
    <Setting Target="Host" Name="AlertOnBadMessage">1</Setting>
    <Setting Target="Host" Name="BadMessageHandler">BO.AdtOut</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BO.AdtOut" Category="Example" ClassName="EnsLib.HL7.Operation.FileOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="FilePath">/data/hl7/out/</Setting>
  </Item>

  <Item Name="Ens.Alert" Category="Example" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>

</Production>
}

}
