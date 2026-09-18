/// Rule: BestPractices_Interop_IRIS.md §4.10 "FHIR interop — the Facade wiring, and why it needs a Foundation namespace"
/// Validity: Verified against IRIS for Health Community 2026.1 in a Foundation namespace.
/// Severity: Medium.
///
/// Pattern: the routing rule named by `production-fhir-facade.cls`, which until now pointed at
/// a class that did not exist — and compiled clean, because a <Setting> value is a string.
///
/// The message here is HS.FHIRServer.Interop.Request, not a project message class and not a raw
/// stream. That shapes what a rule can usefully test: the interesting fields are the request's
/// own properties (the FHIR interaction and the resource type), NOT properties of a payload —
/// the payload is a stream referenced by QuickStreamId. A rule that tries to reach into the
/// resource body is reaching for something that is not there.
///
/// Constraining on msgClass keeps the rule honest if a second, non-FHIR input is ever pointed at
/// this router: without it the catch-all `when 1` would forward anything at all to a FHIR
/// operation, which fails downstream rather than here.
Class Example.RUL.FhirRouting Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="Example.Productions.FhirFacade">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="ForwardFhirRequest" disabled="false">
<constraint name="msgClass" value="HS.FHIRServer.Interop.Request"/>
<when condition="1">
<send transform="" target="BO.FhirOut"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
