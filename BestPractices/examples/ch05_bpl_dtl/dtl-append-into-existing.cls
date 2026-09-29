/// Rule: BestPractices_Interop_IRIS.md §5.26 "Gathering N responses into ONE target: `<foreach>` + a collection context property + `create='existing'`"
/// Validity: Verified against IRIS for Health 2026.1 (Build 235U) — compiled.
/// Severity: Medium (with `create='new'` every turn discards the previous one and the process
/// delivers only the LAST answer, with no error anywhere).
///
/// Pattern: the accumulating half of §5.26. `transformations` presents `Create=Existing` only for
/// SUBTRANSFORMS — "the caller has already initialised the target and is calling you to mutate part
/// of it". That is true and it is not the only use: this is the same attribute used so a BPL can
/// call the SAME DTL once per loop turn and have each call ADD to one target.
///
/// WHY IT WORKS, read off the generated BPL thread code rather than assumed:
///
///     Set iscTemp = context.Batch
///     Set status  = ##class(Example.DT.AppendCycle).Transform(source, .iscTemp, aux)
///     Set context.Batch = iscTemp
///
/// With `create='existing'` the DTL fills the object it was HANDED instead of making one, so the
/// same OREF comes back and the appends survive the turn. That is also why the context property
/// must be `instantiate='1'` — handed a null target, the DTL has nothing to fill.
///
/// `DependsOn` is not decoration: without it the DTL can compile before the classes it names and
/// the generator resolves `source.`/`target.` against nothing (the compile-order trap
/// `transformations` already describes).
Class Example.DT.AppendCycle Extends Ens.DataTransformDTL [ DependsOn = (Example.MSG.FacilityCycleRsp, Example.MSG.CycleBatchReq) ]
{

Parameter IGNOREMISSINGSOURCE = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='Example.MSG.FacilityCycleRsp' targetClass='Example.MSG.CycleBatchReq' create='existing' language='objectscript' >
<assign value='source.FacilityCode' property='target.Codes' action='append' >
<annotation>
<![CDATA[append, not set: one element per loop turn. `set` on a list property would be a type error at runtime, not a compile error.]]>
</annotation>
</assign>
<assign value='target.TotalCycles + source.Cycles' property='target.TotalCycles' action='set' >
<annotation>
<![CDATA[reads the TARGET it was handed. Only possible because create='existing' passed the accumulated object in rather than a fresh one.]]>
</annotation>
</assign>
</transform>
}

}
