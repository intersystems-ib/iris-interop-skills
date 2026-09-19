/// Rule: BestPractices_Interop_IRIS.md §6.20 "`%SOAP.WSDL.Reader.Process`: the measured signature, and why a typed `#Dim` is not a gate"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, and the generation RUN from a local file.
/// Severity: Medium (the call is easy to get wrong and every wrong form compiles clean).
///
/// Pattern: headless WSDL to client/Business-Operation generation, as `soap-bo` describes, wrapped so
/// the arity lives in exactly one place.
///
/// THE MEASURED SIGNATURE, read from `%Dictionary.CompiledMethod`:
///
///     Process(pLocationURL As %String,
///             pPackage As %String = "",
///             pTest As %Boolean = 0,
///             schemaReader As %XML.Utils.SchemaReader = "") As %Status      [ instance method ]
///
/// `ClassMethod = 0`, so it must be reached through `%New()`. Note the fourth parameter IS typed --
/// `%XML.Utils.SchemaReader` -- which `soap-bo` records as a bare `schemaReader = ""`.
///
/// AND HERE IS THE PART THAT CHANGES HOW YOU PIN THIS. A typed `#Dim` does **not** make a wrong call a
/// compile error. Measured, six variants, all compiled with `$System.OBJ.Compile`:
///
///     typed #Dim, correct arity                       compiles clean
///     typed #Dim, FIVE arguments                      compiles clean   <-- no arity check
///     typed #Dim, method that does not exist           compiles clean   <-- no existence check
///     untyped variable, five arguments                compiles clean
///     untyped variable, method that does not exist     compiles clean
///     Process called as a ##class() ClassMethod        compiles clean   <-- despite ClassMethod = 0
///
/// ObjectScript resolves instance-method calls at run time, so the declared type is **documentation,
/// not a contract**. Six ways to get this call wrong, zero of them caught by the compiler. The `#Dim`
/// is still worth writing -- it tells the next reader what the variable is -- but it pins nothing.
///
/// SO WHAT DOES PIN IT: `tdd-wsdl-reader-signature.cls`, which asserts the formal spec out of the
/// dictionary AND actually runs a generation. A version-pinned claim in prose is only as good as the
/// thing that re-checks it, and a compile is not that thing.
///
/// `pLocationURL` TAKES A LOCAL FILE PATH, not only a URL. Measured: `Process("/tmp/x.wsdl", "Pkg")`
/// returned `$$$OK` and generated the classes. That is what makes this testable with no network and no
/// reachable endpoint -- see the oracle, which writes a WSDL out of an XData block and reads it back.
///
/// WHAT IT GENERATES, measured on a one-operation WSDL: `<Package>.<Service>Soap` plus **one class per
/// web method** (`<Package>.<Service>Soap.Add`). So the count to expect is operations + 1, not 1.
Class Example.UTL.WsdlGenerate Extends %RegisteredObject
{

/// Generate from a WSDL location -- a URL, or a path to a local file.
/// pMakeBusinessOperation: 1 also generates a Business Operation plus an Ens.Request/Ens.Response pair
/// per operation, which is the point of doing this inside an interop project. The Reader's own default
/// is 0, which yields the proxy client and nothing else.
ClassMethod FromLocation(pLocation As %String, pPackage As %String, pMakeBusinessOperation As %Boolean = 1) As %Status
{
    // Documentation, not a check: see the class header. Every wrong spelling of the call below compiles.
    #Dim tReader As %SOAP.WSDL.Reader = ##class(%SOAP.WSDL.Reader).%New()
    If '$IsObject(tReader) {
        Quit $$$ERROR($$$GeneralError, "%SOAP.WSDL.Reader.%New() returned no object")
    }
    Set tReader.MakeBusinessOperation = pMakeBusinessOperation
    // THE ONE CALL SITE. Four parameters, of which two are passed; pTest = 0 and schemaReader = "" are
    // the measured defaults. Keeping this in one method is the only reason a signature change becomes
    // one edit rather than a search.
    Quit tReader.Process(pLocation, pPackage)
}

}
