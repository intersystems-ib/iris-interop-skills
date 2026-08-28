/// Rule: BestPractices_Interop_IRIS.md §3.4 "SOAP carrying CDA / HL7 as MessageBody — the canonical pattern"
/// Validity: Still valid.
/// Severity: High.
///
/// When a third-party WSDL specifies a custom `acceptMessage(message)` with the HL7 ER7
/// text in a string field (NOT the standard Ensemble EnsLib.HL7.Util.SOAPClient shape):
///
///   - Change the parameter type from %String -> %Stream.GlobalCharacter
///     (HL7 messages can exceed string limits)
///   - Copy EnsLib.HL7.Operation.SOAPOperation as the BO base
///   - Override Adapter.WebServiceClientClass to point to the custom proxy
///   - Adapt Adapter.InvokeMethod("acceptMessage", ...) (default would call Send)
///
/// The same pattern applies for SOAP-carrying-CDA to a regional document repository
/// (e.g. <publicarDocument> with a CCD <ClinicalDocument xmlns="urn:hl7-org:v3">
/// directly in the SOAP Body parameter).
///
/// One class per .cls file — the BO half of this pattern lives in
/// `ch03_cda/soap-messagebody-hl7-operation.cls` (`Demo.Vendor.BO.AcceptMessage`),
/// which also cites §3.4.
///
/// Wizard-generated SOAP proxy, patched to accept HL7 as a Stream.
Class Demo.Vendor.WSC.AcceptMessageProxy Extends %SOAP.WebClient
{

Parameter NAMESPACE = "http://vendor.example/ws";

Parameter SERVICENAME = "AcceptMessageWS";

/// PATCHED: was Parameter message As %String; HL7 messages can exceed string limits.
Method acceptMessage(message As %Stream.GlobalCharacter) As %String [ WebMethod ]
{
    quit ..WebMethod("acceptMessage").Invoke($this, "acceptMessage", .message)
}

}
