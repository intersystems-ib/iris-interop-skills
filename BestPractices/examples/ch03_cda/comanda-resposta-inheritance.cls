/// Rule: BestPractices_Interop_IRIS.md §3.2 "Comanda/Resposta inheritance trick for one-of-N subtypes payloads"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Problem: the schema defines ONE envelope type whose actual content is one of N subclasses.
/// In this case: a `Comanda` envelope with `SC1` or `SC2` content variants.
///
/// Pattern: make the generated wrapper class ABSTRACT and create concrete subclasses
/// (ComandaSC1, ComandaSC2) that the BS instantiates based on inspection of the inbound payload.
/// The DataTransform Wizard then sees concrete types and proposes correct mappings.
///
/// One class per .cls file — the pattern is spread over seven files in this directory,
/// all citing §3.2:
///   - `comanda-resposta-inheritance.cls`  Demo.MSG.Comanda        (this file, abstract envelope)
///   - `comanda-resposta-sc1.cls`          Demo.MSG.ComandaSC1     (concrete variant)
///   - `comanda-resposta-sc2.cls`          Demo.MSG.ComandaSC2     (concrete variant)
///   - `comanda-resposta-header.cls`       Demo.MSG.ComandaHeader  (shared header payload)
///   - `comanda-resposta-sc1-content.cls`  Demo.MSG.SC1Content     (SC1 payload)
///   - `comanda-resposta-sc2-content.cls`  Demo.MSG.SC2Content     (SC2 payload)
///   - `comanda-receiver-service.cls`      Demo.BS.ComandaReceiver (picks the variant)
///
/// The wrapper envelope from the XSD - left ABSTRACT so DataTransforms target the subclasses.
Class Demo.MSG.Comanda Extends (%SerialObject, %XML.Adaptor) [ Abstract ]
{

Parameter XMLNAME = "Comanda";

Parameter XMLNAMESPACE = "urn:demo:envelope";

/// Concrete subclasses populate this with their typed payload.
Property Header As Demo.MSG.ComandaHeader;

}
