/// Rule: BestPractices_Interop_IRIS.md §5.13 "Calling a function from a DTL — the two forms have opposite rules and the wrong one is silent"
/// Validity: Verified against IRIS for Health 2026.1 — compiled and RUN.
/// Severity: High (the wrong call form compiles and fails only at Transform time).
///
/// Pattern: a DTL that calls BOTH kinds of function — a built-in with `..`, and a custom
/// FunctionSet method with `##class()`. The pair in one file is the point: the two forms look
/// interchangeable and are not.
///
/// `DependsOn` IS NOT OPTIONAL, and this is measured rather than cautionary. A DTL's `Transform`
/// method is generated, and the generator needs the source and target classes ALREADY compiled.
/// Compiling this class in the same batch as its message classes, without DependsOn:
///     single batch, no DependsOn  -> FAILS
///     single batch, DependsOn     -> all compile
/// The failure does not name the real cause either: it surfaces as
/// `<CLASS DOES NOT EXIST> … Ens.DTL.Transform` against the message class, or as
/// `ERROR: Ens.DataTransformDTL.cls(Transform) of generated code compiling subclass`. A DTL
/// without DependsOn compiles only while the batch happens to reach its dependencies first, which
/// is luck, not a property of the code.
///
/// THE TWO CALL FORMS, both measured in this exact context:
///   built-in  `..Lookup(table, key, default)`            compiles, works
///             `Lookup(table, key, default)`              compiles, <UNDEFINED> at Transform
///   custom    `##class(Example.UTL.FunctionSet).Norm…`   compiles, works
///             `..NormalizeKey(…)`                        COMPILE FAILS (MPP5392 No such method)
///             `NormalizeKey(…)`                          compiles, <UNDEFINED> at Transform
/// The bare form is the dangerous one in both rows: it is the only wrong form that passes the
/// compiler, so tier 2 is green and the failure waits for a message.
///
/// THE THIRD ARGUMENT TO `..Lookup` IS THE ON-MISS DEFAULT AND IT IS NOT OPTIONAL IN PRACTICE.
/// Without it a miss yields "" and flows downstream as a legitimately empty value. With `"UNKNOWN"`
/// the miss is visible in the output. Note also that the normalisation runs FIRST: an unnormalised
/// key misses a table whose keys are normalised, and the miss then looks like missing reference
/// data rather than a formatting difference.
Class Example.DT.CensoToMenus Extends Ens.DataTransformDTL [ DependsOn = (Example.MSG.AcceptOrderReq, Example.MSG.VendorOrder, Example.UTL.FunctionSet) ]
{

/// Report an unresolvable path rather than absorbing it into the same "" an empty field gives.
Parameter REPORTERRORS = 1;

Parameter IGNOREMISSINGSOURCE = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='Example.MSG.AcceptOrderReq' targetClass='Example.MSG.VendorOrder' create='new' language='objectscript' >
<assign value='##class(Example.UTL.FunctionSet).NormalizeKey(source.OrderId)' property='target.VendorRef' action='set' />
<assign value='..Lookup("OrderPriority", ##class(Example.UTL.FunctionSet).NormalizeKey(source.PatientId), "UNKNOWN")' property='target.Priority' action='set' />
<assign value='"ref=" _ source.OrderId _ " pid=" _ source.PatientId' property='target.Note' action='set' />
</transform>
}

}
