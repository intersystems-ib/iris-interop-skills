/// Rule: BestPractices_Interop_IRIS.md §5.22 "A collection's child table exists only if you ask — and `array` and `list` disagree on the default"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND its projections read from INFORMATION_SCHEMA.
/// Severity: Medium (loud, `SQLCODE -30` — but it cost a cohort 12 round-trips because the name looks right).
///
/// Pattern: a message class whose collections are queried from SQL, which is where the child-table
/// naming matters. The naming is real — `SCHEMA.Class_Property`, measured — and it is the *second*
/// thing to know. The first is that **whether the table exists at all depends on the collection type.**
///
/// MEASURED, four properties on one class, only the declarations differing:
///
///     Property ListDefault  As list  Of %String                              -> NO child table
///     Property ListTable    As list  Of %String(SQLPROJECTION = "table")     -> ZZ44.V_ListTable
///     Property ArrayDefault As array Of %String                              -> ZZ44.V_ArrayDefault
///     Property ArrayTable   As array Of %String(SQLPROJECTION = "table")     -> ZZ44.V_ArrayTable
///
/// **`array` projects a child table by default. `list` does not.** That asymmetry is the whole finding.
/// A developer who met child tables on an `array` property, then wrote the obvious `SELECT` against a
/// `list` one, gets
///
///     SQLCODE -30, Table 'SCHEMA.CLASS_PROPERTY' not found
///
/// which reads as a typo in a name that is in fact correct — the table simply was never projected.
/// That is why this is loud and still expensive.
///
/// WHERE A DEFAULT `list` ACTUALLY LIVES: as a single `varchar` column on the PARENT table, holding the
/// `$List`. Measured — the parent's columns were `ID bigint`, `Plain varchar`, `ListDefault varchar`,
/// and the three projected collections were absent from it. So the data is queryable, just not
/// relationally: `WHERE ListDefault [ 'x'` works and `JOIN` does not.
///
/// AND THE CHILD TABLE'S SHAPE, which decides how you join it:
///
///     column        list projection        array projection
///     <Parent>      bigint, the parent id  bigint
///     ID            varchar                varchar
///     <Property>    the element value      the element value
///     element_key   INTEGER (the index)    VARCHAR (the array key)
///
/// `element_key` is the ordinal for a list and the key for an array, and its TYPE differs accordingly.
/// A query written against one and pointed at the other compiles and compares an integer to a string.
///
/// WHICH TO USE. Add `SQLPROJECTION = "table"` when the collection is genuinely queried — reporting, a
/// join, an aggregate. Leave it off when the collection is only ever read through the object, which is
/// the common case for an interop message: a child table per collection is another extent to purge,
/// another set of indices, and another thing to keep in step. This class carries one of each so the
/// difference is visible in a single compile.
///
/// NO HAND-WRITTEN `Storage` BLOCK, deliberately. IRIS generates the default storage definition on
/// first compile, and a hand-written one in a bank file is an invitation to paste it into a new class
/// -- which six other headers here already warn against. A first draft of THIS file carried one; it
/// was removed before it shipped.
Class Example.MSG.ObsCollections Extends (%Persistent, %XML.Adaptor)
{

/// The patient the observations belong to. A plain property, for the join key in a report.
Property PatientId As %String(MAXLEN = 64);

/// READ THROUGH THE OBJECT ONLY. No SQLPROJECTION, so no child table: this lands as a single
/// `varchar` column on Example_MSG.ObsCollections holding the $List. Correct for a payload that a DTL
/// fills and a BO consumes.
Property Notes As list Of %String(MAXLEN = 200);

/// QUERIED FROM SQL, so it asks for the table explicitly. Projects
/// Example_MSG.ObsCollections_Codes with element_key as an INTEGER ordinal.
Property Codes As list Of %String(MAXLEN = 20, SQLPROJECTION = "table");

/// An ARRAY, which projects a child table WITHOUT being asked -- kept here precisely so the asymmetry
/// is in one file. element_key holds the array key and is a VARCHAR.
Property Attributes As array Of %String(MAXLEN = 100);


}
