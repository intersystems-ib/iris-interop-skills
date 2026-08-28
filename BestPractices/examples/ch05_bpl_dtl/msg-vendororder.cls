/// Rule: BestPractices_Interop_IRIS.md §5.7 "DTL: declare the transform, don't write it imperatively"
/// Validity: Still valid.
/// Severity: High.
///
/// Sibling: the DTL target message for `dtl-order-to-vendor.cls`, and the request type the
/// `<call>` in `bpl-order-process.cls` builds. Kept in its own file so every example class
/// is one loadable unit.
Class Example.MSG.VendorOrder Extends Ens.Request
{

Parameter XMLNAME = "VendorOrder";

Property VendorRef As %String(MAXLEN = 64);

Property Priority As %String(MAXLEN = 8) [ InitialExpression = "NORMAL" ];

Property Note As %String(MAXLEN = 256);

}
