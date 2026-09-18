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
///
/// THE FUNCTIONSET CALLS ARE BARE, AND THAT IS NOT A STYLE CHOICE. Compiled both ways on 2026.1
/// in this exact context:
///     AlreadyReportedPerSession()=1                             -> COMPILES
///     ##class(Demo.FilterAlerts.FunctionSet).AlreadyReported...  -> FAILS
///         ERROR <Ens>ErrParsingExpression ... <Ens>ErrInvalidToken
/// The rule expression parser resolves methods across every `Ens.Rule.FunctionSet` subclass in the
/// namespace — that is the whole point of the FunctionSet pattern — and qualifying the call defeats
/// it. The superseded `alert-circuit-production.xml` carried the qualified form in both conditions
/// and was therefore unloadable, which no tier could see because it was `.xml`.
///
/// ORDER IS THE LOGIC. The two dedup rules `<return/>` with no `<send>`, which consumes the alert;
/// the forward rule is last and unconditional. Put the forward rule first and the dedup rules can
/// never run — the rule set stops at the first match, so a mis-ordered set is a dedup that silently
/// does nothing.
///
/// The functions come from `alert-dedup-functionset.cls` in this directory
/// (`Demo.FilterAlerts.FunctionSet`); this rule is what actually exercises them.
Class Example.Alerting.RUL.AlertRouter Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="Example.Alerting.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="DedupBySession" disabled="false">
<constraint name="msgClass" value="Ens.AlertRequest"/>
<when condition="AlreadyReportedPerSession()=1">
<return/>
</when>
</rule>
<rule name="DedupByErrorText" disabled="false">
<constraint name="msgClass" value="Ens.AlertRequest"/>
<when condition="AlreadyReportedErr(Document.SourceConfigName,Document.AlertText,60)=1">
<return/>
</when>
</rule>
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
