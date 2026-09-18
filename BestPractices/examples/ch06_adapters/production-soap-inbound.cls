/// Rule: BestPractices_Interop_IRIS.md §6.17 "A SOAP inbound service has two deployment modes, and `EnableStandardRequests` only exists in one of them"
/// Validity: Verified against IRIS for Health 2026.1 — compiled, both items registered.
/// Severity: High (the setting is mandatory in one mode and unsettable in the other).
///
/// Pattern: the SOAP inbound production, wiring **both** modes side by side so the difference is
/// readable in one file. Before this, `EnableStandardRequests` appeared **nowhere** in the bank.
///
/// THE TWO ITEMS ARE THE POINT:
///
///   BS.SoapAdapter   Example.BS.SoapAdapterMode   keeps the inherited EnsLib.SOAP.InboundAdapter.
///                    Carries `Target="Adapter" EnableStandardRequests = 1`, because the adapter's
///                    own default is 0 and an unset one fails the FIRST call with
///                    `<Ens>ErrSOAPNotEnabled: Adapter Setting EnableStandardRequests is not set`.
///
///   Example.BS.MyService   named by its FQCN, and blanks its adapter on purpose. It carries NO
///                    `EnableStandardRequests` at all — there is no adapter instance to route one to,
///                    and adding it would be a setting that silently applies to nothing.
///
/// WHY THE SECOND ITEM'S NAME IS A CLASS NAME, breaking the `<Tipo>.<Name>` convention every other
/// item in this bank follows: for a direct-inbound SOAP service the production item Name must equal
/// the **FQCN of the web-service class**, or URL dispatch cannot resolve the WSDL. That is the one
/// documented exception to the item-naming rule, and it is worth the ugliness because the alternative
/// is an endpoint that 404s with nothing in the Event Log. `soap-bo` states it; this is the first
/// gated production that shows it.
///
/// THE FAILURE IS LOUD BUT MISDIRECTING, which is why the coverage map's "silent" label was wrong.
/// `<Ens>ErrSOAPNotEnabled` names the SETTING and not the TARGET, so the reader's next move is to set
/// the same setting again — on the host, where the Portal accepts it without complaint and nothing
/// changes. The cost is the round trip, not the silence.
Class Example.Productions.SoapInbound Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.SoapInbound" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>SOAP inbound, both modes: adapter-dispatched and direct CSP-dispatched.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <!-- ADAPTER MODE. The service kept EnsLib.SOAP.InboundAdapter, so the adapter exists and the
       setting has somewhere to land. Its default is 0: unset, the first call dies. -->
  <Item Name="BS.SoapAdapter" Category="Example" ClassName="Example.BS.SoapAdapterMode"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="EnableStandardRequests">1</Setting>
    <Setting Target="Adapter" Name="Port">8801</Setting>
    <Setting Target="Host" Name="TargetConfigNames">BP.OrderProcess</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <!-- DIRECT MODE. The item Name IS the web-service class's FQCN, which is the one documented
       exception to the Tipo.Name item convention; without it URL dispatch cannot resolve the WSDL.
       No EnableStandardRequests here: this service blanked its adapter, so there is no adapter
       instance and such a setting would apply to nothing. -->
  <Item Name="Example.BS.MyService" Category="Example" ClassName="Example.BS.MyService"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BP.OrderProcess" Category="Example" ClassName="Example.BP.OrderProcess"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

</Production>
}

}
