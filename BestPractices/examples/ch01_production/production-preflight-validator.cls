/// Rule: BestPractices_Interop_IRIS.md §1.15 "Pre-flight validation — and why the old validator returned OK for every production it could not read"
/// Validity: Verified against IRIS for Health 2026.1 — every claim measured against the two gated productions.
/// Severity: High (a gate that returns OK when it cannot see anything is worse than no gate).
///
/// Pattern: check a production BEFORE starting it — every item's class compiled, and every
/// `<send transform= target=>` in its routers' rules resolving to a real class and a real item.
/// At runtime those failures are `<CLASS DOES NOT EXIST>` or `target 'Y' not an item`, mid-message.
///
/// THREE DEFECTS IN THE VERSION THIS REPLACES, all measured:
///
/// 1. IT RETURNED "OK" FROM EVERY PATH WHERE IT COULD NOT READ ANYTHING. No router found → `OK`.
///    Rule XData missing → `OK`. Nothing matched in the scan → `OK`. So the reassuring answer was
///    also the answer for "I checked nothing", and the two were indistinguishable. This version
///    returns INCONCLUSIVE for those, and only ever says OK about checks it actually performed.
///
/// 2. IT LOOKED FOR THE ROUTER BY THE GENERIC CLASS ONLY —
///    `WHERE ClassName = 'EnsLib.MsgRouter.RoutingEngine'` — so it never matched an HL7 router
///    (`EnsLib.HL7.MsgRouter.RoutingEngine`). Measured against the two gated productions:
///        Example.Alerting.Production   TOP 1 picked  Ens.Alert
///        Example.Productions.Hl7Intake TOP 1 picked  Ens.Alert    <-- NOT Router.Adt
///    In the HL7 production the real router exists, is a different class, and was skipped entirely.
///
/// 3. `TOP 1` MADE IT PICK `Ens.Alert`, because Ens.Alert IS an `EnsLib.MsgRouter.RoutingEngine`.
///    So it validated the ALERT rule and reported on that, in a production whose actual routing it
///    had not looked at. `LIKE '%MsgRouter.RoutingEngine'` matches both classes; iterating every
///    match removes the need to guess which one is "the" router — a production may have several.
///
/// AND THE PREMISE THE MAP DOUBTED IS FINE: `Ens_Config.Item` IS a queryable table. Measured —
/// `SELECT Name, ClassName FROM Ens_Config.Item WHERE Production = ?` returns the items, and the
/// count agrees with `tProd.Items.Count()`. What is NOT true is that a missing production errors:
/// it returns **zero rows**, which is why "no items" must never be reported as OK.
///
/// Embedded `&sql` is what makes the table and its column names compile-verified here: a typo in
/// `Ens_Config.Item` or in `ClassName` fails the compile rather than waiting for a run.
Class Example.UTL.PreflightValidator Extends %RegisteredObject
{

/// Validate before start. Returns one of:
///   "OK ..."           — checks were performed and found nothing wrong
///   "ISSUES: ..."      — checks were performed and found problems
///   "INCONCLUSIVE: ..." — the check could not be performed, so there is no verdict
/// Invoke via: SELECT Example_UTL.PreflightValidator_ValidateProduction('<Pkg>.Production')
ClassMethod ValidateProduction(pProductionName As %String) As %String [ SqlProc ]
{
    Set issues = "", itemsSeen = 0, routersSeen = 0, sendsSeen = 0

    // 1) every item references a compiled class
    &sql(DECLARE C1 CURSOR FOR
         SELECT Name, ClassName FROM Ens_Config.Item WHERE Production = :pProductionName)
    &sql(OPEN C1)
    For {
        &sql(FETCH C1 INTO :itemName, :itemClass)
        Quit:SQLCODE'=0
        Set itemsSeen = itemsSeen + 1
        If '##class(%Dictionary.CompiledClass).%ExistsId(itemClass) {
            Set issues = issues_..Sep(issues)_"item "_itemName_" -> class "_itemClass_" missing/not compiled"
        }
    }
    &sql(CLOSE C1)

    // ZERO ITEMS IS NOT A PASS. An unregistered or misspelled production reads as empty, and the
    // old validator reported OK for exactly this case.
    If itemsSeen = 0 {
        Quit "INCONCLUSIVE: production '"_pProductionName_"' has no items registered -- nothing was checked"
    }

    // 2) EVERY router, matched on both the generic and the HL7 class. Not TOP 1: Ens.Alert is
    //    itself an EnsLib.MsgRouter.RoutingEngine and TOP 1 picks it.
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT ID, Name FROM Ens_Config.Item WHERE Production = ? AND ClassName LIKE '%MsgRouter.RoutingEngine'",
        pProductionName)
    While rs.%Next() {
        Set routersSeen = routersSeen + 1
        Set ruleClass = ..RuleOf(rs.%Get("ID"))
        If ruleClass = "" {
            // A router with no BusinessRuleName routes nothing. That is a finding, not a pass.
            Set issues = issues_..Sep(issues)_"router "_rs.%Get("Name")_" has no BusinessRuleName"
            Continue
        }
        Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(ruleClass_"||RuleDefinition")
        If '$IsObject(xdata) {
            Set issues = issues_..Sep(issues)_"rule "_ruleClass_" has no RuleDefinition XData"
            Continue
        }
        Set sendsSeen = sendsSeen + ..CheckSends(pProductionName, xdata.Data.Read(64000), .issues)
    }

    If routersSeen = 0 {
        Quit "INCONCLUSIVE: no router item in '"_pProductionName_"' -- items checked, rules not"
    }

    Quit $Select(issues '= "": "ISSUES: "_issues,
                 1: "OK "_pProductionName_": "_itemsSeen_" items, "_routersSeen_" router(s), "_sendsSeen_" send target(s) checked")
}

/// The BusinessRuleName of one item, by ID. The ID is what the SELECT returns; %OpenId takes it.
ClassMethod RuleOf(pItemId As %String) As %String [ Private ]
{
    Set itemObj = ##class(Ens.Config.Item).%OpenId(pItemId)
    Quit:'$IsObject(itemObj) ""
    For i = 1:1:itemObj.Settings.Count() {
        Set s = itemObj.Settings.GetAt(i)
        If s.Name = "BusinessRuleName" Quit
    }
    Quit $Select($Get(s) '= "" && $IsObject($Get(s)) && (s.Name = "BusinessRuleName"): s.Value, 1: "")
}

/// Scan every <send transform= target=> in one rule's XML. Returns how many targets were checked,
/// so the caller can say "0 checked" rather than "OK".
ClassMethod CheckSends(pProductionName As %String, pXml As %String, ByRef pIssues As %String) As %Integer [ Private ]
{
    Set checked = 0, scan = pXml
    While $Length(scan) > 0 {
        Set posSend = $Find(scan, "<send")
        Quit:posSend=0
        Set posEnd = $Find(scan, ">", posSend)
        Quit:posEnd=0
        Set sendTag = $Extract(scan, posSend, posEnd - 1)

        Set tPos = $Find(sendTag, "transform=""")
        If tPos > 0 {
            Set tEnd = $Find(sendTag, """", tPos)
            Set transformCls = $Extract(sendTag, tPos, tEnd - 2)
            If transformCls '= "", '##class(%Dictionary.CompiledClass).%ExistsId(transformCls) {
                Set pIssues = pIssues_..Sep(pIssues)_"rule transform "_transformCls_" missing"
            }
        }

        Set tgPos = $Find(sendTag, "target=""")
        If tgPos > 0 {
            Set tgEnd = $Find(sendTag, """", tgPos)
            Set target = $Extract(sendTag, tgPos, tgEnd - 2)
            If target '= "" {
                Set checked = checked + 1
                Set found = 0
                &sql(SELECT COUNT(*) INTO :found
                     FROM Ens_Config.Item
                     WHERE Production = :pProductionName AND Name = :target)
                If +found = 0 {
                    Set pIssues = pIssues_..Sep(pIssues)_"rule target '"_target_"' not an item in production"
                }
            }
        }
        Set scan = $Extract(scan, posEnd, *)
    }
    Quit checked
}

ClassMethod Sep(pSoFar As %String) As %String [ Private ]
{
    Quit $Select(pSoFar = "": "", 1: " | ")
}

}
