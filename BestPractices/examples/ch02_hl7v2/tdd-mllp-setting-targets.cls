/// Rule: BestPractices_Interop_IRIS.md §1.19 "MLLP: which timeout is a Host setting and which is an Adapter one"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN.
/// Severity: High (a setting on the wrong target is not applied, with no error and no log line).
///
/// Pattern: the oracle for `production-hl7-mllp.cls`. Its central check is a SWEEP: for every setting
/// of every item in the production, decide whether the named property lives on the host class or on
/// the adapter the host declares, and compare that with the setting's `Target`.
///
/// WHY A SWEEP AND NOT FOUR ASSERTIONS. A wrong `Target` is silent — the value is simply not applied,
/// the default stays in force, and nothing is logged. There is no error to assert on, so the only
/// reliable check is structural, and it costs no more to check ALL of them than the four the header
/// happens to discuss. It also keeps working when the production grows.
///
/// THE MEASURED SPLIT this pins:
///
///   EnsLib.HL7.Service.TCPService     (adapter EnsLib.HL7.Adapter.TCPInboundAdapter)
///       Port Adapter | LocalInterface Adapter | AckMode Host
///   EnsLib.HL7.Operation.TCPOperation (adapter EnsLib.HL7.Adapter.TCPOutboundAdapter)
///       Port Adapter | ResponseTimeout Adapter | FailureTimeout Host | ReplyCodeActions Host
///
/// The operation carries TWO timeouts on OPPOSITE sides, which is the whole reason this item is worth
/// an example: `ResponseTimeout` is the adapter waiting for an ACK on the wire, `FailureTimeout` is
/// the host deciding when to stop retrying.
///
/// THE SWEEP IS ONLY EVIDENCE IF IT CAN FAIL, so `TestSweepDetectsAWrongTarget` feeds it a
/// deliberately mis-targeted setting and requires a finding. Without that, a sweep returning "all
/// correct" over a production it could not read would look identical to a clean one.
///
/// AND THE VALUES, not just their targets: `FailureTimeout` must be FINITE (the measured default is
/// **-1**, retry for ever) and greater than `ResponseTimeout` per §1.9's precedence rule, and
/// `ReplyCodeActions` must be non-empty (the measured default is `""`, which leaves an application
/// NACK as a SUSPENDED message rather than an errored one).
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                   PASSED 5/5
///     FailureTimeout back to the -1 default         TestTheDefaultsAreOverriddenDeliberately FAILS
///     ReplyCodeActions emptied                      TestTheDefaultsAreOverriddenDeliberately FAILS
///     FailureTimeout below ResponseTimeout          TestTheDefaultsAreOverriddenDeliberately FAILS
///     ResponseTimeout moved to the Host             TestEverySettingTargetsTheRightSide      FAILS
///     FailureTimeout moved to the Adapter           TestEverySettingTargetsTheRightSide      FAILS
///
/// The last two are the ones that matter: a wrong `Target` is silent in IRIS, and the sweep is what
/// makes it loud. All six versions compile, so tier 2 is green on every one of them -- including the
/// two where a setting is simply never applied.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.MllpSettingTargets", namespace="<NS>")
Class Example.Tests.MllpSettingTargets Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.Hl7Mllp";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Where does pProp actually live for pHostClass: "Host", "Adapter", "both" or "" (nowhere)?
ClassMethod WhereDoesItLive(pHostClass As %String, pProp As %String) As %String [ SqlProc ]
{
    Set tOnHost = ..ClassHasProperty(pHostClass, pProp)
    Set tAdapter = ""
    Try {
        Set tAdapter = $parameter(pHostClass, "ADAPTER")
    }
    Catch {
        Set tAdapter = ""
    }
    Set tOnAdapter = 0
    If tAdapter '= "" {
        Set tOnAdapter = ..ClassHasProperty(tAdapter, pProp)
    }
    If tOnHost && tOnAdapter {
        Return "both"
    }
    If tOnHost {
        Return "Host"
    }
    If tOnAdapter {
        Return "Adapter"
    }
    Return ""
}

ClassMethod ClassHasProperty(pClass As %String, pProp As %String) As %Boolean [ Private ]
{
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM %Dictionary.CompiledProperty WHERE parent = :pClass AND Name = :pProp)
    Quit (+$Get(tN) > 0)
}

/// Sweep every setting of every item. Returns "" when all targets agree, or a findings string.
/// pOverrideItem/pOverrideSetting/pOverrideTarget inject one wrong target, so the sweep can be shown
/// to fail -- see TestSweepDetectsAWrongTarget.
ClassMethod SweepTargets(pProduction As %String, pOverrideItem As %String = "", pOverrideSetting As %String = "", pOverrideTarget As %String = "") As %String [ SqlProc ]
{
    Set tProd = ##class(Ens.Config.Production).%OpenId(pProduction)
    If '$IsObject(tProd) {
        // NOT a clean sweep. A production that cannot be opened is one this check did not read.
        Return "CANNOT SWEEP: could not open '" _ pProduction _ "'"
    }

    Set tFindings = "", tChecked = 0
    For i = 1:1:tProd.Items.Count() {
        Set tItem = tProd.Items.GetAt(i)
        For j = 1:1:tItem.Settings.Count() {
            Set tSet = tItem.Settings.GetAt(j)
            Set tTarget = tSet.Target
            If (tItem.Name = pOverrideItem) && (tSet.Name = pOverrideSetting) {
                Set tTarget = pOverrideTarget
            }

            Set tLives = ..WhereDoesItLive(tItem.ClassName, tSet.Name)
            Set tChecked = tChecked + 1

            If tLives = "" {
                Set tFindings = tFindings _ " | " _ tItem.Name _ "." _ tSet.Name _
                                ": that property exists on neither " _ tItem.ClassName _ " nor its adapter"
                Continue
            }
            If tLives = "both" {
                // Ambiguous by nature; not a finding, but worth not silently passing over.
                Continue
            }
            If tTarget '= tLives {
                Set tFindings = tFindings _ " | " _ tItem.Name _ "." _ tSet.Name _
                                ": Target=""" _ tTarget _ """ but the property lives on the " _ tLives
            }
        }
    }

    If tChecked = 0 {
        Return "CANNOT SWEEP: the production opened but carries no settings -- nothing was checked"
    }
    Return tFindings
}

/// THE SWEEP. Every setting in the shipped production must name the side its property is on.
Method TestEverySettingTargetsTheRightSide()
{
    Set tFindings = ##class(Example.Tests.MllpSettingTargets).SweepTargets(..#PRODUCTION)
    Do $$$AssertEquals($Find(tFindings, "CANNOT SWEEP") > 0, 0, "the sweep must have read the production: " _ tFindings)
    Do $$$AssertEquals(tFindings, "", "every setting must target the side its property lives on. Findings:" _ tFindings)
}

/// THE SWEEP'S POSITIVE CONTROL. Injected wrong target -> it must be reported.
Method TestSweepDetectsAWrongTarget()
{
    // FailureTimeout lives on the Host; claim it is an Adapter setting.
    Set tFindings = ##class(Example.Tests.MllpSettingTargets).SweepTargets(..#PRODUCTION, "BO.MllpOut", "FailureTimeout", "Adapter")
    Do $$$AssertNotEquals(tFindings, "", "a mis-targeted setting must be reported")
    Do $$$AssertEquals($Find(tFindings, "FailureTimeout") > 0, 1, "and named: " _ tFindings)
    Do $$$AssertEquals($Find(tFindings, "lives on the Host") > 0, 1, "with the side it really belongs to")
}

/// The split itself, asserted directly so a sweep failure localises.
Method TestTheSplitIsWhereItWasMeasured()
{
    Set tSvc = "EnsLib.HL7.Service.TCPService"
    Set tOp = "EnsLib.HL7.Operation.TCPOperation"

    Do $$$AssertEquals(##class(Example.Tests.MllpSettingTargets).WhereDoesItLive(tSvc, "Port"), "Adapter", "service Port is an Adapter setting")
    Do $$$AssertEquals(##class(Example.Tests.MllpSettingTargets).WhereDoesItLive(tSvc, "AckMode"), "Host", "AckMode is a Host setting")

    Do $$$AssertEquals(##class(Example.Tests.MllpSettingTargets).WhereDoesItLive(tOp, "ResponseTimeout"), "Adapter", "ResponseTimeout is an ADAPTER setting")
    Do $$$AssertEquals(##class(Example.Tests.MllpSettingTargets).WhereDoesItLive(tOp, "FailureTimeout"), "Host", "FailureTimeout is a HOST setting -- the two timeouts are on opposite sides")
    Do $$$AssertEquals(##class(Example.Tests.MllpSettingTargets).WhereDoesItLive(tOp, "ReplyCodeActions"), "Host", "ReplyCodeActions is a Host setting")

    // Control: a name that is on neither side must report "" rather than defaulting to one.
    Do $$$AssertEquals(##class(Example.Tests.MllpSettingTargets).WhereDoesItLive(tOp, "NoSuchSettingAnywhere"), "", "an unknown property belongs to neither side")
}

/// The three overridden DEFAULTS, and the relationship between two of them.
Method TestTheDefaultsAreOverriddenDeliberately()
{
    Set tFail = ..SettingValue("BO.MllpOut", "FailureTimeout")
    Set tResp = ..SettingValue("BO.MllpOut", "ResponseTimeout")
    Set tReply = ..SettingValue("BO.MllpOut", "ReplyCodeActions")

    Do $$$AssertNotEquals(tFail, "", "FailureTimeout must be set at all")
    Do $$$AssertNotEquals(+tFail, -1, "and must not be the default -1, which retries FOR EVER")
    Do $$$AssertEquals(+tFail > 0, 1, "it must be finite and positive: " _ tFail)

    Do $$$AssertNotEquals(tResp, "", "ResponseTimeout must be stated rather than inherited")
    Do $$$AssertEquals(+tFail > +tResp, 1, "and FailureTimeout must exceed it, per the precedence rule (" _ tFail _ " > " _ tResp _ ")")

    Do $$$AssertNotEquals(tReply, "", "ReplyCodeActions must not be the default empty string -- an application NACK would suspend, not error")
}

/// One setting's value out of the production definition.
ClassMethod SettingValue(pItem As %String, pSetting As %String) As %String [ Private ]
{
    Set tProd = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    If '$IsObject(tProd) {
        Quit ""
    }
    For i = 1:1:tProd.Items.Count() {
        Set tItem = tProd.Items.GetAt(i)
        If tItem.Name = pItem {
            For j = 1:1:tItem.Settings.Count() {
                Set tSet = tItem.Settings.GetAt(j)
                If tSet.Name = pSetting {
                    Return tSet.Value
                }
            }
        }
    }
    Quit ""
}

}
