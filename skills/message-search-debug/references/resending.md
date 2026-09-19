# Resending messages

Headless resend (there is no MCP tool for it), edit-and-resend without breaking the trail, and bulk resend. Read this when you are resending, not when you are searching.

## Contents

- Resending
- Headless resend — there is no MCP tool for this
- Edit & resend — change the payload without breaking the trail
- Bulk resend

## Resending

From the Message Viewer, a message can be **resent** to its original target or to a new target.
Useful after a fix on a downstream system.

**A resend stays in the ORIGINAL session.** This is the point of using the supported API rather
than re-sending the body yourself: the new header carries the original `SessionId`, so the resend
appears in the original message's trace and the whole story stays in one place. Measured on IRIS for
Health 2026.1 — one original delivery plus two resends, all in session `2`:

```
what=trace session_id=2
  ID 3  Verify.MSG.PingReq  -> BO.Echo     the original
  ID 6  Verify.MSG.PingReq  -> BO.Echo     plain resend        (same session)
  ID 8  Verify.MSG.PingReq  -> BO.Echo     edited resend       (same session)
```

### Headless resend — there is no MCP tool for this

`iris_interop_query` has no resend mode (`what` accepts only `logs`, `queues`, `messages`, `trace`,
`partners`). Without the Portal, resend one message by header ID with:

```objectscript
Set newId = "", sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(<headerId>, .newId)
// sc = %Status; newId = the header ID of the new message
```

The full signature — read off `%Dictionary.CompiledMethod`, since `docs_introspect` does not surface
it (below):

```
ResendDuplicatedMessage(pOriginalHeaderId, *pNewHeaderId, pNewTarget, pNewBody, pNewSource, pHeadOfQueue) As %Status
```

`pNewTarget` re-routes the resend; `pNewBody` replaces the payload (see edit & resend); all four
trailing arguments are optional.

Run it through `iris_execute`; it persists (this is a runtime side effect, not class generation, so
it does not hit the objectgenerator no-op trap). Verified on IRIS 2026.1: resending header `102`
returned `$$$OK` and `newId = 171`, and the new session appeared in `Ens.MessageHeader` immediately.

**`docs_introspect` will not help you find this method** — asking for
`Ens.MessageHeader::ResendDuplicatedMessage` returns `{"methods":[],"properties":[],"success":true}`,
an empty result that reads as "no such method". It exists; the introspection just doesn't surface it.

Confirm the resend landed by header ID, not by re-listing everything:
`iris_query("SELECT ID, SessionId, TargetConfigName, Status FROM Ens.MessageHeader WHERE ID >= <newId>")`.

### Edit & resend — change the payload without breaking the trail

Resending a message you first had to *fix* (a bad code, a missing field) is the common case, and the
obvious route is the wrong one. **A plain resend SHARES the original body** — verified: original
header `3` and resent header `6` both point at `MessageBodyId=1`. So editing that body in place to
"fix" it rewrites what the original message said, and the audit trail now lies.

Clone the body, edit the clone, and hand it to the resend as `pNewBody`:

```objectscript
Set hdr   = ##class(Ens.MessageHeader).%OpenId(origHeaderId)
Set body  = $classmethod(hdr.MessageBodyClassName, "%OpenId", hdr.MessageBodyId)
Set clone = body.%ConstructClone(1)          ; 1 = deep clone
Set clone.Texto = "corrected value"          ; or SetValueAt(...) on an EnsLib.HL7.Message
Do  clone.%Save()

Set newId = "", sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(origHeaderId, .newId, "", clone)
```

Verified outcome: the new header keeps `SessionId` and `TargetConfigName` of the original, points at
the **new** body, and the original body still reads what it always did.

**Anti-pattern — do NOT re-inject the edited body through `EnsLib.Testing.Service`.** It is the
reflex move, it reports success, and it quietly does the wrong thing: measured, the same clone sent
via `SendTestRequest` landed in **session 10** while the original was session `2`. The resend is then
absent from the original trace, nothing marks it as a resend of anything, and the connection between
the failure and its fix exists only in your memory. The Testing Service is for injecting *new* test
traffic, not for re-driving a real message.

**Check idempotency before you resend anything.** A resend re-executes whatever the message already
did downstream. If the first attempt got far enough to INSERT a row or ACK a partner, the resend does
it again — the reported symptom was `duplicate key value violates unique constraint` from inserting
the same patient twice. A message that *errored* is not necessarily a message that did *nothing*:
check where in the session it stopped (`what=trace`) before assuming it is safe to replay.

### Bulk resend

From the Portal: filter Message Viewer to the affected window + status `Error`, select all, resend.
Headless, there are dedicated APIs — the documentation calls them "more efficient than the Message
Viewer page for resending large numbers of messages":

```objectscript
Set filter("SourceConfigName") = "HttpService"
Set filter("Status") = "Error"
Set sc = ##class(Ens.MessageHeader).ResendMessageBatch(.filter, 0, 0, .count)
```

```
ResendMessageBatch(&filter, resubmit=0, headOfQueue=0, *resentCount) As %Status
ResendMessageBatchAsync(*queueToken, &filter, resubmit=0, headOfQueue=0) As %Status
```

`ResubmitMessage(pHeaderId, pNewTarget, pNewBody, pHeadOfQueue)` and its
`PrepareResubmitMessage(...)` companion also exist for the resubmit (rather than duplicate) flavour.

Before bulk-resending: verify **idempotency** on the downstream BO. A non-idempotent BO will create
duplicates — fix that first or use a manual loop with deduplication logic in the BP. The blast radius
here is the whole filter, so the idempotency question above is not optional at this scale.

## Worked examples in this repo

All four are compiled by CI on every release, and together they are the whole §12.6 circuit — the
point of the fixture is that resend and edit-and-resend share one body row, so an edit rewrites the
history of the original send too:

- `../assets/resend-edit-and-resend.cls` — the two APIs side by side
- `../assets/production-resend-fixture.cls` — the production that makes the shared-body
  behaviour observable
- `../assets/bo-message-sink.cls` — the sink the resent messages land in
- `../assets/tdd-resend-edit-and-resend.cls` — the `%UnitTest` that pins it
