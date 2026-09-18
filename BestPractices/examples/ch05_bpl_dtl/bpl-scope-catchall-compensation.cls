/// Rule: BestPractices_Interop_IRIS.md §5.21 "BPL <scope>: the fault handler that completes the process green"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed inside a started production.
/// Severity: High (a caught-and-logged fault leaves the process Completed with IsError=0).
///
/// Pattern: `<scope>` / `<faulthandlers>` / `<catchall>` / `<compensationhandlers>` — none of which
/// appeared anywhere in this plugin before this file. Measured: `grep -rn '<scope'` over all 20 skills,
/// the whole deliverable and the whole bank returned the coverage-map row and nothing else.
///
/// THE DEFECT, MEASURED END TO END. A catchall that logs the fault and falls through leaves the
/// business process COMPLETED and NOT in error, while the call that failed sits beside it:
///
///     hdr 371 -> the BP     Status=9 (Completed)  IsError=0    <- the caller is told it worked
///     hdr 372 -> the BO     Status=8 (Error)      IsError=0
///     hdr 373 -> the BP     Status=9 (Completed)  IsError=1    <- the error response, inbound
///     catchall log: "caught: ERROR #5001: ... always fails"
///
/// So the failure is visible in the trace and invisible to the caller. `Ens.DataType.MessageStatus`
/// measured in full, because 8 and 9 are the two that matter and guessing them is easy:
/// 1=Created 2=Queued 3=Delivered 4=Discarded 5=Suspended 6=Deferred 7=Aborted 8=Error 9=Completed.
///
/// THE FIX IS ONE LINE IN THE CATCHALL: `set status = ...`. `status` is the variable the generated
/// `Transform`/`OnRequest` wrapper returns — see §5.20 — so assigning it is how a handler propagates
/// instead of swallowing. This BPL does that, and its test asserts the process ends in Error.
///
/// FOUR SCHEMA FACTS, each measured by compiling, because the error messages name everything EXCEPT
/// what you need. `<scope>`'s content model, read out of the compiler by feeding it an unknown
/// element, is:
///
///     (annotation?, ONE activity, compensationhandlers?, faulthandlers)
///
///   1. `<faulthandlers>` is REQUIRED. A `<scope>` without one does not compile:
///      "missing elements in content model". A scope is not a way to group activities; it is a way to
///      attach a handler, and the schema enforces that.
///   2. `<catchall>` must be INSIDE `<faulthandlers>`. Putting it straight under `<scope>` gives
///      "element 'catchall' is not allowed for content model '(annotation?,(alert|assign|...))'" —
///      a dump of every element that IS allowed, which never includes the one you want.
///   3. `<compensationhandlers>` must come BEFORE `<faulthandlers>`. Reversed, it is rejected the same
///      way, and the message again lists only activities.
///   4. `<scope>` takes exactly ONE activity. Several need a `<sequence>` wrapper.
///
/// AND THE CONSTRAINT THAT DECIDES HOW THIS FILE IS WRITTEN: `<compensate>` is legal ONLY as a direct
/// child of `<catchall>`. It is in `<catchall>`'s content model and NOT in `<sequence>`'s. Measured:
///
///     catchall containing just <compensate>                      COMPILES
///     catchall containing a <sequence> of <code>                  COMPILES
///     catchall containing a <sequence> that holds <compensate>    REJECTED
///
/// Since a catchall takes exactly one activity, **a catchall can compensate, or it can do several
/// things, but not both.** A handler that must undo work *and* propagate has to put the logging and
/// the `set status` inside the COMPENSATION HANDLER and leave `<compensate>` as the catchall's only
/// activity. That is not a style preference; it is the only shape the schema accepts.
Class Example.BP.ScopedOrder Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='Ens.StringContainer' response='Ens.StringContainer' height='2000' width='2000' >
<context>
<!-- initialexpression is OBJECTSCRIPT, not a literal. An unquoted word here is an undefined
     variable, and the process dies in %Construct before any activity runs. Measured:
     <UNDEFINED>%Construct+1^<class>.Context.1, with the BP header left at Status=8. -->
<property name='Note' type='%String' initialexpression='"none"' />
</context>
<sequence xend='200' yend='700' >
<scope xpos='200' ypos='250' xend='200' yend='600' >
<call name='Charge' target='BO.Failing' async='0' xpos='200' ypos='250' >
<request type='Ens.StringContainer' >
<assign property="callrequest.StringValue" value="request.StringValue" action="set" />
</request>
<response type='Ens.StringContainer' />
</call>
<compensationhandlers>
<!-- Reachable ONLY from a <compensate> that is a catchall's own single activity. Because of that,
     anything a compensating handler must also do (logging, setting status) belongs HERE. -->
<compensationhandler name='UndoCharge' xpos='500' ypos='250' xend='500' yend='350' >
<code name='Undo' xpos='500' ypos='250' >
<![CDATA[
 set ^Example.ScopedOrder("compensated", $increment(^Example.ScopedOrder("compensated"))) = context.Note
]]>
</code>
</compensationhandler>
</compensationhandlers>
<faulthandlers>
<catchall xpos='200' ypos='500' xend='200' yend='600' >
<!-- ONE activity, so a sequence. That rules out <compensate> in the same handler; see the header. -->
<sequence>
<code name='Record' xpos='200' ypos='250' >
<![CDATA[
 // %LastError is the fault the scope caught. Recording it is necessary and NOT sufficient.
 set context.Note = "caught: "_$system.Status.GetErrorText(..%Context.%LastError)
 set ^Example.ScopedOrder("caught", $increment(^Example.ScopedOrder("caught"))) = context.Note
]]>
</code>
<code name='Propagate' xpos='200' ypos='350' >
<![CDATA[
 // THE LINE THAT MAKES THE DIFFERENCE. Without it this process returns Status=9 Completed with
 // IsError=0 and the caller is told the order was charged. `status` is what the generated wrapper
 // returns -- §5.20.
 set status = $$$ERROR($$$GeneralError, "charge failed and was not retried: "_context.Note)
]]>
</code>
</sequence>
</catchall>
</faulthandlers>
</scope>
<assign name='Reply' property="response.StringValue" value="context.Note" action="set" xpos='200' ypos='700' />
</sequence>
</process>
}

}
