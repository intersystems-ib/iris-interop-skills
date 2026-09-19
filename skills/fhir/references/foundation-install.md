# Installing the FHIR server in a Foundation namespace

A one-time step per environment, which is why it lives here rather than in the skill body: you need
it when standing a namespace up, not while building components.

The prerequisite — `HS.Util.Installer.Foundation.Install("<NS>")` — runs in **HSLIB**, not in the
target namespace, which is why it is a separate call (see the skill).

Signatures verified live against IRIS for Health 2026.1 before this was written, and **kept** verified
because tier 3 compiles the class below on every release:

| call | signature |
|---|---|
| `HS.Util.Installer.Foundation.Install` | `(pNamespace As %String, ByRef pVars)` |
| `HS.FHIRServer.Installer.InstallNamespace` | `(namespace As %String = $namespace)` |
| `HS.FHIRServer.Installer.InstallInstance` | `(pAppKey = "", pStrategyClass, pPackageList, …)` |

`InstallNamespace` defaulting its argument to `$namespace` is why setting the namespace first is
enough — there is no second place to pass it.

```objectscript
/// One-time FHIR server install for a Foundation namespace.
Class Demo.UTL.FhirInstall Extends %RegisteredObject
{

ClassMethod Install(pNamespace As %String, pAppKey As %String) As %Status
{
    New $NAMESPACE
    Set $NAMESPACE = pNamespace
    Set tSC = ##class(HS.FHIRServer.Installer).InstallNamespace()
    If $$$ISERR(tSC) Quit tSC
    Quit ##class(HS.FHIRServer.Installer).InstallInstance(
        pAppKey,
        "HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy",
        $ListBuild("hl7.fhir.r4.core@4.0.1"))
}

}
```

Call it as `Do ##class(Demo.UTL.FhirInstall).Install("<NS>", "/csp/healthshare/<ns>/fhir/r4")`.

**An argument list may span lines; a macro invocation may not.** The `InstallInstance(` call above is
split across four lines and compiles — ObjectScript has no continuation character, but a bracketed
argument list does not need one. `$$$Macro(` split the same way gives `MPP5612: Referenced macro
missing right paren`, which is the trap `interop` §"Invariants when writing ANY ObjectScript class"
describes.
