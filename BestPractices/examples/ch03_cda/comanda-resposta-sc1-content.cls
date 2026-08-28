/// Rule: BestPractices_Interop_IRIS.md §3.2 "Comanda/Resposta inheritance trick for one-of-N subtypes payloads"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Payload of the SC1 variant (`Demo.MSG.ComandaSC1`). Trivial stand-in shipped so the
/// §3.2 example set compiles standalone — replace with the wizard-generated content type.
Class Demo.MSG.SC1Content Extends (%SerialObject, %XML.Adaptor)
{

Parameter XMLNAME = "SC1";

Parameter XMLNAMESPACE = "urn:demo:envelope";

Property OrderCode As %String(MAXLEN = 32);

}
