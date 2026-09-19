/// Rule: BestPractices_Interop_IRIS.md §5.24 "A message carrying the same data twice: fill both, and never read the collection as a scalar"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (one side silently empty, the other silently an OREF).
///
/// Pattern: the oracle for `dtl-fill-both-representations.cls`. No production: a DTL is a class with a
/// `Transform()` entry point, so it can be exercised directly, which makes every failure here about the
/// transform and nothing else.
///
/// THE TWO FAILURE MODES ARE ASSERTED, not described. `TestFillingOnlyTheListLeavesTheLegacySideEmpty`
/// and `TestTheCollectionAsAScalarIsAnOrefNotEmpty` construct the defect by hand and pin what a consumer
/// would see — because a reader who only sees the correct transform cannot tell which parts of it are
/// load-bearing.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=406  8 methods, 0 failed
///     the legacy side is never filled             run=407  4 failed
///     Serialize() dropped from the bridge         run=408  5 failed
///     the delimiter-collision check removed       run=409  1 failed
///     the collection is 'set' not 'append'        run=410  4 failed
///     reverted                                    run=411  8 methods, 0 failed
///
/// THE FIRST VERSION OF THIS SUITE HAD A SURVIVING MUTANT, and it changed the sample. Removing the
/// transform's `$select(Count()=0:"", ...)` empty-collection guard left everything green -- because that
/// guard is INERT. Chasing it produced the delimiter-collision finding, which is the real check, and the
/// inert one was deleted. A guard nothing can break is a guard that does nothing.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.FillBothRepresentations", namespace="<NS>")
Class Example.Tests.FillBothRepresentations Extends %UnitTest.TestCase
{

/// Build a source message holding ONLY the typed representation.
ClassMethod Source(pItems As %String = "PEN,LATEX") As Example.MSG.SuppliesOrder [ Private ]
{
    Set tMsg = ##class(Example.MSG.SuppliesOrder).%New()
    Set tMsg.OrderId = "ORD-1"
    For i = 1:1:$Length(pItems, ",") {
        Continue:$Piece(pItems, ",", i)=""
        Do tMsg.SupplyList.Insert($Piece(pItems, ",", i))
    }
    Quit tMsg
}

/// The transform fills BOTH sides.
Method TestTransformFillsBothRepresentations() As %Status
{
    Set tSource = ..Source()
    // POSITIVE CONTROL: the source really carries the typed side and NOT the legacy one, so the
    // assertions below are about the transform rather than about the input.
    Do $$$AssertEquals(tSource.SupplyList.Count(), 2, "POSITIVE CONTROL: the source has two typed items")
    Do $$$AssertEquals(tSource.Supplies, "", "POSITIVE CONTROL: and an empty legacy string")
    Set tSC = ##class(Example.DT.FillBothRepresentations).Transform(tSource, .tTarget)
    Do $$$AssertStatusOK(tSC, "the transform ran")
    Do $$$AssertTrue($IsObject(tTarget), "and produced a target")
    Do $$$AssertEquals(tTarget.SupplyList.Count(), 2, "the typed side is carried across")
    Do $$$AssertEquals(tTarget.Supplies, "PEN|LATEX", "and the LEGACY side is filled from it, got: " _ tTarget.Supplies)
    Quit $$$OK
}

/// An empty collection yields an empty string -- and needs NO guard to do so.
Method TestAnEmptyCollectionNeedsNoGuard() As %Status
{
    Set tSource = ..Source("")
    Do $$$AssertEquals(tSource.SupplyList.Count(), 0, "POSITIVE CONTROL: the source collection really is empty")
    Set tSC = ##class(Example.DT.FillBothRepresentations).Transform(tSource, .tTarget)
    Do $$$AssertStatusOK(tSC, "the transform ran on an empty collection")
    Do $$$AssertEquals(tTarget.Supplies, "", "and produced an empty legacy string, got: <" _ tTarget.Supplies _ ">")
    // WHY THERE IS NO GUARD FOR THIS. The defensive `$select(Count()=0:"", ...)` is inert: the two
    // primitives already yield "" on their own. Asserted so nobody re-adds it believing it does work.
    Do $$$AssertEquals(tSource.SupplyList.Serialize(), "", "Serialize() of an empty collection is already empty")
    Do $$$AssertEquals($ListToString(tSource.SupplyList.Serialize(), "|"), "", "and $ListToString of that is already empty")
    Quit $$$OK
}

/// THE LOSSY CASE. An item containing the delimiter cannot be expressed, so the transform refuses.
Method TestAnItemContainingTheDelimiterIsRejected() As %Status
{
    Set tMsg = ##class(Example.MSG.SuppliesOrder).%New()
    Set tMsg.OrderId = "ORD-2"
    Do tMsg.SupplyList.Insert("PEN|LATEX")
    Do tMsg.SupplyList.Insert("GAUZE")
    Set tSC = ##class(Example.DT.FillBothRepresentations).Transform(tMsg, .tTarget)
    Do $$$AssertNotTrue($$$ISOK(tSC), "the transform REFUSES an item that contains the delimiter")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "contains the delimiter", "and says why: " _ $System.Status.GetErrorText(tSC))
    // WHAT IT WOULD HAVE PRODUCED, so the reason is on the record and not just asserted.
    Set tWould = $ListToString(tMsg.SupplyList.Serialize(), "|")
    Do $$$AssertEquals(tWould, "PEN|LATEX|GAUZE", "unchecked it would serialise to a string reading as THREE items: " _ tWould)
    Do $$$AssertEquals($Length(tWould, "|"), 3, "which is 3 fields from 2 items -- lossy, and silent")
    // POSITIVE CONTROL: the same two-item shape WITHOUT a collision is accepted, so the refusal above
    // is about the delimiter and not about having two items.
    Set tOk = ##class(Example.DT.FillBothRepresentations).Transform(..Source("PEN,GAUZE"), .tFine)
    Do $$$AssertStatusOK(tOk, "POSITIVE CONTROL: two clean items transform fine")
    Do $$$AssertEquals(tFine.Supplies, "PEN|GAUZE", "into two fields")
    Quit $$$OK
}

/// One item produces no delimiter at all.
Method TestOneItemHasNoDelimiter() As %Status
{
    Set tSC = ##class(Example.DT.FillBothRepresentations).Transform(..Source("PEN"), .tTarget)
    Do $$$AssertStatusOK(tSC, "the transform ran")
    Do $$$AssertEquals(tTarget.Supplies, "PEN", "a single item is just the item, got: <" _ tTarget.Supplies _ ">")
    Quit $$$OK
}

/// FAILURE MODE 1, constructed by hand: fill only the typed side and a legacy consumer sees "".
Method TestFillingOnlyTheListLeavesTheLegacySideEmpty() As %Status
{
    Set tMsg = ..Source()
    Do $$$AssertEquals(tMsg.SupplyList.Count(), 2, "POSITIVE CONTROL: the data IS on the message")
    Do $$$AssertEquals(tMsg.Supplies, "", "yet the legacy property is empty")
    Do $$$AssertEquals($Length(tMsg.Supplies), 0, "with length 0 -- nothing raises, nothing logs")
    // what the legacy consumer computes from it
    Do $$$AssertEquals($Piece(tMsg.Supplies, "|", 1), "", "so $Piece over it yields an empty first field")
    Quit $$$OK
}

/// FAILURE MODE 2, the worse one: the collection read as a scalar is an OREF, which is NOT empty.
Method TestTheCollectionAsAScalarIsAnOrefNotEmpty() As %Status
{
    Set tMsg = ..Source()
    Set tScalar = $Piece(tMsg.SupplyList, "|", 1)
    Do $$$AssertNotEquals(tScalar, "", "reading the collection as a scalar does NOT give an empty string: <" _ tScalar _ ">")
    Do $$$AssertTrue(tScalar [ "%Collection.ListOfDT", "it gives an OREF, which renders as NN@%Collection.ListOfDT: " _ tScalar)
    // The consequence, stated as the guard that fails: a non-empty check passes on garbage.
    Do $$$AssertTrue(tScalar '= "", "so a guard written as `if value '= """"` PASSES on that OREF and forwards it as data")
    Quit $$$OK
}

/// The bridge's own gotcha: $ListToString needs Serialize(), or it raises <LIST>.
Method TestListToStringNeedsSerialize() As %Status
{
    Set tMsg = ..Source()
    Set tRaised = ""
    Try {
        Set tBad = $ListToString(tMsg.SupplyList, "|")
    }
    Catch tException {
        Set tRaised = tException.Name
    }
    Do $$$AssertEquals(tRaised, "<LIST>", "$ListToString on the collection itself raises <LIST>, got: " _ $Select(tRaised="":"no error", 1:tRaised))
    // POSITIVE CONTROL: the Serialize() form works, so the raise above is about the argument and not
    // about $ListToString or the data.
    Do $$$AssertEquals($ListToString(tMsg.SupplyList.Serialize(), "|"), "PEN|LATEX", "while Serialize() first gives the delimited string")
    Quit $$$OK
}

/// The reverse direction an inbound legacy feed needs: the pair round-trips.
Method TestTheLegacyStringRoundTripsBackIntoTheCollection() As %Status
{
    Set tSC = ##class(Example.DT.FillBothRepresentations).Transform(..Source("PEN,LATEX,GAUZE"), .tTarget)
    Do $$$AssertStatusOK(tSC, "the forward transform ran")
    Do $$$AssertEquals(tTarget.Supplies, "PEN|LATEX|GAUZE", "POSITIVE CONTROL: the legacy string was built")
    // Now back, the way a legacy-inbound transform would.
    Set tBack = ##class(Example.MSG.SuppliesOrder).%New()
    Set tBack.Supplies = tTarget.Supplies
    For i = 1:1:$Length(tBack.Supplies, "|") { Do tBack.SupplyList.Insert($Piece(tBack.Supplies, "|", i)) }
    Do $$$AssertEquals(tBack.SupplyList.Count(), 3, "the string splits back into the same number of items")
    Do $$$AssertEquals(tBack.SupplyList.GetAt(1), "PEN", "in order, first item")
    Do $$$AssertEquals(tBack.SupplyList.GetAt(3), "GAUZE", "and last item")
    Quit $$$OK
}

}
