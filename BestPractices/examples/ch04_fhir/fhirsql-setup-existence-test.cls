/// Rule: BestPractices_Interop_IRIS.md §4.13 "An existence test must read the dictionary — a call-through to a missing method compiles clean"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and RUN; every signature read from %Dictionary.
/// Severity: High (the obvious way to write this test passes whether the API exists or not).
///
/// Pattern: pin a version-dependent platform API by **reading the dictionary**. The subject here is the
/// FHIR SQL Builder setup surface, which §4.9 and `skills/fhir` both name.
///
/// WHY NOT JUST CALL IT. Because the call compiles whether the target exists or not. Measured three ways:
///
///     ##class(HS.Totally.Absent).DoesNotExist()                   compiles CLEAN
///     ##class(HS.FHIRServer.Service).NoSuchMethodAnywhere()       compiles CLEAN
///     Property P As HS.Totally.Absent;                            #5373 ... used by 'X:property:P'
///     ClassMethod Go(pArg As HS.Totally.Absent)                   #5373 ... used by 'X:Go:FormalSpec'
///     Class X Extends HS.Totally.Absent                           #5373 ... used by 'X:superclass'
///
/// So `#5373` is raised **only** by a class in a TYPE position -- property, formal spec, superclass. A
/// method CALL never raises it, at compile time or at any time before the call runs. A "does this API
/// exist?" test written as a call-through therefore asserts nothing (§6.20 makes the same point about
/// arity).
///
/// AND A CORRECTION TO THE COVERAGE MAP'S REASONING, which mattered to the design. The row said tier 2
/// "excuses `#5373` as a placeholder dependency". It does not: tier 2 ends `ok = not failed`, so any
/// failure -- `#5373` included -- fails it. The excuse lives in **tier 3**, the skill-snippet tier, where
/// an illustrative `MyApp.Msg.SomeRequest` is legitimate. Either way the conclusion holds, for the
/// stronger reason above: a type reference would fail the bank's gate, and a call-through asserts nothing.
///
/// WHAT THE SURFACE ACTUALLY IS, read from the dictionary rather than from the docs:
///
///     HS.HC.FHIRSQL.Utils.Setup            present in the interop namespace AND in HSLIB
///     Setup(dir="//projects/healthshare/appmodules/HSHC-WIP/HealthConnect.FHIRSQL/latest",
///           pNamespace=..#FHIRNAMESPACE,
///           pStrategyClass:%String="HS.FHIRServer.Storage.Json.InteractionsStrategy")  -> VOID
///     LoadFHIRData(ns=..#FHIRNAMESPACE, dir=".../internal/testing/data",
///                  pSome=0, pPath:%String="", pFileLimit:%Integer="")                  -> VOID
///     Install(pNamespace="HSSYS")   CreateWebApps(pNamespace="HSSYS", pEnabled=0)
///     CreateFHIRApp(...)            CreateUpdateFHIRSQLUIApp(pNamespace="HSSYS")
///     DefineDocDBs(pNamespace=..#APPNAMESPACE, pReIndex=0)
///     Parameters: FHIRNAMESPACE = "DEMO"   APPNAMESPACE = "HSSYS"
///
/// THREE THINGS THAT FOLLOW, and the first two contradict the shipped guidance §4.13 corrects:
///   1. **`Setup` takes THREE parameters, not one.** `Setup("/data/fhirdata/")` compiles and runs, but it
///      is passing a data directory into `dir`, whose default is an InterSystems **build** path.
///   2. **`LoadFHIRData` is the data entry point**, and its own `dir` default points at InterSystems'
///      internal testing data.
///   3. **Both return VOID.** `Set tSC = ##class(...).Setup(...)` raises `<COMMAND>` -- the same trap as
///      `EnsLib.SQL.OutboundAdapter.Disconnect` in §6.21.
Class Example.UTL.FhirSqlSetupCheck Extends %RegisteredObject
{

Parameter SETUPCLASS As STRING = "HS.HC.FHIRSQL.Utils.Setup";

/// Does a class exist, by dictionary lookup? Never by calling it.
ClassMethod ClassPresent(pClass As %String) As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(pClass)
}

/// Does a method exist on it? `%OpenId` on the `Class||Method` id is the lookup; a null object means no.
ClassMethod MethodPresent(pClass As %String, pMethod As %String) As %Boolean
{
    Quit $IsObject(##class(%Dictionary.CompiledMethod).%OpenId(pClass _ "||" _ pMethod, 0))
}

/// The method's formal spec, verbatim, or "" when the method is absent. A signature claim that is only
/// prose goes stale silently; comparing this string is what makes it a standing check.
ClassMethod FormalSpec(pClass As %String, pMethod As %String) As %String
{
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId(pClass _ "||" _ pMethod, 0)
    Quit $Select($IsObject(tDef):tDef.FormalSpec, 1:"")
}

/// How many declared parameters a method has. Counting commas at depth zero, because a default value can
/// itself contain commas and a naive $Length(spec, ",") over-counts.
ClassMethod ParamCount(pClass As %String, pMethod As %String) As %Integer
{
    Set tSpec = ..FormalSpec(pClass, pMethod)
    Quit:tSpec="" 0
    Set tCount = 1, tDepth = 0, tInStr = 0
    For i = 1:1:$Length(tSpec) {
        Set tChar = $Extract(tSpec, i)
        If tChar = """" { Set tInStr = 'tInStr  Continue }
        Continue:tInStr
        If "([{" [ tChar { Set tDepth = tDepth + 1  Continue }
        If ")]}" [ tChar { Set tDepth = tDepth - 1  Continue }
        Set:(tChar=",")&&(tDepth=0) tCount = tCount + 1
    }
    Quit tCount
}

/// Does this method return anything? A void method assigned to a variable raises <COMMAND>.
ClassMethod ReturnsValue(pClass As %String, pMethod As %String) As %Boolean
{
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId(pClass _ "||" _ pMethod, 0)
    Quit:'$IsObject(tDef) 0
    Quit tDef.ReturnType '= ""
}

/// One-line verdict on the FHIR SQL Builder setup surface, for a human or a tool reading one cell:
///     SELECT Example_UTL.FhirSqlSetupCheck_Report()
ClassMethod Report() As %String [ SqlProc ]
{
    If '..ClassPresent(..#SETUPCLASS) {
        Quit "ABSENT: " _ ..#SETUPCLASS _ " is not present in namespace " _ $Namespace _
             " -- FHIR SQL Builder is not installed here"
    }
    Set tOut = "present: " _ ..#SETUPCLASS
    For tMethod = "Setup", "LoadFHIRData", "Install" {
        If '..MethodPresent(..#SETUPCLASS, tMethod) {
            Set tOut = tOut _ " | " _ tMethod _ " MISSING"
            Continue
        }
        Set tOut = tOut _ " | " _ tMethod _ "/" _ ..ParamCount(..#SETUPCLASS, tMethod) _
                   " params, returns " _ $Select(..ReturnsValue(..#SETUPCLASS, tMethod):"a value", 1:"VOID")
    }
    Quit tOut
}

}
