/// Rule: BestPractices_Interop_IRIS.md §3.1 "CDA-from-XSD class generation:
///       Persistent + no Relationships + OnDelete Cascade"
/// Validity: Still valid.
/// Severity: High.
///
/// Sibling of `ch03_cda/cda-from-xsd-persistence-pattern.cls`: the child class that
/// `Example.CDA.ClinicalDocument` references, shipped so that example compiles standalone
/// instead of failing with `#5373: Class 'Example.CDA.Component' does not exist`.
///
/// Deliberately minimal: this is a stand-in for whatever the XML Schema Wizard generates
/// for the CDA <component> element. The point of §3.1 is the three class-level settings
/// (Persistent, no Relationships, parent -> child cascade), not the property layout —
/// replace the properties with the generated ones and keep the settings.
///
/// The parent -> child cascade for this class lives in `Example.CDA.ClinicalDocument`
/// (`%OnDelete`), because the cascade always belongs on the REFERENCING class (CR-11).
///
/// No `Storage` block on purpose: IRIS generates default storage on first compile.
Class Example.CDA.Component Extends (%Persistent, %XML.Adaptor)
{

Parameter XMLNAME = "component";

Parameter XMLNAMESPACE = "urn:hl7-org:v3";

/// Placeholder for the generated attributes of the CDA <component> element.
Property TypeCode As %String(MAXLEN = 50);

/// The section payload, kept as a stream so this stand-in stays small and so large
/// sections do not hit the string limit.
Property SectionText As %Stream.GlobalCharacter;

}
