# Read-only probes

Run each ObjectScript line with `iris_execute(code=…, namespace=<BASE ns>)`. The SQL goes through
`iris_query(namespace=<BASE ns>)`. None of these check anything out, write source or submit anything.

## Environment (Step 0)
```objectscript
Write "Env=",$$Env^%buildccr()," Org=",$$Org^%buildccr()," Sys=",$$Sys^%buildccr()," Disconnected=",##class(%Studio.SourceControl.ISC).Disconnected()," SC=",##class(%Studio.SourceControl.Interface).SourceControlClassGet()," CCRServer=",$$CCRServer^%buildccr()," User=",$USERNAME,!
```
Expected in a working BASE:
- `Env=BASE`.
- `SC=%Studio.SourceControl.ISC`.
- `Disconnected=0` for a connected BASE; 1 or 2 for a disconnected one.
- `User=` the developer's own IRIS user. `_SYSTEM`, `irisowner` or a service account means the MCP is connected as
  the wrong identity: stop and tell the human.

Client-tools version, when reporting a problem: `Do Version^%buildccr`.

## Perforce credentials (connected BASE only)

Presence check. It prints only whether a credential is stored, never its value:
```objectscript
Set ok=##class(%Studio.SourceControl.ISC).GetCredentials(.u,.p,.ws) Write "p4user=",$Get(u)," workspace=",$Get(ws)," credential stored=",($Get(p)'=""),! Kill p
```

Validation runs `p4 login -s`, **once per session**:
```objectscript
Set sc=##class(%Studio.SourceControl.ISC).ValidatePerforceTicket(.left) Write $Select(sc=1:"ticket OK, expires in "_left,1:"NO VALID TICKET: "_$System.Status.GetErrorText(sc)),!
```
On any failure, including a network error, `ValidatePerforceTicket` **deletes the stored ticket**. Never call it
in a loop or as a retry.

## The uncommitted queue
```sql
SELECT InternalName, Action, ChangedBy, CCR, P4Issued, Committed, UpdatedTime, ItemFile
FROM %Studio_SourceControl.Change
WHERE Committed = 0
ORDER BY UpdatedTime
```
Add `AND ChangedBy = '<IRIS user>'` for this user's rows only.
- `Action` is `edit`, `add` or `delete`.
- `P4Issued` set in a connected BASE means the p4 command ran; the change is still not submitted.
- `CCR` is filled only when the check-out was tagged with a CCR, so do not rely on it to select rows.

## One item

- `iris_source_control action=status document=<Name.cls>` returns the lock state and the owner.
- `iris_source_control action=menu document=<Name.cls>` shows what is enabled. `%UndoCheckout` enabled means
  this user holds the check-out. `%CheckOut` enabled means it is free.

## CCR state, without a token
```objectscript
Set sc=##class(%Studio.SourceControl.ItemSet).WSCanUpload("<CCR ID>",$$Org^%buildccr(),$$Sys^%buildccr(),.why) Write $Select(sc=1:"upload allowed",1:$System.Status.GetErrorText(sc)),!
```
It returns "upload allowed", or the CCR server's reason, for example "record is in state In_PREP. The CCR must
be in In_BASE or BASE_Pending_Peer_Review." It calls the CCR server named by `$$CCRServer^%buildccr`.

## What `iris_source_control` can and cannot drive

| Menu item | CCR returns | Through the tool |
|---|---|---|
| `%CheckOut` | 1 (yes/no) | `action=checkout`. Answer `yes` only for planned items. |
| `%UndoCheckout` | 1 (confirm revert) | `action=execute action_id=%UndoCheckout` |
| `%AddToSourceControl` | 1 | `action=execute action_id=%AddToSourceControl` |
| `%GetLatest` | 0 (runs at once) | `action=execute` |
| `%CheckIn`, `CommitChanges`, `CCRControls`, `Diff`, `TakeOwnership` | 2 (a page in the CCR UI) | Not supported ("Unexpected action code 2"). These are human steps. |
| `CCRFileHistory` | 3 (a URL) | Not supported |
| `%Disconnect`, `%Reconnect` | 0 (runs at once, no prompt) | **Never.** They switch the Perforce integration off or on. |
| Any item without a valid Perforce login (connected) | 2 (login page) | Shown as a yes/no question with a Login URL. Answer **no**; the human logs in. |

The iris-interop-dev `interop` toolset hides `iris_source_control`: it needs `IRIS_TOOLSET=baseline`.
