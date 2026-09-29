/// Rule: BestPractices_Interop_IRIS.md §5.26 "Gathering N responses into ONE target: `<foreach>` + a collection context property + `create='existing'`"
/// Validity: Verified against IRIS for Health 2026.1 (Build 235U) — compiled.
/// Severity: Medium (the alternative a model reaches for is a string-merge method in a message class).
///
/// Sibling: the PROCESS INPUT for `bpl-foreach-accumulate.cls`. The collection here is what the
/// `<foreach>` iterates, so it is the reason the pattern is data-driven rather than a `<flow>` with
/// a branch per facility written at authoring time (§5.19 is that other shape).
/// `%Persistent` is LEFTMOST deliberately (§5.10).
Class Example.MSG.CycleReq Extends (%Persistent, Ens.Request)
{

Parameter XMLNAME = "CycleReq";

/// The keys the process loops over. `list` so `<foreach property='request.Facilities'>` can walk it
/// and `GetAt(context.K)` can read the current one.
Property Facilities As list Of %String(MAXLEN = 32);

}
