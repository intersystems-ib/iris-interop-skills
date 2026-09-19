/// Rule: BestPractices_Interop_IRIS.md §1.20 "Scheduling with %SYS.Task.Definition, and the purge settings that do not purge"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed; every default read from the dictionary.
/// Severity: High (the default settings purge almost nothing, and the symptom is a disk that keeps filling).
///
/// Pattern: scheduling `Ens.Util.Tasks.Purge` from code, with its real settings and their real defaults.
///
/// `Ens.Util.Tasks.Purge` EXTENDS `%SYS.Task.Definition` — measured — so it is the platform's own worked
/// example of the pattern in `task-definition-scheduled-bs.cls`, and its settings are ordinary
/// properties that `GetSettings()` renders in the Portal.
///
/// THE SPELLING IS `NumberOfDaysToKeep`. There is no `NumDaysToKeep` anywhere in the instance —
/// measured, zero rows in `%Dictionary.CompiledProperty`, with a positive control on the same query
/// shape returning the two classes that do carry the long name (`Ens.Util.Tasks.Purge` and
/// `Ens.Util.Tasks.PurgeMessageBank`). The short spelling is now a BANNED token in tier 1 (C6),
/// alongside `%SYS.TaskSuper`, because setting a property that does not exist on a `%SYS.Task` is not
/// an error — it is a value that goes nowhere.
///
/// TWO DEFAULTS THAT MAKE THE TASK LOOK BROKEN, both read off the class:
///
///     TypesToPurge   = "events"     <- NOT messages. The default purge removes Event Log rows only.
///     BodiesToo      = 0            <- message bodies SURVIVE a message purge.
///     NumberOfDaysToKeep = 7
///     KeepIntegrity  = 1            <- will not break a session apart; a long-running session pins
///                                      everything in it, so a purge can legitimately remove nothing
///     BitMapPurgeMaxDuration = 600
///     UseSystemMessagesLog = 0
///
/// So "I scheduled the purge task and the database still grows" has two ordinary explanations before
/// anything is wrong: `TypesToPurge` never included messages, and `BodiesToo` left every body behind.
/// Both are one-word settings, and neither reports anything.
///
/// `KeepIntegrity = 1` is the third, and it is the one to leave alone. It refuses to purge a message
/// whose session still has live parts. A purge that removed nothing on a busy instance is usually this
/// working correctly, not a misconfiguration — check for long-running sessions before changing it.
Class Example.UTL.PurgeSchedule Extends %RegisteredObject
{

/// Create (or update) the nightly purge task, spelling every setting the way the class does.
///
/// `%SYS.Task` is the SCHEDULE; `Ens.Util.Tasks.Purge` is the WORK. They are two objects: TaskClass
/// names the second from the first, and the work's own properties travel in the task's Settings.
ClassMethod Schedule(pDaysToKeep As %Integer = 7, pTypes As %String = "all", pBodiesToo As %Boolean = 1, Output pTaskId As %String) As %Status
{
    Set pTaskId = ""
    New $Namespace
    Set tNamespace = $Namespace
    // The Task Manager lives in %SYS; `New $Namespace` restores the caller's on every exit, including
    // an error one -- see §11.13 for what omitting it costs.
    Set $Namespace = "%SYS"

    Set tTask = ##class(%SYS.Task).%New()
    Set tTask.Name = "Example nightly Ensemble purge"
    Set tTask.NameSpace = tNamespace
    Set tTask.TaskClass = "Ens.Util.Tasks.Purge"
    Set tTask.RunAsUser = $Username
    // Daily. TimePeriod 0 = daily; DailyFrequency 0 = once per day, at DailyStartTime.
    Set tTask.TimePeriod = 0
    Set tTask.TimePeriodEvery = 1
    Set tTask.DailyFrequency = 0
    Set tTask.DailyStartTime = 2 * 3600      // 02:00, in seconds past midnight
    Set tTask.Priority = 2

    // The WORK's settings. NumberOfDaysToKeep -- not NumDaysToKeep, which does not exist.
    Set tSettings = $ListBuild("NumberOfDaysToKeep", pDaysToKeep,
                               "TypesToPurge", pTypes,
                               "BodiesToo", pBodiesToo)
    Set tTask.Settings = tSettings

    Set tSC = tTask.%Save()
    If $$$ISERR(tSC) { Quit tSC }
    Set pTaskId = tTask.%Id()
    Quit $$$OK
}

/// The defaults as the class declares them, so a caller can show the operator what they are about to
/// change rather than describing them from memory.
ClassMethod Defaults(Output pDefaults) As %Status
{
    Kill pDefaults
    // NO NAMESPACE HOP HERE, and that is the point. The two halves of a scheduled task live in
    // DIFFERENT namespaces: %SYS.Task (the schedule) is %SYS-scoped, and Ens.Util.Tasks.Purge (the
    // work) is an Ens class mapped into an INTEROP namespace and NOT into %SYS. Hopping to read it
    // returns zero rows -- measured, and with SQLCODE 100, so a `< 0` guard does not fire and the
    // caller gets an empty array with $$$OK. Read the work class where it lives.
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, InitialExpression FROM %Dictionary.CompiledProperty "_
        "WHERE parent = 'Ens.Util.Tasks.Purge' AND Private = 0 AND $EXTRACT(Name) <> '%'")
    If tRs.%SQLCODE < 0 {
        Set tWhy = "could not read the purge task's properties: SQLCODE " _ tRs.%SQLCODE _ " " _ tRs.%Message
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    While tRs.%Next() {
        Set pDefaults(tRs.%Get("Name")) = tRs.%Get("InitialExpression")
    }
    // A CLEAN ZERO IS NOT AN ANSWER. Ens.Util.Tasks.Purge is present in any interop-enabled
    // namespace, so an empty result means this ran somewhere it cannot see the class -- report that
    // rather than hand back an empty array with $$$OK.
    If '$Data(pDefaults) {
        Quit $$$ERROR($$$GeneralError, "no properties found for Ens.Util.Tasks.Purge -- is this an interop-enabled namespace?")
    }
    Quit $$$OK
}

}
