/// Rule: BestPractices_Interop_IRIS.md §5.10 "Message class design — `%Persistent` must be leftmost, and no compile will tell you it is not"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (silent; and expensive exactly when it is finally noticed).
///
/// Pattern: the canonical interop message class. The only thing it demonstrates is the
/// superclass LIST ORDER, because that is the only thing about it that can be silently wrong.
///
/// THE MEASUREMENT, because this is a claim nobody can check by reading. All three spellings
/// below compile clean, project to SQL, save, and read their properties back correctly. Only the
/// storage global differs. Read out of %Dictionary.CompiledStorage.DataLocation on 2026.1:
///
///   Extends (%Persistent, Ens.Request)   ->  ^Example.MSG.OrderEventD    own extent
///   Extends (Ens.Request, %Persistent)   ->  ^Ens.MessageBodyD           SHARED
///   Extends Ens.Request                  ->  ^Ens.MessageBodyD           SHARED
///
/// The middle line is the trap, and it is worse than the third: `%Persistent` is present, so the
/// rule LOOKS followed. IRIS takes the leftmost superclass as primary and the primary superclass
/// drives storage, so `%Persistent` anywhere but first is the same as not writing it at all.
///
/// WHY THE SHARED EXTENT COSTS YOU. Every message body in the namespace lands in one global.
/// Per-message-type purging, a selective index, a SELECT over one message type, and any per-type
/// storage tuning all stop being available -- and you find out when you have a production-sized
/// ^Ens.MessageBodyD and the least freedom to change anything. In development it is invisible:
/// with a hundred test messages, nothing about a shared extent looks wrong.
///
/// NO TIER OF THE GATE CAN CATCH THIS. It is not a syntax error, not a runtime error, and not a
/// wrong result -- it is a storage decision a compiler has no opinion about. tdd-message-own-extent.cls
/// in this directory is the only mechanical check that exists: it reads DataLocation and asserts
/// the global name.
///
/// NO HAND-WRITTEN STORAGE BLOCK. Let the compiler generate it. A hand-written `Storage Default`
/// pinned to the wrong global is how this defect survives a later correction of the superclass
/// list -- the declaration gets fixed, the storage keeps pointing where it always did.
Class Example.MSG.OrderEvent Extends (%Persistent, Ens.Request)
{

/// The business key. Measured, so the comment does not overclaim: this index COMPILES under the
/// wrong superclass order too -- what changes is that on the shared extent it spans every message
/// type in the namespace instead of this one. The index is not a check on the rule; the
/// DataLocation is.
Property OrderId As %String(MAXLEN = 64) [ Required ];

Property PatientId As %String(MAXLEN = 64);

Property EventType As %String(VALUELIST = ",NEW,AMEND,CANCEL") [ InitialExpression = "NEW" ];

Property OccurredAt As %TimeStamp [ InitialExpression = {$ZDateTime($Horolog, 3)} ];

Index OrderIdIdx On OrderId;

}
