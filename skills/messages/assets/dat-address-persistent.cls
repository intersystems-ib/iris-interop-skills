/// Rule: BestPractices_Interop_IRIS.md §5.11 "A `%Persistent` child needs a delete cascade, and the obvious cascade discards its own error"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (rows accumulate forever, with nothing in the Event Log).
///
/// Pattern: the CHILD half of the cascade pair — a sub-object deliberately declared
/// `%Persistent` rather than `%SerialObject`, which is what creates the obligation to cascade.
///
/// WHICH ONE TO USE, because the choice IS the whole subject:
///
///   %SerialObject   serialised INLINE into the parent's row. No separate table, no separate
///                   rows, and therefore NOTHING to cascade — purging the message purges the
///                   address with it. This is the right default.
///   %Persistent     its own table and its own rows. The parent holds a reference. Purging the
///                   message leaves the child row behind unless something deletes it.
///
/// Reach for `%Persistent` when the inline form is the problem: a deeply recursive structure
/// (CDA sections containing sections is the standard offender) bloats the parent's row and
/// inflates retention storage that does not free cleanly. The cost of switching is exactly one
/// obligation — the cascade in the companion file — and it is an obligation nothing enforces.
///
/// NOT AN Ens.Request. This is a data class, hence the DAT Tipo. It is referenced BY a message;
/// it is not itself a message body, and giving it an Ens superclass would put it on the message
/// header's extent and defeat the point of the split.
Class Example.DAT.Address Extends (%Persistent, %XML.Adaptor)
{

Property Street As %String(MAXLEN = 200);

Property City As %String(MAXLEN = 100);

Property PostCode As %String(MAXLEN = 10);

}
