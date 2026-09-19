/// Rule: BestPractices_Interop_IRIS.md §5.3 "XML projection of message classes — three settings to know"
/// Validity: Still valid (verify in IRIS 2024.x — long-standing quirks).
/// Severity: Medium.
///
/// The three settings, exercised:
///
/// 1. XMLIGNORENULL = 1 (class-level, NOT property-level).
///    Forces empty-string properties to appear in the XML output as empty elements (<NOM/>).
///    Caveat: for `list of <T>` collections where every item is empty, the list element
///    is omitted entirely — there is no clean way to force its presence except manual XML
///    manipulation.
///
/// 2. CONTENT = "STRING" vs CONTENT = "ESCAPE" on %Stream.GlobalCharacter properties.
///    - STRING wraps in <![CDATA[...]]>. Pick when the payload is XML you don't want re-escaped
///      (e.g. a CDA going through a SOAP envelope).
///    - ESCAPE XML-escapes the text. Pick for free-text fields.
///
/// 3. OUTPUTTYPEATTRIBUTE = 0 on the SOAP proxy class — suppresses xsi:type on every element.
///    See examples/ch06_adapters/soap-xsi-type-suppress.cls for the SOAP-client variant.
Class Example.MSG.OrderReq Extends (%SerialObject, %XML.Adaptor)
{

/// Empty-string properties emit as <NOM/> rather than disappearing.
Parameter XMLIGNORENULL = 1;

Property NOM As %String(MAXLEN = 100);

/// CDATA-wrapped payload: don't re-escape XML coming from a CDA generator.
Property CDABody As %Stream.GlobalCharacter(CONTENT = "STRING");

/// Escape free-text properly (e.g. clinician notes).
Property Notes As %Stream.GlobalCharacter(CONTENT = "ESCAPE");

}
