/// Rule: BestPractices_Interop_IRIS.md §1.18 "`RecoverProduction()` returns `$$$OK` having done nothing — verify the STATE, not the status"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed against live productions.
/// Severity: High (a recovery helper reports success while the production is still down).
///
/// Pattern: the production lifecycle helper — start, stop, restart and recover, each returning a
/// verdict that names the state it ESTABLISHED rather than the status the API handed back.
///
/// THE STATE CODES, measured from the `$$$eProductionState*` macros rather than guessed:
///
///     1 = Running     2 = Stopped     3 = Suspended     4 = Troubled
///
/// Every method below reports the number AND its name, because "state=3" in a log is unreadable and
/// 3 is the one that blocks every subsequent start.
///
/// THE DEFECT THIS FILE EXISTS FOR, measured on 2026.1:
///
///     production STOPPED, then RecoverProduction()  ->  returns $$$OK, state stays 2 (Stopped)
///     production RUNNING, then RecoverProduction()  ->  returns $$$OK, state stays 1 (Running)
///
/// `RecoverProduction()` returns `$$$OK` either way. It takes **no arguments** — there is nothing to
/// get wrong and nothing to check. So a helper that reports from the status alone produces
///
///     {"state":"2","success":true}
///
/// for a production that is not running: success is true because the API said so, and the state is
/// the one nobody looked at. That is the shape the whole of this bank keeps finding — a clean status
/// is the API's word for what it attempted, never evidence of the outcome. Read the state back.
///
/// THE LADDER, in the order that makes each step's answer usable:
///
///   1. ASK FIRST. `GetProductionStatus(.name, .state)` before doing anything — the right action
///      depends on the state, and three of the four states need different treatment.
///   2. CLASSIFY THE REFUSAL. A start that fails because the production is already running is not
///      the same as one that fails because it is Suspended, which is not the same as a missing class.
///      Returning one "could not start" for all three sends the reader to the wrong fix.
///   3. SUSPENDED NEEDS `CleanProduction`, NOT `Recover`. State 3 blocks every subsequent
///      `StartProduction`, and `RecoverProduction()` leaves it exactly where it was (above).
///   4. VERIFY, then report. Every verdict below ends with a state read back from the instance.
///
/// TWO API SHAPES WORTH KNOWING, both measured:
///
///   * `StartProduction(pProductionName = {$GET(^Ens.Configuration("csp","LastProduction"))})`
///     DEFAULTS TO WHATEVER WAS STARTED LAST. Called with no argument on a fresh process it starts
///     the previous production, which on a shared instance is somebody else's. Always pass the name.
///   * `RecoverProduction()` takes no arguments; `CleanProduction(pKillAppDataToo)` takes one;
///     `StopProduction(pTimeout=10, pForce=0)` and `RestartProduction(pTimeout=10, pForce=0)` take
///     two. They are not interchangeable and the arities are easy to transpose.
///
/// ONE CLAIM FROM THE COVERAGE MAP DID NOT REPRODUCE, recorded so it is not carried forward as fact.
/// The row's headline was a wait-for-Running loop, because "StartProduction returns before Running".
/// Measured on a four-item production: `StartProduction` returned `$$$OK` and the state read **1
/// (Running)** immediately, with no settle time. It may well return early for a large production or
/// one with slow hosts — that is unmeasured here — so `StartAndWait` below keeps a bounded wait, but
/// it is defensive rather than demonstrated, and the header says which.
Class Example.UTL.ProductionLifecycle Extends %RegisteredObject
{

/// Human-readable state, so no caller has to remember that 3 is the bad one.
/// Invoke via: SELECT Example_UTL.ProductionLifecycle_StateName(3)
ClassMethod StateName(pState As %Integer) As %String [ SqlProc ]
{
    Quit $Case(+pState, 1: "Running", 2: "Stopped", 3: "Suspended", 4: "Troubled", : "Unknown(" _ pState _ ")")
}

/// The current state, as "<code> <name> [<production>]". Never guesses: if the read itself fails,
/// it says so rather than returning a state nobody obtained.
ClassMethod Status() As %String [ SqlProc ]
{
    Set tName = ""
    Set tState = ""
    Set tSC = ##class(Ens.Director).GetProductionStatus(.tName, .tState)
    If $$$ISERR(tSC) {
        Return "UNREADABLE: " _ $system.Status.GetErrorText(tSC)
    }
    Return +$Get(tState) _ " " _ ..StateName($Get(tState)) _ " [" _ $Get(tName) _ "]"
}

/// Start a named production and CONFIRM it is running. pWaitSeconds is a bounded settle -- see the
/// header for why it is defensive rather than demonstrated.
ClassMethod StartAndWait(pProduction As %String, pWaitSeconds As %Integer = 10) As %String [ SqlProc ]
{
    If pProduction = "" {
        // StartProduction would default to whatever ran last. Refuse instead.
        Return "REFUSED: no production named. StartProduction defaults to the LAST one started, " _
               "which on a shared instance is somebody else's."
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pProduction) {
        Return "REFUSED: '" _ pProduction _ "' is not a compiled class -- nothing to start"
    }

    // 1. ASK FIRST.
    Set tName = ""
    Set tState = ""
    Do ##class(Ens.Director).GetProductionStatus(.tName, .tState)

    // 2. CLASSIFY, before attempting anything.
    If (+$Get(tState) = 3) {
        Return "BLOCKED: '" _ $Get(tName) _ "' is Suspended (state 3). Every StartProduction will " _
               "refuse until it is cleaned -- RecoverProduction does NOT clear it. Call CleanOut()."
    }
    If (+$Get(tState) = 1) {
        If ($Get(tName) = pProduction) {
            Return "OK: '" _ pProduction _ "' was already Running -- nothing to do"
        }
        Return "BLOCKED: a DIFFERENT production is Running ('" _ $Get(tName) _ "'). Stop that one by " _
               "name before starting '" _ pProduction _ "'."
    }

    Set tSC = ##class(Ens.Director).StartProduction(pProduction)
    If $$$ISERR(tSC) {
        Return "FAILED to start '" _ pProduction _ "': " _ $system.Status.GetErrorText(tSC) _
               " (state is now " _ ..Status() _ ")"
    }

    // 3. VERIFY. The status above is the API's word for what it attempted.
    For i = 1:1:pWaitSeconds {
        If ##class(Ens.Director).IsProductionRunning() {
            Return "OK: '" _ pProduction _ "' is Running (confirmed after " _ (i - 1) _ "s)"
        }
        Hang 1
    }
    Return "FAILED: StartProduction returned OK but the production is not Running after " _
           pWaitSeconds _ "s -- state is " _ ..Status()
}

/// Recover, and report the STATE rather than the status. This is the method the whole file is about.
ClassMethod RecoverAndVerify() As %String [ SqlProc ]
{
    Set tSC = ##class(Ens.Director).RecoverProduction()

    // RecoverProduction returns $$$OK from ANY state, including Stopped, where it changes nothing.
    // Reporting success from tSC alone is how a helper claims to have fixed a production that is
    // still down. Read the state.
    Set tName = ""
    Set tState = ""
    Do ##class(Ens.Director).GetProductionStatus(.tName, .tState)

    If '##class(Ens.Director).IsProductionRunning() {
        Return "NOT RECOVERED: RecoverProduction returned " _
               $Select($$$ISOK(tSC): "$$$OK", 1: "an error") _
               " but the production is " _ ..StateName($Get(tState)) _ " (state " _ +$Get(tState) _
               "). Recover does not start a stopped production and does not clear a suspended one."
    }
    Return "OK: '" _ $Get(tName) _ "' is Running after recovery"
}

/// Clear a Suspended production. Separate from recovery because it is the step recovery cannot do,
/// and because it is destructive enough to be asked for explicitly.
ClassMethod CleanOut(pKillAppDataToo As %Boolean = 0) As %String [ SqlProc ]
{
    Set tBefore = ..Status()
    Set tSC = ##class(Ens.Director).CleanProduction(pKillAppDataToo)
    If $$$ISERR(tSC) {
        Return "FAILED to clean: " _ $system.Status.GetErrorText(tSC) _ " (was " _ tBefore _ ")"
    }
    Return "OK: cleaned. was " _ tBefore _ ", now " _ ..Status()
}

/// Stop a production and confirm it stopped.
ClassMethod StopAndVerify(pTimeout As %Integer = 10, pForce As %Boolean = 0) As %String [ SqlProc ]
{
    Set tSC = ##class(Ens.Director).StopProduction(pTimeout, pForce)
    Set tNow = ..Status()
    If ##class(Ens.Director).IsProductionRunning() {
        Return "NOT STOPPED: StopProduction returned " _ $Select($$$ISOK(tSC): "$$$OK", 1: "an error") _
               " and the production is still " _ tNow
    }
    Return "OK: stopped. now " _ tNow
}

}
