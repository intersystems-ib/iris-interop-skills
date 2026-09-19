/// Rule: BestPractices_Interop_IRIS.md §4.12 "`Bundle.type` decides whether all-or-nothing applies, and `batch` satisfies the prose while breaking the guarantee"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (a `batch` Bundle is indistinguishable from a `transaction` to every check but one).
///
/// Pattern: the oracle for `fhir-bundle-transaction-guard.cls`. Two halves, and the second is unusual:
///
///   * `TestGuard*` exercise the guard on each `Bundle.type`.
///   * `TestPlatform*` assert the SHIPPED `HS.FHIRServer.DefaultBundleProcessor` still branches the way
///     §4.12 says it does. The guard's entire reason to exist is that platform behaviour, so an IRIS
///     upgrade that changes it should fail a test rather than quietly invalidate a section.
///
/// NO FHIR ENDPOINT IS NEEDED, and none exists in the gate namespace. The guard is pure inspection, and
/// the platform half reads the dictionary. Nothing here posts a Bundle, and the header of the sample says
/// plainly that the rollback was therefore not exercised.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=433  7 methods, 0 failed
///     batch accepted like transaction             run=434  1 failed -- GuardRefusesBatchAndSaysWhy
///     the resourceType check removed              run=435  1 failed
///     absent type not distinguished               run=436  1 failed
///     a parse failure reported as a bad Bundle    run=437  1 failed
///     every type accepted                         run=438  3 failed
///     reverted                                    run=439  7 methods, 0 failed
///
/// THE TWO `TestPlatform*` METHODS ARE NOT KILLED BY ANY MUTATION, and cannot be: their subject is IRIS's
/// own code, not this sample. What protects them from passing vacuously is the length check on the
/// implementation text -- a deployed class would read as "" and every search would trivially succeed.
/// They are a drift alarm for §4.12, not a check on the guard.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.FhirBundleTransactionGuard", namespace="<NS>")
Class Example.Tests.FhirBundleTransactionGuard Extends %UnitTest.TestCase
{

/// A Bundle of the given type, structurally complete in every other respect.
ClassMethod Bundle(pType As %String, pIncludeType As %Boolean = 1) As %DynamicObject [ Private ]
{
    Set tJson = "{""resourceType"":""Bundle"""
        _ $Select(pIncludeType:",""type"":""" _ pType _ """", 1:"")
        _ ",""entry"":[{""resource"":{""resourceType"":""Patient"",""id"":""p1""}},"
        _ "{""resource"":{""resourceType"":""Observation"",""id"":""o1""}}]}"
    Quit ##class(%DynamicObject).%FromJSON(tJson)
}

/// The accepted case.
Method TestGuardAcceptsTransaction() As %Status
{
    Set tBundle = ..Bundle("transaction")
    // POSITIVE CONTROL: the fixture really is a complete two-entry Bundle, so an acceptance below is
    // not acceptance of something empty.
    Do $$$AssertEquals(tBundle.resourceType, "Bundle", "POSITIVE CONTROL: the fixture is a Bundle")
    Do $$$AssertEquals(tBundle.entry.%Size(), 2, "with two entries")
    Do $$$AssertStatusOK(##class(Example.UTL.FhirBundleGuard).Check(tBundle), "a transaction Bundle passes the guard")
    Quit $$$OK
}

/// THE CASE THIS FILE EXISTS FOR. `batch` is structurally identical and must still be refused.
Method TestGuardRefusesBatchAndSaysWhy() As %Status
{
    Set tBatch = ..Bundle("batch")
    // The point, asserted: every check other than `type` cannot tell them apart.
    Set tTransaction = ..Bundle("transaction")
    Do $$$AssertEquals(tBatch.resourceType, tTransaction.resourceType, "batch and transaction have the SAME resourceType")
    Do $$$AssertEquals(tBatch.entry.%Size(), tTransaction.entry.%Size(), "and the same entry count")
    Do $$$AssertNotEquals(tBatch.type, tTransaction.type, "only `type` differs -- which is why a guard has to read it")
    Set tSC = ##class(Example.UTL.FhirBundleGuard).Check(tBatch)
    Do $$$AssertNotTrue($$$ISOK(tSC), "and the guard refuses the batch Bundle")
    Set tText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tText [ "batch", "naming the type: " _ tText)
    Do $$$AssertTrue(tText [ "successful entries committed", "and the consequence, not just the rule: " _ tText)
    Quit $$$OK
}

/// Every other type is refused too, and the message says the server would 400 it.
Method TestGuardRefusesTheOtherBundleTypes() As %Status
{
    Set tRefused = 0
    For tType = "collection", "document", "message", "searchset", "history", "transaction-response" {
        Set tSC = ##class(Example.UTL.FhirBundleGuard).Check(..Bundle(tType))
        Do $$$AssertNotTrue($$$ISOK(tSC), "the guard refuses Bundle.type '" _ tType _ "'")
        Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "400", "and says the endpoint would answer 400 for '" _ tType _ "'")
        Set tRefused = tRefused + 1
    }
    // POSITIVE CONTROL: the loop really ran, so six passes are six checks and not an empty iteration.
    Do $$$AssertEquals(tRefused, 6, "POSITIVE CONTROL: six types were actually checked, not zero")
    Quit $$$OK
}

/// An absent `type` is distinguished from a wrong one -- they need different fixes.
Method TestAbsentTypeIsReportedAsAbsent() As %Status
{
    Set tSC = ##class(Example.UTL.FhirBundleGuard).Check(..Bundle("", 0))
    Do $$$AssertNotTrue($$$ISOK(tSC), "a Bundle with no type at all is refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "absent", "and reported as ABSENT rather than as a wrong value: " _ $System.Status.GetErrorText(tSC))
    Quit $$$OK
}

/// A non-Bundle and a non-JSON payload are each reported as themselves.
Method TestNonBundleAndNonJsonAreDistinguished() As %Status
{
    Set tNotBundle = ##class(%DynamicObject).%FromJSON("{""resourceType"":""Patient"",""id"":""p1""}")
    Set tSC = ##class(Example.UTL.FhirBundleGuard).Check(tNotBundle)
    Do $$$AssertNotTrue($$$ISOK(tSC), "a Patient is not a Bundle")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "not a Bundle", "and says so: " _ $System.Status.GetErrorText(tSC))
    Set tSC = ##class(Example.UTL.FhirBundleGuard).CheckJson("{not json at all")
    Do $$$AssertNotTrue($$$ISOK(tSC), "malformed JSON is refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "not valid JSON", "as a PARSE failure, not as a bad Bundle type: " _ $System.Status.GetErrorText(tSC))
    // POSITIVE CONTROL: the same entry point accepts good JSON, so the refusal is about the payload.
    Do $$$AssertStatusOK(##class(Example.UTL.FhirBundleGuard).CheckJson("{""resourceType"":""Bundle"",""type"":""transaction""}"), "POSITIVE CONTROL: CheckJson accepts a well-formed transaction Bundle")
    Quit $$$OK
}

/// Read one shipped method's implementation text.
ClassMethod PlatformImpl(pMethod As %String) As %String [ Private ]
{
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId("HS.FHIRServer.DefaultBundleProcessor||" _ pMethod, 0)
    Quit:'$IsObject(tDef) ""
    Set tText = ""
    If $IsObject(tDef.Implementation) {
        Do tDef.Implementation.Rewind()
        While 'tDef.Implementation.AtEnd { Set tText = tText _ tDef.Implementation.Read(8000) }
    }
    Quit tText
}

/// THE PLATFORM HALF. Only `transaction` and `batch` reach the processor, and only `transaction` sets
/// the flag the rollback is guarded by. If an upgrade changes this, §4.12 is stale and this fails.
Method TestPlatformAcceptsOnlyTransactionAndBatch() As %Status
{
    Set tText = ..PlatformImpl("ProcessBundle")
    // POSITIVE CONTROL: the implementation was actually read. A deployed class would give "" and every
    // search below would vacuously pass.
    Do $$$AssertTrue($Length(tText) > 500, "POSITIVE CONTROL: ProcessBundle's implementation was read, " _ $Length(tText) _ " chars")
    Do $$$AssertTrue(tText [ """transaction""", "it branches on the literal ""transaction""")
    Do $$$AssertTrue(tText [ """batch""", "and on ""batch""")
    Do $$$AssertTrue(tText [ "isTransaction", "setting an isTransaction flag from that branch")
    Do $$$AssertTrue(tText [ "InvalidBundleTypeForTransaction", "and throwing InvalidBundleTypeForTransaction for anything else: the 400 the guard predicts")
    Quit $$$OK
}

/// And the rollback is on the transaction path only.
Method TestPlatformRollsBackOnlyForTransaction() As %Status
{
    Set tText = ..PlatformImpl("ExecuteBundleMain")
    Do $$$AssertTrue($Length(tText) > 500, "POSITIVE CONTROL: ExecuteBundleMain's implementation was read, " _ $Length(tText) _ " chars")
    Do $$$AssertTrue(tText [ "TROLLBACK", "it mentions TROLLBACK")
    Do $$$AssertTrue(tText [ "pBundleType = ""transaction""", "guarded by a pBundleType = ""transaction"" test")
    // The absence that matters: no batch-specific rollback.
    Do $$$AssertNotTrue(tText [ "pBundleType = ""batch""", "and there is NO batch branch around it -- which is why batch leaves partial data")
    Quit $$$OK
}

}
