# Check-in hand-off: <CCR ID> "<title>"

Prepared by the agent. The **author** submits it.

**Namespace** `<BASE ns>`, **IRIS user** `<user>`, **system** `<Org>/<Sys>`, **mode** connected (Perforce) or
disconnected (ItemSet).

## Items to tick (and only these)
| Item | Action | What changed, in one line | Look at the diff for |
|---|---|---|---|
| `<Name.CLS>` | edit / add / delete | … | … |

Untouched check-outs that were undone: `<list, or none>`.
In the queue but **not** part of this CCR, so leave them unticked: `<list, or none>`.

## Fields
- **Description:** `<CCR ID>: <CCR title>`, followed by one line per logical change.
- **Perforce Job:** `<CCR ID>` (required in a connected BASE).
- **Disconnected BASE only:** the CCR ID and the *Access Token* from Perforce Details. The author types the token
  in the Bundle screen; it never goes in the chat.

## Steps for the author
1. Connected: *Source Control → Check In*. Disconnected: *Source Control → Commit Changes via ItemSet*.
2. Diff every ticked item.
3. Tick exactly the items above, fill in the fields and submit.
4. In the CCR: Perforce Details → Submitted Changes lists every item with the right action.
5. Tell the agent. It then checks the queue rows are committed, and drafts "Testing Steps Taken in BASE" and the
   review packet.
