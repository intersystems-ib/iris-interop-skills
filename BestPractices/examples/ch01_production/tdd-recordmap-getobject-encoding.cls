/// Rule: BestPractices_Interop_IRIS.md §1.17 "Compiling a RecordMap does NOT generate its `.Record` class"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (it is the only thing in the repo that would have noticed the bank's own map was incomplete).
///
/// Pattern: the oracle for `recordmap-generate-bootstrap.cls`, and the executable check that the
/// bank's RecordMap is actually usable.
///
/// THIS TEST EXISTS BECAUSE ITS SUBJECT WAS BROKEN IN THIS REPO. Measured after compiling the whole
/// bank: `Example.RecordMap.Censo` compiled, `Example.RecordMap.Censo.Record` ABSENT. The definition
/// compiles, tier 2 is green, `production-censo-intake.cls` names the map — and the record class the
/// prebuilt service must instantiate was never generated, so that production could not process a
/// single record. No tier could see it: tier 2 compiles files, and the missing class is one no file
/// declares.
///
/// THE SYMPTOM, measured, and it names the wrong class:
///
///     ERROR #5002: ObjectScript error: <CLASS DOES NOT EXIST>
///       zGetObject+11^Example.RecordMap.Censo.1 *Example.Record
///
/// The class that is missing is `Example.RecordMap.Censo.Record`. The error says `*Example.Record`.
/// So the one clue points at a class that does not exist under that name either, which is how this
/// gets diagnosed as "the map is broken" rather than "the map was never generated".
///
/// WHERE `GetObject` LIVES, since the coverage map warned about picking the wrong one: on the MAP
/// class. `Example.RecordMap.Censo` has it (inherited from `EnsLib.RecordMap.RecordMap`);
/// `EnsLib.RecordMap.Base`, which the generated `.Record` extends, does NOT. Calling it on the record
/// class raises `<METHOD DOES NOT EXIST>` — the same error text as an ungenerated map, for a
/// different reason, which is exactly the confusion the row anticipated.
///
/// THE ENCODING HALF IS SCOPED DOWN, and the reason is worth more than the assertion would have been.
/// The row expected `CharEncoding="UTF-8"` to be load-bearing: "default Native returns `?gel` with
/// `$$$OK`". **It does not reproduce on this instance.** Measured on a real file holding real UTF-8
/// bytes, read through `%IO.FileStream`:
///
///     CharEncoding default   ->  FullName = 'Ángel Muñoz'   (11 chars)   CORRECT
///     CharEncoding = 'UTF8'  ->  FullName = 'Ángel Muñoz'   (11 chars)   CORRECT
///
/// Both right, because this instance's default character encoding already handles UTF-8. That is not
/// a refutation of the row — it is the host-dependence `recordmap-censo.cls` already warns about
/// ("the platform default differs across hosts"), demonstrated. So the test below asserts the thing
/// that holds on ANY host — that an EXPLICIT `CharEncoding` round-trips the file correctly — and does
/// not assert mojibake, which would fail here, nor correctness-by-default, which would fail on a
/// Latin-1 host. Where a claim is host-dependent, pin the explicit setting, not the default.
///
/// A NOTE ON A HARNESS THAT LIED FIRST. The first attempt fed `GetObject` a `%IO.StringStream` and
/// reported the OPPOSITE result — default correct, `CharEncoding='UTF8'` mojibake. That harness was
/// wrong, not the platform: a string stream written with character data has no byte-to-character
/// boundary to translate at, so it cannot represent a file. Setting an encoding on it applied a
/// translation to text that had already been decoded. The question is about a FILE, so the
/// measurement has to use one.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  PASSED 11/11
///     drop-before-generate removed                 TestGenerateIsIdempotent              FAILS
///     the verdict never says "regenerated"         TestGenerateIsIdempotent              FAILS
///     the is-a-RecordMap guard removed             TestNonRecordMapClassIsNamedCorrectly FAILS
///
/// ONE BRANCH IS DEFENSIVE AND UNFALSIFIED, and the bootstrap says so at the branch: removing the
/// "did the class actually appear" check after a successful GenerateObject leaves the suite green,
/// because no input was found on which the generator returns $$$OK without creating the class. It is
/// kept for two lines, and it is NOT covered -- which is recorded rather than implied, because a
/// mutation that passes has to be explained one way or the other.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.RecordMapGetObject", namespace="<NS>")
Class Example.Tests.RecordMapGetObject Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

Parameter MAP = "Example.RecordMap.Censo";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Leave the namespace with the record class present, whatever the tests did to it -- these tests
/// drop and regenerate shared state, and the production wired to this map needs it afterwards.
Method OnAfterAllTests() As %Status
{
    Do ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)
    Quit $$$OK
}

/// THE DEFECT. Dropping the generated class leaves the map itself compiled -- so "absent" is
/// specifically the record class, which is what makes this indistinguishable from a broken map.
Method TestRecordClassIsSeparateFromTheMap()
{
    Do ##class(Example.UTL.RecordMapBootstrap).DropRecordClass(..#MAP)

    Do $$$AssertEquals(##class(Example.UTL.RecordMapBootstrap).RecordClassExists(..#MAP), 0, "the record class is gone")
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId(..#MAP), 1, "while the MAP is still compiled -- the two are independent")

    Do ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)
}

/// The generator creates it, and the bootstrap reports what it established rather than what it hoped.
Method TestGenerateCreatesTheRecordClass()
{
    Do ##class(Example.UTL.RecordMapBootstrap).DropRecordClass(..#MAP)
    Do $$$AssertEquals(##class(Example.UTL.RecordMapBootstrap).RecordClassExists(..#MAP), 0, "control: absent before")

    Set tVerdict = ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)

    Do $$$AssertEquals($Find(tVerdict, "OK:") > 0, 1, "generation must report OK: " _ tVerdict)
    Do $$$AssertEquals($Find(tVerdict, ".Record") > 0, 1, "and name the class it made")
    Do $$$AssertEquals(##class(Example.UTL.RecordMapBootstrap).RecordClassExists(..#MAP), 1, "and the class must actually exist")
}

/// Running it twice is safe -- a bootstrap that is not idempotent cannot go in a deployment script.
/// This is the assertion that forced the drop-first design: see TestRawGeneratorIsNotIdempotent.
Method TestGenerateIsIdempotent()
{
    Set tFirst = ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)
    Do $$$AssertEquals($Find(tFirst, "OK:") > 0, 1, "first call: " _ tFirst)

    Set tSecond = ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)
    Do $$$AssertEquals($Find(tSecond, "OK:") > 0, 1, "second call on an already-generated map: " _ tSecond)
    Do $$$AssertEquals($Find(tSecond, "regenerated") > 0, 1, "and it must say it REGENERATED, so the two paths are distinguishable")
    Do $$$AssertEquals(##class(Example.UTL.RecordMapBootstrap).RecordClassExists(..#MAP), 1, "still there")
}

/// THE REASON THE BOOTSTRAP DROPS FIRST. The raw generator is not idempotent, and this pins it -- so
/// if a future IRIS makes it idempotent, this test fails and the drop can be reconsidered rather than
/// carried for ever as folklore.
Method TestRawGeneratorIsNotIdempotent()
{
    Do ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)
    Do $$$AssertEquals(##class(Example.UTL.RecordMapBootstrap).RecordClassExists(..#MAP), 1, "control: the record class is present")

    Set tTarget = ""
    Set tStructure = 1
    Set tSC = ##class(EnsLib.RecordMap.Generator).GenerateObject(..#MAP, .tTarget, .tStructure)

    Do $$$AssertStatusNotOK(tSC, "calling the raw generator over an existing record class must FAIL")
    Do $$$AssertEquals($System.Status.GetErrorCodes(tSC), 5768, "with #5768 Class already exists: " _ $Extract($system.Status.GetErrorText(tSC), 1, 90))
}

/// A name that is not a compiled RecordMap must be refused, not reported OK.
Method TestBadMapNameIsRefused()
{
    Set tVerdict = ##class(Example.UTL.RecordMapBootstrap).Generate("Example.RecordMap.NoSuchThing")
    Do $$$AssertEquals($Find(tVerdict, "FAILED") > 0, 1, "an unknown map must be refused: " _ tVerdict)
    Do $$$AssertEquals($Find(tVerdict, "OK:") > 0, 0, "and must not contain an OK verdict")
}

/// THE GUARD THAT EARNS ITS PLACE. A class that EXISTS but is not a RecordMap: the raw generator
/// calls that "Class does not exist", which is false and sends you looking for a missing class.
Method TestNonRecordMapClassIsNamedCorrectly()
{
    Set tVictim = "Example.UTL.RecordMapBootstrap"
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId(tVictim), 1, "control: this class really does exist")
    Do $$$AssertEquals(##class(Example.UTL.RecordMapBootstrap).IsRecordMap(tVictim), 0, "and is not a RecordMap")
    Do $$$AssertEquals(##class(Example.UTL.RecordMapBootstrap).IsRecordMap(..#MAP), 1, "control: the real map IS one")

    Set tVerdict = ##class(Example.UTL.RecordMapBootstrap).Generate(tVictim)
    Do $$$AssertEquals($Find(tVerdict, "is NOT a RecordMap") > 0, 1, "the verdict must say what is actually wrong: " _ tVerdict)
    Do $$$AssertEquals($Find(tVerdict, "no compiled class named") > 0, 0, "and must NOT claim the class does not exist")

    // And the raw generator's misleading error, pinned -- so if IRIS improves it, this test says so.
    Set tTarget = ""
    Set tStruct = 1
    Set tSC = ##class(EnsLib.RecordMap.Generator).GenerateObject(tVictim, .tTarget, .tStruct)
    Do $$$AssertStatusNotOK(tSC, "the raw generator refuses it too")
    Do $$$AssertEquals($System.Status.GetErrorCodes(tSC), 5351, "but with #5351 'Class does not exist' -- about a class that does: " _ $Extract($system.Status.GetErrorText(tSC), 1, 80))
}

/// THE CONSEQUENCE. Without the record class, GetObject fails at runtime -- and the error names a
/// class that is not the one missing.
Method TestGetObjectFailsWithoutTheRecordClass()
{
    Do ##class(Example.UTL.RecordMapBootstrap).DropRecordClass(..#MAP)

    Set tS = ##class(%IO.StringStream).%New()
    Do tS.Write("12345,Ana,WARD1" _ $Char(10))
    Do tS.Rewind()

    Set tObj = ""
    Set tSC = ##class(Example.RecordMap.Censo).GetObject(tS, .tObj)

    Do $$$AssertStatusNotOK(tSC, "GetObject must fail when the record class is absent")
    Do $$$AssertEquals($Find($system.Status.GetErrorText(tSC), "CLASS DOES NOT EXIST") > 0, 1, "with <CLASS DOES NOT EXIST>: " _ $Extract($system.Status.GetErrorText(tSC), 1, 120))
    Do $$$AssertEquals($IsObject(tObj), 0, "and no object comes back")

    Do ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)
}

/// And with the class present, the same call works -- the positive control that makes the test above
/// evidence of the missing class rather than of a broken map.
Method TestGetObjectWorksOnceGenerated()
{
    Do ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)

    Set tS = ##class(%IO.StringStream).%New()
    Do tS.Write("12345,Ana,WARD1" _ $Char(10))
    Do tS.Rewind()

    Set tObj = ""
    Set tSC = ##class(Example.RecordMap.Censo).GetObject(tS, .tObj)

    Do $$$AssertStatusOK(tSC, "the same call succeeds once the record class exists")
    Do $$$AssertEquals($IsObject(tObj), 1, "and returns a record")
    Do $$$AssertEquals(tObj.PatientId, "12345", "with the first field parsed")
    Do $$$AssertEquals(tObj.Ward, "WARD1", "and the last")
}

/// GetObject is on the MAP class, not on the generated record class.
Method TestGetObjectIsOnTheMapNotTheRecord()
{
    Do ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)

    Do $$$AssertEquals(..HasMethod(..#MAP, "GetObject"), 1, "the map class has GetObject")
    Do $$$AssertEquals(..HasMethod(..#MAP _ ".Record", "GetObject"), 0, "the generated record class does NOT")
    Do $$$AssertEquals(..HasMethod("EnsLib.RecordMap.Base", "GetObject"), 0, "nor does the base the record class extends")
    Do $$$AssertEquals(..HasMethod("EnsLib.RecordMap.RecordMap", "GetObject"), 1, "it comes from EnsLib.RecordMap.RecordMap")
}

/// An EXPLICIT CharEncoding round-trips a real UTF-8 file. The default is host-dependent and is
/// deliberately not asserted -- see the header.
Method TestExplicitUtf8FileRoundTrips()
{
    Set tPath = "/tmp/example_recordmap_utf8.csv"
    Do ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)

    // Write real UTF-8 BYTES with a binary stream, so nothing is translated on the way in.
    Set tW = ##class(%Stream.FileBinary).%New()
    Set tW.Filename = tPath
    Do tW.Write("12345," _ $Char(195) _ $Char(129) _ "ngel Mu" _ $Char(195) _ $Char(177) _ "oz,WARD1" _ $Char(10))
    Do $$$AssertStatusOK(tW.%Save(), "the fixture file must be written")

    Set tF = ##class(%IO.FileStream).%New()
    Set tF.CharEncoding = "UTF8"
    Do tF.Open(tPath, "R", , , .tOpenSC)
    Do $$$AssertStatusOK($Get(tOpenSC, 1), "the file must open")

    Set tObj = ""
    Set tSC = ##class(Example.RecordMap.Censo).GetObject(tF, .tObj)
    Do $$$AssertStatusOK(tSC, "GetObject must parse the UTF-8 record")
    Do $$$AssertEquals($IsObject(tObj), 1, "and return it")

    // 11 CHARACTERS, not 13 bytes. A double decode gives 13, a failed decode gives replacement chars.
    Do $$$AssertEquals($Length(tObj.FullName), 11, "the accented name must arrive as 11 CHARACTERS, not bytes: '" _ tObj.FullName _ "'")
    Do $$$AssertEquals(tObj.PatientId, "12345", "and the ASCII fields are unaffected")
    Do $$$AssertEquals(tObj.Ward, "WARD1", "including the last one, so the record was not truncated")

    Do tF.Close()
    Do ##class(%File).Delete(tPath)
}

ClassMethod HasMethod(pClass As %String, pMethod As %String) As %Boolean [ Private ]
{
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM %Dictionary.CompiledMethod WHERE parent = :pClass AND Name = :pMethod)
    Quit (+$Get(tN) > 0)
}

}
