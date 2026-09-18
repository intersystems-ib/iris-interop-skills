/// Rule: BestPractices_Interop_IRIS.md §2.14 "Repeating segments: iterate by index, and the group path fails with an error status"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed with three repeats.
/// Severity: High (the zero-iteration form completes successfully and produces nothing).
///
/// Pattern: the repeating-segment transform. Every version of this in the plugin was outside the gate
/// — loose fragments and ```xml fences, neither of which any tier compiles — so the shape people
/// actually copy had never been run.
///
/// THE WORST FAILURE MODE IS A SUCCESSFUL TRANSFORM THAT PROCESSED NOTHING. A loop whose bound is
/// wrong, or whose filter never matches, leaves the target empty and returns `$$$OK`. The message
/// completes, the Visual Trace is clean, and the collection has no entries. Nothing surfaces. That is
/// why the companion test asserts **three** entries rather than "no error" — an absence assertion
/// passes against a transform that did nothing at all.
///
/// ITERATE BY INDEX AND FILTER BY NAME. `source.SegCount` bounds it; `seg.Name` selects. In a grouped
/// message this is not merely how you enumerate REPEATS — it is how you reach anything below the top
/// level at all, including single segments. Measured on the ORU_R01 below, `PID` is inside
/// `PATIENT_RESULT -> PATIENT`, and **every** message-level path to it fails with an error status:
/// `PID:PatientIdentifierList(1).IDNumber`, `PID:3(1).1`, `PID:3.1`, `PID:PatientName(1).FamilyName`,
/// and four group-prefixed spellings besides. The index route returns the value. The first draft of
/// this file opened with an `<assign>` on one of those paths and shipped an empty `PatientId`:
///
///     GetSegmentAt(i) for i = 1..SegCount, filter seg.Name="OBX"   ->  reaches all three repeats
///     GetSegmentAt("OBX(1)") on an ORU_R01                         ->  NO object
///     GetValueAt("OBX(1):3.2")                                     ->  ""
///
/// AND BOTH OF THOSE FAILURES SET AN ERROR STATUS — which the skills did not say until v1.48.0, and
/// which changes how you find them. Measured:
///
///     msg.GetSegmentAt("OBX(1)", .sc)   ->  sc = ERROR <Ens>ErrGeneral: No segment found at path 'OBX(1)'
///     msg.GetValueAt("OBX(1):3.2", , .sc) -> sc = the same class of error
///
/// So this is silent only if you discard the status, and `GetValueAt`'s status is its **third
/// by-reference argument** — exactly the one a `<code>` block omits. Pass it and check it and the group
/// trap announces itself instead of looking like missing data.
///
/// WHETHER A SEGMENT IS GROUPED DEPENDS ON THE MESSAGE TYPE, which is why this example is an ORU_R01
/// and not the ADT the coverage map suggested. `NK1` and `AL1` are TOP-LEVEL in an ADT_A01, so
/// `GetSegmentAt("NK1(1)")` there returns the object and `GetValueAt("NK1(1):2.1")` returns the value —
/// the message-level path works. It is `OBX` in an ORU_R01, and `NK1` in message types that group it,
/// where the path fails. Check the structure before concluding the path form is at fault.
///
/// `DependsOn` IS MANDATORY ON A DTL — §5.13 and tier-1 C13. Without it this compiles alone and fails
/// the moment an unrelated error perturbs a batch compile, which is how `dtl-order-to-vendor` shipped
/// broken for several releases.
Class Example.DT.OruToObsSummary Extends Ens.DataTransformDTL [ DependsOn = (EnsLib.HL7.Message, Example.MSG.ObsSummary, Example.DT.ObxToText) ]
{

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='Example.MSG.ObsSummary' sourceDocType='2.5:ORU_R01' create='new' language='objectscript' >
<code>
<![CDATA[
 // ONE LOOP FOR BOTH JOBS, and PID is in it for a reason worth reading.
 //
 // The obvious first line here is an <assign> reading source.{PID:PatientIdentifierList(1).IDNumber}.
 // It was the first line here, and it silently produced EMPTY -- because in an ORU_R01 PID itself is
 // inside a group (PATIENT_RESULT -> PATIENT -> PID), so no message-level path reaches it either.
 // Measured on this exact message: PID:PatientIdentifierList(1).IDNumber, PID:3(1).1, PID:3.1 and
 // PID:PatientName(1).FamilyName ALL return "" with an error status, and four plausible
 // group-prefixed spellings -- PIDgrp(1).PID:3.1, PATIENT(1).PID:3.1,
 // PATIENT_RESULT(1).PATIENT.PID:3.1 and PATIENT_RESULT(1).PATIENT(1).PID:3.1 -- fail the same way.
 // The index route returns 12345. So in a grouped message the index route is not a fallback for
 // repeats; it is the route for anything below the top level.
 for i = 1:1:source.SegCount {
   set tSeg = source.GetSegmentAt(i, .tSegSC)
   // A status that is checked, not discarded: a gap in the index is a real condition, not a
   // reason to stop.
   continue:$$$ISERR($get(tSegSC, 1))
   continue:'$isobject(tSeg)

   // Relative to a SEGMENT there is no index and no group, so numeric paths just work.
   if tSeg.Name = "PID" {
     set target.PatientId = tSeg.GetValueAt("3.1")
     continue
   }
   continue:tSeg.Name'="OBX"

   // One repeat through the sub-transform. It takes a SEGMENT, so it never needs to know which
   // repeat this is.
   set tSC = ##class(Example.DT.ObxToText).Transform(tSeg, .tText)
   continue:$$$ISERR(tSC)
   continue:'$isobject(tText)
   do target.Observations.Insert(tText.StringValue)
 }
]]>
</code>
</transform>
}

}
