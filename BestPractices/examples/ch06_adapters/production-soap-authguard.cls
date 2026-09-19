/// Rule: BestPractices_Interop_IRIS.md §6.19 "HTTP Basic on an inbound SOAP service: `OnPreWebMethod` denies by raising a fault, never by returning a status"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and started.
/// Severity: Medium (the fixture; the finding it makes visible is CRITICAL).
///
/// Pattern: the smallest production that lets `soap-inbound-onprewebmethod-auth.cls` be called at all.
///
/// WHY A PRODUCTION IS PART OF THIS SAMPLE, and it is a finding in its own right. An
/// `EnsLib.SOAP.Service` will not dispatch without a running production. Measured, with no production
/// up, a perfectly credentialed SOAP POST comes back:
///
///     HTTP 500   faultstring "Server Application Error"
///     <detail> ERROR <Ens>ErrProductionNotRunning: No production is running </detail>
///
/// and `OnPreWebMethod` **never runs** — the counter inside it stays at 0. A plain `%SOAP.WebService`
/// with the same callback runs it happily with no production, so the requirement comes from the
/// `Ens.BusinessService` half of the lineage, not from the callback.
///
/// THE TRAP THAT CREATES. "I stopped the production and the endpoint refused my request" is not
/// evidence that the auth guard works. A stopped production refuses EVERYTHING, with a fault generic
/// enough to be mistaken for a denial. Any test of this guard must therefore prove a *permitted*
/// request gets through first — which is why the oracle's positive control runs before its denials.
Class Example.Productions.SoapAuthGuardFixture Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.SoapAuthGuardFixture" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>The §6.19 SOAP inbound guard plus a sink, so a permitted call has somewhere to land.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <!-- THE ITEM NAME IS THE CLASS NAME, and that is deliberate. Everywhere else in interop an item is
       named <Tipo>.<Name> and a class name is the wrong thing to use. A direct-mode SOAP service is
       the exception: the CSP dispatcher resolves the config item from the class it was reached
       through, so an item named BS.SoapAuthGuard leaves the endpoint answering
       ErrBusinessDispatchNameNotRegistered: Business dispatch name 'Example.BS.SoapAuthGuard' is not
       registered to run.
       PoolSize 0: inbound is driven by the CSP request, not by a polling job. An Item's content
       model is (Setting*), so a Description element inside one does not compile. -->
  <Item Name="Example.BS.SoapAuthGuard" Category="Example" ClassName="Example.BS.SoapAuthGuard"
        PoolSize="0" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
  </Item>

  <Item Name="BO.Sink" Category="Example" ClassName="Example.BO.MessageSink"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>

</Production>
}

}
