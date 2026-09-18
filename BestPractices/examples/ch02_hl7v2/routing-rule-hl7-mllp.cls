/// Rule: BestPractices_Interop_IRIS.md §1.19 "MLLP: which timeout is a Host setting and which is an Adapter one"
/// Validity: Verified against IRIS for Health 2026.1 — compiled.
/// Severity: Medium (this file exists so the MLLP production has a rule that resolves).
///
/// Pattern: the routing rule for `production-hl7-mllp.cls`. A separate file because a rule's
/// `production=` attribute PINS it: tier-1 C10 resolves every `<send target>` against the items of
/// the production the rule names, so `Example.RUL.AdtRouting` — pinned to
/// `Example.Productions.Hl7Intake` — cannot be reused by a second production even though its rule
/// logic would be identical. One rule per production is not a style choice here; it is what the
/// `production=` attribute means.
///
/// `<send target>` names `BO.MllpOut`, and the production's `BadMessageHandler` is `BO.MllpBad` —
/// deliberately a DIFFERENT item, because tier-1 C11 refuses a router whose BadMessageHandler is also
/// one of its rule's send targets. That check exists because both gated HL7 productions shipped that
/// collision until v1.25.0, which made every malformed message land where the valid ones go.
Class Example.RUL.MllpRouting Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="Example.Productions.Hl7Mllp">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="AdmitOverMllp" disabled="false">
<constraint name="docCategory" value="2.5"/>
<constraint name="docName" value="ADT_A01"/>
<when condition="Document.{MSH:MessageType.MessageCode}=&quot;ADT&quot;">
<send transform="" target="BO.MllpOut"/>
<return/>
</when>
</rule>
<rule name="EverythingElse" disabled="false">
<constraint name="docCategory" value="2.5"/>
<when condition="1">
<send transform="" target="BO.MllpOut"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
