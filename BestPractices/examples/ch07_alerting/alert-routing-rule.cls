/// Rule: BestPractices_Interop_IRIS.md §7.1 "Alert circuit — the canonical pattern"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (an alert circuit that matches nothing is indistinguishable from a quiet system).
///
/// Pattern: the rule named by `alert-circuit-production.xml`'s Ens.Alert item. That production
/// is XML, which tier 2 skips entirely — so this BusinessRuleName was not merely uncompiled,
/// it was unreachable by any gate until tier 1 C8 started reading .xml artefacts too.
///
/// THE CIRCUIT ONLY WORKS IF EVERY LINK EXISTS, and every break in it is silent:
///   - the item must be named literally `Ens.Alert` — the framework routes Ens.AlertRequest to
///     that name and nothing else;
///   - this rule must actually match, or alerts are consumed and dropped with no error;
///   - AlertOnError must be 1 on runtime items and 0 on Ens.Alert and the sink operation, or a
///     failing alert alerts about itself, forever.
/// None of those produce a diagnostic when wrong. A system that has never alerted and a system
/// whose alert circuit is broken look exactly alike from the outside — which is why this is worth
/// a compiled artefact rather than a paragraph.
///
/// The context is the generic RoutingEngine: an Ens.AlertRequest is not an HL7 message, so the
/// HL7 assist would be the wrong pairing here (the mirror image of CR-6).
Class Example.Alerting.RUL.AlertRouter Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="Example.Alerting.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="AllAlertsToEmail" disabled="false">
<constraint name="msgClass" value="Ens.AlertRequest"/>
<when condition="1">
<send transform="" target="BO.AlertEmail"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
