/// Rule: BestPractices_Interop_IRIS.md §4.10 "FHIR interop — the Facade wiring, and why it needs a Foundation namespace"
/// Validity: Verified against IRIS for Health Community 2026.1 in a Foundation namespace.
/// Severity: High (the namespace prerequisite is invisible until nothing resolves).
///
/// Pattern: a FHIR Facade — an inbound FHIR endpoint whose requests are routed through
/// interoperability to an EXTERNAL FHIR server, rather than served from a local repository.
///
/// THE PREREQUISITE THAT IS NOT A CODE PROBLEM, and which costs the most time because it
/// presents as a name problem. HS.* is NOT mapped into an ordinary namespace. In USER,
/// HS.FHIRServer.Interop.Operation simply does not exist, so every reference looks like a typo
/// and the obvious response is to go hunting for the "real" class name. There isn't one — the
/// namespace is wrong. IRIS for Health ships HSLIB/HSSYS/HSCUSTOM in the image; a FOUNDATION
/// namespace is what maps them in, and it is interop-enabled at the same time:
///
///     Do ##class(HS.Util.Installer.Foundation).Install("FHIRFOUNDATION")
///     Set $namespace = "FHIRFOUNDATION"
///     Do ##class(HS.FHIRServer.Installer).InstallNamespace()
///     Do ##class(HS.FHIRServer.Installer).InstallInstance(appKey, strategyClass, packages)
///
/// (HXFHIRINS section 2.3.1, "Programmatic FHIR Server Installation Example". The last two lines
/// create the endpoint; the first two are all this example's classes need to compile.)
///
/// Verified, and worth stating because it makes the gate cheap: a Foundation namespace is a
/// strict SUPERSET of a plain interop namespace. The whole example bank and every inline snippet
/// compile in it with byte-identical results, so the gate can simply run there and FHIR stops
/// being a special case.
///
/// THE THREE CLASSES, none of which are guessable:
///   HS.FHIRServer.Interop.Service       inbound — hands the FHIR request to the production
///   HS.FHIRServer.Interop.Operation     outbound to a LOCAL FHIR server in this namespace
///   HS.FHIRServer.Interop.HTTPOperation outbound to an EXTERNAL FHIR server over HTTP
/// The message body travelling between them is HS.FHIRServer.Interop.Request /
/// HS.FHIRServer.Interop.Response — not a project message class, and not a raw stream. A DTL
/// over a FHIR payload therefore operates on the Request's QuickStreamId, not on properties.
///
/// FACADE vs REPOSITORY, decided here by ONE item: this production uses HTTPOperation, so the
/// resources live in the external server and nothing is persisted locally. Swap it for
/// Interop.Operation and the same wiring becomes a Repository, serving from this namespace's own
/// storage. That is the whole architectural choice, and it is one ClassName.
Class Example.Productions.FhirFacade Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.FhirFacade" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>FHIR Facade: inbound FHIR endpoint, routed out to an external FHIR server.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <!-- Inbound. The FHIR endpoint's web application dispatches here; like any REST inbound there
       is no polling adapter, so the item exists to give the service a ConfigName and settings. -->
  <Item Name="BS.FhirIn" Category="Example" ClassName="HS.FHIRServer.Interop.Service"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="TargetConfigNames">Router.Fhir</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="Router.Fhir" Category="Example" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="BusinessRuleName">Example.RUL.FhirRouting</Setting>
    <Setting Target="Host" Name="AlertOnBadMessage">1</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <!-- FACADE: outbound to an EXTERNAL FHIR server. Replace this ClassName with
       HS.FHIRServer.Interop.Operation and the same production becomes a REPOSITORY,
       serving from local storage instead. -->
  <Item Name="BO.FhirOut" Category="Example" ClassName="HS.FHIRServer.Interop.HTTPOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="HTTPServer">fhir.example.org</Setting>
    <Setting Target="Adapter" Name="HTTPPort">443</Setting>
    <Setting Target="Adapter" Name="URL">/fhir/r4</Setting>
    <Setting Target="Adapter" Name="SSLConfig">FhirPartnerTLS</Setting>
    <Setting Target="Adapter" Name="Credentials">FhirPartnerCredentials</Setting>
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
