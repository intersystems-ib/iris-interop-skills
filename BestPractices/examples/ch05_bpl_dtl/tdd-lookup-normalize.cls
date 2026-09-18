/// Rule: BestPractices_Interop_IRIS.md §5.13 "Calling a function from a DTL — the two forms have opposite rules and the wrong one is silent"
/// Validity: Verified against IRIS for Health 2026.1 — loads a real lookup table and RUNS the lookups.
/// Severity: High (an unnormalised key misses every row and the default hides the miss).
///
/// Pattern: the proof that normalisation is what makes a lookup HIT. It loads one row, looks it up
/// two ways, and asserts the difference — which is the only way to show that
/// `Example.UTL.FunctionSet.NormalizeKey` earns its place rather than merely existing.
///
/// RE-SCOPED FROM THE COVERAGE MAP, and the reason is recorded here so it is not re-litigated. The
/// map's S7 proposed contrasting a working `NormalizeKey` against "the tier-3-green broken one".
/// That broken snippet was fixed in v1.15.0 (wave-0 N4: `"*-CWE"` raised `<FUNCTION>`), and v1.26.0
/// shipped the working version as `Example.UTL.FunctionSet`. So the contrast the row was built on no
/// longer exists in this repo. What was still missing — and is what this file does — is a lookup
/// against an actually-loaded table, proving the normalised key matches and the raw one does not.
///
/// MEASURED before these assertions were written, with one row keyed `diabetica`:
///     %GetValue(table, "diabetica")        -> "DIA"      exists = 1
///     %GetValue(table, "  Diabética  ")    -> ""         exists = 0
///     FunctionSet.Lookup(table, norm, "UNKNOWN") -> "DIA"
///     FunctionSet.Lookup(table, raw,  "UNKNOWN") -> "UNKNOWN"
///
/// THE LAST LINE IS THE SILENT FAILURE IN ONE VALUE. With a default supplied, an unnormalised key
/// returns the DEFAULT — not an error, not an empty string, a plausible-looking value. Every message
/// is then mapped to the fallback code and the pipeline reports success. With `""` as the default it
/// is worse in a different way: the miss becomes an empty field that flows downstream as if the
/// source had sent nothing.
///
/// `exists` IS WHAT SEPARATES A MISS FROM AN EMPTY VALUE, and it is the third, by-ref argument of
/// `%GetValue` — not a default, which is what it looks like. A row whose DataValue is genuinely
/// empty returns `""` with `exists = 1`; a missing row returns `""` with `exists = 0`. Without it
/// the two are the same answer.
///
/// LOADING IS DELETE-THEN-INSERT, always. Re-running an INSERT alone either duplicates the key or
/// fails, so a loader that is not idempotent breaks the second time it runs — which is the first
/// time anyone re-runs a deployment. Embedded `&sql` works here: in a COMPILED class it behaves
/// normally, unlike `&sql` sent through `iris_execute`, which is rewritten and loses `SQLCODE`
/// (intersystems-ib/iris-interop-dev#145).
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.LookupNormalize", namespace="<NS>")
Class Example.Tests.LookupNormalize Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test.
Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// The table this test owns. Named so it cannot collide with a real one.
Parameter TABLE = "ExampleTestDietas";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Idempotent load: delete then insert. See the header on why the delete is not optional.
ClassMethod LoadOne(pKey As %String, pValue As %String) As %Status [ Private ]
{
    Set tTable = ..#TABLE
    Set tSQL = "DELETE FROM Ens_Util.LookupTable WHERE TableName = ?"
    Do ##class(%SQL.Statement).%ExecDirect(, tSQL, tTable)
    Set tSQL = "INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES (?,?,?)"
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, tTable, pKey, pValue)
    Quit $Select(tRS.%SQLCODE = 0: $$$OK, 1: $$$ERROR($$$GeneralError, "load failed SQLCODE " _ tRS.%SQLCODE))
}

ClassMethod Unload() [ Private ]
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.LookupTable WHERE TableName = ?", ..#TABLE)
}

/// The point: the normalised key hits, the raw key does not.
Method TestNormalisedKeyHitsAndRawMisses()
{
    Do $$$AssertStatusOK(..LoadOne("diabetica", "DIA"))

    Set tRaw = "  Diabética  "
    Set tNorm = ##class(Example.UTL.FunctionSet).NormalizeKey(tRaw)
    Do $$$AssertEquals(tNorm, "diabetica", "NormalizeKey must produce the stored key form")

    Set tHit = ##class(Ens.Util.LookupTable).%GetValue(..#TABLE, tNorm, .tExistsHit)
    Do $$$AssertEquals(tHit, "DIA", "the normalised key must find the row")
    Do $$$AssertEquals(tExistsHit, 1, "and exists must say it was found")

    Set tMiss = ##class(Ens.Util.LookupTable).%GetValue(..#TABLE, tRaw, .tExistsMiss)
    Do $$$AssertEquals(tMiss, "", "the RAW key must miss -- this is what normalisation prevents")
    Do $$$AssertEquals(tExistsMiss, 0, "and exists must say it was NOT found")

    Do ..Unload()
}

/// The silent failure in one value: with a default, a missed key returns the DEFAULT — a
/// plausible code, not an error — and every message is quietly mapped to the fallback.
Method TestMissReturnsTheDefaultNotAnError()
{
    Do $$$AssertStatusOK(..LoadOne("diabetica", "DIA"))

    Set tGood = ##class(Ens.Util.FunctionSet).Lookup(..#TABLE, "diabetica", "UNKNOWN")
    Set tBad = ##class(Ens.Util.FunctionSet).Lookup(..#TABLE, "  Diabética  ", "UNKNOWN")

    Do $$$AssertEquals(tGood, "DIA", "the normalised key resolves through the FunctionSet too")
    Do $$$AssertEquals(tBad, "UNKNOWN", "an unnormalised key silently returns the DEFAULT")
    Do $$$AssertNotEquals(tBad, tGood, "control: the two keys really do resolve differently")

    Do ..Unload()
}

/// The control that makes `exists` meaningful: a row whose value is genuinely empty returns ""
/// WITH exists = 1, so "" alone cannot tell you whether the row was there.
Method TestEmptyValueIsNotAMiss()
{
    Do $$$AssertStatusOK(..LoadOne("emptyvalue", ""))

    Set tVal = ##class(Ens.Util.LookupTable).%GetValue(..#TABLE, "emptyvalue", .tExists)
    Do $$$AssertEquals(tVal, "", "a row with an empty DataValue returns an empty value")
    Do $$$AssertEquals(tExists, 1, "but exists = 1 -- so only exists separates this from a miss")

    Do ..Unload()
}

}
