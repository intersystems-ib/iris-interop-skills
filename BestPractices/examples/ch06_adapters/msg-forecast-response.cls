/// Rule: BestPractices_Interop_IRIS.md §6.16 "The typed SOAP BO: the client class belongs in configuration, and what that costs"
/// Validity: Verified against IRIS for Health 2026.1 — compiled.
/// Severity: Medium (the sibling that keeps the BO's signature resolvable).
///
/// Pattern: the response the SOAP BO fills. Note `Approved` is a `%String`, not a `%Boolean`, and
/// that is deliberate: §6.15 measured that SOAP and JSON booleans arrive as the STRINGS `"true"` and
/// `"false"`, and that **neither** `"true"=1` nor `"false"=0` is true. Typing this `%Boolean` would
/// make the datatype coerce `"true"` to 0 on the way in — losing the answer before anyone tests it.
/// Keep the wire value, and convert with an explicit string test.
Class Example.MSG.ForecastRsp Extends (%Persistent, Ens.Response)
{

Property Location As %String(MAXLEN = 100);

Property Forecast As %String(MAXLEN = 500);

/// The wire value, unconverted -- see the class comment.
Property Approved As %String(MAXLEN = 10);

}
