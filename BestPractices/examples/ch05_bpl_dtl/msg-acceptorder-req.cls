/// Rule: BestPractices_Interop_IRIS.md §5.1 "BS that exposes a SOAP service: how to wire it"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Inbound message of the §5.1 SOAP Business Service (`ch05_bpl_dtl/soap-business-service.cls`).
/// Shipped so that example compiles standalone instead of failing with
/// `#5373: Class 'Example.MSG.AcceptOrderReq' does not exist`.
///
/// `<Pkg>.MSG.<Name>Req` per the naming convention; Ens.Request already brings
/// %Persistent + %XML.Adaptor, which is what lets it appear in a WSDL as a SOAP parameter.
/// No `Storage` block: IRIS generates default storage on first compile.
Class Example.MSG.AcceptOrderReq Extends Ens.Request
{

Parameter XMLNAME = "AcceptOrderReq";

Property OrderId As %String(MAXLEN = 64);

Property PatientId As %String(MAXLEN = 64);

}
