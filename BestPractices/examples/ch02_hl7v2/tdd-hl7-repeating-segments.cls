/// Rule: BestPractices_Interop_IRIS.md §2.14 "Repeating segments: iterate by index, and the group path fails with an error status"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN with three repeats.
/// Severity: High (the failure it guards is a successful transform that produced nothing).
///
/// Pattern: the oracle for `dtl-hl7-repeating-segments.cls` and its sub-transform.
///
/// THE CENTRAL ASSERTION IS A COUNT, NOT AN ABSENCE. A repeat loop whose bound is wrong, or whose
/// filter never matches, leaves the target empty and returns `$$$OK` — the message completes, the trace
/// is clean, and nothing surfaces. `TestThreeRepeatsLand` asserts **three** entries with their values;
/// an assertion of the form "the transform did not error" passes against a transform that did nothing,
/// and `TestZeroRepeatsStillSucceeds` proves that by showing a no-OBX message transform cleanly to an
/// empty list.
///
/// AND THE GROUP TRAP IS ASSERTED WITH ITS STATUS. The skills framed it as returning empty with no
/// error; measured, both forms set an error status, so it is silent only for a caller that discards one.
/// `GetValueAt`'s status is its **third by-reference argument**, which is exactly the one a `<code>`
/// block omits.
///
/// MEASURED VALUES this pins, from the run that preceded it:
///     PatientId='12345'  count=3  [Glucose: 5.5 mmol/L] [Sodium: 140 mmol/L] [Potassium: 4.1 mmol/L]
///     GetSegmentAt("OBX(1)")   -> no object, error status
///     GetValueAt("OBX(1):3.2") -> "",        error status
///     every message-level PID path             -> "", error status
///     the index route to PID 3.1               -> '12345'
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  PASSED 6/6
///     the filter never matches (Name="OBZ")        TestThreeRepeatsLand +
///                                                TestZeroRepeatsStillSucceeds      FAIL
///     the sub-transform result is not Inserted     the same two                     FAIL
///     PID read via a message-level path again      TestIndexRouteIsNeededForGroupedSingles FAILS
///     the sub-transform reads field 3.9 not 3.2    TestSubTransformTakesASegment +
///                                                TestThreeRepeatsLand              FAIL
///
/// ONE MUTATION PASSED, AND IT IS NOT A GAP. Changing the loop to `for i = 2:1:source.SegCount`
/// leaves the suite green — because segment 1 of an HL7 message is always `MSH`, which is neither an
/// `OBX` nor a `PID`, so skipping it is **behaviourally identical** for this transform. That is a
/// mutation that does not mutate, not an assertion that is missing: no input reachable through this
/// DTL distinguishes the two versions. Recorded rather than papered over, because a passing mutation
/// has to be explained one way or the other, and "the test is weak" is only one of the two
/// explanations.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.Hl7RepeatingSegments", namespace="<NS>")
Class Example.Tests.Hl7RepeatingSegments Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// An ORU_R01 with pHowManyObx observation repeats.
ClassMethod MakeOru(pHowManyObx As %Integer, Output pDoc) As %Status [ Private ]
{
    Set tCR = $Char(13)
    Set t = "MSH|^~\&|LAB|F|HIS|F|20260101120000||ORU^R01|M1|P|2.5" _ tCR
    Set t = t _ "PID|1||12345^^^MRN||DOE^JOHN" _ tCR
    Set t = t _ "OBR|1||A1|PANEL^Chemistry" _ tCR
    If pHowManyObx >= 1 { Set t = t _ "OBX|1|NM|GLU^Glucose||5.5|mmol/L" _ tCR }
    If pHowManyObx >= 2 { Set t = t _ "OBX|2|NM|NA^Sodium||140|mmol/L" _ tCR }
    If pHowManyObx >= 3 { Set t = t _ "OBX|3|NM|K^Potassium||4.1|mmol/L" _ tCR }
    Set pDoc = ##class(EnsLib.HL7.Message).ImportFromString(t, .tSC)
    Quit:$$$ISERR(tSC) tSC
    Quit pDoc.DocTypeSet("2.5:ORU_R01")
}

/// THE POINT. Three repeats in, three entries out, with their values.
Method TestThreeRepeatsLand()
{
    Do $$$AssertStatusOK(..MakeOru(3, .tMsg))
    Set tSC = ##class(Example.DT.OruToObsSummary).Transform(tMsg, .tOut)

    Do $$$AssertStatusOK(tSC, "the transform must succeed")
    Do $$$AssertEquals($IsObject(tOut), 1, "and produce a target")
    Do $$$AssertEquals(tOut.Observations.Count(), 3, "THREE repeats must land -- a count, not an absence")

    Do $$$AssertEquals(tOut.Observations.GetAt(1), "Glucose: 5.5 mmol/L", "first repeat, formatted by the sub-transform")
    Do $$$AssertEquals(tOut.Observations.GetAt(2), "Sodium: 140 mmol/L", "second")
    Do $$$AssertEquals(tOut.Observations.GetAt(3), "Potassium: 4.1 mmol/L", "third")
}

/// THE REASON THE COUNT MATTERS. A message with no OBX transforms CLEANLY to an empty list -- so
/// "it did not error" is not evidence that anything was processed.
Method TestZeroRepeatsStillSucceeds()
{
    Do $$$AssertStatusOK(..MakeOru(0, .tMsg))
    Set tSC = ##class(Example.DT.OruToObsSummary).Transform(tMsg, .tOut)

    Do $$$AssertStatusOK(tSC, "a message with NO repeats still transforms successfully -- this is the trap")
    Do $$$AssertEquals(tOut.Observations.Count(), 0, "and produces an empty list, with nothing to surface")

    // So the only thing separating this from a broken loop is the COUNT.
    Do $$$AssertStatusOK(..MakeOru(3, .tThree))
    Do $$$AssertStatusOK(##class(Example.DT.OruToObsSummary).Transform(tThree, .tOut3))
    Do $$$AssertNotEquals(tOut3.Observations.Count(), tOut.Observations.Count(), "three repeats and zero repeats differ ONLY in the count")
}

/// The grouped path fails, and it SETS AN ERROR STATUS.
Method TestGroupedPathFailsWithAnErrorStatus()
{
    Do $$$AssertStatusOK(..MakeOru(3, .tMsg))

    Set tSegSC = 1
    Set tSeg = tMsg.GetSegmentAt("OBX(1)", .tSegSC)
    Do $$$AssertEquals($IsObject(tSeg), 0, "a message-level path to a GROUPED segment returns no object")
    Do $$$AssertStatusNotOK(tSegSC, "and it SETS AN ERROR STATUS -- not silent, unless you discard it")

    Set tValSC = 1
    Set tVal = tMsg.GetValueAt("OBX(1):3.2", , .tValSC)
    Do $$$AssertEquals(tVal, "", "GetValueAt on the same path returns empty")
    Do $$$AssertStatusNotOK(tValSC, "with an error status in its THIRD by-reference argument")

    // The control: the index route reaches the very same segment.
    Set tReached = 0
    For i = 1:1:tMsg.SegCount {
        Set tS = tMsg.GetSegmentAt(i)
        If $IsObject(tS), tS.Name = "OBX" {
            Set tReached = tReached + 1
        }
    }
    Do $$$AssertEquals(tReached, 3, "control: the index route reaches all three, so the segments do exist")
}

/// In a grouped message the index route is needed for SINGLE segments too, not only repeats.
Method TestIndexRouteIsNeededForGroupedSingles()
{
    Do $$$AssertStatusOK(..MakeOru(3, .tMsg))

    // PID is inside PATIENT_RESULT -> PATIENT in an ORU_R01. Every message-level path fails.
    For tPath = "PID:3.1", "PID:PatientIdentifierList(1).IDNumber", "PID:PatientName(1).FamilyName" {
        Set tSC = 1
        Set tV = tMsg.GetValueAt(tPath, , .tSC)
        Do $$$AssertEquals(tV, "", "message-level path '" _ tPath _ "' yields empty on a grouped PID")
        Do $$$AssertStatusNotOK(tSC, "and sets an error status")
    }

    // The index route reaches it, which is what the shipped DTL does.
    Set tFound = ""
    For i = 1:1:tMsg.SegCount {
        Set tS = tMsg.GetSegmentAt(i)
        If $IsObject(tS), tS.Name = "PID" {
            Set tFound = tS.GetValueAt("3.1")
        }
    }
    Do $$$AssertEquals(tFound, "12345", "the index route reaches the grouped PID")

    // And the transform gets it, which is the end-to-end proof.
    Do $$$AssertStatusOK(##class(Example.DT.OruToObsSummary).Transform(tMsg, .tOut))
    Do $$$AssertEquals(tOut.PatientId, "12345", "so the target's PatientId is populated, not empty")
}

/// The sub-transform takes a SEGMENT, so it needs no index and no group.
Method TestSubTransformTakesASegment()
{
    Do $$$AssertStatusOK(..MakeOru(1, .tMsg))

    Set tSeg = ""
    For i = 1:1:tMsg.SegCount {
        Set tS = tMsg.GetSegmentAt(i)
        If $IsObject(tS), tS.Name = "OBX" {
            Set tSeg = tS
        }
    }
    Do $$$AssertEquals($IsObject(tSeg), 1, "control: an OBX segment was isolated")

    Set tSC = ##class(Example.DT.ObxToText).Transform(tSeg, .tText)
    Do $$$AssertStatusOK(tSC, "the sub-transform runs on one segment")
    Do $$$AssertEquals(tText.StringValue, "Glucose: 5.5 mmol/L", "and formats it")

    // Relative to a segment, numeric paths need no index -- the thing that makes it reusable.
    Do $$$AssertEquals(tSeg.GetValueAt("3.2"), "Glucose", "a segment-relative numeric path just works")
}

}
