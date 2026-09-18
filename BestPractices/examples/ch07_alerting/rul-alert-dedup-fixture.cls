/// Rule: BestPractices_Interop_IRIS.md §7.4 "Testing the alert circuit without an SMTP server"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed as the Ens.Alert rule of a started production.
/// Severity: High (an inverted guard here suppresses every alert, and nothing reports it).
///
/// Pattern: the `Ens.Alert` router's rule, with the §7.2 dedup guards in front of the send.
///
/// THE ORDER OF THE RULES IS THE BEHAVIOUR. A rule that matches ends evaluation at its `<return/>`,
/// so the two dedup rules must come BEFORE the catch-all send. Put the send first and the guards
/// never run, and the only symptom is more email than expected — the failure that gets noticed.
/// The opposite mistake is the dangerous one: invert a guard, or leave one matching everything, and
/// the circuit goes silent. **A suppressed alert stream is indistinguishable from a healthy
/// production**, which is why `tdd-alert-dedup.cls` asserts that the first alert DOES arrive and not
/// only that the second does not.
///
/// EVERY RULE CONSTRAINS ON `msgClass`. Without it a non-alert message pointed at this router would
/// reach the guards, which call `Document.AlertText` — a property that does not exist on anything but
/// `Ens.AlertRequest` — and the rule would fail at evaluation time rather than decline to match.
///
/// This is the fixture twin of `alert-routing-rule.cls`: the same guards, bound to the startable
/// production beside it, sending to a recorder instead of to SMTP.
Class Example.RUL.AlertDedupFixture Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="Example.Productions.AlertDedupFixture">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="DedupByErrorText" disabled="false">
<constraint name="msgClass" value="Ens.AlertRequest"/>
<when condition="AlreadyReportedErr(Document.SourceConfigName,Document.AlertText,60)=1">
<return/>
</when>
</rule>
<rule name="AllAlertsToRecorder" disabled="false">
<constraint name="msgClass" value="Ens.AlertRequest"/>
<when condition="1">
<send transform="" target="BO.AlertRecorder"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
