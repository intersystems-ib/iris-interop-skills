/// Rule: BestPractices_Interop_IRIS.md §5.4 "ObjectScript error-handling idiom"
/// Validity: Still valid.
///
/// Why: Ensemble libraries and wizard-generated code don't use modern try/catch;
/// refactor opportunistically. Always return %Status.
///
/// Named `Example.UTL.TryCatchIdiom`: plain helper/utility classes take the `.UTL`
/// sub-package (skills/interop §"naming convention"), Tipo in the middle.
Class Example.UTL.TryCatchIdiom Extends %RegisteredObject
{

/// The idiom: make the call, throw on a bad %Status, convert the exception back to
/// %Status in the catch, and return %Status. Never `Quit <value>` inside the Try (#1043).
///
/// There is a one-line equivalent of the two executable lines below:
///
///     $$$THROWONERROR(tSC, ..InnerCall(pInput, .pOutput))
///
/// Pick ONE of the two forms. They do the same thing, so writing both — as this example
/// used to, separated by a `// OR` comment — calls InnerCall twice.
ClassMethod DoSomething(pInput As %String, Output pOutput As %String) As %Status
{
    #DIM tSC as %Status = $$$OK
    #DIM errObj as %Exception.AbstractException
    try {
        set tSC = ..InnerCall(pInput, .pOutput)
        $$$ThrowOnError(tSC)
    } catch (errObj) {
        set tSC = errObj.AsStatus()
    }
    quit tSC
}

ClassMethod InnerCall(pInput As %String, Output pOutput As %String) As %Status
{
    set pOutput = pInput
    quit $$$OK
}

}
