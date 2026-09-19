/// Rule: BestPractices_Interop_IRIS.md §1.21 "RecordMap field types are not per-record validation, and what they do instead differs by type"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (relying on the field type gives no routable rejection, and one type raises instead).
///
/// Pattern: the oracle for `dtl-censo-validate-flags.cls` AND for the claim that motivates it. It has
/// two halves, and the first is the one that makes the second worth reading:
///
///   * `TestTypedFieldsDoNotValidate*` drive `Example.RecordMap.CensoTyped` directly and pin what the
///     field types actually do -- accept, raise, or silently discard.
///   * `TestTransform*` drive the DTL and pin that every record becomes a message with a verdict.
///
/// NO PRODUCTION. Both halves work at the class level: a RecordMap parses through `GetObject` and a DTL
/// runs through `Transform`, so nothing here can fail for a reason that belongs to a service.
///
/// WHAT THIS SUITE DELIBERATELY DOES NOT ASSERT. Whether the RecordMap **service** creates a message is
/// not measured here -- that needs a polling file service, and a test built on directory polling reports
/// timing as failure. The mechanism is on the record instead: the service's own signature is
/// `GetObject(pStream As %IO.DeviceStream, ...)` and it delegates to the map's `GetObject`, so a record
/// whose parse raises cannot become a message and a record whose parse succeeds will. The `%Integer`
/// case succeeds at parse, so its bad value DOES reach the production.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=426  9 methods, 0 failed
///     the not-a-number check removed              run=427  2 failed
///     the date check removed                      run=428  2 failed
///     IsValid always 1                            run=429  3 failed
///     Beds filled even when invalid (guard gone)  run=430  1 failed
///     empty not distinguished from invalid        run=431  1 failed
///     reverted                                    run=432  9 methods, 0 failed
///
/// TWO HARNESS DEFECTS CAME FIRST, and both are the same shape as the subject of this section.
/// (1) The setup was spelled `%OnBeforeAllTests`, which does not exist -- dead code, never called. Four
/// parse tests then failed by RAISING, with no failing assertion recorded, and the record class was
/// simply absent. (2) Mutation 4 first "removed" a guard by appending a comment to the same line, so the
/// file changed and the behaviour did not; it survived every test and looked like a missing assertion.
/// The harness now refuses a mutation that leaves the file byte-identical.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.CensoValidateFlags", namespace="<NS>")
Class Example.Tests.CensoValidateFlags Extends %UnitTest.TestCase
{

Parameter MAP As STRING = "Example.RecordMap.CensoTyped";

/// `OnBeforeAllTests`, NOT `%OnBeforeAllTests`. `%UnitTest.TestCase` declares the UNPREFIXED names
/// (`OnBeforeAllTests`, `OnAfterAllTests`, `OnBeforeOneTest`, `OnAfterOneTest`); a `%`-prefixed method
/// compiles clean as dead code that is never called, and the suite then runs with no setup at all.
/// Measured: with the `%` in place, four parse tests failed by RAISING, with no failing assertion
/// recorded -- and the record class the setup was meant to generate was simply absent.
Method OnBeforeAllTests() As %Status
{
    // The generated .Record class is not shipped; the bank's bootstrap makes it. Its verdict is
    // checked rather than assumed, because every parse assertion below depends on it existing.
    Set tVerdict = ##class(Example.UTL.RecordMapBootstrap).Generate(..#MAP)
    If $Find(tVerdict, "FAILED") > 0 {
        Quit $$$ERROR($$$GeneralError, "could not generate the record class: " _ tVerdict)
    }
    Quit $$$OK
}

/// Parse one delimited record through the map. Returns the status; pObj is the record or "".
ClassMethod Parse(pRecord As %String, Output pObj As %RegisteredObject) As %Status [ Private ]
{
    Set pObj = ""
    // %IO.StringStream, NOT %Stream.*: the map wants an %IO stream (the service's signature says
    // %IO.DeviceStream), and a %Stream.GlobalCharacter fails with <PROPERTY DOES NOT EXIST> *Name.
    // A missing record class is the one failure that would make every case below raise identically,
    // so it is named here rather than surfacing as <CLASS DOES NOT EXIST> four times.
    If '##class(%Dictionary.CompiledClass).%ExistsId(..#MAP _ ".Record") {
        Quit $$$ERROR($$$GeneralError, "the record class " _ ..#MAP _ ".Record is absent -- OnBeforeAllTests did not run or its bootstrap failed")
    }
    Set tStream = ##class(%IO.StringStream).%New()
    Do tStream.Write(pRecord _ $Char(10))
    // REWIND. Write() leaves it at the end, and without this every case returns the same
    // <EnsRecordMap>ErrStreamAtEnd -- identical results, which is a broken harness, not a finding.
    Do tStream.Rewind()
    Quit $ClassMethod(..#MAP, "GetObject", tStream, .pObj)
}

/// `%Integer` accepts a non-number at PARSE time. The type is not a gate.
Method TestTypedIntegerAcceptsANonNumberAtParse() As %Status
{
    Set tSC = ..Parse("P2,ABC,64000,ICU", .tObj)
    Do $$$AssertStatusOK(tSC, "GetObject returns OK for Beds=ABC -- the %Integer field does NOT reject it")
    Do $$$AssertTrue($IsObject(tObj), "and a record object comes back")
    Do $$$AssertEquals(tObj.Beds, "ABC", "holding the literal text in an %Integer property: <" _ tObj.Beds _ ">")
    // It is only caught later, which is too late to route.
    Set tVal = tObj.%ValidateObject()
    Do $$$AssertNotTrue($$$ISOK(tVal), "%ValidateObject DOES object -- at save time, not at parse time")
    Do $$$AssertTrue($System.Status.GetErrorText(tVal) [ "7207", "with #7207 Datatype value ... is not a valid number: " _ $Extract($System.Status.GetErrorText(tVal), 1, 120))
    Quit $$$OK
}

/// POSITIVE CONTROL for the above: a good record parses AND validates, so the failure is about the value.
Method TestAGoodRecordParsesAndValidates() As %Status
{
    Set tSC = ..Parse("P1,12,64000,ICU", .tObj)
    Do $$$AssertStatusOK(tSC, "POSITIVE CONTROL: a well-formed record parses")
    Do $$$AssertEquals(tObj.Beds, 12, "with Beds as a number")
    Do $$$AssertStatusOK(tObj.%ValidateObject(), "and validates, so the rejection above is about the value")
    Quit $$$OK
}

/// `%Date` is the opposite: it RAISES at parse, and the error names a generated method.
Method TestTypedDateRaisesAtParse() As %Status
{
    Set tSC = ..Parse("P4,12,NOTADATE,ICU", .tObj)
    Do $$$AssertNotTrue($$$ISOK(tSC), "GetObject FAILS for a bad %Date -- the opposite of the %Integer case")
    Do $$$AssertNotTrue($IsObject(tObj), "and no record comes back, so there is nothing to route")
    Set tText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tText [ "ZODAT", "it is a <ZODAT> exception wrapped in a status: " _ $Extract(tText, 1, 130))
    Do $$$AssertTrue(tText [ "DisplayToLogical", "and it names a GENERATED method, not your field or your file: " _ $Extract(tText, 1, 130))
    Quit $$$OK
}

/// Field count is not checked. Too few leaves the rest empty; too many discards the extras.
Method TestFieldCountIsNotChecked() As %Status
{
    Set tSC = ..Parse("P5,12", .tShort)
    Do $$$AssertStatusOK(tSC, "a record with TOO FEW fields parses clean")
    Do $$$AssertEquals(tShort.Ward, "", "the missing trailing fields are simply empty")
    Do $$$AssertStatusOK(tShort.%ValidateObject(), "and it VALIDATES, because empty is a legal %Integer")
    Set tSC = ..Parse("P6,12,64000,ICU,EXTRA,MORE", .tLong)
    Do $$$AssertStatusOK(tSC, "a record with TOO MANY fields also parses clean")
    Do $$$AssertEquals(tLong.Ward, "ICU", "the mapped fields are right")
    Do $$$AssertStatusOK(tLong.%ValidateObject(), "and the extras are DISCARDED with no status, no log and no exception")
    Quit $$$OK
}

/// Build the message a validating transform takes, as the fields arrive: strings.
ClassMethod Raw(pId As %String, pBeds As %String, pAdmitted As %String, pWard As %String) As Example.MSG.CensoValidated [ Private ]
{
    Set tMsg = ##class(Example.MSG.CensoValidated).%New()
    Set tMsg.PatientId = pId
    Set tMsg.BedsRaw = pBeds
    Set tMsg.AdmittedRaw = pAdmitted
    Set tMsg.Ward = pWard
    Quit tMsg
}

/// A good record comes out valid, with the typed property filled.
Method TestTransformPassesAGoodRecord() As %Status
{
    Set tSC = ##class(Example.DT.CensoValidateFlags).Transform(..Raw("P1", "12", "2026-09-19", "ICU"), .tOut)
    Do $$$AssertStatusOK(tSC, "the transform ran")
    Do $$$AssertEquals(tOut.IsValid, 1, "a good record is valid")
    Do $$$AssertEquals(tOut.Problems, "", "with no problems recorded: <" _ tOut.Problems _ ">")
    Do $$$AssertEquals(tOut.Beds, 12, "and the typed property is filled")
    Quit $$$OK
}

/// A bad number still becomes a message -- which is the point.
Method TestTransformFlagsABadNumberInsteadOfDropping() As %Status
{
    Set tSC = ##class(Example.DT.CensoValidateFlags).Transform(..Raw("P2", "ABC", "2026-09-19", "ICU"), .tOut)
    Do $$$AssertStatusOK(tSC, "the transform SUCCEEDS -- the record is not dropped")
    Do $$$AssertTrue($IsObject(tOut), "and a message exists, so Visual Trace has something to show")
    Do $$$AssertEquals(tOut.IsValid, 0, "flagged invalid")
    Do $$$AssertTrue(tOut.Problems [ "not a number", "with the reason: " _ tOut.Problems)
    Do $$$AssertEquals(tOut.Beds, "", "and the typed property is left UNSET, so no consumer reads a value the transform rejected")
    Do $$$AssertEquals(tOut.BedsRaw, "ABC", "while the raw text is preserved for the human who has to fix it")
    Quit $$$OK
}

/// A bad date is flagged, not raised -- the case `%Date` could not give you.
Method TestTransformFlagsABadDateInsteadOfRaising() As %Status
{
    Set tRaised = ""
    Try {
        Set tSC = ##class(Example.DT.CensoValidateFlags).Transform(..Raw("P4", "12", "NOTADATE", "ICU"), .tOut)
    }
    Catch tException {
        Set tRaised = tException.Name
    }
    Do $$$AssertEquals(tRaised, "", "the transform does not RAISE on a bad date, unlike the %Date field: " _ tRaised)
    Do $$$AssertStatusOK(tSC, "it returns OK")
    Do $$$AssertEquals(tOut.IsValid, 0, "with the record flagged invalid")
    Do $$$AssertTrue(tOut.Problems [ "not a date", "and the reason named: " _ tOut.Problems)
    Quit $$$OK
}

/// Every reason is reported, not just the first.
Method TestAllProblemsAreReported() As %Status
{
    Set tSC = ##class(Example.DT.CensoValidateFlags).Transform(..Raw("", "ABC", "NOTADATE", "ICU"), .tOut)
    Do $$$AssertStatusOK(tSC, "the transform ran")
    Do $$$AssertEquals(tOut.IsValid, 0, "flagged invalid")
    Do $$$AssertTrue(tOut.Problems [ "PatientId", "reports the empty id: " _ tOut.Problems)
    Do $$$AssertTrue(tOut.Problems [ "not a number", "AND the bad number")
    Do $$$AssertTrue(tOut.Problems [ "not a date", "AND the bad date -- three reasons, not one")
    // POSITIVE CONTROL: the separator really is there, so "contains all three" is not one long accident.
    Do $$$AssertEquals($Length(tOut.Problems, "; "), 3, "as three separated clauses: " _ tOut.Problems)
    Quit $$$OK
}

/// An empty value is distinguished from an invalid one -- they need different fixes.
Method TestEmptyIsReportedSeparatelyFromInvalid() As %Status
{
    Set tSC = ##class(Example.DT.CensoValidateFlags).Transform(..Raw("P3", "", "2026-09-19", "ICU"), .tOut)
    Do $$$AssertStatusOK(tSC, "the transform ran")
    Do $$$AssertTrue(tOut.Problems [ "Beds is empty", "an empty number says EMPTY: " _ tOut.Problems)
    Do $$$AssertNotTrue(tOut.Problems [ "not a number", "and not 'not a number', which would send the reader looking at the value")
    Quit $$$OK
}

}
