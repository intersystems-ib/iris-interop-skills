/// Rule: BestPractices_Interop_IRIS.md §1.21 "RecordMap field types are not per-record validation, and what they do instead differs by type"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, generated, and parsed.
/// Severity: High (relying on the field type gives you no routable rejection, and one type raises instead).
///
/// FIXTURE. It exists so the oracle can show what a typed field actually does at parse time. It is NOT
/// the recommended shape: see `dtl-censo-validate-flags.cls` for where validation belongs.
///
/// WHY A SEPARATE RECORDMAP AND NOT A CHANGE TO `Example.RecordMap.Censo`. Censo's four fields are all
/// `%String`, so it cannot demonstrate a type failure -- but it is referenced by §1.11, by the
/// `GetObject` sections, and by `tdd-recordmap-getobject-encoding.cls`. Adding a typed field there would
/// edit a gated artefact and its test to serve a different section. This fixture carries the typed
/// fields instead and leaves Censo exactly as it was.
///
/// WHAT THE TYPES DO, measured field by field with `GetObject` followed by `%ValidateObject()`:
///
///     record                     GetObject            values            %ValidateObject  %Save
///     P1,12,64000,ICU            OK                   Beds=12           OK               OK
///     P2,ABC,64000,ICU           **OK**               **Beds=ABC**      ERR #7207/#5802  ERR
///     P3,,64000,ICU              OK                   Beds=""           OK               OK
///     P4,12,NOTADATE,ICU         **ERR <ZODAT>**      no object         --               --
///     P5,12       (too few)      OK                   Admitted="" Ward=""  OK            OK
///     P6,...,EXTRA,MORE (many)   OK                   extras DISCARDED  OK               OK
///
/// Read the second and fourth rows together. **`%Integer` is permissive at parse and strict at save**:
/// `GetObject` returns `$$$OK` and puts the literal `ABC` into an `%Integer` property, and only
/// `%ValidateObject()`/`%Save()` objects (`#7207 Datatype value 'ABC' is not a valid number` wrapped in
/// `#5802 Datatype validation failed on property ...:Beds`). **`%Date` is strict at parse and dies
/// badly**: it raises `<ZODAT>` inside the generated `AdmittedDisplayToLogical`, surfaced as
/// `#5002 ObjectScript error` -- an error naming a generated method, not your field or your file.
///
/// So the type gives you, depending which type you picked, either a value you did not want or an
/// exception you cannot route. Neither is per-record validation.
///
/// THE TWO SILENT ONES ARE WORSE THAN BOTH. A record with **too few** fields parses clean and leaves the
/// missing ones empty. A record with **too many** parses clean and the extras are **discarded**. No
/// status, no log entry, no exception -- and `%ValidateObject()` is happy, because empty is a legal
/// `%Integer`. Field count is not checked at all.
///
/// AND A HARNESS NOTE that cost two wrong runs. `GetObject` takes an **`%IO.`** stream -- the service's
/// own signature says `pStream As %IO.DeviceStream`. Handed a `%Stream.GlobalCharacter` it fails with
/// `<PROPERTY DOES NOT EXIST> *Name`, naming neither the stream nor the requirement. And an
/// `%IO.StringStream` is left positioned at the end by `Write()`, so without `Rewind()` every case
/// returns the same `<EnsRecordMap>ErrStreamAtEnd` -- six identical results, which is the shape of a
/// broken measurement rather than a finding.
Class Example.RecordMap.CensoTyped Extends EnsLib.RecordMap.RecordMap [ Not ProcedureBlock ]
{

XData RecordMap [ XMLNamespace = "http://www.intersystems.com/Ensemble/RecordMap" ]
{
<Record xmlns="http://www.intersystems.com/Ensemble/RecordMap"
        name="Example.RecordMap.CensoTyped"
        type="delimited"
        char_encoding="UTF-8"
        recordTerminator="&#xA;"
        targetClassname="Example.RecordMap.CensoTyped.Record"
        escaping="quote"
        escapeSequence="&quot;">
  <Separators>
    <Separator>,</Separator>
  </Separators>
  <annotation>FIXTURE for §1.21: typed fields, to show what the type does and does not do.</annotation>
  <Field name="PatientId" datatype="%String" />
  <!-- Permissive at parse, strict at save. GetObject accepts "ABC" here. -->
  <Field name="Beds"      datatype="%Integer" />
  <!-- Strict at parse, and raises rather than returning a status. -->
  <Field name="Admitted"  datatype="%Date" />
  <Field name="Ward"      datatype="%String" />
</Record>
}

}
