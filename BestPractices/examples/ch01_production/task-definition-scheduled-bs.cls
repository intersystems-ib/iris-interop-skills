/// Rule: BestPractices_Interop_IRIS.md §1.20 "Scheduling with %SYS.Task.Definition, and the purge settings that do not purge"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed.
/// Severity: High (the silent failure is a task that runs on time and dispatches nothing).
///
/// Pattern: the NATIVE TASK route to scheduled work — `%SYS.Task.Definition` — which §5.2 offers and
/// which had no artefact. Its sibling `adp-scheduler-inbound-adapter.cls` shows the other route, a
/// custom `Ens.InboundAdapter`; §5.2 compares them, and the choice is not arbitrary:
///
///   THIS route  — the trigger is an instance-wide Task Manager entry. It survives a stopped
///                 production, is visible and runnable from the Portal's Task Manager, and can run in
///                 a namespace with no production at all.
///   THE ADAPTER — the trigger IS a production item: enabled and disabled with the production, shown
///                 in the Visual Trace, and its dispatch carries a session id like any other message.
///
/// Pick the task when the schedule must outlive the production; pick the adapter when the firing
/// should be part of the interop record.
///
/// THE SUPERCLASS IS `%SYS.Task.Definition`. `%SYS.TaskSuper` also exists, is `%Persistent`, and has
/// **no `OnTask`** — measured. So it survives a "does this class exist?" check and then never runs
/// anything, which is why it is a BANNED token in this bank's own gate (tier 1, C6).
///
/// THE CONTRACT, read from the dictionary rather than remembered:
///     OnTask()                      As %Status   -- NO arguments
///     GetTaskName()                 As %String   -- what the Task Manager lists it as
///     OnSubmit(&pID, pSubmit)       As %Status   -- called when the task is saved
///     GetSettings()/SetSettings()                -- how the Portal renders your properties
/// and the only properties the superclass brings are `%RunDate` and `%RunTime`. Everything the task
/// needs, it declares.
///
/// THE LINE THAT MATTERS, and the reason this needs an example rather than a paragraph:
///
///     Set tSC = tService.ProcessInput(tRequest, .tOutput)
///
/// An `OnTask()` that decides it is due and returns `$$$OK` without dispatching is the canonical
/// silent failure of scheduled work. The Task Manager shows a successful run, "Last Finished" advances,
/// there is nothing in the Event Log, and no message is ever produced. Measured: with the call, one
/// dispatch per run; without it, `OnTask` still returns `$$$OK`.
///
/// `PoolSize=1` ON THE TARGET SERVICE, AND A SYNCHRONOUS DISPATCH. The Task Manager gives no overlap
/// guarantee: a run that takes longer than the interval can be re-entered. A pool of one plus a
/// synchronous `ProcessInput` means the second firing queues behind the first instead of both walking
/// the same input. If the work is genuinely parallel, make that a decision with a comment on it rather
/// than a side effect of the default.
Class Example.UTL.ScheduledCensusTask Extends %SYS.Task.Definition
{

/// What the Portal's Task Manager lists. Without it the entry shows the class name, which is
/// indistinguishable from every other task in a long list.
Parameter TaskName = "Example census intake";

/// The Business Service to dispatch into. A property, not a literal, so the same task can drive a
/// different service per environment; GetSettings() renders it in the Portal automatically.
Property TargetService As %String [ InitialExpression = "BS.Census" ];

/// Marker so a test can prove the dispatch happened rather than that the method returned OK.
Property DispatchLog As %String [ InitialExpression = "^Example.ScheduledTask" ];

Method OnTask() As %Status
{
    // The service must exist in a RUNNING production. CreateBusinessService returns an error rather
    // than throwing when it does not, and reporting that error is what makes a mis-named target
    // visible in the Task Manager instead of silent.
    Set tSC = ##class(Ens.Director).CreateBusinessService(..TargetService, .tService)
    If $$$ISERR(tSC) { Quit tSC }
    If '$IsObject(tService) {
        Quit $$$ERROR($$$GeneralError, "no service instance for " _ ..TargetService)
    }

    Set tRequest = ##class(Ens.StringContainer).%New("census run " _ $ZDateTime($Horolog, 3))

    // THE DISPATCH. Omit this and the task ticks for ever, green, producing nothing.
    Set tSC = tService.ProcessInput(tRequest, .tOutput)
    If $$$ISERR(tSC) { Quit tSC }

    Set @..DispatchLog@($Increment(@..DispatchLog)) = tRequest.StringValue
    Quit $$$OK
}

}
