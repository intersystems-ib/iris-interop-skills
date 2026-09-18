/// Rule: BestPractices_Interop_IRIS.md §1.11 "RecordMap file intake — configure the prebuilt service, never subclass it"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (silent data corruption).
///
/// Pattern: the RecordMap DEFINITION — the only class you author for a delimited-file intake.
/// The Business Service, the poll loop and the per-record dispatch are all prebuilt; see the
/// companion production class for how it is wired.
///
/// THREE ATTRIBUTES THAT COST THE MOST ATTEMPTS, all silent when wrong:
///
///   1. fieldSeparator must be ABSENT for type="delimited". Setting the obvious
///      fieldSeparator="," fails with
///        ERROR <EnsRecordMap>ErrInvalidRecordProp: Invalid value for property
///        'fieldSeparator' in Record of type delimited
///      which reads as "your value is malformed" but means "this property must not be set
///      here". The separator goes in <Separators><Separator>.
///
///   2. recordTerminator must name the REAL line ending of the file. &#xA; is LF; CRLF is
///      &#xD;&#xA;. It is baked into the generated .Record class at compile time, so after
///      changing it you must REGENERATE — the runtime reads the compiled value, not this XML.
///      Built programmatically instead of in XData, the same value is written "\x0a" (hex
///      escape): left empty it defaults to $char(32), a SPACE, and every field containing a
///      space is silently truncated at it.
///
///   3. char_encoding must be set explicitly when the data carries non-ASCII. The platform
///      default differs across hosts, and a mismatch turns header names into mojibake
///      ("Acompanante" read as "AcompaA+-ante"), so the field mapping stops matching and the
///      map produces empty records rather than an error.
///
/// escaping="quote" + escapeSequence="&quot;" is what makes RFC-4180 quoting work, so
/// "Garcia, hijo" stays one field instead of splitting on the embedded comma.
///
/// WHAT IS NOT IN THIS FILE, and must not be hand-written: GetObject, PutObject, GetRecord,
/// PutRecord, GetGeneratedClasses, Parameter OBJECTNAME and the whole .Record class are all
/// written by EnsLib.RecordMap.Generator. A plain compile of this class does NOT create them —
/// it succeeds and leaves the service dying at runtime with
/// <METHOD DOES NOT EXIST>GetObject ... ^EnsLib.RecordMap.Service.Base.1.
/// Generate with the headless [SqlProc] pattern (business-services §"Generating the Record
/// Map"), then iris_doc(mode=get) both classes back to src/ — generated code is committed, not
/// left in the namespace.
Class Example.RecordMap.Censo Extends EnsLib.RecordMap.RecordMap [ Not ProcedureBlock ]
{

XData RecordMap [ XMLNamespace = "http://www.intersystems.com/Ensemble/RecordMap" ]
{
<Record xmlns="http://www.intersystems.com/Ensemble/RecordMap"
        name="Example.RecordMap.Censo"
        type="delimited"
        char_encoding="UTF-8"
        recordTerminator="&#xA;"
        targetClassname="Example.RecordMap.Censo.Record"
        escaping="quote"
        escapeSequence="&quot;">
  <Separators>
    <Separator>,</Separator>
  </Separators>
  <annotation>Patient census read from a CSV drop.</annotation>
  <Field name="PatientId" datatype="%String" />
  <Field name="FullName"  datatype="%String" />
  <Field name="Ward"      datatype="%String" />
  <Field name="Diet"      datatype="%String" />
</Record>
}

}
