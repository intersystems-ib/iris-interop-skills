/// Rule: BestPractices_Interop_IRIS.md §5.17 "Loading a lookup table: embedded `&sql` is NOT compile-verified, and a reload without a transaction leaves a partial table"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (a half-loaded lookup table returns plausible values and raises nothing).
///
/// Pattern: the bootstrap loader for `Ens_Util.LookupTable`, with the two things the snippet it
/// replaces omits — a transaction bracket, and an `SQLCODE` check after every statement.
///
/// THE PREMISE THIS FILE WAS COMMISSIONED ON WAS FALSE, and saying so is the most useful thing here.
/// The coverage map asked for this file because "embedded `&sql` makes
/// `Ens_Util.LookupTable (TableName, KeyName, DataValue)` compile-verified". **It does not.**
/// Measured on 2026.1, with a deliberate typo, forced fresh compiles, and a positive control
/// proving the detector reports real compile errors (`#1054`):
///
///     &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyNam, DataValue) …)   COMPILES CLEAN
///     &sql(INSERT INTO Ens_Util.LookupTabl  (TableName, KeyName, DataValue) …)  COMPILES CLEAN
///
/// Both fail at RUNTIME instead:
///
///     column typo  ->  SQLCODE = -29   Field 'ENS_UTIL.LOOKUPTABLE.KEYNAM' not found …
///     table typo   ->  SQLCODE = -30   Table 'ENS_UTIL.LOOKUPTABL' not found compiling
///                                      EMBEDDED CACHED QUERY from <class>
///
/// That last phrase is the platform telling you why: an embedded query is compiled on its FIRST
/// EXECUTION, not when the class compiles. So embedded `&sql` buys exactly nothing over dynamic SQL
/// for name checking, and a bootstrap's only real protection is to check `SQLCODE` and then count
/// the rows it actually loaded — which is what this class does.
///
/// (`&sql` still earns its place for a different reason the `lookup-tables` skill gives correctly:
/// inside a compiled `[SqlProc]` the macro sets the bare `SQLCODE` the idiom expects, whereas the
/// MCP's `iris_execute` rewrite binds it to a generated local and `If SQLCODE<0` is `<UNDEFINED>`
/// — after the write has already gone through.)
///
/// WHAT A FAILED RELOAD LEAVES BEHIND, measured, and it is the reason for the transaction:
///
///     seeded with 2 rows
///     NON-transactional reload (DELETE, good INSERT, bad INSERT) fails at SQLCODE=-29
///         -> the table holds 1 row. Permanently. Not the old content, not the new content.
///     the SAME sequence inside TSTART … TROLLBACK
///         -> mid-transaction the table holds 1, after TROLLBACK it holds 2 — the old content,
///            intact.
///
/// A half-loaded lookup table is the worst of the three outcomes, because every key that happens to
/// have loaded still resolves and every key that did not returns `""` with `exists = 0` — which is
/// indistinguishable from a key that was never supposed to be there. `DELETE` + bulk `INSERT`
/// inside one transaction is what the `lookup-tables` skill prescribes for exactly this, and the
/// snippet it prescribes it next to does not do it.
///
/// THREE THINGS THE REPLACED SNIPPET GOT WRONG, all of which this file fixes:
///   1. no transaction, so a mid-load failure is permanent (above);
///   2. no `SQLCODE` check between statements, so the failure is never noticed;
///   3. `Quit "OK"` unconditionally — it reports success it never established. Below, the verdict
///      carries the row count, so "loaded 0" cannot be read as "loaded".
/// It also lived as a bare `ClassMethod` fence with no host class, which is one of the two shapes
/// tier 3 cannot compile — so none of this was gated either.
Class Example.UTL.LookupBootstrap Extends %RegisteredObject
{

/// The table this loader owns. It DELETEs by this name, so it must own it outright.
Parameter TABLE = "Example.Genero";

/// Load the table atomically. Returns a verdict that carries the count, never a bare "OK".
/// Invoke via: SELECT Example_UTL.LookupBootstrap_Load()
ClassMethod Load() As %String [ SqlProc ]
{
    Set tTable = ..#TABLE
    Set tWanted = 3

    TSTART

    &sql(DELETE FROM Ens_Util.LookupTable WHERE TableName = :tTable)
    // SQLCODE 100 is "no rows deleted" -- expected on a first load, NOT an error.
    If (SQLCODE < 0) {
        TROLLBACK
        Return "FAILED at DELETE: SQLCODE=" _ SQLCODE _ " " _ $Get(%msg)
    }

    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (:tTable, 'M', '1'))
    If (SQLCODE < 0) {
        TROLLBACK
        Return "FAILED at INSERT M: SQLCODE=" _ SQLCODE _ " " _ $Get(%msg)
    }

    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (:tTable, 'F', '2'))
    If (SQLCODE < 0) {
        TROLLBACK
        Return "FAILED at INSERT F: SQLCODE=" _ SQLCODE _ " " _ $Get(%msg)
    }

    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (:tTable, 'U', '9'))
    If (SQLCODE < 0) {
        TROLLBACK
        Return "FAILED at INSERT U: SQLCODE=" _ SQLCODE _ " " _ $Get(%msg)
    }

    // COUNT BEFORE COMMITTING. Neither SQL form checked the column names at compile time, so the
    // only evidence that this loader did what it claims is the rows it can see.
    Set tGot = ..Rows()
    If (tGot '= tWanted) {
        TROLLBACK
        Return "FAILED: loaded " _ tGot _ " of " _ tWanted _ " rows; rolled back, old content intact"
    }

    TCOMMIT
    Return "OK: " _ tGot _ " rows in '" _ tTable _ "'"
}

/// How many rows the table currently holds. Public so a reviewer can check without a reload.
ClassMethod Rows() As %Integer [ SqlProc ]
{
    Set tTable = ..#TABLE
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM Ens_Util.LookupTable WHERE TableName = :tTable)
    Quit +$Get(tN)
}

/// Remove the table's rows. Separate from Load() so a test can establish a known starting state.
ClassMethod Clear() As %String [ SqlProc ]
{
    Set tTable = ..#TABLE
    &sql(DELETE FROM Ens_Util.LookupTable WHERE TableName = :tTable)
    Quit $Select(SQLCODE < 0: "FAILED: SQLCODE=" _ SQLCODE, 1: "cleared")
}

}
