/// Rule: BestPractices_Interop_IRIS.md §5.23 "Asserting a BPL ran: `$IsObject(resp)` passes on a process that failed every call"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, started and driven.
/// Severity: Medium as a fixture; the assertion gap it exposes is High.
///
/// FIXTURE, AND DELIBERATELY WRONG. This BPL carries the exact defect §5.21 warns about: a `<catchall>`
/// that records the fault and never propagates it. **Do not copy this shape.** It exists so
/// `tdd-testproduction-bpl.cls` can prove that the assertions in `tdd`'s own gated snippet pass on a
/// process where every `<call>` failed.
///
/// Compare `bpl-scope-catchall-compensation.cls`, which is the SAME shape plus the one line that makes it
/// honest (`set ..%Context.%LastError` propagated via `status`). The difference between the two files is
/// the difference between a caller being told the truth and a caller being told nothing.
///
/// WHAT IT DOES, measured:
///
///     input          BO result   process status   response.StringValue
///     HAPPY-...      succeeds    9 Completed      "none"     <- the context initial expression
///     FAIL-...       fails       9 Completed      "caught: ERROR #5001: ..."
///
/// Both complete green. The response field is the only thing in the reply that differs -- which is why
/// the oracle asserts the VALUE and not the object's existence.
Class Example.BP.SwallowedFault Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='Ens.StringContainer' response='Ens.StringContainer' height='2000' width='2000' >
<context>
<!-- initialexpression is OBJECTSCRIPT: the quotes are required (§5.21). "none" is what a caller sees
     on the happy path, because nothing on that path assigns to it. -->
<property name='Note' type='%String' initialexpression='"none"' />
</context>
<sequence xend='200' yend='700' >
<scope xpos='200' ypos='250' xend='200' yend='600' >
<call name='Charge' target='BO.Failing' async='0' xpos='200' ypos='250' >
<request type='Ens.StringContainer' >
<assign property="callrequest.StringValue" value="request.StringValue" action="set" />
</request>
<response type='Ens.Response' />
</call>
<faulthandlers>
<catchall xpos='200' ypos='500' xend='200' yend='600' >
<!-- THE DEFECT. It records and stops. No `set status`, so the fault dies here and the process
     goes on to complete at 9. Kept short on purpose: a longer note overflows StringValue's MAXLEN
     and logs #7201, which is a second, unrelated error in the way. -->
<code name='Record' xpos='200' ypos='250' >
<![CDATA[
 set context.Note = "caught: "_$extract($system.Status.GetErrorText(..%Context.%LastError), 1, 80)
]]>
</code>
</catchall>
</faulthandlers>
</scope>
<assign name='Fill' property="response.StringValue" value='context.Note' action="set" xpos='200' ypos='650' />
</sequence>
</process>
}

}
