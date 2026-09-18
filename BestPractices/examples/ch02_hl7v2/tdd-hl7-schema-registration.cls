/// Rule: BestPractices_Interop_IRIS.md §2.13 "Headless HL7 schema bootstrap — a dropped override falls back to the base, it does not linger"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, importing and removing a real category.
/// Severity: High (the failure it isolates returns a plausible DocType from the wrong category).
///
/// Pattern: the oracle for `schema-bootstrap-sqlproc.cls`. It imports and removes a real HL7 category,
/// which makes it stateful — see the cleanup note.
///
/// THE SUPERCLASS IS THE FIRST THING THIS FILE FIXES. `hl7-schemas` tells the reader to paste its test
/// into `%UnitTest.TestCase`. The plugin's own non-negotiable rule is `%UnitTest.TestProduction` for
/// ANY interop test — it is what provides `GetEventLog`, `SendRequest` and the `PRODUCTION` parameter
/// — and a fence that says otherwise sends the reader into a class that cannot do the interop half.
/// This class extends `TestProduction`, which is also why it must declare `PRODUCTION` at all.
///
/// THE TWO RESOLUTION ARITIES, measured — and the second parameter of the first one is real:
///
///     ResolveSegNameToStructure(pSchemaCategory, pDummy As %String = "", pSegName, *pStatus)
///     ResolveSchemaTypeToDocType(pSchemaCategory, pTypeName, *pStatus, pDocTypeResolution = "")
///
/// `pDummy` is its actual name. The row's `(cat, "", "ZAL", .sc)` shape is therefore right, and anyone
/// who assumes a 3-argument call puts the segment name where the dummy goes and gets nothing back.
///
/// WHAT RESOLUTION ACTUALLY RETURNS, on the shipped `Example_2.5` category (base `2.5`):
///
///     ResolveSegNameToStructure   ZAL      -> 'Example_2.5:ZAL'    the override
///                                 PID      -> '2.5:PID'            inherited, BASE-prefixed
///                                 ZZZ      -> (empty)              unknown
///     ResolveSchemaTypeToDocType  ADT_A01  -> 'Example_2.5:ADT_A01' the override
///                                 ADT_A04  -> '2.5:ADT_A01'        NOT overridden: falls to the base
///                                 ORU_R01  -> '2.5:ORU_R01'        inherited
///                                 NOSUCH   -> (empty)
///
/// THE LINE THAT MATTERS IS `ADT_A04 -> '2.5:ADT_A01'`. It is not empty and it is not an error. A
/// category that inherits will answer for a type it does not define, with the BASE's DocType — so a
/// DTL bound to `Example_2.5:ADT_A04` silently gets base semantics, and the only signal is that the
/// returned prefix is the base's name rather than yours. `TestPrefixTellsYouWhichCategoryAnswered`
/// is the assertion that makes that readable, because the prefix is the whole diagnosis.
///
/// AND THE CLAIM THAT DID NOT REPRODUCE. `hl7-schemas` says a re-import "overwrites but does not
/// clean: a segment you renamed or removed lingers". Measured: it cleans. Re-importing the same
/// category with `ZAL` renamed leaves `ZAL` resolving to **(empty)**, and the dropped MessageType's
/// globals are gone. `TestReimportCleansTheOldSegment` pins that, so the skill's caution is not
/// carried forward as fact — what IS true is the inheritance fallback above, which is a different
/// mechanism with the same symptom.
///
/// CLEANUP. This suite imports `Example_2.5` and leaves it imported, because the bootstrap's own
/// verdicts are asserted against a registered category. `OnAfterAllTests` re-imports rather than
/// removing, so the namespace ends in the state the bank's other artefacts expect.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                    PASSED 7/7
///     the verdict never says "re-imported"           TestImportRegistersTheCategory FAILS
///     RemoveSchema kills only ^EnsHL7.Description    TestImportRegistersTheCategory +
///                                                   TestRemoveIsIdempotentAndHonest FAIL
///     "nothing to remove" becomes "OK: removed"      TestRemoveIsIdempotentAndHonest FAILS
///     the empty-category guard removed               TestEmptyCategoryIsRefused FAILS
///
/// The two-global mutation reddening two tests is the point of killing both: `CategoryExists` reads
/// `^EnsHL7.Schema`, so dropping that kill makes the removal silently ineffective.
///
/// ONE MUTATION PASSED, and it is annotated at the branch rather than papered over: removing the
/// bootstrap's "did the category actually register" check leaves this suite green, because no input
/// was found on which `Import` returns `$$$OK` without registering. It is kept as defence and it is
/// NOT covered.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.Hl7SchemaRegistration", namespace="<NS>")
Class Example.Tests.Hl7SchemaRegistration Extends %UnitTest.TestProduction
{

/// Compile-time mandatory on TestProduction -- and the reason the fence's `%UnitTest.TestCase`
/// advice is wrong for an interop test.
Parameter PRODUCTION = "Example.Productions.CensoIntake";

Parameter CATEGORY = "Example_2.5";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Leave the category registered: the bootstrap's verdicts are asserted against it, and other
/// artefacts may reference the DocType.
Method OnAfterAllTests() As %Status
{
    Do ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()
    Quit $$$OK
}

ClassMethod Seg(pCategory As %String, pSeg As %String) As %String [ Private ]
{
    Set tSC = 1
    Quit ##class(EnsLib.HL7.Schema).ResolveSegNameToStructure(pCategory, "", pSeg, .tSC)
}

ClassMethod Doc(pCategory As %String, pType As %String) As %String [ Private ]
{
    Set tSC = 1
    Quit ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType(pCategory, pType, .tSC)
}

/// The import registers the category, and the verdict distinguishes a first import from a re-import.
Method TestImportRegistersTheCategory()
{
    Do ##class(Example.UTL.Hl7SchemaBootstrap).RemoveSchema(..#CATEGORY)
    Do $$$AssertEquals(##class(Example.UTL.Hl7SchemaBootstrap).CategoryExists(..#CATEGORY), 0, "control: not registered to begin with")

    Set tFirst = ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()
    Do $$$AssertEquals($Find(tFirst, "OK:") > 0, 1, "the import must succeed: " _ tFirst)
    Do $$$AssertEquals($Find(tFirst, "imported") > 0, 1, "and say what it did")
    Do $$$AssertEquals(##class(Example.UTL.Hl7SchemaBootstrap).CategoryExists(..#CATEGORY), 1, "and the category must actually be registered")

    Set tAgain = ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()
    Do $$$AssertEquals($Find(tAgain, "re-imported") > 0, 1, "a second run must say RE-imported, so the two paths are distinguishable: " _ tAgain)
}

/// The override resolves, and the arity is the four-argument one with the dummy second.
Method TestOverrideResolves()
{
    Do ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()

    Do $$$AssertEquals(..Seg(..#CATEGORY, "ZAL"), "Example_2.5:ZAL", "the Z-segment resolves inside the category")
    Do $$$AssertEquals(..Doc(..#CATEGORY, "ADT_A01"), "Example_2.5:ADT_A01", "and the overridden message type resolves to OUR DocType")
}

/// THE PREFIX IS THE DIAGNOSIS. An inherited answer carries the BASE's name, not yours.
Method TestPrefixTellsYouWhichCategoryAnswered()
{
    Do ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()

    // Inherited segment: answered by the base, and says so.
    Do $$$AssertEquals(..Seg(..#CATEGORY, "PID"), "2.5:PID", "an inherited segment comes back BASE-prefixed")

    // The dangerous one: a type we do NOT override still resolves -- to the base's DocType.
    Set tA04 = ..Doc(..#CATEGORY, "ADT_A04")
    Do $$$AssertNotEquals(tA04, "", "a non-overridden type does NOT resolve to empty -- it falls through to the base")
    Do $$$AssertEquals($Piece(tA04, ":", 1), "2.5", "and the prefix is the BASE's, which is the only signal: " _ tA04)
    Do $$$AssertNotEquals($Piece(tA04, ":", 1), ..#CATEGORY, "it is NOT our category answering")

    // Genuinely unknown things do come back empty -- the control that makes the above meaningful.
    Do $$$AssertEquals(..Seg(..#CATEGORY, "ZZZ"), "", "an unknown segment resolves to empty")
    Do $$$AssertEquals(..Doc(..#CATEGORY, "NOSUCHTYPE"), "", "and so does an unknown type")
}

/// A re-import CLEANS -- the skill's "lingers" does not reproduce.
Method TestReimportCleansTheOldSegment()
{
    Do ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()
    Do $$$AssertEquals(..Seg(..#CATEGORY, "ZAL"), "Example_2.5:ZAL", "control: ZAL is there to begin with")

    // Import a variant of the SAME category with the segment renamed, with NO removal in between.
    Set tSC = ..ImportVariant("ZALRENAMED")
    Do $$$AssertStatusOK(tSC, "the variant must import")

    Do $$$AssertEquals(..Seg(..#CATEGORY, "ZALRENAMED"), "Example_2.5:ZALRENAMED", "the new name resolves")
    Do $$$AssertEquals(..Seg(..#CATEGORY, "ZAL"), "", "and the OLD name is GONE -- a re-import cleans, it does not leave the old segment behind")

    Do ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()
}

/// Removal takes the category out, and says so when there is nothing to take out.
Method TestRemoveIsIdempotentAndHonest()
{
    Do ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()

    Set tFirst = ##class(Example.UTL.Hl7SchemaBootstrap).RemoveSchema(..#CATEGORY)
    Do $$$AssertEquals($Find(tFirst, "OK: removed") > 0, 1, "the first removal removes: " _ tFirst)
    Do $$$AssertEquals(##class(Example.UTL.Hl7SchemaBootstrap).CategoryExists(..#CATEGORY), 0, "and it is gone")
    Do $$$AssertEquals(..Seg(..#CATEGORY, "ZAL"), "", "so its Z-segment no longer resolves")

    Set tAgain = ##class(Example.UTL.Hl7SchemaBootstrap).RemoveSchema(..#CATEGORY)
    Do $$$AssertEquals($Find(tAgain, "nothing to remove") > 0, 1, "a second removal says so rather than claiming to have removed something: " _ tAgain)
    Do $$$AssertEquals($Find(tAgain, "OK: removed") > 0, 0, "and must not report a removal")

    Do ##class(Example.UTL.Hl7SchemaBootstrap).ImportFromXData()
}

/// An empty category name must be refused.
Method TestEmptyCategoryIsRefused()
{
    Set tOut = ##class(Example.UTL.Hl7SchemaBootstrap).RemoveSchema("")
    Do $$$AssertEquals($Find(tOut, "FAILED") > 0, 1, "an empty category name must be refused: " _ tOut)
}

/// Write a variant of the category with the Z-segment renamed, and import it. Kept in the test rather
/// than the bootstrap: the bootstrap owns ONE grammar, and a second one exists only to prove the
/// re-import behaviour.
ClassMethod ImportVariant(pSegName As %String) As %Status [ Private ]
{
    Set tFile = "/tmp/example_hl7_category_variant.xml"
    Set tStream = ##class(%Stream.FileCharacter).%New()
    Set tStream.Filename = tFile
    Do tStream.WriteLine("<?xml version=""1.0"" encoding=""UTF-8""?>")
    Do tStream.WriteLine("<Category name='" _ ..#CATEGORY _ "' base='2.5' description='variant for the re-import test'>")
    Do tStream.WriteLine("  <SegmentStructure name='" _ pSegName _ "' description='renamed allergy segment'>")
    Do tStream.WriteLine("    <SegmentSubStructure piece='1' description='Allergy Id' datatype='ST' max_length='10' required='O' ifrepeating='0'/>")
    Do tStream.WriteLine("  </SegmentStructure>")
    Do tStream.WriteLine("  <MessageStructure name='ADT_A01' definition='2.5:MSH~[~" _ pSegName _ "~]~2.5:EVN~2.5:PID'/>")
    Do tStream.WriteLine("  <MessageType name='ADT_A01' structure='ADT_A01'/>")
    Do tStream.WriteLine("</Category>")
    Set tSC = tStream.%Save()
    Quit:$$$ISERR(tSC) tSC

    Set tImported = ""
    Set tSC = ##class(EnsLib.HL7.SchemaXML).Import(tFile, .tImported)
    Do ##class(%File).Delete(tFile)
    Quit tSC
}

}
