/// Rule: BestPractices_Interop_IRIS.md §4.13 "An existence test must read the dictionary — a call-through to a missing method compiles clean"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (the obvious spelling of this test passes either way).
///
/// Pattern: the oracle for `fhirsql-setup-existence-test.cls`. Two halves:
///
///   * `TestLookup*` exercise the helper on names that DO and DO NOT exist, so each verdict has a control.
///   * `TestSurface*` pin the FHIR SQL Builder signatures §4.9 depends on. Those are the drift alarms: if
///     an IRIS upgrade changes them, the section is stale and a test says so.
///
/// AND ONE TEST WITH AN UNUSUAL SUBJECT. `TestCallThroughWouldNotHaveWorked` compiles a throwaway class
/// that calls a method which does not exist, and asserts the compile **succeeds** -- because that is the
/// whole reason this helper reads the dictionary instead. Its expected result is "no error", which is the
/// shape that passes when nothing ran, so it carries a control proving the compiler was invoked.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=469  8 methods, 0 failed
///     ClassPresent always says yes                run=470  1 failed
///     MethodPresent always says yes               run=471  1 failed
///     the depth guard dropped                     run=472  1 failed
///     ReturnsValue always says a value            run=473  2 failed
///     the in-string guard dropped                 run=474  1 failed
///     reverted                                    run=475  8 methods, 0 failed
///
/// TWO MUTANTS SURVIVED THE FIRST TWO ROUNDS, and both pointed at the same missing case. Dropping either
/// comma guard in `ParamCount` left the suite green, because none of the three real FHIR SQL specs has a
/// comma inside a quoted default or inside parentheses -- the guards were correct and never exercised.
/// `TestParamCountSurvivesCommasInTypesAndDefaults` builds the shape they exist for. The first attempt at
/// it put every comma inside QUOTES, which killed only the in-string guard; the depth guard needed a comma
/// inside PARENTHESES and not in a string, which is what `%String(MAXLEN=10,TRUNCATE=1)` provides.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.FhirSqlSetupExistence", namespace="<NS>")
Class Example.Tests.FhirSqlSetupExistence Extends %UnitTest.TestCase
{

Parameter SETUP As STRING = "HS.HC.FHIRSQL.Utils.Setup";

Parameter PROBE As STRING = "ExampleFhirSqlProbe.CallThrough";

/// A class that certainly does not exist, for the negative side of every lookup.
Parameter ABSENT As STRING = "HS.Totally.Absent.NotAClass";

/// The lookup says yes for a real class and no for an invented one.
Method TestLookupDistinguishesPresentFromAbsent() As %Status
{
    Set tHelper = "Example.UTL.FhirSqlSetupCheck"
    // POSITIVE CONTROL: a class we KNOW is here, so a false below is about the name, not the lookup.
    Do $$$AssertTrue($ClassMethod(tHelper, "ClassPresent", "%Dictionary.CompiledClass"), "POSITIVE CONTROL: the lookup finds a class that certainly exists")
    Do $$$AssertNotTrue($ClassMethod(tHelper, "ClassPresent", ..#ABSENT), "and does not find an invented one")
    Do $$$AssertTrue($ClassMethod(tHelper, "MethodPresent", "%Dictionary.CompiledClass", "%ExistsId"), "it finds a method that exists")
    Do $$$AssertNotTrue($ClassMethod(tHelper, "MethodPresent", "%Dictionary.CompiledClass", "NoSuchMethodHere"), "and not one that does not")
    // A method on an absent class is absent, not an error.
    Do $$$AssertNotTrue($ClassMethod(tHelper, "MethodPresent", ..#ABSENT, "Setup"), "a method on an absent class is simply absent")
    Quit $$$OK
}

/// The parameter counter handles a default value that itself contains commas.
Method TestParamCountIgnoresCommasInsideDefaults() As %Status
{
    Set tHelper = "Example.UTL.FhirSqlSetupCheck"
    // Setup's first default is a long quoted path; a naive comma split would still get 3 here, so use a
    // method whose defaults are known to be quoted strings AND assert the quoted-comma case directly.
    Do $$$AssertEquals($ClassMethod(tHelper, "ParamCount", ..#SETUP, "Setup"), 3, "Setup declares three parameters")
    Do $$$AssertEquals($ClassMethod(tHelper, "ParamCount", ..#SETUP, "LoadFHIRData"), 5, "LoadFHIRData declares five")
    Do $$$AssertEquals($ClassMethod(tHelper, "ParamCount", ..#SETUP, "Install"), 1, "Install declares one")
    // An absent method has no parameters rather than raising.
    Do $$$AssertEquals($ClassMethod(tHelper, "ParamCount", ..#SETUP, "NoSuchMethod"), 0, "an absent method counts zero")
    Quit $$$OK
}

/// THE TWO GUARDS IN ParamCount NEEDED A CASE BUILT FOR THEM. Mutation-checking found that dropping
/// either the depth guard or the in-string guard left the suite green: none of the three real FHIR SQL
/// specs contains a comma inside a quoted default or inside parentheses, so both guards were correct and
/// unexercised. This test constructs the shape they exist for -- a parameter whose TYPE PARAMETER LIST
/// contains commas, and a default VALUE containing a comma -- so a naive `$Length(spec, ",")` over-counts
/// 2 as 4.
Method TestParamCountSurvivesCommasInTypesAndDefaults() As %Status
{
    Set tHelper = "Example.UTL.FhirSqlSetupCheck"
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Set tClass = ##class(%Dictionary.ClassDefinition).%New(..#PROBE)
    Set tClass.Super = "%RegisteredObject"
    Set tMethod = ##class(%Dictionary.MethodDefinition).%New()
    Set tMethod.Name = "Awkward"
    Set tMethod.ReturnType = "%Status"
    // Two parameters, carrying a comma in EACH of the two places that fool a naive split:
    //   MAXLEN=10,TRUNCATE=1   a comma inside PARENTHESES and not inside a string  -> depth guard
    //   "a,b"                  a comma inside a QUOTED default                     -> in-string guard
    // A naive $Length(spec, ",") sees four fields here; there are two parameters.
    Set tMethod.FormalSpec = "pA:%String(MAXLEN=10,TRUNCATE=1)=""a,b"",pB:%Integer"
    Do tMethod.Implementation.WriteLine("    Quit $$$OK")
    Do tClass.Methods.Insert(tMethod)
    Do $$$AssertStatusOK(tClass.%Save(), "the awkward probe saved")
    Do $$$AssertStatusOK($System.OBJ.Compile(..#PROBE, "-d"), "and compiled")
    // POSITIVE CONTROL: the spec really did come back with the commas in it, or there is nothing to count.
    Set tSpec = $ClassMethod(tHelper, "FormalSpec", ..#PROBE, "Awkward")
    Do $$$AssertTrue(tSpec [ "MAXLEN=10,TRUNCATE=1", "POSITIVE CONTROL: the parenthesised type parameter list survived into the dictionary: " _ tSpec)
    Do $$$AssertTrue(tSpec [ "a,b", "and so did the comma inside the quoted default value")
    Do $$$AssertEquals($Length(tSpec, ","), 4, "POSITIVE CONTROL: a naive comma split really does see FOUR fields here")
    // THE ASSERTION THE GUARDS EXIST FOR.
    Do $$$AssertEquals($ClassMethod(tHelper, "ParamCount", ..#PROBE, "Awkward"), 2, "ParamCount counts TWO parameters, not the four a naive comma split would give: " _ tSpec)
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Quit $$$OK
}

/// THE DRIFT ALARM for §4.9's setup instruction.
Method TestSetupSignatureIsWhatTheSectionSays() As %Status
{
    Set tHelper = "Example.UTL.FhirSqlSetupCheck"
    Do $$$AssertTrue($ClassMethod(tHelper, "ClassPresent", ..#SETUP), "POSITIVE CONTROL: HS.HC.FHIRSQL.Utils.Setup is present in this namespace")
    Set tSpec = $ClassMethod(tHelper, "FormalSpec", ..#SETUP, "Setup")
    Do $$$AssertNotEquals(tSpec, "", "POSITIVE CONTROL: its formal spec was read, so the checks below are not vacuous")
    // The three facts §4.13 rests on.
    Do $$$AssertTrue(tSpec [ "pNamespace", "Setup takes a pNamespace parameter -- it is NOT Setup(path): " _ tSpec)
    Do $$$AssertTrue(tSpec [ "pStrategyClass", "and a pStrategyClass parameter")
    Do $$$AssertNotTrue($ClassMethod(tHelper, "ReturnsValue", ..#SETUP, "Setup"), "and it returns VOID, so `Set tSC = ..Setup(...)` would raise <COMMAND>")
    Quit $$$OK
}

/// LoadFHIRData is the data entry point, not Setup.
Method TestLoadFhirDataIsTheDataEntryPoint() As %Status
{
    Set tHelper = "Example.UTL.FhirSqlSetupCheck"
    Do $$$AssertTrue($ClassMethod(tHelper, "MethodPresent", ..#SETUP, "LoadFHIRData"), "LoadFHIRData exists")
    Set tSpec = $ClassMethod(tHelper, "FormalSpec", ..#SETUP, "LoadFHIRData")
    Do $$$AssertTrue(tSpec [ "dir", "and it is the one taking a dir parameter for data: " _ tSpec)
    Do $$$AssertNotTrue($ClassMethod(tHelper, "ReturnsValue", ..#SETUP, "LoadFHIRData"), "it also returns VOID")
    Quit $$$OK
}

/// The class parameters the method defaults refer to.
Method TestNamespaceParametersAreWhatTheyWere() As %Status
{
    Do $$$AssertEquals($Parameter(..#SETUP, "APPNAMESPACE"), "HSSYS", "APPNAMESPACE is HSSYS -- the namespace the install methods default to")
    Do $$$AssertEquals($Parameter(..#SETUP, "FHIRNAMESPACE"), "DEMO", "FHIRNAMESPACE is DEMO")
    Quit $$$OK
}

/// THE REASON THIS HELPER READS THE DICTIONARY. A call-through to a method that does not exist compiles
/// clean, so it can never be an existence test.
Method TestCallThroughWouldNotHaveWorked() As %Status
{
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Set tClass = ##class(%Dictionary.ClassDefinition).%New(..#PROBE)
    Set tClass.Super = "%RegisteredObject"
    Set tMethod = ##class(%Dictionary.MethodDefinition).%New()
    Set tMethod.Name = "Go"
    Set tMethod.ReturnType = "%Status"
    Do tMethod.Implementation.WriteLine("    Set x = ##class(" _ ..#ABSENT _ ").DoesNotExist()")
    Do tMethod.Implementation.WriteLine("    Quit $$$OK")
    Do tClass.Methods.Insert(tMethod)
    Do $$$AssertStatusOK(tClass.%Save(), "the probe class saved")
    Set tSC = $System.OBJ.Compile(..#PROBE, "-d")
    Do $$$AssertStatusOK(tSC, "a call to a method on a NONEXISTENT class compiles clean -- which is why an existence test cannot be a call")
    // POSITIVE CONTROL: the same harness rejects genuinely broken code, so the pass above is a real
    // compile and not a compiler that was never invoked.
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Set tBad = ##class(%Dictionary.ClassDefinition).%New(..#PROBE)
    Set tBad.Super = "%RegisteredObject"
    Set tBadMethod = ##class(%Dictionary.MethodDefinition).%New()
    Set tBadMethod.Name = "Go"
    Set tBadMethod.ReturnType = "%Status"
    Do tBadMethod.Implementation.WriteLine("    Set x = ((( ")
    Do tBad.Methods.Insert(tBadMethod)
    Do $$$AssertStatusOK(tBad.%Save(), "the broken probe saved")
    Do $$$AssertNotTrue($$$ISOK($System.OBJ.Compile(..#PROBE, "-d")), "POSITIVE CONTROL: the same harness DOES reject a syntax error")
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Quit $$$OK
}

/// And a TYPE reference to the same absent class does fail -- with #5373, the error the coverage map
/// discussed. Asserted so the distinction between a call and a type position is on the record.
Method TestTypeReferenceToAnAbsentClassFailsWith5373() As %Status
{
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Set tClass = ##class(%Dictionary.ClassDefinition).%New(..#PROBE)
    Set tClass.Super = "%RegisteredObject"
    Set tProp = ##class(%Dictionary.PropertyDefinition).%New()
    Set tProp.Name = "P"
    Set tProp.Type = ..#ABSENT
    Do tClass.Properties.Insert(tProp)
    Do $$$AssertStatusOK(tClass.%Save(), "the probe class saved")
    Set tSC = $System.OBJ.Compile(..#PROBE, "-d")
    Do $$$AssertNotTrue($$$ISOK(tSC), "a PROPERTY typed as an absent class DOES fail to compile")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "5373", "with #5373: " _ $Extract($System.Status.GetErrorText(tSC), 1, 130))
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Quit $$$OK
}

}
