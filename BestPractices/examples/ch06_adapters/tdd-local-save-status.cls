/// Rule: BestPractices_Interop_IRIS.md §6.14 "The adapter-less BO — and the discarded `%Save()` status that reports success"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (the defect it isolates completes the message and writes nothing).
///
/// Pattern: the oracle for `bo-local-object-save.cls` in this directory.
///
/// THE ONE ASSERTION A COMPILE CANNOT MAKE. `Do obj.%Save()` and `Set sc = obj.%Save()` differ by one
/// character and both compile. They differ only in what a caller learns when the save FAILS, so the
/// test needs a save that reliably fails — and `Example.DAT.Address.PostCode` is `MAXLEN = 10`,
/// which §5.15 established rejects an 11th character with `#7201` rather than truncating. That gives
/// a deterministic failure with no mocking and no external state.
///
/// MEASURED, both forms against the same over-long PostCode:
///
///     Set tSC = tAddr.%Save()  /  Return tSC   ->  #7201 returned, NO row written
///     Do tAddr.%Save()         /  Return $$$OK ->  $$$OK returned, NO row written
///
/// Identical outcome in the database; opposite outcome for the operator. The first errors the message
/// and shows up; the second completes it, leaves the Event Log empty, and the row is simply absent.
///
/// THE POSITIVE CONTROL IS NOT OPTIONAL HERE. Every assertion below about a failed save is worthless
/// unless a SUCCESSFUL save has been seen to write a row through the same path — otherwise "no row"
/// could mean the BO never writes anything at all. `TestGoodAddressIsSaved` is that control, and it
/// reads the row back by the id the BO returns rather than trusting the status.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                       PASSED 7/7
///     `Set tSC = tAddr.%Save()` -> `Do tAddr.%Save()`    TestFailedSaveIsReported       FAILS
///     unmapped request returns $$$OK                    TestUnmappedRequestErrors      FAILS
///     the row id is not returned                        TestGoodAddressIsSaved         FAILS
///     the missing-address guard removed                 TestMissingAddressIsNotAnError FAILS
///
/// All five versions compile, so tier 2 is green on every one of them -- including the one that
/// completes a message having written nothing, and the one that writes a junk row.
///
/// THAT LAST MUTATION PASSED AT FIRST, and the reason is recorded on AddressCount() below: the
/// count was filtered (`WHERE City = 'Barcelona'`) and the defect writes an EMPTY row, which fell
/// outside the predicate. The assertion could not see the row it existed to catch. A mutation that
/// passes is either a guard that does nothing or a test that looks in the wrong place -- and the
/// only way to tell is to measure what the unguarded version actually does.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.LocalSaveStatus", namespace="<NS>")
Class Example.Tests.LocalSaveStatus Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// %New() ON AN Ens.BusinessOperation SUBCLASS NEEDS A CONFIG NAME. Measured:
///     ##class(Example.BO.LocalSave).%New()                -> "", $IsObject = 0, NO error
///     ##class(Example.BO.LocalSave).%New("BO.LocalSave")  -> a live instance
/// The bank already recorded this for `Ens.BusinessService` (section 5.2, v1.18.0); it is the same
/// for an operation, and it was found here by walking into it. The failure is not an error you can
/// read: the argument-less form hands back "", the next line calls a method on it, and the test
/// method THROWS -- which %UnitTest records as a failed method with ZERO failed assertions, so the
/// verdict reader showed `failedAsserts=0` beside four failed methods. A test that throws and a
/// test that asserts false do not look alike; when the assert count is zero, suspect the setup
/// rather than the subject.
Parameter CONFIGNAME = "BO.LocalSave";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// A request carrying an address. pPostCode decides whether the save will succeed.
ClassMethod MakeRequest(pPostCode As %String) As Example.MSG.PersonReqCascade [ Private ]
{
    Set tAddr = ##class(Example.DAT.Address).%New()
    Set tAddr.Street = "Main St"
    Set tAddr.City = "Barcelona"
    Set tAddr.PostCode = pPostCode

    Set tReq = ##class(Example.MSG.PersonReqCascade).%New()
    Set tReq.Name = "Ana"
    // NOT saved: the BO reads the request's address as an in-memory object. §5.15 measured that an
    // over-long value survives in memory untouched and is refused only at the persistence boundary,
    // which is why an invalid PostCode can travel this far at all.
    Set tReq.Address = tAddr
    Quit tReq
}

/// EVERY row in the target table, deliberately unfiltered.
///
/// The first version of this counted `WHERE City = 'Barcelona'`, and that made
/// TestMissingAddressIsNotAnError VACUOUS: removing the BO's missing-address guard writes an EMPTY
/// row (City = ''), which fell outside the predicate, so the assertion could not see the very row it
/// existed to catch. Measured -- the mutation passed. An assertion that counts a FILTERED subset
/// cannot detect a defect that produces rows outside the filter.
ClassMethod AddressCount() As %Integer [ Private ]
{
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM Example_DAT.Address)
    Quit +$Get(tN)
}

/// THE POSITIVE CONTROL. A valid address is saved, and the row is read back by the id the BO
/// returned -- not merely inferred from a clean status.
Method TestGoodAddressIsSaved()
{
    Set tBefore = ..AddressCount()
    Set tReq = ..MakeRequest("08001")

    Set tSC = ##class(Example.BO.LocalSave).%New(..#CONFIGNAME).SaveAddress(tReq, .tResp)
    Do $$$AssertStatusOK(tSC, "a valid address must save")
    Do $$$AssertNotEquals($Get(tResp), $$$NULLOREF, "a response must come back")
    Do $$$AssertNotEquals(tResp.StringValue, "", "and it must carry the new row's id")

    Do $$$AssertEquals(##class(Example.DAT.Address).%ExistsId(tResp.StringValue), 1, "the id must name a real row")
    Do $$$AssertEquals(..AddressCount(), tBefore + 1, "and the table must have grown by exactly one")
}

/// THE POINT. An over-long PostCode fails the save, and the BO must SAY so.
Method TestFailedSaveIsReported()
{
    Set tBefore = ..AddressCount()
    // 11 characters against MAXLEN = 10.
    Set tReq = ..MakeRequest("123456789AB")

    Set tSC = ##class(Example.BO.LocalSave).%New(..#CONFIGNAME).SaveAddress(tReq, .tResp)

    Do $$$AssertStatusNotOK(tSC, "a failed save must be REPORTED, not swallowed")
    Do $$$AssertEquals($System.Status.GetErrorCodes(tSC), 7201, "and the reason must be the #7201 that names the field")
    Do $$$AssertEquals(..AddressCount(), tBefore, "no row may be written")
}

/// The same failure with the status DISCARDED -- the defect, reproduced locally so the contrast is
/// executed rather than described. This is what `Do tAddr.%Save()` buys you.
Method TestDiscardedStatusLooksLikeSuccess()
{
    Set tBefore = ..AddressCount()

    Set tAddr = ##class(Example.DAT.Address).%New()
    Set tAddr.Street = "Main St"
    Set tAddr.City = "Barcelona"
    Set tAddr.PostCode = "123456789AB"
    Do tAddr.%Save()                     // the defect: status discarded
    Set tPretendStatus = $$$OK           // ... and the method returns OK

    Do $$$AssertStatusOK(tPretendStatus, "the discarding form reports success")
    Do $$$AssertEquals(..AddressCount(), tBefore, "while writing nothing -- identical database outcome, opposite report")
}

/// An unmapped request must ERROR, not be quietly accepted.
Method TestUnmappedRequestErrors()
{
    Set tWrong = ##class(Ens.StringRequest).%New()
    Set tWrong.StringValue = "not a PersonReq"

    Set tSC = ##class(Example.BO.LocalSave).%New(..#CONFIGNAME).OnMessage(tWrong, .tResp)
    Do $$$AssertStatusNotOK(tSC, "an unhandled request type must be an error, not $$$OK")
}

/// A request with no address is not a failure -- and must write NOTHING.
///
/// The second half is the load-bearing one, and not for the reason the guard's comment first gave.
/// Measured on an unset reference: `pRequest.Address` is "" with `$IsObject = 0`, and reading
/// `.Street` off it returns "" with NO error -- ObjectScript does not raise `<INVALID OREF>` here.
/// So an unguarded BO does not fail; it copies three empty strings into a new object and SAVES it,
/// producing a junk row with every column blank and reporting success. A third silent mode, and the
/// quietest of the three: the message completes, the status is OK, and the table grows.
Method TestMissingAddressIsNotAnError()
{
    Set tBefore = ..AddressCount()
    Set tReq = ##class(Example.MSG.PersonReqCascade).%New()
    Set tReq.Name = "NoAddress"

    Set tSC = ##class(Example.BO.LocalSave).%New(..#CONFIGNAME).SaveAddress(tReq, .tResp)
    Do $$$AssertStatusOK(tSC, "nothing to save is not a failed save")
    Do $$$AssertEquals(..AddressCount(), tBefore, "and NO row is written -- not even an empty one")
}

/// The shape itself: this BO declares no adapter.
Method TestNoAdapterIsDeclared()
{
    Do $$$AssertEquals($parameter("Example.BO.LocalSave", "ADAPTER"), "", "the adapter-less BO declares no ADAPTER")
    // Control: a BO that DOES declare one reads back non-empty, so the assertion above is not
    // passing because $parameter always returns "".
    Do $$$AssertNotEquals($parameter("Example.BO.RestOutbound", "ADAPTER"), "", "control: an adapter-bearing BO reports its adapter")
}

}
