/// Rule: BestPractices_Interop_IRIS.md §6.1.1 "wsp:PolicyReference (#6447) compile failure"
/// Validity: Still valid in current IRIS; SOAP wizard still emits this XData block
///           from WSDLs that contain WS-Policy.
/// Severity: High.
///
/// Symptom: The generated *HTTPPortConfig class fails to compile with
///   ERROR #6447: Elemento inesperado, wsp:PolicyReference, de namespace WS-Policy
///                en el bloque XData de %SOAP.Configuration
///
/// Three equivalent fixes; pick (a) when you want to keep the WSDL-generated XData block
/// for reference, (b) when you control the WSDL source, (c) when you don't.
///
/// Fix (a) - add Parameter REPORTANYERROR = 0 to the offending Config class.
/// That is the parameter kept below.
///
/// Fix (b) - strip the <wsp:PolicyReference> block from the WSDL BEFORE re-running
/// the SOAP Wizard. Example sed pre-processing:
///
///   sed -i.bak '/<wsp:PolicyReference/d' vendor-service.wsdl
///
/// Then re-import the cleaned WSDL.
///
/// Fix (c) - delete (or rename) the generated XData OnConfigurationCompile block.
/// That is what this file shows: the wizard-emitted
///   XData OnConfigurationCompile [ XMLNamespace = "http://www.w3.org/ns/wsdl/extensions" ]
/// block, whose only content was the <wsp:PolicyReference URI="#somePolicy"/> element
/// lifted from the vendor WSDL, has been removed. The class then compiles and the
/// WS-Policy assertion - unused at runtime by the Ensemble client - is simply gone.
///
/// What NOT to do: leave the XData block behind holding only an XML comment.
/// An XData body with no root element is not a document, so it fails earlier and
/// harder, with
///   ERROR #6301: SAX XML Parser Error: invalid document structure
/// which REPORTANYERROR cannot suppress - it suppresses policy errors, not a
/// malformed XData body.
Class Example.Vendor.WSC.SomeServiceHTTPPortConfig Extends %SOAP.Configuration
{

/// Suppresses the #6447 compile error raised by a WS-Policy assertion in the
/// wizard-generated XData block. Keep it even after applying fix (c): re-running
/// the SOAP Wizard re-emits the block, and this parameter is what lets the
/// re-imported class compile untouched.
/// The actual policy (TLS, signing) is configured separately in the BO.
Parameter REPORTANYERROR = 0;

}
