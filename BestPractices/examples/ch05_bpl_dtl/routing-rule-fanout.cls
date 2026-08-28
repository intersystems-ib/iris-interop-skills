/// Rule: BestPractices_Interop_IRIS.md §5.8 "Routing rule: one rule per source msgClass, N sends inside it"
/// Validity: Still valid.
/// Severity: High.
///
/// The canonical fan-out routing rule: ONE `<rule>` per source message class, with N `<send>`
/// actions inside its `<when>` block.
///
/// ANTI-PATTERN: splitting into one rule per destination ("Order-to-Vendor", "Order-to-Audit")
/// to "isolate failures". That conflates runtime fault tolerance with architecture. Flaky
/// destinations are handled by settings on the Router ITEM — `AlertOnError`, `BadMessageHandler`,
/// `ReplyCodeActions` — not by multiplying rules.
///
/// ENGINE/ASSIST PAIRING: this rule is for CUSTOM `Ens.Request` subclasses, so it pairs
/// `EnsLib.MsgRouter.RuleAssist` with a `context` of `EnsLib.MsgRouter.RoutingEngine`. An HL7
/// router needs `EnsLib.HL7.MsgRouter.RuleAssist` + `EnsLib.HL7.MsgRouter.RoutingEngine`
/// instead; running HL7 through the generic engine still compiles and still passes tests, but
/// you silently lose schema validation and the `{MSH:9.1}` paths (conformance CR-6).
///
/// CONDITION-LANGUAGE TRAPS — a `condition=` is NOT ObjectScript, and the generator reports
/// offsets into GENERATED code, so `#5490` never points at what you wrote:
///   `'=`                              -> use `!=`
///   `document.Field`                  -> use `Document.Field` (capitalised; lowercase won't resolve)
///   `##class(Pkg.UTL.X).Check(...)`   -> put the method on an `Ens.Rule.FunctionSet` subclass
///                                        and call it bare by name: `Check(...)`
///
/// COMPILES BUT STILL BREAKS AT RUNTIME: nothing here checks that `transform=` and `target=`
/// resolve. A missing transform class or a target that is not a production item compiles clean
/// and fails at runtime with `<CLASS DOES NOT EXIST>` or `target 'X' not an item`. That gap is
/// exactly why the pre-flight `ValidateProduction()` validator in the `bpl` skill exists — run
/// it before every production start.
Class Example.RUL.OrderRouting Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="Example.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="AcceptOrder" disabled="false">
<constraint name="msgClass" value="Example.MSG.AcceptOrderReq"/>
<when condition="Document.OrderId != &quot;&quot;">
<send transform="Example.DT.OrderToVendor" target="BO.Vendor"/>
<send target="BO.Audit"/>
<return/>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
