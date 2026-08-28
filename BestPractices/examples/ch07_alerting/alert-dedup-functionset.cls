/// Rule: BestPractices_Interop_IRIS.md §7.2 "Alert deduplication FunctionSet"
/// Validity: Still valid; portable function-set.
///
/// Usage as routing-rule guard inside Ens.Alert (context EnsLib.MsgRouter.RoutingEngine,
/// so the Ens.AlertRequest fields are reached through `Document.`):
///   when AlreadyReportedErr(Document.SourceConfigName, Document.AlertText, 60) -> skip
///
/// Protects against:
///   1. A BP and a BO in the same session both raise an alert -> duplicate email.
///   2. A failing BO retries every N seconds and emits an alert each retry -> mailbox flood.
Class Demo.FilterAlerts.FunctionSet Extends Ens.Rule.FunctionSet [ LegacyInstanceContext, Not ProcedureBlock ]
{

/// True if this ErrorMessage was already reported in the CURRENT time bucket of today.
///
/// Read the contract literally, because two things about it surprise people:
///
/// 1. The window is a FIXED bucket (`seconds \ Interval`), not a sliding "within Interval
///    seconds". Two errors one second apart but on opposite sides of a bucket boundary BOTH
///    alert; two errors 59s apart inside one 60-second bucket dedupe. That is the deliberate
///    trade: one global write, no read-modify-write, no timer, and an alert can never be
///    suppressed for longer than `Interval` seconds.
/// 2. SourceConfigName is accepted (so the rule reads naturally and the key can be widened
///    later) but is NOT part of the key. Keying on the error text alone is what makes failure
///    mode 1 dedupe: the BP and the BO report the SAME text under DIFFERENT config names.
///    Add SourceConfigName to the subscripts below only if you want one alert per host.
ClassMethod AlreadyReportedErr(SourceConfigName, ErrorMessage, Interval = 60) As %Boolean
{
    set datetime=$H, day=+datetime, seconds=$p(datetime,",",2)
    do ..PurgeDaysBefore("Err",day)  // every earlier day, not just day-1
    if $data(^FilterAlerts("Err",day,seconds\Interval,$extract(ErrorMessage,1,200))) {
        quit 1
    } else {
        set ^FilterAlerts("Err",day,seconds\Interval,$extract(ErrorMessage,1,200))=""
    }
    quit 0
}

/// True if any alert was already produced for this Ensemble session today.
/// `%Ensemble("SessionId")` only exists inside a business-host process. Referenced bare from
/// anywhere else (a terminal call, a unit test outside a production) it raises <UNDEFINED>,
/// which surfaces as a rule-evaluation error and loses the alert. With no session context the
/// honest answer is "not reported yet" — let the alert through rather than fail.
ClassMethod AlreadyReportedPerSession() As %Boolean
{
    set SessionId=$get(%Ensemble("SessionId"))
    quit:SessionId="" 0
    set day=+$H
    do ..PurgeDaysBefore("Session",day)
    if ($data(^FilterAlerts("Session",day,SessionId))) {
        quit 1
    } else {
        set ^FilterAlerts("Session",day,SessionId)=""
    }
    quit 0
}

/// Drop every ^FilterAlerts(pKind,<day>) subtree older than pToday.
/// `kill ^FilterAlerts(pKind,pToday-1)` only ever reaches YESTERDAY, so each day on which no
/// alert is evaluated leaks its subtree for good: after a quiet weekend, Friday's and
/// Saturday's buckets are never revisited and stay in the global for ever.
ClassMethod PurgeDaysBefore(pKind As %String, pToday As %Integer) [ Private ]
{
    set tDay=$order(^FilterAlerts(pKind,""))
    while (tDay'="") && (tDay<pToday) {
        kill ^FilterAlerts(pKind,tDay)
        set tDay=$order(^FilterAlerts(pKind,tDay))
    }
    quit
}

}
