/// Rule: BestPractices_Interop_IRIS.md §5.11 "A `%Persistent` child needs a delete cascade, and the obvious cascade discards its own error"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (silent; the table becomes the biggest thing in the namespace).
///
/// Pattern: the CARRIER half. A message with a `%Persistent` child (Example.DAT.Address, in this
/// directory) and the delete trigger that stops the child rows accumulating.
///
/// WHY THE CASCADE IS NOT OPTIONAL. `Ens.Util.Tasks.Purge` deletes `Ens.MessageHeader` and the
/// message row. It knows nothing about a child in its own table, so the child rows stay — with
/// no error, no warning, and nothing in the Event Log. You find out when the table is the
/// largest object in the namespace, which is also the point of least freedom to fix it.
///
/// THREE THINGS IN THE TRIGGER, EACH OF WHICH HAS SHIPPED WRONG IN THIS REPO:
///
/// 1. `{Address}`, NOT `{ID}`. Inside a trigger `{ID}` is the row being deleted — the CARRIER's
///    own id. `%DeleteId({ID})` therefore deletes whichever CHILD happens to share that id: an
///    unrelated row, or none at all. It leaks exactly what the trigger was added to clean up,
///    and silently, because deleting nothing raises nothing. Use the REFERENCE property — the
///    column that actually holds the child's id.
///
/// 2. THE CHILD MUST REALLY BE `%Persistent`. The inline snippet this example replaces pointed
///    its cascade at a class declared `(%SerialObject, %XML.Adaptor)` while a comment claimed
///    "%Persistent in this variant". Measured on 2026.1: `%DeleteId` DOES exist on
///    `%SerialObject` — so this compiles — and at runtime returns
///        ERROR #5753: Cannot instantiate abstract class 'MyApp.DAT.Address'
///    A serial child has no rows of its own to leak, so the trigger was solving a problem that
///    did not exist, by a means that could not work.
///
/// 3. CAPTURE THE `%Status`. `Do ##class(...).%DeleteId(...)` DISCARDS it. Combined with (2)
///    that is the whole silent failure: the call fails, the status is thrown away, the trigger
///    reports success, the parent delete proceeds, and nothing anywhere records that the cascade
///    did nothing. `Set tSC = …` and act on it — below, by refusing the delete.
///
/// 4. GUARD THE EMPTY REFERENCE. `Address` is optional, and `%DeleteId("")` returns an error.
///    Without the `If {Address} '= ""` below, any carrier that never had a child sets `%ok = 0`
///    and becomes UNDELETABLE — so the trigger added to help a purge is what stops it. This one
///    is loud rather than silent, but it is loud in production and at scale.
///
/// THE TRADE-OFF IN `Set %ok = 0`, stated because it is a real choice and not a detail. Failing
/// the trigger ABORTS the parent delete, so a purge that cannot clean a child stops rather than
/// orphaning it — loud, and it will interrupt a purge schedule. The alternative is to log and let
/// the delete proceed, which keeps purges running and leaves a recorded orphan. Pick deliberately;
/// what is never right is the third option, discarding the status, because that is both an orphan
/// AND no record.
Class Example.MSG.PersonReqCascade Extends (%Persistent, Ens.Request)
{

Property Name As %String(MAXLEN = 100);

/// The reference. `{Address}` in the trigger below is THIS column — the child's id.
Property Address As Example.DAT.Address;

Trigger DeleteCascade [ Event = DELETE, Foreach = row/object ]
{
    // The empty guard is load-bearing, not defensive noise. Address is optional, and
    // %DeleteId("") returns an error -- so without this line a carrier that never had a child
    // sets %ok = 0 and becomes UNDELETABLE, which stops the purge it was meant to help.
    If {Address} '= "" {
        Set tSC = ##class(Example.DAT.Address).%DeleteId({Address})
        If $$$ISERR(tSC) {
            Set %ok = 0
            Set %msg = "cascade delete of Example.DAT.Address failed: "_$system.Status.GetErrorText(tSC)
        }
    }
}

}
