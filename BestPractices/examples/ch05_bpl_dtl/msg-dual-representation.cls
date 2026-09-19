/// Rule: BestPractices_Interop_IRIS.md §5.24 "A message carrying the same data twice: fill both, and never read the collection as a scalar"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, saved and read back.
/// Severity: High (the failure is silent on one path and produces a plausible wrong value on the other).
///
/// Pattern: the message shape you end up with when a modern producer sends a typed collection and an
/// older consumer still reads a delimited string. Both representations live on the class; a transform
/// is what keeps them in step.
///
/// THIS SHAPE IS A COMPROMISE, NOT A GOAL. Two properties holding one fact can disagree, and nothing in
/// IRIS will tell you they have. Carry it only while the legacy consumer exists, and delete `Supplies`
/// the day it does not.
///
/// WHY BOTH, MEASURED. Fill only `SupplyList` and save, then read the legacy side:
///
///     msg.Supplies                        ""        length 0 -- silent
///     msg.SupplyList.Count()              2         the data is there, in the other property
///
/// So a legacy Business Operation doing `$Piece(msg.Supplies, "|", 1)` gets an empty string and no error.
/// That is the row's claim and it holds.
///
/// AND THERE IS A WORSE ONE THE ROW DOES NOT MENTION. A consumer that reaches for the *collection* as if
/// it were the string does not get "" either:
///
///     $Piece(msg.SupplyList, "|", 1)      "41@%Collection.ListOfDT"
///     msg.SupplyList used as a scalar     "41@%Collection.ListOfDT"
///
/// An OREF renders as a **non-empty** string. So a guard written as `if value '= ""` passes, and the
/// object reference travels downstream as data. Empty is recoverable; `41@%Collection.ListOfDT` in a
/// vendor feed is a support call.
///
/// THE BRIDGE HAS ONE GOTCHA. `$ListToString` does not take the collection:
///
///     $ListToString(msg.SupplyList, "|")              RAISES <LIST>
///     $ListToString(msg.SupplyList.Serialize(), "|")  "PEN|LATEX"
///
/// `Serialize()` is what turns the collection into the `$List` that `$ListToString` wants. See
/// `dtl-fill-both-representations.cls` for the transform that uses it.
Class Example.MSG.SuppliesOrder Extends (%Persistent, Ens.Request)
{

Property OrderId As %String(MAXLEN = 64);

/// LEGACY representation: pipe-delimited, because the consumer predates the typed one. MAXLEN is the
/// real ceiling on how many items can be expressed this way -- another reason not to keep it for ever.
Property Supplies As %String(MAXLEN = 500);

/// TYPED representation, the one new code should read. No SQLPROJECTION: this collection is read
/// through the object, not joined (§5.22).
Property SupplyList As list Of %String(MAXLEN = 50);

/// The delimiter, in one place. A transform and a consumer that disagree about it fail silently too.
Parameter DELIM As STRING = "|";

}
