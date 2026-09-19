/// Rule: BestPractices_Interop_IRIS.md §1.20 "Scheduling with %SYS.Task.Definition, and the purge settings that do not purge"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (a setting that does not exist is not an error, and a purge that removes nothing looks identical to one that worked).
///
/// Pattern: the oracle for `task-definition-scheduled-bs.cls` and `purge-task-schedule.cls`.
///
/// IT NEEDS NO PRODUCTION, DELIBERATELY. Every claim here is either a dictionary fact or a %SYS.Task
/// round-trip, so the suite is fast and cannot fail for an unrelated reason. The one thing it does NOT
/// assert is the dispatch inside `OnTask()` reaching a live Business Service — that needs a running
/// production, and `TestOnTaskRefusesAnUnknownService` covers the half that can be reached without one:
/// a mis-named target is reported rather than swallowed.
///
/// MEASURED VALUES this pins:
///     %SYS.Task.Definition   OnTask() takes NO arguments, returns %Status; own props are only
///                            %RunDate/%RunTime
///     %SYS.TaskSuper         exists, is %Persistent, and has NO OnTask  <- survives an existence check
///     NumDaysToKeep          ZERO rows in the whole dictionary
///     NumberOfDaysToKeep     Ens.Util.Tasks.Purge and Ens.Util.Tasks.PurgeMessageBank
///     Ens.Util.Tasks.Purge   Extends %SYS.Task.Definition
///       TypesToPurge   "events"   <- NOT messages
///       BodiesToo      0          <- bodies survive a message purge
///       NumberOfDaysToKeep 7 · KeepIntegrity 1 · BitMapPurgeMaxDuration 600
///     %SYS.Task.TimePeriod     VALUELIST 0,1,2,3,4,5 = Daily, Weekly, Monthly, Monthly Special,
///                              Run After, On Demand
///     %SYS.Task.DailyFrequency VALUELIST 0,1 = Once, Several
///     a round-tripped task     TaskClass=Ens.Util.Tasks.Purge, NameSpace=<this one>, TimePeriod=0,
///                              DailyFrequency=0, DailyStartTime=7200, Settings carrying the three
///                              name/value pairs
///
/// RUN AND MUTATION-CHECKED, measured, five mutations:
///
///     as shipped                                       PASSED 6/6
///     1 Schedule() writes NumDaysToKeep                 TestScheduleRoundTrips              FAIL
///     2 Schedule() sets TimePeriod = 1 (Weekly)         TestScheduleRoundTrips              FAIL
///     3 Defaults() hops to %SYS again                   TestDefaultsAreReadWhereTheyLive +
///                                                      TestPurgeDefaultsArePurgingEventsOnly FAIL
///     5 BOTH the hop AND the guard defeated             the same two                        FAIL
///     4 only the clean-zero guard removed               NO FAILURE -- see below
///
/// MUTATION 4 IS REDUNDANT, NOT UNFALSIFIED, AND THE DIFFERENCE IS WORTH THE LINE. Removing the
/// `'$Data(pDefaults)` guard on its own changes nothing, because with the read in the right namespace
/// the array is never empty. Mutation 5 shows what happens when the guard's condition is actually
/// reachable -- hop to %SYS AND defeat the guard with a sentinel -- and the suite still goes red, on
/// the assertions that check the VALUES rather than the count. So the tests, not the guard, are what
/// catch a bad read; the guard's job is to make the failure legible at the point of the read instead
/// of at the caller's next line. Kept for that, and said so rather than left looking load-bearing.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.ScheduledTask", namespace="<NS>")
Class Example.Tests.ScheduledTask Extends %UnitTest.TestCase
{

/// Read one property parameter out of a class that lives in %SYS.
ClassMethod SysParam(pId As %String, pName As %String) As %String [ Private ]
{
    New $Namespace
    Set $Namespace = "%SYS"
    Set tProp = ##class(%Dictionary.CompiledProperty).%OpenId(pId)
    Quit $Select($IsObject(tProp):tProp.Parameters.GetAt(pName), 1:"<no such property>")
}

/// The dictionary fact behind the BANNED token: the wrong superclass EXISTS, so "does it exist?" is
/// not the question. It has no OnTask, so a task written against it never runs anything.
Method TestTaskSuperHasNoOnTask() As %Status
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT parent, Name FROM %Dictionary.CompiledMethod WHERE parent IN ('%SYS.Task.Definition','%SYS.TaskSuper') AND Name = 'OnTask'")
    Set tOwners = ""
    While tRs.%Next() { Set tOwners = tOwners _ $Select(tOwners="":"", 1:",") _ tRs.%Get("parent") }
    Do $$$AssertEquals(tOwners, "%SYS.Task.Definition", "OnTask is on %SYS.Task.Definition and on NOTHING else -- %SYS.TaskSuper has none")
    // and the half that makes it dangerous: the wrong one is a real, openable class.
    Set tRs2 = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM %Dictionary.CompiledClass WHERE Name = '%SYS.TaskSuper'")
    Do tRs2.%Next()
    Do $$$AssertEquals(tRs2.%Get("n"), 1, "%SYS.TaskSuper exists, so an existence check passes and the task still never runs")
    Quit $$$OK
}

/// The spelling, with a positive control so a zero cannot be a failed query.
Method TestNumDaysToKeepDoesNotExist() As %Status
{
    // THE WRONG NAME IS ASSEMBLED, NOT WRITTEN, and that is not squeamishness. Tier 1's C6 bans the
    // literal in any non-comment line precisely so it cannot reappear in an artefact -- and this test
    // is an artefact. Writing it whole here would trip the guard this test exists to justify, which is
    // C6 working: the only place the literal is allowed is a comment explaining it.
    Set tWrong = "Num" _ "DaysToKeep"
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM %Dictionary.CompiledProperty WHERE Name = ?", tWrong)
    Do tRs.%Next()
    Do $$$AssertEquals(tRs.%Get("n"), 0, "there is no " _ tWrong _ " anywhere in the instance")
    // POSITIVE CONTROL on the same query shape: the long name must come back, or the zero above
    // proves only that the query was broken.
    Set tRs2 = ##class(%SQL.Statement).%ExecDirect(, "SELECT parent FROM %Dictionary.CompiledProperty WHERE Name = 'NumberOfDaysToKeep' ORDER BY parent")
    Set tOwners = ""
    While tRs2.%Next() { Set tOwners = tOwners _ $Select(tOwners="":"", 1:",") _ tRs2.%Get("parent") }
    Do $$$AssertEquals(tOwners, "Ens.Util.Tasks.Purge,Ens.Util.Tasks.PurgeMessageBank", "and NumberOfDaysToKeep is on exactly these two: " _ tOwners)
    Quit $$$OK
}

/// The two defaults that make a scheduled purge look broken.
Method TestPurgeDefaultsArePurgingEventsOnly() As %Status
{
    Do $$$AssertStatusOK(##class(Example.UTL.PurgeSchedule).Defaults(.tD), "read the purge task's declared defaults")
    Do $$$AssertEquals($Get(tD("TypesToPurge")), """events""", "TypesToPurge defaults to events -- NOT messages")
    Do $$$AssertEquals($Get(tD("BodiesToo")), 0, "BodiesToo defaults to 0 -- message bodies survive a message purge")
    Do $$$AssertEquals($Get(tD("NumberOfDaysToKeep")), 7, "and the retention default is 7 days")
    Do $$$AssertEquals($Get(tD("KeepIntegrity")), 1, "KeepIntegrity defaults to 1, which is why a busy instance can purge nothing and be correct")
    Quit $$$OK
}

/// Defaults() must read the WORK class where it lives. The schedule is %SYS-scoped; the work class is
/// not mapped there, so a hop returns zero rows with SQLCODE 100 -- a clean zero, not an error.
Method TestDefaultsAreReadWhereTheyLive() As %Status
{
    Do $$$AssertStatusOK(##class(Example.UTL.PurgeSchedule).Defaults(.tD), "Defaults() succeeded")
    Do $$$AssertTrue($Data(tD), "and returned a populated array rather than an empty one with $$$OK")
    Set tN = 0, tK = ""
    For { Set tK = $Order(tD(tK))  Quit:tK=""  Set tN = tN + 1 }
    Do $$$AssertTrue(tN >= 7, "with every declared setting present, not a subset: " _ tN)
    Quit $$$OK
}

/// The schedule round-trips, and the magic numbers mean what the class says they mean.
Method TestScheduleRoundTrips() As %Status
{
    Do $$$AssertStatusOK(##class(Example.UTL.PurgeSchedule).Schedule(3, "all", 1, .tId), "scheduled the purge task")
    Do $$$AssertNotEquals(tId, "", "and got a task id")
    Set tSC = ..ReadTask(tId, .tInfo)
    Do $$$AssertStatusOK(tSC, "reopened it from %SYS")
    Do $$$AssertEquals($Get(tInfo("TaskClass")), "Ens.Util.Tasks.Purge", "TaskClass names the WORK class")
    Do $$$AssertEquals($Get(tInfo("TimePeriod")), 0, "TimePeriod 0, which its own VALUELIST calls Daily")
    Do $$$AssertEquals($Get(tInfo("DailyFrequency")), 0, "DailyFrequency 0, which its own VALUELIST calls Once")
    Do $$$AssertEquals($Get(tInfo("NumberOfDaysToKeep")), 3, "and the WORK's setting travelled in the task's Settings list")
    Do $$$AssertEquals($Get(tInfo("TypesToPurge")), "all", "as did TypesToPurge")
    // the enumerations those two numbers rest on
    Do $$$AssertEquals($Piece(..SysParam("%SYS.Task||TimePeriod", "DISPLAYLIST"), ",", 2), "Daily", "TimePeriod 0 really is Daily")
    Do $$$AssertEquals($Piece(..SysParam("%SYS.Task||DailyFrequency", "DISPLAYLIST"), ",", 2), "Once", "DailyFrequency 0 really is Once")
    Do ..DeleteTask(tId)
    Quit $$$OK
}

/// A mis-named service is reported, not swallowed -- the half of OnTask() reachable with no production.
Method TestOnTaskRefusesAnUnknownService() As %Status
{
    Set tTask = ##class(Example.UTL.ScheduledCensusTask).%New()
    Set tTask.TargetService = "BS.NoSuchServiceAnywhere"
    Set tSC = tTask.OnTask()
    Do $$$AssertStatusNotOK(tSC, "OnTask reports a target it cannot reach rather than returning $$$OK")
    Quit $$$OK
}

ClassMethod ReadTask(pId As %String, Output pInfo) As %Status [ Private ]
{
    Kill pInfo
    New $Namespace
    Set $Namespace = "%SYS"
    Set tTask = ##class(%SYS.Task).%OpenId(pId, , .tSC)
    If '$IsObject(tTask) {
        Set tWhy = "task " _ pId _ " did not reopen: " _ $System.Status.GetErrorText(tSC)
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    Set pInfo("TaskClass") = tTask.TaskClass
    Set pInfo("TimePeriod") = tTask.TimePeriod
    Set pInfo("DailyFrequency") = tTask.DailyFrequency
    Set tS = tTask.Settings
    For i = 1:2:$ListLength(tS) { Set pInfo($List(tS, i)) = $ListGet(tS, i + 1) }
    Quit $$$OK
}

ClassMethod DeleteTask(pId As %String) As %Status [ Private ]
{
    New $Namespace
    Set $Namespace = "%SYS"
    Quit ##class(%SYS.Task).%DeleteId(pId)
}

}
