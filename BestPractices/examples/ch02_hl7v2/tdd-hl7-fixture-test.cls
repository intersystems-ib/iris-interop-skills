/// Rule: BestPractices_Interop_IRIS.md §2.11 "Symbolic HL7 field paths — and why an empty result proves nothing"
/// Validity: Verified against IRIS for Health 2026.1 — the assertions below were EXECUTED.
/// Severity: High (this is the only check that can tell a resolving path from a silent one).
///
/// Pattern: the HL7 fixture test. It builds a message in code, assigns a DocType, and asserts on
/// fields the transform WRITES — the only way to distinguish a working symbolic path from one that
/// resolves to nothing, since both compile.
///
/// THE FIXTURE RULES, all three measured rather than assumed:
///   1. `ImportFromString` is a CLASSMETHOD on EnsLib.HL7.Message, and its third argument is
///      `pConfigItem` — NOT a schema category. You cannot pass "2.5" to it.
///   2. Segments are separated by `$Char(13)`, not $Char(10) and not a newline in a string literal.
///   3. **DocType is EMPTY after import** — measured: `docTypeBefore=[]`. It must be assigned with
///      `DocTypeSet("2.5:ADT_A01")` before any symbolic path will resolve. Skip that and every
///      symbolic path returns "" and the test passes on empty strings.
///
/// THE NEGATIVE CONTROL IS THE POINT OF TestEmptyIsAmbiguous. Measured on the same message:
///     PID:PatientIdentifierList(1).IDNumber  -> "12345"  status OK
///     PID:PatientIdentifierList(1).ID        -> ""       status ERROR "PropertyPath … is invalid"
///     PID:PatientID  (real field, empty here) -> ""      status OK
/// A mistyped path and an empty field BOTH yield "". Asserting "the field came back empty" is
/// therefore not evidence of anything, and a test built only on that passes against a transform
/// that resolves nothing at all. Capture the status, or assert on a value you know is non-empty.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.Hl7SymbolicPaths", namespace="<NS>")
Class Example.Tests.Hl7SymbolicPaths Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test (see TestControl).
Parameter PRODUCTION = "Example.Productions.Hl7Intake";

/// Neutralises the production start/stop this superclass would otherwise drive.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// One ADT^A01, built with $Char(13) separators and given its DocType. Returns the message.
ClassMethod Fixture(Output pDoc As EnsLib.HL7.Message) As %Status [ Private ]
{
    Set tCR = $Char(13)
    Set tMsg = "MSH|^~\&|SEND|FAC|RECV|FAC|20260101120000||ADT^A01|MSG0001|P|2.5" _ tCR
    Set tMsg = tMsg _ "EVN|A01|20260101120000" _ tCR
    Set tMsg = tMsg _ "PID|1||12345^^^MRN||DOE^JOHN^Q||19800101|M" _ tCR
    Set tMsg = tMsg _ "PV1|1|I|WARD^101^A" _ tCR

    Set pDoc = ##class(EnsLib.HL7.Message).ImportFromString(tMsg, .tSC)
    Quit:$$$ISERR(tSC) tSC
    // No $$$ERROR/$$$GeneralError here on purpose: those macros come with the Ensemble includes
    // that an Ens.* superclass brings, and %UnitTest.TestProduction does not --
    //   MPP5610: Referenced macro not defined: 'GeneralError'
    // Callers assert $IsObject instead, which is a better assertion anyway.
    Quit:'$IsObject(pDoc) tSC
    Quit pDoc.DocTypeSet("2.5:ADT_A01")
}

/// DocType is empty after import and must be assigned. Without this step every symbolic path
/// below returns "" and every assertion would pass on an empty string.
Method TestDocTypeMustBeAssigned()
{
    Set tCR = $Char(13)
    Set tMsg = "MSH|^~\&|S|F|R|F|20260101120000||ADT^A01|M1|P|2.5" _ tCR _ "PID|1||12345^^^MRN||DOE^JOHN" _ tCR
    Set tDoc = ##class(EnsLib.HL7.Message).ImportFromString(tMsg, .tSC)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tDoc.DocType, "", "import leaves DocType EMPTY -- this is the trap")

    Do $$$AssertStatusOK(tDoc.DocTypeSet("2.5:ADT_A01"))
    Do $$$AssertEquals(tDoc.DocType, "2.5:ADT_A01", "DocTypeSet is what makes symbolic paths resolve")
}

/// A correct symbolic path returns the value. Asserted against a NON-empty expected value, so
/// the assertion cannot be satisfied by a path that resolves to nothing.
Method TestSymbolicPathsResolve()
{
    Do $$$AssertStatusOK(..Fixture(.tDoc))
    Do $$$AssertTrue($IsObject(tDoc), "the fixture must produce a message")

    Do $$$AssertEquals(tDoc.GetValueAt("PID:PatientName(1).FamilyName.Surname"), "DOE", "symbolic surname")
    Do $$$AssertEquals(tDoc.GetValueAt("PID:PatientName(1).GivenName"), "JOHN", "symbolic given name")
    Do $$$AssertEquals(tDoc.GetValueAt("PID:PatientIdentifierList(1).IDNumber"), "12345", "component is IDNumber, not ID")

    // The numeric equivalents, to show they address the same data.
    Do $$$AssertEquals(tDoc.GetValueAt("PID:5.1"), "DOE", "numeric path reaches the same field")
    Do $$$AssertEquals(tDoc.GetValueAt("PID:5.2"), "JOHN", "numeric path reaches the same component")
}

/// The negative control, and the argument of §2.11 in one method: "" does not tell you which
/// kind of mistake you made, so the STATUS is the only discriminator.
Method TestEmptyIsAmbiguous()
{
    Do $$$AssertStatusOK(..Fixture(.tDoc))

    // A path that does not exist: empty value, and an ERROR status.
    Set tBadValue = tDoc.GetValueAt("PID:PatientNameXX(1).GivenName", , .tBadStatus)
    Do $$$AssertEquals(tBadValue, "", "an invalid path yields an empty value")
    Do $$$AssertStatusNotOK(tBadStatus, "...but it DOES set an error status -- the only signal there is")

    // A real field that happens to be empty: same empty value, and an OK status.
    Set tEmptyValue = tDoc.GetValueAt("PID:PatientID", , .tEmptyStatus)
    Do $$$AssertEquals(tEmptyValue, "", "a valid but empty field also yields an empty value")
    Do $$$AssertStatusOK(tEmptyStatus, "...with an OK status -- identical value, opposite meaning")

    // Therefore: the two-argument form, which is what everyone writes, cannot tell them apart.
    Set tMistake = tDoc.GetValueAt("PID:PatientNameXX(1).GivenName")
    Set tEmptyField = tDoc.GetValueAt("PID:PatientID")
    Do $$$AssertEquals(tMistake, tEmptyField, "without the status both mistakes look identical")
}

/// The transform must actually write the fields it claims to. A DTL with a mistyped symbolic
/// path compiles clean, so this is the only place it can be caught.
Method TestTransformWritesWhatItClaims()
{
    Do $$$AssertStatusOK(..Fixture(.tDoc))
    Set tSC = ##class(Example.DT.AdtNormalise).Transform(tDoc, .tOut)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertTrue($IsObject(tOut), "the transform must produce a target")

    Do $$$AssertEquals(tOut.GetValueAt("PID:PatientName(1).FamilyName.Surname"), "DOE", "surname upper-cased and written")
    Do $$$AssertEquals(tOut.GetValueAt("PID:PatientIdentifierList(1).IDNumber"), "12345", "identifier carried across")
    // create='copy' means untouched segments survive; create='new' would drop this silently.
    Do $$$AssertEquals(tOut.GetValueAt("PV1:2"), "I", "create='copy' carries segments the transform never touches")
}

}
