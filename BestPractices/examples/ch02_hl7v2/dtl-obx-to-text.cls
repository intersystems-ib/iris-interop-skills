/// Rule: BestPractices_Interop_IRIS.md §2.14 "Repeating segments: iterate by index, and the group path fails with an error status"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: Medium (the per-repeat sub-transform).
///
/// Pattern: the SUB-TRANSFORM — one repeat in, one string out. `component-map` prescribes exactly this
/// shape for repeating segments: source `EnsLib.HL7.Segment`, target `Ens.StringContainer`.
///
/// WHY A SEGMENT SOURCE AND NOT A MESSAGE. The caller has already isolated one repeat, so this
/// transform never has to know which repeat it is or how many there were. That is what makes it
/// reusable and testable on its own — and it is why the numeric paths below are `3.2` and `5`, not
/// `OBX(1):3.2`: relative to a SEGMENT there is no index.
///
/// NUMERIC PATHS, DELIBERATELY. §2.11 says name fields rather than numbering them, and that rule is
/// about MESSAGE-level paths where the DocType resolves names. A segment obtained from a message does
/// inherit the message's DocType — §2.11 measured `seg.DocType` coming back as `2.5:OBX` on its own —
/// so symbolic names would work here too. Numerics are used because a sub-transform declared over the
/// bare `EnsLib.HL7.Segment` class has no `sourceDocType` to resolve them against, and a DTL with no
/// DocType silently yields empty for a symbolic path. Give the sub-transform a DocType if you want
/// names; without one, numbers are the honest choice.
///
/// NAMED `ObxToText`, NOT `Al1ToText` AS THE COVERAGE MAP ASKED. Two reasons. The rename constraint in
/// the row itself forbids colliding with the snippet `MyApp.DT.AL1Subtransform`. And AL1 is
/// **top-level** in an ADT_A01, so an AL1 example cannot demonstrate the group-path trap that is the
/// other half of this rule — OBX inside an ORU_R01 is grouped, which is what makes the failure real.
Class Example.DT.ObxToText Extends Ens.DataTransformDTL [ DependsOn = (EnsLib.HL7.Segment, Ens.StringContainer) ]
{

Parameter IGNOREMISSINGSOURCE = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Segment' targetClass='Ens.StringContainer' create='new' language='objectscript' >
<assign value='source.GetValueAt("3.2")_": "_source.GetValueAt("5")_" "_source.GetValueAt("6")' property='target.StringValue' action='set' />
</transform>
}

}
