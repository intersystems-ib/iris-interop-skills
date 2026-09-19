/// Rule: BestPractices_Interop_IRIS.md §5.6 "Custom BPL: context variables, a sync call, and the code-block idiom"
/// Validity: Still valid.
/// Severity: Medium.
///
/// The canonical custom-BPL shape: `Ens.BusinessProcessBPL` + an `XData BPL` block.
///
/// Reach for a custom BPL only for multi-step orchestration — sync sub-calls, conditional
/// branches, fan-out/aggregation, error compensation. For plain "route this message onwards",
/// use a MessageRouter + routing rule instead (`routing-rule-fanout.cls`); a hand-written
/// `Ens.BusinessProcess.OnRequest` doing the routing is conformance CR-1.
///
/// CONTEXT VARIABLES are the point of the `<context>` block: they persist for the BPL's whole
/// lifetime and survive a `<call>`, so they are where state that crosses an async boundary
/// lives. Locals inside a `<code>` activity do not survive the call.
///
/// SOURCE-OF-TRUTH TRAP: the BPL editor writes straight into the namespace, and on some IRIS
/// versions it silently strips `XData BPL` on first open — the class then reports
/// "Missing BPL Data". Recovery is a copy-paste back into this block, which only works if the
/// class is on disk as text. A Portal edit also bypasses the PreToolUse source-of-truth gate,
/// so after any editor session, `iris_doc(mode=get)` the class and write it back to `src/`.
Class Example.BP.OrderProcess Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='Example.MSG.AcceptOrderReq' response='Example.MSG.AcceptOrderRsp' height='2000' width='2000'>
<context>
<property name='VendorRef' type='%String' initialexpression=''/>
</context>
<sequence>
<code name='Capture reference'>
<![CDATA[ set context.VendorRef = request.OrderId ]]>
</code>
<call name='SendToVendor' target='BO.Vendor' async='0'>
<request type='Example.MSG.VendorOrder'>
<assign property='callrequest.VendorRef' value='context.VendorRef' action='set'/>
<assign property='callrequest.Priority' value='"NORMAL"' action='set'/>
</request>
<response type='Ens.Response'/>
</call>
<assign name='Accept' property='response.Accepted' value='1' action='set'/>
</sequence>
</process>
}

}
