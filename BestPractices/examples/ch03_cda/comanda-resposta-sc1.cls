/// Rule: BestPractices_Interop_IRIS.md §3.2 "Comanda/Resposta inheritance trick for one-of-N subtypes payloads"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Concrete subclass for the SC1 variant of the abstract `Demo.MSG.Comanda` envelope
/// (`comanda-resposta-inheritance.cls`). Concrete because the DataTransform Wizard can
/// only propose mappings against a concrete type.
Class Demo.MSG.ComandaSC1 Extends Demo.MSG.Comanda
{

Property Content As Demo.MSG.SC1Content;

}
