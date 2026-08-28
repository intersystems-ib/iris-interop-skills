/// Rule: BestPractices_Interop_IRIS.md §5.5 "Async logging: prefer ^IRISTemp.* + %SYSTEM.Semaphore over IPQ"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Why temp globals over IPQ:
///   - IPQ is one-writer-one-reader per queue; many-writers needs the undocumented %SYSTEM.IPQSet.
///   - IPQ has bounded size: a full queue blocks writers, cascading pause across the app.
///   - IPQ is memory-only (lost on crash).
///   - Temp globals (^IRISTemp.*) are not journalled, never part of the writer's transaction
///     (no rollback risk), and spill to disk on memory overflow - graceful degradation.
///   - IPQ's pass-by-reference benefit only matters for very-large objects; for typical log
///     records (<1 MB) it's dwarfed by the blocking risk.
///
/// Pattern:
///   - Writers push records into ^IRISTemp.AppLog with $Increment for the slot key, then signal a semaphore.
///   - Reader sleeps on the semaphore; when woken, drains ^IRISTemp.AppLog (oldest first) and re-sleeps.
///   - Multiple readers possible; they share the same semaphore.
///
/// The semaphore API, verified on IRIS 2026.1:
///   The class is `%SYSTEM.Semaphore` — singular, `%`-prefixed — reached as `$SYSTEM.Semaphore`.
///   It is an OBJECT API, not a set of class methods on `$SYSTEM`: `%New()`, then `Open(name)`
///   or `Create(name, initialValue)` (both return 0 on failure), then:
///     - `Increment(amount)`            — signal; returns nothing
///     - `Decrement(amount, timeout)`   — wait; timeout in seconds, -1 = forever;
///                                        returns the amount decremented, 0 on timeout
///     - `GetValue()`, `SetValue()`, `Delete()`, `AddToWaitMany()`, `RmFromWaitMany()`,
///       `WaitCompleted()`, and the class method `WaitMany(timeout)`
///   There is no `Signal` and no `Wait` method: `$SYSTEM.Semaphore.Signal(...)` /
///   `$SYSTEM.Semaphore.Wait(...)` compile fine (`$SYSTEM.x.y()` resolves at runtime) and
///   then fail with <METHOD DOES NOT EXIST> the first time the logger runs.
///
/// Named `Example.UTL.AsyncLogger`: plain helper/utility classes take the `.UTL`
/// sub-package (skills/interop §"naming convention"), Tipo in the middle.
Class Example.UTL.AsyncLogger Extends %RegisteredObject
{

/// Process-shared semaphore name.
Parameter SEMNAME = "AppLogSemaphore";

/// Fallback drain interval in seconds: the reader wakes at least this often even when
/// no writer signals, so a lost signal can never strand queued records.
Parameter DRAINTIMEOUT = 60;

/// Log file name. Resolved at runtime against the instance's mgr/ directory — CR-10:
/// an example must not hardcode an absolute path such as /var/log/iris/applog.log.
/// In a real production, make this a Setting on the hosting component instead.
Parameter LOGFILE = "applog.log";

/// Open the shared semaphore, creating it (initial value 0) the first time.
/// Both Open and Create return 0 on failure, so this returns 0 if neither worked.
/// In production create the semaphore once at startup rather than racing on first use.
ClassMethod OpenSemaphore(Output pSem As %SYSTEM.Semaphore) As %Boolean
{
    set pSem = ##class(%SYSTEM.Semaphore).%New()
    if pSem.Open(..#SEMNAME) { quit 1 }
    quit (pSem.Create(..#SEMNAME, 0) '= 0)
}

/// Writer entrypoint - call from any process to enqueue a log record.
ClassMethod Write(pRecord As %String) As %Status
{
    #DIM tSlot as %Integer
    #DIM tSem as %SYSTEM.Semaphore
    set tSlot = $Increment(^IRISTemp.AppLog)
    set ^IRISTemp.AppLog(tSlot) = $ZDateTime($Horolog, 3, 1) _ "|" _ pRecord
    // Wake the reader: Increment IS the signal (non-blocking).
    if ..OpenSemaphore(.tSem) { do tSem.Increment(1) }
    quit $$$OK
}

/// Reader loop entrypoint - run as a long-lived job (one-shot job; or a scheduled BS).
/// Processes records oldest-first, sleeps until a writer signals, and returns cleanly
/// when RequestStop() is called - so the final `quit $$$OK` is reachable.
ClassMethod ReaderLoop() As %Status
{
    #DIM tSem as %SYSTEM.Semaphore
    #DIM tWoken as %Integer
    if '..OpenSemaphore(.tSem) {
        quit $$$ERROR($$$GeneralError, "Cannot open or create semaphore " _ ..#SEMNAME)
    }
    // Clear any stop flag left behind by a previous run.
    kill ^IRISTemp.AppLogControl("stop")
    while '..StopRequested() {
        do ..Drain()
        // Sleep until a writer Increments, or until the fallback timeout expires.
        set tWoken = tSem.Decrement(1, ..#DRAINTIMEOUT)
    }
    // Final drain so records queued while stopping are not lost.
    do ..Drain()
    quit $$$OK
}

/// Ask a running ReaderLoop to finish its current drain and return.
ClassMethod RequestStop() As %Status
{
    #DIM tSem as %SYSTEM.Semaphore
    set ^IRISTemp.AppLogControl("stop") = 1
    // Wake the reader so it notices the flag now rather than at the next timeout.
    if ..OpenSemaphore(.tSem) { do tSem.Increment(1) }
    quit $$$OK
}

ClassMethod StopRequested() As %Boolean [ CodeMode = expression ]
{
''$Get(^IRISTemp.AppLogControl("stop"), 0)
}

/// Drain everything currently queued, oldest slot first.
ClassMethod Drain()
{
    #DIM tKey as %Integer
    #DIM tRec as %String
    set tKey = $Order(^IRISTemp.AppLog(""))
    while tKey '= "" {
        set tRec = $Get(^IRISTemp.AppLog(tKey))
        kill ^IRISTemp.AppLog(tKey)
        do ..PersistRecord(tRec)
        set tKey = $Order(^IRISTemp.AppLog(tKey))
    }
}

/// Replace with your persistence target (file, persistent class, OS syslog, etc.).
ClassMethod PersistRecord(pRecord As %String)
{
    #DIM tFile as %String
    #DIM tPrevious as %String
    set tFile = ##class(%Library.File).NormalizeFilename(..#LOGFILE, ##class(%Library.File).ManagerDirectory())
    set tPrevious = $IO
    // Append, 2-second open timeout; $Test is 0 if the open timed out.
    open tFile:("WAS"):2
    if $Test {
        use tFile write pRecord, !
        close tFile
        use tPrevious
    }
}

}
