/// Rule: BestPractices_Interop_IRIS.md §2.11 "Symbolic HL7 field paths — and why an empty result proves nothing"
/// Validity: Verified against IRIS for Health 2026.1 — paths resolved against the stock 2.5 schema.
/// Severity: High (a mistyped path and an empty field are indistinguishable by value).
///
/// Pattern: a DTL over an HL7 v2 message using SYMBOLIC field paths. Until this file the bank's
/// only DTL was object→object, in a plugin whose primary subject is HL7.
///
/// WHAT `sourceDocType` BUYS, and it is the whole reason to set it: with a DocType assigned, the
/// `{...}` paths below may be written by NAME. Without one, only numeric paths resolve and the
/// transform becomes `{PID:5(1).2}` — correct, and unreadable at review time, which is where HL7
/// transforms are actually checked.
///
/// THE COMPILER CANNOT HELP YOU HERE. Measured on 2026.1: this class compiles with
/// `{PID:PatientName(1).FamilyName.Surname}` and compiles JUST AS CLEANLY with
/// `{PID:PatientNameXX(1).FamilyName.Surname}`, which resolves to nothing. Tier 2 is green on
/// both. The only thing that separates them is running the transform and asserting the output —
/// see tdd-hl7-fixture-test.cls beside this file.
///
/// AND THE RESULT IS AMBIGUOUS. Measured with GetValueAt on the same message:
///     PID:PatientIdentifierList(1).IDNumber  -> "12345"  status OK
///     PID:PatientIdentifierList(1).ID        -> ""       status ERROR "PropertyPath ... is invalid"
///     PID:PatientID  (real field, empty here) -> ""      status OK
/// Both mistakes and empty fields yield "". The status is the only discriminator, and the two-arg
/// `GetValueAt(path)` — the form everyone writes, and the form a DTL `<assign>` generates —
/// DISCARDS it. That is why "the assertion passed on an empty string" is the characteristic way an
/// HL7 transform is wrong.
///
/// NOTE `.IDNumber`, NOT `.ID`. The field name `PatientIdentifierList` is right and the obvious
/// component name is wrong — a reminder that guessing the second half of a path is as risky as
/// guessing the first, and fails the same silent way.
///
/// `create='copy'` carries every segment the transform does not touch. For an ADT passing through
/// a normalisation step that is what you want; `create='new'` starts from an empty message and
/// silently drops everything you did not explicitly assign.
Class Example.DT.AdtNormalise Extends Ens.DataTransformDTL [ DependsOn = EnsLib.HL7.Message ]
{

/// Report a path that does not resolve rather than absorbing it. The default leaves a bad path
/// looking exactly like an empty field, which is the ambiguity described above.
Parameter REPORTERRORS = 1;

Parameter IGNOREMISSINGSOURCE = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message' sourceDocType='2.5:ADT_A01' targetDocType='2.5:ADT_A01' create='copy' language='objectscript' >
<assign value='$ZCONVERT(source.{PID:PatientName(1).FamilyName.Surname},"U")' property='target.{PID:PatientName(1).FamilyName.Surname}' action='set' />
<assign value='$ZCONVERT(source.{PID:PatientName(1).GivenName},"U")' property='target.{PID:PatientName(1).GivenName}' action='set' />
<assign value='source.{PID:PatientIdentifierList(1).IDNumber}' property='target.{PID:PatientIdentifierList(1).IDNumber}' action='set' />
</transform>
}

}
