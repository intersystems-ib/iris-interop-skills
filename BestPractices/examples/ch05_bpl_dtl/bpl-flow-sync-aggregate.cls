/// Rule: BestPractices_Interop_IRIS.md §5.19 "`<flow>`/`<sync>` fan-out: an async `<call>` that no `<sync>` awaits completes the process green"
/// Validity: Verified against IRIS for Health 2026.1 — compiled.
/// Severity: High (the process completes successfully with responses unprocessed).
///
/// Pattern: the BPL fan-out/aggregate template. `bpl` recommends this shape for parallel work and
/// then says, correctly, **"do not generate a wall of `<call>`/`<sync>`/`<reply>` BPL XML from a
/// vague description — it'll be wrong in ways that are subtle to debug."** Until this file there was
/// no template to copy instead, so the only options were improvising the thing the skill forbids or
/// opening the graphical editor (which on some IRIS versions strips `XData BPL` on first open — see
/// `bpl-order-process.cls`).
///
/// THE THREE ELEMENTS, with the attribute names measured off `Ens.BPL.Flow` / `Ens.BPL.Sync` /
/// `Ens.BPL.Call` rather than guessed:
///
///   <flow>              container; each child <sequence> is one parallel branch
///   <call async='1'>    starts a branch without waiting. `Ens.BPL.Call` carries Async, Name, Target
///   <sync calls='...'>  waits. `Ens.BPL.Sync` carries Calls, Type (default "all"), Timeout,
///                       AllowResync
///
/// `calls` is a comma-separated list of `<call>` NAMES — not targets, not branch names. That is the
/// join, and it is made by string matching, so a typo in it is a silent miss rather than an error.
///
/// THE SILENT DEFECT, measured: a `<sync>` that lists only ONE of two async calls **compiles clean**.
/// Both of these compiled without a warning on 2026.1:
///
///     <sync calls='AskVendor,AskLab'/>   correct
///     <sync calls='AskVendor'/>          AskLab is never awaited -- COMPILES CLEAN
///
/// The process then reaches its end activity while AskLab is still outstanding, and completes. The
/// Visual Trace shows a completed process; the response AskLab would have contributed is simply not
/// in the aggregate. Nothing is logged, because nothing went wrong — the process did exactly what
/// its definition said.
///
/// Omitting the `<sync>` entirely has the same effect and is equally clean. There is no compile-time
/// check that every async call is awaited, which is why `utl-bpl-sync-audit.cls` in this directory
/// exists: it reads the XData back and reports async calls no `<sync>` covers.
///
/// CONTEXT, not locals. The three `<context>` properties below survive the calls; a local set inside
/// a `<code>` activity does not, because the process is saved and resumed around each async
/// boundary. Aggregation therefore reads and writes `context.*`, which is the detail that decides
/// where the aggregation step can live at all.
///
/// WHAT THIS FILE DOES NOT PROVE. It is compiled, not executed: driving it would need a started
/// production with two live targets and a response from each. So the fan-out SHAPE is gated and the
/// runtime aggregation is not. The audit class and its test are the executable half.
Class Example.BP.FlowSyncAggregate Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='Example.MSG.AcceptOrderReq' response='Example.MSG.AcceptOrderRsp' height='2000' width='2000'>
<context>
<property name='VendorAccepted' type='%Boolean' initialexpression='0'/>
<property name='LabAccepted' type='%Boolean' initialexpression='0'/>
<property name='Replies' type='%Integer' initialexpression='0'/>
</context>
<sequence>
<flow name='Ask both in parallel'>
  <sequence name='Vendor branch'>
    <call name='AskVendor' target='BO.Vendor' async='1'>
      <request type='Example.MSG.VendorOrder'>
        <assign property='callrequest.VendorRef' value='request.OrderId' action='set'/>
        <assign property='callrequest.Priority' value='"NORMAL"' action='set'/>
      </request>
      <response type='Ens.Response'/>
    </call>
  </sequence>
  <sequence name='Lab branch'>
    <call name='AskLab' target='BO.Vendor' async='1'>
      <request type='Example.MSG.VendorOrder'>
        <assign property='callrequest.VendorRef' value='request.OrderId' action='set'/>
        <assign property='callrequest.Priority' value='"STAT"' action='set'/>
      </request>
      <response type='Ens.Response'/>
    </call>
  </sequence>
</flow>
<sync name='Await both' calls='AskVendor,AskLab' type='all' timeout='60'/>
<code name='Aggregate'>
<![CDATA[
 set context.Replies = 2
 set response.Accepted = (context.VendorAccepted || context.LabAccepted)
]]>
</code>
</sequence>
</process>
}

}
