/// Rule: BestPractices_Interop_IRIS.md §5.17 "Loading a lookup table: embedded `&sql` is NOT compile-verified, and a reload without a transaction leaves a partial table"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (the state it guards against is silent and permanent).
///
/// Pattern: the oracle for `lookup-bootstrap-sqlproc.cls` in this directory. Its central assertion
/// is one a compile cannot make, because the defect it protects against COMPILES.
///
/// WHY A COMPILE PROVES NOTHING HERE, stated precisely because the coverage map believed the
/// opposite. A typo'd column or table name inside embedded `&sql` compiles clean — measured with
/// forced fresh compiles and a positive control (`#1054`) proving the detector works. The name is
/// resolved when the query is first EXECUTED, which the platform says out loud in its own error:
/// "Table 'ENS_UTIL.LOOKUPTABL' not found compiling embedded cached query". So the loader's
/// correctness is entirely a runtime property, and only a run can establish it.
///
/// THE MEASURED CONTRAST these tests pin, taken before they were written:
///
///     seeded 2 rows
///     non-transactional reload, fails midway (SQLCODE=-29)  ->  table holds 1     PARTIAL, permanent
///     same sequence in TSTART … TROLLBACK                   ->  table holds 2     old content intact
///
/// One row is the worst of the three possible outcomes. Every key that happened to load still
/// resolves; every key that did not returns `""` with `exists = 0` — which is exactly what a key
/// that was never meant to exist returns. There is no reading of the table that reveals the
/// difference, which is why the loader counts rows before it commits.
///
/// WHAT THESE TESTS DO NOT COVER, so a green is not over-read. The compile-clean half of the
/// finding is measured in the headers, not asserted here: asserting it from inside a test would
/// mean generating and compiling a class at run time, and the fragility of that is worse than the
/// coverage is worth. What IS asserted is the runtime half — that the same typo produces SQLCODE
/// -29 when the statement is prepared — which is the half that reaches an operator.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                              PASSED 6/6
///     loader returns a bare "OK", no count    TestLoadIsIdempotent + TestPartialLoadIsRefused FAIL
///     the bracketed reload loses TSTART       TestFailedReloadLeavesOldContent  FAILS
///     column typo expected to prepare cleanly TestTypoFailsAtPrepareNotCompile  FAILS
///     idempotence asserted as 6 rows          TestLoadIsIdempotent              FAILS
///
/// The first mutation reddens TWO tests, which is correct and worth noting: both of them read the
/// verdict STRING, so dropping the count from it breaks the idempotence check and the
/// bare-"OK" refusal together. All five versions compile.
///
/// AND ONE MEASUREMENT THAT NEARLY WENT IN AS A GREEN. The first attempt at this mutation run
/// reported `(no rows)` for every version, shipped and mutated alike -- which reads like "nothing
/// to see" and is nothing of the kind. `Example.UTL.UnitTestResult` had been deleted by the gate's
/// own tier-2 cleanup, so the verdict SqlProc did not exist and every call returned SQLCODE -359.
/// The suite had been running and passing the whole time. An absent reader and a failing suite look
/// identical from the outside, which is the same lesson this file's subject teaches one layer down:
/// distinguish "I read nothing" from "there was nothing".
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.LookupBootstrap", namespace="<NS>")
Class Example.Tests.LookupBootstrap Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// A table name this suite owns outright, distinct from the loader's, so the two cannot interfere.
Parameter SCRATCH = "Example.ScratchGenero";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Rows currently in the scratch table.
ClassMethod ScratchRows() As %Integer [ Private ]
{
    Set tT = ..#SCRATCH
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM Ens_Util.LookupTable WHERE TableName = :tT)
    Quit +$Get(tN)
}

/// Put the scratch table into a known two-row state.
ClassMethod Seed() As %Status [ Private ]
{
    Set tT = ..#SCRATCH
    &sql(DELETE FROM Ens_Util.LookupTable WHERE TableName = :tT)
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (:tT, 'OLD1', 'a'))
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (:tT, 'OLD2', 'b'))
    Quit $$$OK
}

/// A reload that fails part-way through, WITHOUT a transaction. This is the shape the replaced
/// snippet had. The second INSERT names a column that does not exist.
ClassMethod BrokenReloadNoTx() As %Integer [ Private ]
{
    Set tT = ..#SCRATCH
    &sql(DELETE FROM Ens_Util.LookupTable WHERE TableName = :tT)
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (:tT, 'NEW1', 'x'))
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyNam, DataValue) VALUES (:tT, 'NEW2', 'y'))
    Quit SQLCODE
}

/// The same reload, bracketed. On failure it rolls back and the old content survives.
ClassMethod BrokenReloadWithTx() As %Integer [ Private ]
{
    Set tT = ..#SCRATCH
    TSTART
    &sql(DELETE FROM Ens_Util.LookupTable WHERE TableName = :tT)
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (:tT, 'NEW1', 'x'))
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyNam, DataValue) VALUES (:tT, 'NEW2', 'y'))
    Set tCode = SQLCODE
    If (tCode < 0) {
        TROLLBACK
        Quit tCode
    }
    TCOMMIT
    Quit tCode
}

/// The loader is idempotent and reports the count it actually loaded.
Method TestLoadIsIdempotent()
{
    // Control: establish that the table can be observed EMPTY first, so "3" below is a real change
    // and not a number that was already there.
    Do ##class(Example.UTL.LookupBootstrap).Clear()
    Do $$$AssertEquals(##class(Example.UTL.LookupBootstrap).Rows(), 0, "control: the table reads as empty after Clear")

    Set tV1 = ##class(Example.UTL.LookupBootstrap).Load()
    Do $$$AssertEquals(##class(Example.UTL.LookupBootstrap).Rows(), 3, "first load puts 3 rows in")
    Do $$$AssertEquals(tV1, "OK: 3 rows in 'Example.Genero'", "and says so, with the count")

    Set tV2 = ##class(Example.UTL.LookupBootstrap).Load()
    Do $$$AssertEquals(##class(Example.UTL.LookupBootstrap).Rows(), 3, "a second load is idempotent -- still 3, not 6")
    Do $$$AssertEquals(tV2, tV1, "and reports the same verdict")
}

/// A verdict must never be a bare "OK": it carries the count, so a zero-row load cannot read as
/// success. This is the assertion that stops the replaced snippet's `Quit "OK"` coming back.
Method TestPartialLoadIsRefused()
{
    Set tVerdict = ##class(Example.UTL.LookupBootstrap).Load()
    Do $$$AssertNotEquals(tVerdict, "OK", "the verdict must not be a bare OK")
    Do $$$AssertEquals($Find(tVerdict, "3 rows") > 0, 1, "it must carry the row count it established")
}

/// THE POINT. A reload that fails midway must leave the OLD content, not a partial table.
Method TestFailedReloadLeavesOldContent()
{
    Do ..Seed()
    Do $$$AssertEquals(..ScratchRows(), 2, "control: seeded with 2 rows")

    Set tCode = ..BrokenReloadWithTx()
    Do $$$AssertEquals(tCode, -29, "the broken reload must fail with SQLCODE -29")
    Do $$$AssertEquals(..ScratchRows(), 2, "after TROLLBACK the OLD content is intact")
}

/// The negative control for the test above: without the transaction the same failure leaves the
/// table PARTIAL. Without this, TestFailedReloadLeavesOldContent would still pass against a reload
/// that never deleted anything in the first place.
Method TestWithoutTransactionTheTableIsLeftPartial()
{
    Do ..Seed()
    Do $$$AssertEquals(..ScratchRows(), 2, "control: seeded with 2 rows")

    Set tCode = ..BrokenReloadNoTx()
    Do $$$AssertEquals(tCode, -29, "same failure, same SQLCODE")
    Do $$$AssertEquals(..ScratchRows(), 1, "and the table is left holding 1 row -- neither old nor new")

    Do ..Seed()
}

/// The name check happens when the statement is prepared, not when the class compiles -- which is
/// why the loader cannot rely on its own compilation having proved anything.
Method TestTypoFailsAtPrepareNotCompile()
{
    Set tT = ..#SCRATCH

    // Control: the correct statement prepares and runs.
    Set tOK = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (?,?,?)", tT, "PREPOK", "1")
    Do $$$AssertEquals(tOK.%SQLCODE, 0, "control: the correct column names prepare and insert")

    // The same typo that compiled clean inside embedded &sql.
    Set tBad = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO Ens_Util.LookupTable (TableName, KeyNam, DataValue) VALUES (?,?,?)", tT, "PREPBAD", "2")
    Do $$$AssertEquals(tBad.%SQLCODE, -29, "a bad COLUMN name is caught only here, at prepare time")

    Set tBadT = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO Ens_Util.LookupTabl (TableName, KeyName, DataValue) VALUES (?,?,?)", tT, "PREPBAD", "2")
    Do $$$AssertEquals(tBadT.%SQLCODE, -30, "and a bad TABLE name likewise")

    Do ..Seed()
}

}
