/// Rule: BestPractices_Interop_IRIS.md §5.26 "Gathering N responses into ONE target: `<foreach>` + a collection context property + `create='existing'`"
/// Validity: Verified against IRIS for Health 2026.1 (Build 235U) — compiled.
/// Severity: Medium (without a template the model writes a string-merge method in a message class
/// or a `<code>` block, which is the imperative shape §5.7 exists to prevent).
///
/// Pattern: "call the same operation once per key, combine the answers into ONE request, make ONE
/// final call." The idiomatic IRIS shape, and the one `bpl` had no template for: a `<foreach>` over
/// a collection on the request, the answers kept in a COLLECTION context property, and a
/// `<transform>` whose DTL runs `create='existing'` so each turn appends to the same target.
///
/// NOT the same shape as §5.19's `<flow>`/`<sync>`, and the difference is which one to reach for:
///
///   <flow>/<sync>   N branches written at AUTHORING time, run in parallel, joined by `calls=`.
///   <foreach>       N driven by the DATA, run sequentially, accumulated into one target.
///
/// A facility list that arrives in the request cannot be a `<flow>`: you would have to know N when
/// you wrote the XML.
///
/// THE FOUR THINGS THAT MAKE IT WORK, each measured rather than assumed:
///
///  1. `instantiate='1'` on the target context property. `create='existing'` hands the DTL the
///     object the process is holding; a null one gives it nothing to fill.
///  2. `action='append'` on the response assign. `set` would keep only the last answer.
///  3. `<scope>` INSIDE the `<foreach>`, so one failed call is a recorded skip and the loop goes
///     on. A `<faulthandlers>` outside the loop ends the process on the first failure.
///  4. The key travels on the RESPONSE (`FacilityCode`), not through `aux=`. A BPL
///     `<transform aux='...'>` compiles clean and arrives EMPTY — `Ens.BPL.Transform` has an `Aux`
///     property and its generator emits it, but `Ens.BPL.Parser:parseTransform` reads only
///     `class`, `source` and `target`, so nothing ever populates it (§5.26).
///
/// `Example.BO.Cycles` / `Example.BO.Batch` are item names, not classes — wire them in the
/// production. The process compiles without them; a missing target fails at RUNTIME, which is what
/// the pre-flight validator in `bpl` exists to catch before a restart.
Class Example.BP.CycleGather Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='Example.MSG.CycleReq' response='Ens.Response' height='2000' width='2000' >
<context>
<property name='K' type='%Integer' initialexpression='0' instantiate='0' />
<property name='Answers' type='Example.MSG.FacilityCycleRsp' collection='list' instantiate='0' />
<property name='Batch' type='Example.MSG.CycleBatchReq' instantiate='1' />
<property name='Skipped' type='%String' initialexpression='""' instantiate='0' />
</context>
<sequence xend='200' yend='800' >
<foreach property='request.Facilities' key='context.K' name='EachFacility' xpos='200' ypos='250' xend='200' yend='550' >
<scope xpos='200' ypos='250' xend='200' yend='400' >
<call name='Lookup' target='Example.BO.Cycles' async='0' xpos='200' ypos='250' >
<request type='Ens.StringRequest' >
<assign property='callrequest.StringValue' value='request.Facilities.GetAt(context.K)' action='set' />
</request>
<response type='Example.MSG.FacilityCycleRsp' >
<assign property='context.Answers' value='callresponse' action='append' />
</response>
</call>
<transform name='Accumulate' class='Example.DT.AppendCycle' source='context.Answers.GetAt(context.Answers.Count())' target='context.Batch' xpos='200' ypos='350' />
<faulthandlers>
<catchall xpos='200' ypos='250' xend='200' yend='350' >
<assign name='RecordSkip' property='context.Skipped' value='context.Skipped_request.Facilities.GetAt(context.K)_","' action='set' xpos='200' ypos='250' />
</catchall>
</faulthandlers>
</scope>
</foreach>
<call name='Deliver' target='Example.BO.Batch' async='0' xpos='200' ypos='650' >
<request type='Example.MSG.CycleBatchReq' >
<assign property='callrequest' value='context.Batch' action='set' />
</request>
</call>
</sequence>
</process>
}

}
