/// Rule: BestPractices_Interop_IRIS.md §2.13 "Headless HL7 schema bootstrap — a dropped override falls back to the base, it does not linger"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed end to end.
/// Severity: High (a category that resolves to the base's definitions looks correctly imported).
///
/// Pattern: the headless custom-HL7-category bootstrap, with the category grammar carried as `XData`
/// so it travels with the class and is source-controlled rather than living in a loose `.xml`.
///
/// WHAT WAS UNGATED BEFORE THIS FILE. `hl7-schemas` has carried `ImportSchema` and `RemoveSchema` as
/// **bare `ClassMethod`s in a fence with no host class** — two of the shapes tier 3 cannot compile —
/// so neither had ever been through a compiler, and the fence hardcoded
/// `C:\path\to\src\Hospital\HL7\PharmacySchema.xml`, which C6 bans. Both are here now, with the path
/// as a parameter.
///
/// THE ONLY HEADLESS PATH, confirmed: `EnsLib.HL7.SchemaXML.Import(pFile, *pCategoryImported,
/// pForceCategory = "")` and `.Export(pCategory, pFile)`, both ClassMethods, plus an unmentioned
/// `.GetImportCategory(pFilename)` which reads the category name out of a file without importing it.
/// `Import` takes a FILE, which is why an `XData`-carried grammar has to be written out first.
/// The plausible neighbour `EnsLib.HL7.Util.SchemaDocument` **does not exist** — `hl7-schemas` is
/// right to name that as an anti-pattern.
///
/// THERE IS NO PLATFORM `RemoveSchema`. Searching the whole dictionary for that name returns nothing.
/// Removal is the two-global kill below, which is what `hl7-schemas`' own companion does; this file
/// is that companion, compiled.
///
/// AND THE CLAIM THAT DID NOT REPRODUCE, which changes what the guard is for. `hl7-schemas` says a
/// re-import "overwrites but does not clean: a segment you renamed or removed lingers in the
/// category". Measured three ways — it cleans:
///
///     import a category defining ZAL                       ZAL -> 'Cat:ZAL'
///     re-import the SAME category with ZAL renamed ZAL2,   ZAL -> (empty)      <- gone, not lingering
///       with NO removal in between                         ZAL2 -> 'Cat:ZAL2'
///     drop a MessageType override and re-import            ^EnsHL7.Schema(cat,"MT","ADT_A04") absent
///
/// So nothing lingers. **The silent failure is real but it is inheritance, not staleness.** A category
/// declared `base='2.5'` inherits, so when an override is dropped, resolution does not fail — it
/// falls through to the base and returns a plausible different answer:
///
///     with the ADT_A04 override:     ResolveSchemaTypeToDocType(cat,"ADT_A04") -> 'Cat:ADT_A04'
///     after dropping it:             ResolveSchemaTypeToDocType(cat,"ADT_A04") -> '2.5:ADT_A01'
///
/// Not empty. Not an error. A DTL bound to `Cat:ADT_A04` now gets the BASE's structure, and the
/// category still "looks re-imported". Whereas a dropped Z-segment — which the base has no equivalent
/// of — resolves to `(empty)`, and is therefore the detectable case. The rule that falls out:
/// **after a re-import, verify the things you OVERRODE, not just the things you added.** The additions
/// fail loudly; the overrides fail quietly.
///
/// THE KILL PAIR IS STILL WORTH KEEPING, for a different reason than the skill gives: it makes the
/// import deterministic. A re-import over an existing category is an overwrite whose outcome depends
/// on what was there before; killing first means the resulting category is exactly the XData and
/// nothing else. `ImportFromXData` below does that, and reports which path it took.
Class Example.UTL.Hl7SchemaBootstrap Extends %RegisteredObject
{

/// The category this class owns. It KILLS by this name, so it must own it outright.
Parameter CATEGORY = "Example_2.5";

/// Where the XData is written on its way to `Import`. A PARAMETER, not a hardcoded path: the fence
/// this replaces carried `C:\path\to\src\...`, which C6 bans and which is wrong on every Linux host.
Parameter WORKDIR = "/tmp/";

/// The category grammar. Carried here so it is source-controlled with the code that imports it, and
/// so a review of this file sees the schema rather than a filename.
///
/// Shapes that are easy to get wrong, all per `hl7-schemas`: the root is `<Category>`, not `<Schema>`;
/// fields are `<SegmentSubStructure piece='N'>`, not `<Field>`; a MessageStructure definition is a
/// single tilde-separated string, not nested elements; and every segment inherited from the base must
/// carry the literal `base:` prefix, because overriding a structure re-resolves every segment in it
/// against THIS category.
///
/// `base:` IS THE PREFIX, NOT THE VERSION. A `2.5:` prefix names a category and early-binds to it:
/// measured on 2026.1, the same definition imported under `base="2.5.1"` still stores `2.5:PID` with
/// `sc=OK`, and a 2.5.1 field name then fails at run time with
/// `PropertyPath 'producersreference' is invalid`. `base:` is resolved against the `base` attribute of
/// this `<Category>`, so it keeps pointing at the right parent if that attribute is changed.
///
/// AND READING IT BACK SHOWS `2.5:` AGAIN, which is not a sign the XML was ignored. The importer
/// RESOLVES `base:` on the way in, so `^EnsHL7.Schema` holds the resolved names — which is exactly
/// what `tdd-hl7-schema-registration.cls` asserts (`PID -> '2.5:PID'`). `EnsLib.HL7.SchemaXML.Export`
/// writes `base:` back out. Both directions measured.
XData Category
{
<?xml version="1.0" encoding="UTF-8"?>
<Category name='Example_2.5' base='2.5' description='Example category: ADT_A01 with a ZAL allergy Z-segment'>
  <SegmentStructure name='ZAL' description='Allergy identified (Z-segment)'>
    <SegmentSubStructure piece='1' description='Allergy Id' datatype='ST' max_length='10' required='O' ifrepeating='0'/>
    <SegmentSubStructure piece='2' description='Allergy Text' datatype='ST' max_length='60' required='O' ifrepeating='0'/>
  </SegmentStructure>
  <MessageStructure name='ADT_A01' definition='base:MSH~[~ZAL~]~base:EVN~base:PID~[~base:PV1~]'/>
  <MessageType name='ADT_A01' structure='ADT_A01'/>
</Category>
}

/// Write the XData out and import it. Kills the category first so the result is exactly the XData.
/// Invoke via: SELECT Example_UTL.Hl7SchemaBootstrap_ImportFromXData()
ClassMethod ImportFromXData() As %String [ SqlProc ]
{
    Set tCat = ..#CATEGORY
    Set tFile = ..#WORKDIR _ "example_hl7_category.xml"

    Set tExisted = ..CategoryExists(tCat)
    If tExisted {
        Do ..RemoveSchema(tCat)
    }

    Set tSC = ..WriteXDataToFile(tFile)
    If $$$ISERR(tSC) {
        Return "FAILED writing " _ tFile _ ": " _ $system.Status.GetErrorText(tSC)
    }

    Set tImported = ""
    Set tSC = ##class(EnsLib.HL7.SchemaXML).Import(tFile, .tImported)
    Do ##class(%File).Delete(tFile)
    If $$$ISERR(tSC) {
        Return "FAILED importing: " _ $system.Status.GetErrorText(tSC)
    }

    // ESTABLISH IT, do not infer it. Import returning $$$OK is its word for what it attempted.
    //
    // HONEST NOTE: this branch is DEFENSIVE AND UNFALSIFIED. Removing it leaves the companion test
    // green, because no input was found on which Import returns $$$OK without registering the
    // category. Two lines against a silent failure is worth keeping, but it is NOT covered, and this
    // comment is here so a clean suite is not read as covering it. The `tImported` check below IS
    // covered -- a category-name mismatch between the XData and CATEGORY is reachable.
    If '..CategoryExists(tCat) {
        Return "FAILED: Import returned OK but ^EnsHL7.Schema(""" _ tCat _ """) is not there"
    }
    If $Get(tImported) '= tCat {
        Return "FAILED: imported category is '" _ $Get(tImported) _ "', not '" _ tCat _
               "' -- the XData's Category name attribute and CATEGORY disagree"
    }

    Return "OK: " _ $Select(tExisted: "re-imported", 1: "imported") _ " '" _ tCat _ "'"
}

/// Is the category registered?
ClassMethod CategoryExists(pCategory As %String) As %Boolean [ SqlProc ]
{
    Return ($Data(^EnsHL7.Schema(pCategory)) '= 0)
}

/// Remove a category. There is no platform `RemoveSchema`; this is the two-global kill, and both
/// globals matter -- `^EnsHL7.Description` holds the human-readable descriptions and a category left
/// half-removed reads oddly in the Schema Editor.
ClassMethod RemoveSchema(pCategory As %String) As %String [ SqlProc ]
{
    If pCategory = "" {
        Return "FAILED: category required"
    }
    If '..CategoryExists(pCategory) {
        Return "nothing to remove: '" _ pCategory _ "' is not registered"
    }
    Kill ^EnsHL7.Schema(pCategory)
    Kill ^EnsHL7.Description(pCategory)
    Return $Select(..CategoryExists(pCategory): "FAILED: still registered after the kill",
                   1: "OK: removed '" _ pCategory _ "'")
}

/// Dump an existing category to a file, which is how you discover the canonical format for a shape
/// this XData does not cover. Export any BUILT-IN category and read it.
ClassMethod ExportCategory(pCategory As %String, pFile As %String) As %String [ SqlProc ]
{
    If pFile = "" {
        Return "FAILED: a target file is required"
    }
    Set tSC = ##class(EnsLib.HL7.SchemaXML).Export(pCategory, pFile)
    If $$$ISERR(tSC) {
        Return "FAILED: " _ $system.Status.GetErrorText(tSC)
    }
    Return "OK: exported '" _ pCategory _ "' to " _ pFile
}

/// The XData, written to disk. Separated out because `Import` takes a file and nothing else.
ClassMethod WriteXDataToFile(pFile As %String) As %Status [ Private ]
{
    Set tX = ##class(%Dictionary.XDataDefinition).%OpenId($classname() _ "||Category")
    If '$IsObject(tX) {
        Return $$$ERROR($$$GeneralError, "cannot open XData Category on " _ $classname())
    }
    Set tStream = ##class(%Stream.FileCharacter).%New()
    Set tStream.Filename = pFile
    Do tX.Data.Rewind()
    While 'tX.Data.AtEnd {
        Do tStream.WriteLine(tX.Data.ReadLine())
    }
    Return tStream.%Save()
}

}
