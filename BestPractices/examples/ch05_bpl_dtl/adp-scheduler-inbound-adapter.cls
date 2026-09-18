/// Rule: BestPractices_Interop_IRIS.md §5.2 "BS that runs on a schedule: use a custom adapter for wall-clock triggers"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (the failure mode is a service that runs for ever and produces nothing).
///
/// Pattern: a CUSTOM INBOUND ADAPTER. §5.2 has named `Demo.ADP.SchedulerAdapter` since the
/// deliverable was written; before this file, `grep "Ens.InboundAdapter"` over the whole plugin —
/// all 20 skills and the whole bank — returned **zero**. The shape was prescribed and never shown.
///
/// THE ONE LINE THAT MATTERS, and the reason this needs an example rather than a paragraph:
///
///     Quit ..BusinessHost.ProcessInput($$$NULLOREF, .tOut)
///
/// An `OnTask()` that evaluates its schedule and returns `$$$OK` **without** that call is the
/// canonical silent failure of this component. The adapter is polled, the production is green, the
/// service shows as running, the Event Log is empty, and nothing is ever produced. There is no
/// error to find because nothing went wrong — the work simply was never requested. Measured:
/// with the call, one dispatch per match; without it, `OnTask` still returns `$$$OK`.
///
/// WHAT THE BASE CLASS ALREADY GIVES YOU, so you do not re-declare it:
///   BusinessHost    As Ens.BusinessService  — the service to dispatch into
///   CallInterval    As %Numeric             — how often OnTask is polled (NOT the schedule)
///   Credentials, KeepaliveInterval, RegistryID
/// `CallInterval` and `Schedule` are different things and both are needed: CallInterval decides how
/// often you get asked "is it time?", Schedule decides the answer. A CallInterval of 60 with a
/// minute-precision cron is the sane pairing; a CallInterval of 3600 means a daily 08:30 job fires
/// somewhere in the 08:00 hour, or not at all.
///
/// WHY AN ADAPTER RATHER THAN %SYS.Task.Definition. §5.2 offers both and prefers the native task
/// framework for greenfield, which is right when the work is a standalone job. Choose the adapter
/// when the trigger must BE a production item: it appears in the production, it is enabled and
/// disabled with it, its firing is visible in the Visual Trace, and the message it starts carries a
/// session id like any other. A %SYS.Task has none of that.
///
/// ONE MEASURED OBJECTSCRIPT TRAP, because it cost a compile here: `Quit:<cond> <value>` takes the
/// value as its RETURN. Writing `Quit:+$Piece(spec,",",i) = pValue` parses the postconditional as
/// `Quit:(+$Piece(...))` and then `= pValue` as the return expression —
///   #1054: Invalid expression : '='
/// which points at the `=` and not at the real mistake. Inside a loop, set a flag.
Class Demo.ADP.SchedulerAdapter Extends Ens.InboundAdapter
{

/// Cron-style `min hour day month dayOfWeek`. `*` matches anything; a field may list values
/// (`0,30`). dayOfWeek is 0=Sunday. Exposed as a production Setting so the schedule is
/// configuration, not code.
Property Schedule As %String [ InitialExpression = "* * * * *" ];

Parameter SETTINGS = "Schedule:Basic";

/// Polled every CallInterval seconds by the framework.
Method OnTask() As %Status
{
    Quit:'..Matches($Horolog) $$$OK

    // THE DISPATCH. Omit this and the adapter ticks for ever, green, producing nothing.
    // $$$NULLOREF because a scheduled trigger carries no inbound payload — the service's
    // OnProcessInput is what decides what work to do.
    Quit ..BusinessHost.ProcessInput($$$NULLOREF, .tOut)
}

/// Does $Horolog match Schedule? Split out from OnTask so it is testable without a production.
Method Matches(pH As %String) As %Boolean
{
    Set tDate = $Piece(pH, ",", 1)
    Set tTime = $Piece(pH, ",", 2)
    Set tMin = tTime \ 60 # 60
    Set tHour = tTime \ 3600
    // $Horolog day 1 is 1840-12-31, a Thursday; +4 aligns the modulus to 0=Sunday.
    Set tDow = (tDate + 4) # 7
    Set tDay = +$Piece($ZDate(tDate, 3), "-", 3)
    Set tMon = +$Piece($ZDate(tDate, 3), "-", 2)

    Quit:'..FieldMatches($Piece(..Schedule, " ", 1), tMin) 0
    Quit:'..FieldMatches($Piece(..Schedule, " ", 2), tHour) 0
    Quit:'..FieldMatches($Piece(..Schedule, " ", 3), tDay) 0
    Quit:'..FieldMatches($Piece(..Schedule, " ", 4), tMon) 0
    Quit ..FieldMatches($Piece(..Schedule, " ", 5), tDow)
}

/// One cron field against one value. A flag rather than a conditional Quit — see the header.
Method FieldMatches(pSpec As %String, pValue As %Integer) As %Boolean
{
    Quit:pSpec="*" 1
    Set tHit = 0
    For i = 1:1:$Length(pSpec, ",") {
        If +$Piece(pSpec, ",", i) = pValue {
            Set tHit = 1
        }
    }
    Quit tHit
}

}
