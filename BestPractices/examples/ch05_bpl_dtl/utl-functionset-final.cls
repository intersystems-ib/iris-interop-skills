/// Rule: BestPractices_Interop_IRIS.md §5.13 "Calling a function from a DTL — the two forms have opposite rules and the wrong one is silent"
/// Validity: Verified against IRIS for Health 2026.1 — every call form below was compiled AND run.
/// Severity: High (the wrong form compiles and throws only when a message flows).
///
/// Pattern: a custom function set. Subclass `Ens.Rule.FunctionSet` — NOT `Ens.Util.FunctionSet`,
/// which is its superclass. Per EGDV §12.1 only class methods defined in YOUR class become
/// utility functions, and because there is no polymorphism support they must be marked `[ Final ]`.
///
/// HOW THIS IS CALLED DEPENDS ON WHERE YOU CALL IT FROM, and the two contexts have OPPOSITE
/// requirements. All six combinations measured on 2026.1:
///
///   In a DTL <assign>:
///     ##class(Example.UTL.FunctionSet).NormalizeKey(x)   compiles, WORKS          <-- use this
///     ..NormalizeKey(x)                                  COMPILE FAILS, MPP5392 "No such method"
///     NormalizeKey(x)                                    compiles, <UNDEFINED> at Transform time
///
///   In a business rule <when condition>:
///     AlreadyReportedErr(...)                            compiles, WORKS          <-- use this
///     ##class(Demo.FilterAlerts.FunctionSet).Already...  COMPILE FAILS, <Ens>ErrInvalidToken
///
/// So a DTL wants the call QUALIFIED and a rule wants it BARE, for the same method on the same
/// class. That inversion is the whole reason this is got wrong, and the two failures are not
/// equally kind: the DTL's `..` form and the rule's `##class()` form fail at COMPILE, which is
/// fine, while the DTL's BARE form compiles clean and throws `<UNDEFINED>` only when a message
/// flows through it -- in production, on real data, long after the gate went green.
///
/// BUILT-INS ARE THE OPPOSITE WAY ROUND AGAIN, which is where the one-character mistake comes
/// from. Measured in a DTL:
///     ..Strip(source.Raw,"<>W")     compiles, WORKS
///     Strip(source.Raw,"<>W")       compiles, <UNDEFINED> at Transform time
///     ..Lookup("T",x,"dflt")        compiles, WORKS
///     Lookup("T",x,"dflt")          compiles, <UNDEFINED> at Transform time
/// A built-in in a DTL takes `..`; a custom function in a DTL takes `##class()`. Neither takes the
/// bare form, and the bare form is the one that reaches production.
Class Example.UTL.FunctionSet Extends Ens.Rule.FunctionSet
{

/// Fold case, strip whitespace and remove accents, so a lookup key matches whatever the partner
/// sent. `[ Final ]` is required for this to be usable as a utility function (EGDV §12.1).
///
/// The mask is `"*WC"` and the accents are folded with $TRANSLATE. Do not "simplify" it: measured,
/// `"*-CWE"` raises <FUNCTION> and `"*CWE"` returns "" for every input, and neither is visible to
/// a compiler. See `lookup-tables` §"Two `$ZSTRIP` traps".
ClassMethod NormalizeKey(pValue As %String) As %String [ Final ]
{
    Set tAccents = "áéíóúàèìòùäëïöüâêîôûñç"
    Set tPlain = "aeiouaeiouaeiouaeiouncc"
    Quit $TRANSLATE($ZSTRIP($ZCONVERT(pValue, "L"), "*WC"), tAccents, tPlain)
}

/// DD/MM/YYYY to a %Date, empty on bad input. The policy -- empty rather than an error -- belongs
/// here so every call site agrees; validation of the RESULT belongs in the DTL.
ClassMethod ParseDateDMY(pValue As %String) As %Date [ Final ]
{
    Set tDate = $ZDATEH(pValue, 4, , , , , , , -1)
    Quit $Select(tDate = -1: "", 1: tDate)
}

}
