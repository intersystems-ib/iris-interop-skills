# Connected BASE

A connected BASE reaches its Perforce server directly. The CCR client tools run the Perforce client (`p4`)
on the IRIS server, with no ItemSet in between:

| CCR menu action | What the client tools run |
|---|---|
| Check Out | `p4 edit` on the exported file, plus a row in the uncommitted queue (`P4Issued` set, `Committed=0`) |
| Add to Source Control | `p4 add` |
| Undo Check Out | `p4 revert`, then the item is reloaded from the file |
| Check In | `p4 submit` of a changelist whose **Job** is the CCR ID; the queue rows become committed |

`Disconnected()` returns 0. A value of 1 or 2 means disconnected: see `disconnected-base.md`.

## Perforce identity: the MCP's IRIS user matters

- The client tools look up the Perforce credentials **for `$USERNAME`**, the IRIS user of the process. Through
  the MCP, that is the IRIS user the MCP connects as.
- In a multi-developer BASE with a shared Perforce workspace, the client tools use the **IRIS username as the
  Perforce username**. The MCP must therefore connect as the developer's own IRIS user, never as `_SYSTEM` or
  a shared service account. Otherwise every check-out and change is attributed to the wrong person, or fails.
- Each MCP call runs in a fresh IRIS process, so a password typed into an IDE session does not carry over.
  What does work across processes is a **Perforce ticket stored for that IRIS user**. The human creates it by
  logging in through the source-control menu (the Perforce login page), and it lasts until it expires.
- Check the ticket with `ValidatePerforceTicket` (`probes.md`) at the start of every session. If it is not
  valid:
  - CCR turns every check-out into a **login page**: `UserAction` returns action 2 with a `…action=Login…` URL.
  - `iris_source_control` shows that URL as a yes/no question. **Do not answer yes.** Stop, and ask the human to
    log in to Perforce.

## Tool output in a connected BASE

- The client tools echo each p4 command to the current device (`CMD: p4 edit //…`), and may print warnings
  such as `Warning: file … is currently checked out by <client>`.
- **The MCP's answer after a "yes" is not reliable.** iris-interop-dev (0.25.0) keeps only the first line of
  the hook's output, and CCR's output always starts with a newline. So every action resumed with "yes"
  (check-out, add, undo) is reported as `success:true`, **even when it failed**. A failed `%AddToSourceControl`
  returned `success:true` while CCR had deleted the file and the queue row (intersystems-ib/iris-interop-dev#418).
- Rule: after **any** "yes", confirm the effect yourself. Use `iris_source_control action=status` or `action=menu`
  (an enabled `%UndoCheckout` means this user holds it), and for an add or an undo, the uncommitted queue. Never retry a check-out blindly: a second `p4 edit` on a
  file you already hold is harmless, but a retry on a file someone else holds is not.
- "checked out by <client>" means another Perforce workspace holds the file. Stop and report it.

## The check-in: prepared by the agent, submitted by the human

CCR's Check In is a page, not an API. `%Studio.SourceControl.ISC.CheckIn` is not implemented, and the menu item
opens `%Studio.SourceControl.UI` (action 2).

The page writes a changelist spec and runs `p4 submit -i`. The spec contains:
- `Change: new`
- `Jobs: <CCR ID>`
- `Client`
- `User`
- `Description`
- `Files: <selected depot paths>`

Files in a non-default changelist are first reopened into the default one.

What the agent does:
1. **List the queue rows for this CCR and user** (`probes.md`): item, action, file. Flag any row that is not on
   the plan.
2. **Undo every check-out that has no change** (SKILL.md, loop step 7).
3. **Fill `assets/checkin-handoff.md`:**
   - the items to tick;
   - the description `<CCR ID>: <title>`, plus one line per logical change;
   - Job = CCR ID;
   - the diffs to look at.
4. **Stop.** The human opens *Source Control → Check In* (VS Code server-side source control, or Studio),
   diffs each file, ticks the items, pastes the description, sets **Job = CCR ID** and submits.
5. **After the human confirms, verify:** the queue rows are `Committed=1`, and the CCR's Perforce Details →
   Submitted Changes lists the items with the right actions (edit, add, delete). The human reads the CCR page;
   the agent reads the queue.

Never run `p4 submit`, `p4 change` or any other `p4` command yourself, through `iris_execute` or otherwise. That
skips the queue bookkeeping and the human diff review.

## After the human's check-in
- The check-in page runs `p4 submit` but does **not** update CCR's uncommitted queue.
  `%Studio.SourceControl.Change.RefreshUncommitted` runs only on Reconnect and Disconnect.
- Until the item's next check-out, the queue still lists the submitted item as uncommitted (`add` or `edit`).
  `status` and `menu` are correct, though: the file is read-only again, so the item shows as not checked
  out, and the next edit asks for a check-out as usual. That check-out marks the stale row committed and opens
  a new `edit` row. (Measured 2026-10-04/05, with the workspace on a normal filesystem.)
- So when preparing a hand-off, do not trust the queue alone. List only the rows whose item `status` says
  checked out by you. The others are already in Perforce.
- The workspace must be on a normal filesystem. On a macOS Docker bind mount, read-only files look writable
  to IRIS, and then status, export and check-out all go wrong.

## The workspace file wins on open
When the workspace file changes (a `p4 sync`, a GetLatest, a colleague's submit), the next open of the item
(`iris_doc get`) imports the file over the IRIS copy (`OnBeforeLoad` → `Load()`). Never leave an edit in IRIS
that is not checked out and exported: it can be overwritten silently.
