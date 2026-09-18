/// Rule: BestPractices_Interop_IRIS.md §2.10 "HL7 file intake — the prebuilt HL7 service and the HL7-SPECIFIC router"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (the wrong assist class matches nothing, silently).
///
/// Pattern: the routing rule for an HL7 flow — the half that `production-hl7-intake.cls` names
/// in BusinessRuleName and that, until now, did not exist. A production whose BusinessRuleName
/// points at nothing still compiles: a <Setting> value is a string, so nothing in tier 2 can
/// see it. Tier 1 C8 checks it now.
///
/// THE ASSIST CLASS IS THE WHOLE DIFFERENCE, and getting it wrong fails silently.
///   EnsLib.HL7.MsgRouter.RuleAssist   <- HL7. Gives docCategory/docName constraints and
///                                        {MSH:9.1} path syntax in conditions.
///   EnsLib.MsgRouter.RuleAssist       <- generic. The rule still compiles and still loads;
///                                        it simply never matches an HL7 message the way you
///                                        expect, and a router that matches nothing reports
///                                        no error. Pair it with the generic RoutingEngine
///                                        and you have CR-6.
/// The assist class and the RoutingEngine class must agree: HL7 assist with
/// EnsLib.HL7.MsgRouter.RoutingEngine, generic with EnsLib.MsgRouter.RoutingEngine.
///
/// CONSTRAIN BY docCategory/docName, NOT by a raw MSH:9.1 string compare. That is CR-5. A
/// string compare on MSH:9.1 ties the rule to one schema version's spelling and skips the
/// schema resolution entirely, so the same message under 2.5.1 stops matching with no
/// diagnostic. docCategory/docName are resolved against the DocType the service assigned via
/// MessageSchemaCategory — which is why that setting on the service is load-bearing for the
/// ROUTER, not just for the service.
Class Example.RUL.AdtRouting Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="Example.Productions.Hl7Intake">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="AdmitAndTransfer" disabled="false">
<constraint name="docCategory" value="2.5"/>
<constraint name="docName" value="ADT_A01"/>
<when condition="Document.{MSH:9.1}=&quot;ADT&quot;">
<send transform="" target="BO.AdtOut"/>
<return/>
</when>
</rule>
<rule name="EverythingElse" disabled="false">
<constraint name="docCategory" value="2.5"/>
<when condition="1">
<send transform="" target="BO.AdtOut"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
