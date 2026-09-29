/// Rule: BestPractices_Interop_IRIS.md §5.26 "Gathering N responses into ONE target: `<foreach>` + a collection context property + `create='existing'`"
/// Validity: Verified against IRIS for Health 2026.1 (Build 235U) — compiled.
/// Severity: Medium.
///
/// Sibling: the ACCUMULATING TARGET for `dtl-append-into-existing.cls`, and the single request the
/// process finally sends. One of these is built for the whole loop, not one per turn — which is why
/// the context property that holds it needs `instantiate='1'` in `bpl-foreach-accumulate.cls`.
/// `%Persistent` is LEFTMOST deliberately (§5.10).
Class Example.MSG.CycleBatchReq Extends (%Persistent, Ens.Request)
{

Parameter XMLNAME = "CycleBatchReq";

/// Appended to once per loop turn by the DTL running with `create='existing'`.
Property Codes As list Of %String(MAXLEN = 32);

/// Running total, read-then-written by the same DTL. Needs the InitialExpression: with
/// `create='existing'` the DTL is handed an object the PROCESS made, and `"" + n` is n, but an
/// explicit 0 is what makes the first turn's arithmetic readable rather than accidental.
Property TotalCycles As %Integer [ InitialExpression = 0 ];

}
