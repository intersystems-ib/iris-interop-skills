---
name: bpl
description: BPL processes, routing rules, message routers. Routed from interop. Triggers: MessageRouter, routing rule, enrutador, regla de enrutamiento, router, BPL, Ens.BusinessProcess, business process, fan-out.
---

# BPL Business Processes

BPL (Business Process Language) is the visual orchestration language for IRIS Interop. Two distinct shapes use it: **HL7 Message Routers** (BPL under the hood, hidden behind the rule editor) and **custom BPL** (the activity diagram in the BPL editor). The customer-validated patterns below cover both.

## When to use this skill

The user mentioned BPL, Message Router, routing rules, BP context, BPL orchestration, sub-flow, or `Ens.BusinessProcessBPL`.

## What this skill currently knows

### One Message Router + one Routing Rule per origin

This is the **non-negotiable starting point** for any production. Each Business Service points its `TargetConfigNames` at its **own** dedicated `EnsLib.MsgRouter.RoutingEngine` item, configured with **one** `Ens.Rule.Definition` (the routing rule). Don't:

- Combine origins (BS.Censo and BS.Lab feeding the same router) — routing logic from different sources tangles, troubleshooting collapses.
- Combine channels (one rule sending to functional BO + an alert + a logger) into "one rich rule" — fan-out belongs in `Ens.Alert` (separate router) or in multiple `<send>` actions within the same rule, not in elaborate combined logic.
- Skip the router and target a BO directly from the BS — works, but you lose the rule-edit-without-recompile property, and you can't add a filter or a transform later without rewiring.

A "trivial" router (single rule, single `<send>`) is **not** infrastructure waste — it's the seam where future routing changes will live. Audit it as good, not as gap.

### Match the router engine to the message class — and never mix HL7 with custom

The routing-engine class is **not** one-size-fits-all; pick it from what the router actually carries:

| The router handles… | Runtime engine class | Rule assist class |
|---|---|---|
| `EnsLib.HL7.Message` (HL7 v2.x) | `EnsLib.HL7.MsgRouter.RoutingEngine` | `EnsLib.HL7.MsgRouter.RuleAssist` |
| Other virtual docs (X12, ASTM, XML VDoc) | `EnsLib.MsgRouter.VDocRoutingEngine` | `EnsLib.MsgRouter.VDocRuleAssist` |
| Custom `Ens.Request` subclasses, RecordMap records, JSON/REST messages | `EnsLib.MsgRouter.RoutingEngine` | `EnsLib.MsgRouter.RuleAssist` |

A rule for an **HL7** router sets `RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist"` and its `<ruleDefinition>` uses `context="EnsLib.HL7.MsgRouter.RoutingEngine"`, so the rule editor knows about `docCategory`/`docName` and exposes the `{SEG:field}` virtual-property syntax. Run an HL7 message class through the **generic** `EnsLib.MsgRouter.RoutingEngine` and it still compiles and passes tests — but you **lose HL7 schema validation in the rule editor** and the `{MSH:9.1}`-style paths, and you'll be matching on raw message metadata instead.

**Do not mix `EnsLib.HL7.Message` and custom message classes in the same router** (even across separate rules in one rule set). The engine is chosen per router, so a router that must serve both can only pick one, and the other half loses its proper assist/validation. Give HL7 sources an HL7 router and custom sources a generic router — which is just the "one router per origin" rule applied to message *shape*, not only to source. Add `docCategory` + `docName` constraints on HL7 rules so an unexpected message type never silently matches.

```xml
<rule name="ADT_A01">
  <constraint name="msgClass"     value="EnsLib.HL7.Message"/>
  <constraint name="docCategory"  value="2.5"/>
  <constraint name="docName"      value="ADT_A01"/>
  <when condition='Document.{MSH:9.2}="A01"'>
    <send transform="MyApp.DT.AdtToCanon" target="BO.Target"/><return/>
  </when>
</rule>
```

(The conformance reviewer flags the mixed-router / wrong-engine case as **CR-6**; this section is the build-time guidance so you avoid it in the first place, not just catch it after.)

```
BS.Censo  →  Router.Censo  →  BO.Cocina
            (Rule.RoutingCenso: 1 rule, 1 send, possibly a filter)

BS.Lab    →  Router.Lab    →  BO.LIS
            (Rule.RoutingLab: independent rule, independent file)
```

### Other guidance

- An HL7 **Message Router** is the most common BP type for HL7 productions. It validates messages, runs the rule set, and forwards.
- A **custom BPL** is needed for multi-step orchestration: synchronous sub-calls, conditional branches, parallel fan-out/aggregation, error compensation.
- BPL **context variables** persist across the BPL's lifetime — survive a `<call>` and resume after the response. Use them for state that crosses async calls.
- IRIS 2026 introduces **delete-on-context** for persistent properties on the BPL context, so message-body bloat from long-lived BPLs is reduced. (Validate the exact syntax via docs before relying on it.)
- When BPL becomes hard to read (>30 activities, deep nesting), consider a custom `Ens.BusinessProcess` in plain ObjectScript — sometimes more maintainable.

### Routing rule structure: one rule per source `msgClass`, multiple `<send>` per rule

When a single origin needs to fan out to multiple destinations (e.g. CSV → PostgreSQL + SOAP + REST), the canonical structure is **one `<rule>` per source message class, with N `<send>` actions inside its `<when>` block**:

```xml
<ruleSet>
  <rule name="CensoCSV">
    <constraint name="msgClass" value="MyApp.RecordMap.Censo.Record"/>
    <when condition="1">
      <send transform="MyApp.DT.Censo2Sql"   target="BO.Cocina"/>
      <send transform="MyApp.DT.Censo2Rich"  target="BO.CocinaSOAP"/>
      <send transform="MyApp.DT.Censo2Rich"  target="BO.CocinaREST"/>
    </when>
  </rule>
  <rule name="CensoREST">
    <constraint name="msgClass" value="MyApp.Msg.MenuRequestRich"/>
    <when condition="1">
      <send target="BO.Cocina"/>
      <send target="BO.CocinaSOAP"/>
      <send target="BO.CocinaREST"/>
    </when>
  </rule>
</ruleSet>
```

**Anti-pattern**: splitting into one rule per destination ("CSV-to-SQL", "CSV-to-SOAP", "CSV-to-REST") to "isolate failures". That conflates *runtime fault tolerance* with *architecture*; it multiplies rules, makes routing harder to reason about, and the symptom it's trying to fix — a missing transform class or target BO — is a **development error** caught much earlier by a pre-flight validator (below), not by rule fragmentation.

### What a `condition=` can and cannot contain

The rule XData is compiled into `evaluateRuleDefinition` by a code generator. The condition language
is **not ObjectScript**, and the generator reports offsets into *generated* code, so the message never
points at what you actually wrote:

```
ERROR <Ens>ErrInvalidName: Invalid name at offset 1
ERROR <Ens>ErrInvalidToken: Invalid token at offset 21
  > ERROR #5490: Error running generator for method 'evaluateRuleDefinition:MyApp.RUL.Router'
```

| Don't write this in a condition | Write this instead |
|---|---|
| `##class(MyApp.UTL.Validar).EsValido(Document)=1` | put the method in an **`Ens.Rule.FunctionSet` subclass** and call it bare, by name: `EsValido(Document)=1` |
| `Document.Planta '= ""` — ObjectScript's "not equal" | `Document.Planta != ""` |
| `document.Planta` on an `EnsLib.MsgRouter.RoutingEngine` | `Document.Planta` — **capitalised**; the lowercase form doesn't resolve |

Once the FunctionSet class exists in the namespace, its methods are offered by name in the rule editor
and accepted in the XData. Measured over a workshop cohort: **12 of 18 students** hit `#5490` on a
routing rule, all of it on these three shapes.

### Pre-flight validator for missing classes / targets

When a `<send transform="X" target="Y"/>` references a class or item that doesn't exist, the BP terminates at runtime with `<CLASS DOES NOT EXIST>` or `target 'Y' not an item`. The remedy is a **validator invoked before production start** that parses the rule's XData and checks each `transform=` and `target=` against the dictionary and the production's item list. A canonical SqlProc:

Full implementation:

```objectscript
ClassMethod ValidateProduction(pProductionName As %String) As %String [ SqlProc ]
{
    Set issues = ""

    // 1) Each Item references a compiled class
    &sql(DECLARE C1 CURSOR FOR
         SELECT Name, ClassName FROM Ens_Config.Item WHERE Production = :pProductionName)
    &sql(OPEN C1)
    For {
        &sql(FETCH C1 INTO :itemName, :itemClass)
        Quit:SQLCODE'=0
        If '##class(%Dictionary.CompiledClass).%ExistsId(itemClass) {
            Set issues = issues_$S(issues="":"", 1:" | ")_
                         "item "_itemName_" -> class "_itemClass_" missing/not compiled"
        }
    }
    &sql(CLOSE C1)

    // 2) Find the Router item, get its rule class, parse the rule's XData
    Set ruleClass = ""
    &sql(SELECT TOP 1 ID INTO :routerItem
         FROM Ens_Config.Item
         WHERE Production = :pProductionName
           AND ClassName = 'EnsLib.MsgRouter.RoutingEngine')
    If $G(routerItem, "") '= "" {
        Set itemObj = ##class(Ens.Config.Item).%OpenId(routerItem)
        If $IsObject(itemObj) {
            Set settings = itemObj.Settings
            For i = 1:1:settings.Count() {
                Set s = settings.GetAt(i)
                If s.Name = "BusinessRuleName" Set ruleClass = s.Value Quit
            }
        }
    }
    If ruleClass = "" Quit $S(issues="":"OK", 1:"ISSUES: "_issues)

    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(ruleClass_"||RuleDefinition")
    If '$IsObject(xdata) Quit $S(issues="":"OK", 1:"ISSUES: "_issues)
    Set xml = xdata.Data.Read(64000)

    // 3) Scan every <send transform="X" target="Y" ...> tag
    Set scan = xml
    While $L(scan) > 0 {
        Set posSend = $F(scan, "<send")  If posSend = 0 Quit
        Set posEnd  = $F(scan, ">", posSend)  If posEnd = 0 Quit
        Set sendTag = $E(scan, posSend, posEnd - 1)

        // transform=
        Set tPos = $F(sendTag, "transform=""")
        If tPos > 0 {
            Set tEnd = $F(sendTag, """", tPos)
            Set transformCls = $E(sendTag, tPos, tEnd - 2)
            If transformCls '= "", '##class(%Dictionary.CompiledClass).%ExistsId(transformCls) {
                Set issues = issues_$S(issues="":"", 1:" | ")_
                             "rule transform "_transformCls_" missing"
            }
        }
        // target=
        Set tgPos = $F(sendTag, "target=""")
        If tgPos > 0 {
            Set tgEnd = $F(sendTag, """", tgPos)
            Set target = $E(sendTag, tgPos, tgEnd - 2)
            If target '= "" {
                Set found = 0
                &sql(SELECT COUNT(*) INTO :found
                     FROM Ens_Config.Item
                     WHERE Production = :pProductionName AND Name = :target)
                If +found = 0 {
                    Set issues = issues_$S(issues="":"", 1:" | ")_
                                 "rule target '"_target_"' not an item in production"
                }
            }
        }
        Set scan = $E(scan, posEnd, *)
    }

    Quit $S(issues="":"OK production="_pProductionName_" all classes/targets validated", 1:"ISSUES: "_issues)
}
```

Invoke via `SELECT MyApp_Bootstrap_ValidateProduction('MyApp.Production')` before every restart. CI step. Test fixture. This catches 90% of the "BP fails with weird error" class of bugs at edit time.

For multi-router productions, extend step 2 to iterate every `EnsLib.MsgRouter.RoutingEngine` item (drop the `TOP 1`) and concatenate the results. The string-scan parser is good enough for `<send>` extraction (rule XData uses a stable shape) — replace with `%XML.TextReader` only if you start tracking `<assign>` or `<switch>` activities.

### Runtime fault tolerance — separate concern from architecture

If a destination is *legitimately flaky* (network, downstream service that does go down), use `EnsLib.MsgRouter.RoutingEngine` settings rather than rewriting rules:

- `AlertOnError` — emit an `Ens.AlertRequest` instead of terminating the BP.
- `BadMessageHandler` — a target item where un-routable messages go (configure a file logger or an alerts router as the value).
- `ReplyCodeActions` — per-error-code action table (Retry / Fail / Suspend / Skip per error class).

These are knobs on the Router item itself, not on individual rules. **In production XML they are
`<Setting>` elements, never `<Item>` attributes:**

```xml
<Item Name="Router" ClassName="EnsLib.MsgRouter.RoutingEngine">
  <Setting Target="Host" Name="AlertOnError">1</Setting>
  <Setting Target="Host" Name="BadMessageHandler">ErrorFileLogger</Setting>
</Item>
```

`<Item ... AlertOnError="true">` fails the whole class with *attribute 'AlertOnError' is not
declared for element 'Item'*. The `<Item>` element maps to `Ens.Config.Item`, whose 19 properties
are `Name`, `ClassName`, `Enabled`, `PoolSize`, `Schedule`, `Category`, `Comment`,
`DisableErrorTraps`, `Foreground`, `InactivityTimeout`, `LogTraceEvents`, `AlertGroups` and the
rest — `AlertOnError` is not among them. Host settings reach the item through its `Settings`
collection (`Ens.Config.Setting`), which is what `<Setting>` builds. Note the value is `1`/`0`,
not `"true"`.

## Timeout precedence — BO timeout MUST be smaller than calling BP

A BO's `Response Timeout` and `Failure Timeout` MUST be **smaller** than the timeout of the BP that calls it. Whichever side times out first owns the error context:

- BO times out first → BO raises `Ens.AlertRequest` with stack trace; BP gets the failure and can decide to retry, reroute, or abort.
- BP times out first → BO is still processing, has no chance to mark its own error; the BP sees a generic timeout with no diagnostic chain.

Pick the BP timeout last, after all downstream BO timeouts are set. Common mistake: copying the BP from a working flow and inheriting a too-tight timeout for a slower downstream.

## Synchronous chain when source rows have ordering dependencies

When source-system rows must be applied in order (e.g. an UPDATE that cannot apply before its INSERT, a "Reprogramacion" that depends on its prior "Programacion"), prefer a synchronous BS → BP → BO chain over async messaging.

Async messaging gives the queue freedom to reorder. Sync chains preserve order at the cost of throughput. The BO that writes to the downstream system can also use `AutoCommit=0` so it can roll back row changes if the call fails.

Document the trade-off explicitly in the production: "this BS is synchronous because the source has ordering dependencies; throughput is lower than async would be." Otherwise a future "optimisation" to async will silently corrupt downstream state.

## Routing-rule guard against alert flooding

When a BP catches an error and raises `Ens.AlertRequest`, a downstream BO catching the same error raises another. The session emits two alerts for one operational incident. Filter at the `Ens.Alert` router with a dedup function set — see `alerting` for the canonical guard.

```
when MyApp.UTL.AlertFilterFunctions.AlreadyReportedErr(SourceConfigName, AlertText, 60) → skip
```

## ObjectScript error-handling idiom inside BPL code blocks

When dropping to ObjectScript in a `<code>` activity (or a custom `Ens.BusinessProcess` subclass), wrap the work in try/catch, convert exceptions with `errObj.AsStatus()`, and always return `%Status` — the BPL framework expects it and surfaces errors correctly. Never `Quit <value>` inside the `Try` (`#1043`), and standardise new code on `$$$ThrowOnError` rather than wizard-style `$$$ISERR` chains. Full idiom: `unit-tests` §"Error handling inside test methods"; canonical copy-paste class: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/objectscript-trycatch.cls` (§5.4 in `examples/README.md`).

## BPL editor regression: `Missing BPL Data`

A class that compiled fine on an older Caché/Ensemble may report `Missing BPL Data` (`<XData BPL>` missing) on certain IRIS versions. The BPL editor in some versions silently strips the `XData BPL` section on first open.

**Fix**: paste the original BPL XML back into the `XData BPL` block and recompile. **Prevention**: source-control the BPL class as-text on disk, not just as a portal-edited class — see `production-lifecycle` for the disk-as-source-of-truth principle.

**The BPL editor and the rule editor both write straight into the namespace.** The PreToolUse
source-of-truth gate cannot see them — it watches `iris_doc(mode=put)`, and a Portal edit
bypasses it. After any editing session in the Portal, `iris_doc(mode=get)` the BPL class and the
`Ens.Rule.Definition` class and write them to `src/`. This is what makes the regression above
recoverable: with the XData on disk, restoring a stripped `XData BPL` is a copy-paste; without
it, the process definition is gone.

## Canonical routing / BPL shapes

Four shapes cover most orchestration needs. Reach for the closest match before authoring from scratch:

| Shape | What it shows |
|---|---|
| **HL7 Message Router rule** (1-rule-per-source) | Two rules on the same router (e.g. `ORM_O01` → Pharmacy when `MSH:ReceivingApplication.namespaceID="PHARMACY"`; `ADT_A06` → Transfer). Each rule pins `source=<BS name>`, `msgClass=EnsLib.HL7.Message`, `docCategory=2.3.1`, `docName=…`, with a `<send transform target>` for each. RuleAssistClass = `EnsLib.HL7.MsgRouter.RuleAssist`. |
| **Generic message router rule (fan-out)** | One source `msgClass`, multiple `<send>` to SQL + SOAP + REST destinations in the same `<when>` block. The canonical fan-out pattern (see the `<ruleSet>` example above). |
| **Custom BPL business process** | Sync `<call>` to a BO with context-vars, response handlers, and decision logic on the returned data. Drive it under test via `EnsLib.Testing.Service.SendTestRequest` (see `tdd`). |
| **Alerts router rule** | Subscribes to `Ens.AlertRequest`, fans out to a file-logger BO; xref `alerting` for the dedup function-set pattern that goes on top. |

Worked examples, all compiled against live IRIS 2026.1:

- Custom BPL — `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/bpl-order-process.cls` (§5.6): `<context>` property, a sync `<call>` with `callrequest` bindings, a `<code>` activity.
- Fan-out routing rule — `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/routing-rule-fanout.cls` (§5.8): one `<rule>` per source `msgClass`, two `<send>` inside one `<when>`, correct engine/assist pairing, and the `!=` / `Document.` condition traps in its header.

The pre-flight `ValidateProduction()` validator shown above is the full version (item-class check **plus** rule-XData parsing of `transform=`/`target=`). A lighter starter that only checks item classes is fine early on — extend it with the rule-XData parser as the production matures.

## What this skill does NOT yet do

- Generate BPL XML automatically from a plain-English orchestration description.
- Recommend specific routing rule structures for non-trivial cases.
- Validate complex BPL designs end-to-end.

## How to proceed

1. Tell the student: this area is not yet automated; let's design it together using the Management Portal's BPL editor.
2. Point them to the BPL docs: https://docs.intersystems.com/healthconnectlatest/csp/docbook/DocBook.UI.Page.cls?KEY=EBPL
3. For a Message Router specifically, generate the production XML stub and let them author routing rules in the Rule Editor.
4. **Do not** generate a wall of `<call>`/`<sync>`/`<reply>` BPL XML from a vague description — it'll be wrong in ways that are subtle to debug.

## See also

- `business-services` — what feeds the BP
- `business-operations` — what the BP dispatches to; timeout precedence (BO < BP)
- `transformations` — what a BPL invokes mid-flow
- `messages` — Request/Response types of every BPL call
- `alerting` — `Ens.Alert` routing rule with dedup function set
- `production-lifecycle` — disk-as-source-of-truth for BPL classes (prevents the `Missing BPL Data` regression)
