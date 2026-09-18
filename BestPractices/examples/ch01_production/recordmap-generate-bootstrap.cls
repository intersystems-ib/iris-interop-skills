/// Rule: BestPractices_Interop_IRIS.md §1.17 "Compiling a RecordMap does NOT generate its `.Record` class"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (the production wired to the map cannot process a record, and every tier is green).
///
/// Pattern: the bootstrap that generates a RecordMap's record class. It exists because of a defect
/// this bank was shipping in its own artefacts.
///
/// THE FINDING, and it is about `recordmap-censo.cls` in this directory. Measured on 2026.1 after
/// compiling the whole bank:
///
///     Example.RecordMap.Censo          exists = 1
///     Example.RecordMap.Censo.Record   exists = 0        <-- never generated
///
/// Compiling a RecordMap DEFINITION does not generate its `.Record` class. The definition compiles,
/// tier 2 is green, `production-censo-intake.cls` names the map, and the record class the prebuilt
/// service needs to instantiate is simply absent — so that production could not have processed a
/// single record. It had been that way for every release that shipped the map.
///
/// Nothing catches it. Tier 2 compiles `.cls` files; generation is a separate step no tier performs,
/// and the class that is missing is one no file declares, so C4's index-vs-directory check cannot see
/// it either. `GetObject` on the map raises `<METHOD DOES NOT EXIST>` on the generated class at
/// RUNTIME, which reads as a broken map rather than an ungenerated one.
///
/// WHAT ACTUALLY GENERATES IT, measured — and this corrects the coverage map (W1), which named
/// `SaveToClass` and `GenerateObject` as though they sat together:
///
///     EnsLib.RecordMap.Generator::GenerateObject(pRecordMap, &pTargetClassname, &pStructure = 1)
///         -> $$$OK, pTargetClassname = "<map>.Record", and the class exists AND is compiled after
///     EnsLib.RecordMap.Model.Record::SaveToClass()          arity 0, on the MODEL class
///
/// They are on two different classes. `EnsLib.RecordMap.RecordMap` — the one the name suggests — has
/// NEITHER. `SaveToClass` also exists on `Ens.Config.Production` and
/// `EnsLib.RecordMap.Model.ComplexBatch` with different signatures, so the name cannot be
/// pattern-matched. The generator is what this file calls, because it takes the map NAME, which is
/// what a bootstrap has.
///
/// AND IT IS NOT IDEMPOTENT, which the row does not mention and which decides the shape of the whole
/// method. Called with the record class already present, `GenerateObject` fails:
///
///     ERROR #5768: Class already exists: 'Example.RecordMap.Censo.Record'
///
/// Measured three times in a row -- not a first-call-only condition. A bootstrap that simply calls
/// the generator therefore works exactly once and fails on every redeploy afterwards, which is the
/// worst possible schedule for discovering it: the first deployment succeeds. `Generate()` below
/// drops first and reports "generated" or "regenerated" so the two paths are distinguishable.
///
/// ONE MOTIVATION FROM THE ROW IS VOID, recorded so nobody rebuilds on it. It said `[SqlProc]`
/// "appears 51 times across 11 skills and in **zero** compiled artefacts". Measured: **nine** bank
/// `.cls` files carry `[SqlProc]` — including `recordmap-censo.cls` itself, plus the drift report,
/// the pre-flight validator, the destination assert, the SDS audit, the lookup bootstrap, the verdict
/// reader and the BPL sync audit. That gap closed while the map sat unbuilt.
///
/// WHY `%String` AND NOT `%Status`. A `[SqlProc]` invoked as `SELECT Example_UTL.…()` returns its
/// value into a result set; a `%Status` arrives there as an opaque encoded string a caller is very
/// unlikely to decode, so a failure reads like a success with an odd-looking value. Returning a
/// verdict STRING that names what happened is what makes the call readable from the outside — the
/// same reason the loaders and audits elsewhere in this bank return counts rather than `"OK"`.
///
/// THE PROJECTION SPELLING, verified: package `Example.UTL` + class `RecordMapBootstrap` + method
/// `Generate` projects as `Example_UTL.RecordMapBootstrap_Generate` — schema from the PACKAGE with
/// dots to underscores, then `<Class>_<Method>`. The all-underscores form
/// (`Example_UTL_RecordMapBootstrap…`) resolves to `SQLUSER` and returns `-359`.
Class Example.UTL.RecordMapBootstrap Extends %RegisteredObject
{

/// Generate (or regenerate) the `.Record` class for a RecordMap, and report what happened.
/// Invoke via: SELECT Example_UTL.RecordMapBootstrap_Generate('Example.RecordMap.Censo')
ClassMethod Generate(pRecordMap As %String) As %String [ SqlProc ]
{
    // CHECK IT IS A RECORDMAP, not merely that it exists -- and the difference is the whole point of
    // this guard. Measured: the raw generator reports BOTH of these as
    //     ERROR #5351: Class 'X' does not exist.
    // for an unknown name AND for a real compiled class that is not a RecordMap. The second is
    // false: the class does exist. That error sends you looking for a missing class instead of at
    // the name you actually mistyped, so the guard's value is the MESSAGE, not the refusal.
    If '##class(%Dictionary.CompiledClass).%ExistsId(pRecordMap) {
        Return "FAILED: no compiled class named '" _ pRecordMap _ "' -- compile the RecordMap definition first"
    }
    If '..IsRecordMap(pRecordMap) {
        Return "FAILED: '" _ pRecordMap _ "' is compiled but is NOT a RecordMap (it does not extend " _
               "EnsLib.RecordMap.RecordMap). The raw generator would call this 'Class does not exist', which is false."
    }

    // GenerateObject IS NOT IDEMPOTENT. Called with the record class already present it fails:
    //     ERROR #5768: Class already exists: 'Example.RecordMap.Censo.Record'
    // Measured three times in a row -- it is not a first-call-only condition. So a bootstrap that
    // simply calls the generator works exactly once and fails on every redeploy, which is the worst
    // possible schedule for finding out. Drop first, and say which path was taken.
    Set tExisted = ..RecordClassExists(pRecordMap)
    If tExisted {
        Set tDrop = ..DropRecordClass(pRecordMap)
        If $Find(tDrop, "FAILED") > 0 {
            Return "FAILED: could not drop the existing record class -- " _ tDrop
        }
    }

    Set tTarget = ""
    Set tStructure = 1
    Set tSC = ##class(EnsLib.RecordMap.Generator).GenerateObject(pRecordMap, .tTarget, .tStructure)
    If $$$ISERR(tSC) {
        Return "FAILED: " _ $system.Status.GetErrorText(tSC)
    }

    // ESTABLISH THE RESULT, do not infer it. GenerateObject returning $$$OK is the generator's
    // word for it; the class either exists afterwards or it does not, and that is cheap to read.
    //
    // HONEST NOTE: this branch is DEFENSIVE AND UNFALSIFIED. Removing it leaves the test suite green,
    // because no input was found on which the generator returns $$$OK without creating the class.
    // It is kept because the cost is two lines and the failure it would catch is a silent one -- but
    // it is not covered, and this comment is here so a clean run is not read as covering it.
    If '##class(%Dictionary.CompiledClass).%ExistsId(tTarget) {
        Return "FAILED: GenerateObject returned OK but '" _ tTarget _ "' is not compiled"
    }

    Return "OK: " _ $Select(tExisted: "regenerated", 1: "generated") _ " and compiled '" _ tTarget _ "'"
}

/// Does pClass extend EnsLib.RecordMap.RecordMap? Uses the compiled superclass chain, so it answers
/// for an inherited definition too.
ClassMethod IsRecordMap(pClass As %String) As %Boolean [ SqlProc ]
{
    Return ##class(%Dictionary.CompiledClass).%ExistsId(pClass) &&
           $ClassMethod(pClass, "%Extends", "EnsLib.RecordMap.RecordMap")
}

/// Is a RecordMap's record class present? The check a deployment should make, and the one no tier
/// makes for it. Public so a reviewer can ask without generating anything.
ClassMethod RecordClassExists(pRecordMap As %String) As %Boolean [ SqlProc ]
{
    Return ##class(%Dictionary.CompiledClass).%ExistsId(pRecordMap _ ".Record")
}

/// Remove the generated class, so a test can establish a known starting state. Deliberately separate
/// from Generate(): a bootstrap that silently deleted and rebuilt would make "it was already there"
/// and "I just made it" indistinguishable.
ClassMethod DropRecordClass(pRecordMap As %String) As %String [ SqlProc ]
{
    Set tTarget = pRecordMap _ ".Record"
    If '##class(%Dictionary.ClassDefinition).%ExistsId(tTarget) {
        Return "nothing to drop"
    }
    Set tSC = $System.OBJ.Delete(tTarget, "-d")
    Return $Select($$$ISERR(tSC): "FAILED: " _ $system.Status.GetErrorText(tSC), 1: "dropped '" _ tTarget _ "'")
}

}
