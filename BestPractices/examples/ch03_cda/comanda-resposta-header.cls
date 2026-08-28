/// Rule: BestPractices_Interop_IRIS.md §3.2 "Comanda/Resposta inheritance trick for one-of-N subtypes payloads"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Shared header carried by every `Demo.MSG.Comanda` variant. Shipped as a trivial
/// stand-in so `comanda-resposta-inheritance.cls` compiles standalone instead of failing
/// with `#5373: Class 'Demo.MSG.ComandaHeader' does not exist` — replace the properties
/// with whatever the XML Schema Wizard generated for your envelope header.
Class Demo.MSG.ComandaHeader Extends (%SerialObject, %XML.Adaptor)
{

Parameter XMLNAME = "Header";

Parameter XMLNAMESPACE = "urn:demo:envelope";

Property MessageId As %String(MAXLEN = 64);

Property SentAt As %String(MAXLEN = 32);

}
