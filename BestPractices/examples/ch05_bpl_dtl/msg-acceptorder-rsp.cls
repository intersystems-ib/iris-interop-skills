/// Rule: BestPractices_Interop_IRIS.md §5.1 "BS that exposes a SOAP service: how to wire it"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Outbound message of the §5.1 SOAP Business Service (`ch05_bpl_dtl/soap-business-service.cls`).
/// Shipped so that example compiles standalone instead of failing with
/// `#5373: Class 'Example.MSG.AcceptOrderRsp' does not exist`.
///
/// `<Pkg>.MSG.<Name>Rsp` per the naming convention; Ens.Response already brings
/// %Persistent + %XML.Adaptor.
/// No `Storage` block: IRIS generates default storage on first compile.
Class Example.MSG.AcceptOrderRsp Extends Ens.Response
{

Parameter XMLNAME = "AcceptOrderRsp";

Property Accepted As %Boolean [ InitialExpression = 0 ];

Property Reason As %String(MAXLEN = 256);

}
