/// Rule: BestPractices_Interop_IRIS.md §2.14 "Repeating segments: iterate by index, and the group path fails with an error status"
/// Validity: Verified against IRIS for Health 2026.1 — compiled.
/// Severity: Medium (the collection target the repeat loop fills).
///
/// Pattern: the target of a repeating-segment transform — one entry per repeat, in a `list Of`.
///
/// `list Of %String` RATHER THAN A FIXED SET OF PROPERTIES. A message with `Obs1`, `Obs2`, `Obs3`
/// silently drops the fourth repeat, and HL7 puts no upper bound on OBX. The list projects to a child
/// table `Example_MSG.ObsSummary_Observations` for SQL, per §5.x on collections.
///
/// `%Persistent` IS LEFTMOST (§5.10), so this has its own extent and the test can read rows back.
Class Example.MSG.ObsSummary Extends (%Persistent, Ens.Request)
{

Property PatientId As %String(MAXLEN = 50);

/// One entry per OBX repeat. Sized to the source rather than left bare -- §5.15 measured that a bare
/// %String is MAXLEN=50 and REJECTS a longer value with #7201 rather than truncating.
Property Observations As list Of %String(MAXLEN = 200);

}
