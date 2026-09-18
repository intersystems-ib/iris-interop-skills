/// Rule: BestPractices_Interop_IRIS.md §1.11 "RecordMap file intake — configure the prebuilt service, never subclass it"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: Medium.
///
/// Pattern: the routing rule named by `production-censo-intake.cls`. It exists so that the
/// production is honest — a BusinessRuleName pointing at a class nobody wrote compiles clean,
/// because a <Setting> value is only a string.
///
/// This is also where the RESHAPING belongs for a RecordMap flow. You do not subclass the
/// FileService to turn a record into a project message (§1.11 — its OnProcessInput receives the
/// whole file as a stream and has no per-record hook). You put a DTL on the rule's <send>, where
/// it is declarative, visible in the Portal, and testable on its own with %UnitTest.
///
/// The context is the GENERIC RoutingEngine here, and that is correct: the message is a
/// RecordMap .Record, not an EnsLib.HL7.Message. CR-6 is about HL7 flowing through a generic
/// router — a non-HL7 flow through the generic engine is the intended use, not a violation.
Class Example.RUL.CensoRouting Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="Example.Productions.CensoIntake">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="RouteCensusRecord" disabled="false">
<when condition="1">
<send transform="" target="BO.Census"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
