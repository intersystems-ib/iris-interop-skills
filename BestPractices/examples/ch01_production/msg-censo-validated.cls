/// Rule: BestPractices_Interop_IRIS.md §1.21 "RecordMap field types are not per-record validation, and what they do instead differs by type"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, transformed and read back.
/// Severity: Medium (the message shape; the finding it serves is High).
///
/// Pattern: the message a validating transform produces. Every field arrives as it was read -- as a
/// STRING -- and the verdict travels alongside it rather than replacing it.
///
/// WHY THE INBOUND FIELDS ARE `%String` AND NOT TYPED. That is the whole point of §1.21: a type on the
/// way in either accepts a value you did not want (`%Integer`) or raises (`%Date`). Keep the raw text,
/// decide about it explicitly, and carry the decision.
///
/// WHY A FLAG AND NOT A DROP. A record rejected inside the RecordMap never becomes a message, so there
/// is nothing in Visual Trace and nothing to route. A record that becomes a message WITH a verdict can
/// be sent to an error operation, counted, replayed, and seen. The cost of the flag is one property.
Class Example.MSG.CensoValidated Extends (%Persistent, Ens.Request)
{

Property PatientId As %String(MAXLEN = 64);

/// As READ, not as typed. The transform decides whether it is a number.
Property BedsRaw As %String(MAXLEN = 32);

/// As READ. `%Date` would have raised on a bad value before you could see it.
Property AdmittedRaw As %String(MAXLEN = 32);

Property Ward As %String(MAXLEN = 64);

/// The verdict. Empty means the record passed every check.
Property Problems As %String(MAXLEN = 500);

/// Set only when `Problems` is empty, so a consumer never reads a number the transform rejected.
Property Beds As %Integer;

/// 1 when the record passed. A boolean beside the reason, so a routing rule needs no string parsing.
Property IsValid As %Boolean [ InitialExpression = 0 ];

}
