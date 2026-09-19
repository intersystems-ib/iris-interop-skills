/// Rule: BestPractices_Interop_IRIS.md §3.1 "CDA-from-XSD class generation:
///       Persistent + no Relationships + OnDelete Cascade"
/// Validity: Still valid.
/// Severity: High.
///
/// When importing CDA into ObjectScript classes from the XSD via the XML Schema Wizard,
/// the ONLY working combination is:
///   - Persistent (so messages persist with Ensemble messages)
///   - NO Relationships (Relationships=1 causes serialisation to XML to take ~60s per CDA)
///   - A parent -> child delete cascade (so purging an Ensemble message also purges the
///     CDA child rows). How that cascade is actually written: see below.
///
/// Tested alternatives that FAIL:
///   - Serializable classes: cyclic-reference compile error (Component contains Component).
///   - Persistent with Relationships: slow XML serialisation as above.
///
/// How the cascade is really written (CR-11, skills/conformance-review):
///   `OnDelete` is a keyword of %Dictionary.ForeignKeyDefinition — it is NOT an Index
///   keyword, so `Index ... [ OnDelete = cascade ]` declares nothing and deletes nothing.
///   And even as a genuine ForeignKey the cascade runs child -> parent (it removes the
///   REFERENCING row when the referenced row goes), which is the opposite of what is
///   needed here. The canonical parent -> child cascade is a `%OnDelete` callback (or a
///   `Trigger [ Event = DELETE ]`) on the REFERENCING class — this one. See %OnDelete
///   at the bottom of the class.
///
/// No `Storage` block on purpose: IRIS generates the default storage definition on first
/// compile. Hand-writing one pins invented global names onto the extent and is refused on
/// write (`STORAGE_STRIP_BLOCKED`); see skills/messages §"persistent message classes".
///
/// This file is a TEMPLATE - replace the property layout with whatever the XML Schema
/// Wizard generated for your CDA template, then enforce the three settings above.
/// Sibling shipped alongside: `ch03_cda/cda-from-xsd-component.cls` (Example.CDA.Component).
Class Example.CDA.ClinicalDocument Extends (%Persistent, %XML.Adaptor)
{

Parameter XMLNAME = "ClinicalDocument";

Parameter XMLNAMESPACE = "urn:hl7-org:v3";

/// CDA Component as a plain object reference. CRITICAL: NOT a Relationship.
Property Component As Example.CDA.Component;

/// Repeated Component children: use array of references, NOT a Relationships block.
Property Components As array Of Example.CDA.Component;

/// Lookup index on the child reference. Note there is deliberately NO `OnDelete` keyword
/// here — it does not exist on an Index. The cascade lives in %OnDelete below.
Index ComponentIdx On Component;

/// Parent -> child delete cascade. Fires on every delete of this document, including the
/// one Ens.Util.Tasks.Purge performs when it purges the Ensemble message that carries it,
/// so the CDA child rows never accumulate as orphans.
ClassMethod %OnDelete(oid As %ObjectIdentity) As %Status [ Private, ServerOnly = 1 ]
{
    #DIM tSC as %Status = $$$OK
    #DIM errObj as %Exception.AbstractException
    #DIM tDoc as Example.CDA.ClinicalDocument
    #DIM tChild as Example.CDA.Component
    #DIM tKey as %String
    try {
        set tDoc = ##class(Example.CDA.ClinicalDocument).%Open(oid, 0)
        if $IsObject(tDoc) {
            if $IsObject(tDoc.Component) {
                $$$ThrowOnError(##class(Example.CDA.Component).%DeleteId(tDoc.Component.%Id()))
            }
            set tKey = ""
            for {
                set tChild = tDoc.Components.GetNext(.tKey)
                if tKey = "" { quit }
                if $IsObject(tChild) {
                    $$$ThrowOnError(##class(Example.CDA.Component).%DeleteId(tChild.%Id()))
                }
            }
        }
    } catch (errObj) {
        set tSC = errObj.AsStatus()
    }
    quit tSC
}

}
