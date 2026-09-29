/// Rule: BestPractices_Interop_IRIS.md §5.26 "Gathering N responses into ONE target: `<foreach>` + a collection context property + `create='existing'`"
/// Validity: Verified against IRIS for Health 2026.1 (Build 235U) — compiled.
/// Severity: Medium.
///
/// Sibling: one call's answer in `bpl-foreach-accumulate.cls`, and the DTL source in
/// `dtl-append-into-existing.cls`.
///
/// `FacilityCode` IS THE POINT OF THIS CLASS. The DTL needs to know which facility an answer came
/// from, and the BPL `<transform>` element has no working channel for passing it: `aux=` is parsed
/// by nothing (§5.26, measured on `Ens.BPL.Parser`). So the key travels back ON THE RESPONSE, which
/// is the shape that works and the one the skill now prescribes.
Class Example.MSG.FacilityCycleRsp Extends (%Persistent, Ens.Response)
{

Parameter XMLNAME = "FacilityCycleRsp";

/// Echoed back by the operation so the transform can attribute the answer without `aux`.
Property FacilityCode As %String(MAXLEN = 32);

Property Cycles As %Integer [ InitialExpression = 0 ];

}
