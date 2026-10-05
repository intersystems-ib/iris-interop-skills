---
name: ccr-workflow
description: Editing an IRIS BASE namespace under InterSystems CCR change control (IRIS_INTEROP_SCM=ccr) - environment check, check-out, edit and test through the MCP, undo untouched check-outs, check-in or bundle hand-off; the human submits, moves the CCR and reviews. Triggers EN: CCR, change control, check-out, check-in, uncommitted queue, ItemSet, Bundle and Upload, Perforce job, Perforce ticket, BASE namespace, In_BASE, %buildccr, IRIS_INTEROP_SCM. Triggers ES: CCR, control de cambios, hacer check-out, hacer check-in, cola de cambios pendientes, subir al CCR, entorno BASE, ticket de Perforce.
---
# CCR workflow: editing an IRIS namespace under CCR change control

Under CCR the IRIS **BASE namespace is the source of truth**, not files on disk. Every save goes through the
source-control hooks (`%Studio.SourceControl.ISC`). The hooks export the item to the CCR workspace and record
it in the **uncommitted queue** (`%Studio_SourceControl.Change`).

A "commit" sends those items into **one CCR**:
- in a **connected BASE** (the usual setup), a Perforce check-in whose Job is the CCR ID;
- in a disconnected BASE, a Bundle and Upload of an ItemSet.

People, not the agent, move a CCR through its workflow. This skill changes *where the truth is* and *who
submits*; how to build the components themselves is still in the other `iris-interop-skills` skills.

**It applies only in CCR mode.** Establish the mode as the `interop` router says (`check_config` if it reports
the mode as set, then `IRIS_INTEROP_SCM`, then `.claude/iis-scm`). If the namespace's source-control class is
`%Studio.SourceControl.ISC` but the mode is `files`, **stop** and ask the human to set
`IRIS_INTEROP_SCM=ccr` (README, "Source control: git vs CCR"). In `files` mode the gates push you to write
`src/` first, and a local copy put over a checked-out item loses the server's version.

## Never (non-negotiable)

- **Never change a CCR's state.** That covers `markPREPComplete`, `markBASEComplete`, peer review, every
  authorize and move transition, backout, merge and cancel. Transitions are accountability points for named
  people.
- **Never peer-review a change you took part in.** The agent and the human driving it count as one author.
  Draft the packet for *another* reviewer instead.
- **Never submit.** Do not run `p4 submit`, do not upload an ItemSet, and do not check in without an explicit
  human "yes" given for this CCR in this conversation. By default, prepare the hand-off and let the human
  submit.
- **Never work outside BASE.** If the environment check says `TEST`, `UAT` or `LIVE`, stop. If a check-out
  dialog warns "Changes to '<env>' should only be made for critical debug purposes", answer **no** and stop.
- **Never run `%Disconnect`, `%Reconnect` or `TakeOwnership`.** Never run `p4` through `iris_execute` (`$ZF`),
  and never load code with `$SYSTEM.OBJ.Load/Compile`. All of these bypass the CCR bookkeeping.
- **Never let a secret into the chat, a file or memory.** That covers the CCR access token, the Perforce
  password and the IRIS password. The human enters them in the CCR UI or directly into IRIS.
- **Never check out "just in case".** A check-out is an exclusive lock per IRIS user. Every item you lock and
  do not change blocks a colleague and pollutes the CCR.

## Step 0: establish the context, once per session

**Before the first probe, read [references/probes.md](references/probes.md).** It carries the exact read-only
one-liners for the environment, the Perforce ticket, the queue and the CCR state, each tested on a connected
BASE, and the table of which CCR menu actions the MCP can drive.

1. **Environment.** One read-only `iris_execute` (the Environment probe). It reports `Env`, `Org`, `Sys`,
   `Disconnected()` (0 = connected), the source-control class, `CCRServer` and the IRIS user. Continue only if:
   - `Env` is `BASE`;
   - the source-control class is `%Studio.SourceControl.ISC`;
   - the IRIS user is the developer's own, not `_SYSTEM` or a shared account.
2. **The CCR.** Ask the human for the CCR ID and title if they are not in the prompt, and confirm it is
   **In_BASE** (the CCR record shows it; in a disconnected BASE, `ItemSet.WSCanUpload` also reports it).
   - In_PREP: do not edit. Offer to draft the planning fields and stop.
   - Any state past BASE: hands off. **Before deciding what a state allows, read
     [references/states-and-roles.md](references/states-and-roles.md).** It carries the per-state table of
     what the agent may and must not do, and the warnings that mean stop.
3. **Connected BASE only: Perforce access.** Run `ValidatePerforceTicket` once.
   - Without a valid ticket for the IRIS user the MCP connects as, every check-out turns into a CCR login page.
     Ask the human to log in to Perforce through the source-control menu, and stop.
   - **Before the first check-out in a connected BASE, read
     [references/connected-base.md](references/connected-base.md).** It carries the Perforce identity rules,
     why the MCP's answer after a "yes" cannot be trusted, what the Check In page does, and why the queue still
     lists items that were already submitted.
   - **In a disconnected BASE, read [references/disconnected-base.md](references/disconnected-base.md)
     instead.** It carries Bundle and Upload, access tokens and the token-free state check.
4. **Tooling.** `iris_source_control` must be in your tool list. The `iris-interop-dev` default `interop`
   toolset hides it: ask the human to set `IRIS_TOOLSET=baseline`. Pass `namespace=` on every call.

## The loop, per item

1. **Plan the smallest item list** that implements the CCR, and show it before touching anything. Each item is
   a class, a rule, a DTL, a production host (PTD) or a lookup table. Anything unrelated you notice becomes a
   *suggestion for a new CCR*, never an extra item.
2. **Status first:** `iris_source_control action=status document=<Item.cls>`.
   - Checked out by someone else: stop and name the owner.
   - Already checked out by this user: skip to 4.
3. **Check out:** `iris_source_control action=checkout`. CCR answers with a yes/no dialog: relay the message
   and answer `yes` only for an item on the plan.
   - **After every `yes` (check-out, add, undo), verify the effect** with `action=status` and, for an add or an
     undo, the queue. The MCP can report `success:true` when the CCR action failed (iris-interop-dev#418).
   - The tool may also report `SCM_CHECKOUT_FAILED` quoting `CMD: p4 edit …` for a check-out that worked.
     Verify with `action=status` before any retry.
4. **Refresh:** `iris_doc mode=get` right after the check-out. Edit *that* content, never an older local copy:
   `iris_doc put` does not detect conflicts, so a stale copy silently overwrites the server version. The get is
   also what this plugin's PreToolUse gate looks for before it lets a put through.
5. **Edit, put, compile:** `iris_doc mode=put` then `iris_compile`, following the interop skills for the
   content.
   - **New item:** first `iris_doc mode=head` to confirm it does not exist (that read clears the gate for a new
     document). A class created with `iris_doc put` is **not** under source control yet: no queue row, no
     export, nothing in Perforce. Right after its first put, run
     `iris_source_control action=execute action_id=%AddToSourceControl` (answer `yes`), then confirm it
     appears in the queue with Action `add`.
   - **After the first save, `iris_doc get` again.** The CCR hook may insert `Parameter SrcVer = "$Id$";`,
     so the version in IRIS is no longer the one you wrote.
   - **Deleting an item:** ask the human first.
6. **Test** with `iris_test` as the `tdd` skill says.
   - Test classes land in the CCR too, unless the project maps them elsewhere. Ask the human once per CCR
     whether tests belong in it.
   - After test runs, check the queue for `IrisDevTmp.*` rows (MCP scratch classes) and report any.
7. **Close the loop.** Read the queue for this user. Undo the check-out of every item on it that you did not
   change: `action=execute action_id=%UndoCheckout`, answer `yes`.
   - After an undo, `iris_doc get` the item. Perforce and the queue are reverted, but IRIS can keep the
     edited version. If it differs from the workspace file, report it to the human. Do not put the old
     copy back.

**On any error, warning or unexpected tool answer, read [references/errors.md](references/errors.md) before
retrying.** It maps each symptom (false success, login URL, `#5865`, "Invalid Token", conflict warnings) to
what it means and the one thing to do.

## Productions

- With production decomposition, each business host is its own source-controlled item (a PTD file). After
  changing a host through `iris_production_item`, check the queue: only that host should appear.
- Do **not** `iris_doc put` the whole production class to "sync" it. That touches every host and can revert
  items changed by someone else.
- Environment-specific values (ports, IP addresses, credentials) belong in System Default Settings or in the
  CCR's Implementation Plan, not hard-coded in the production.

## The hand-off: the human submits

When every item compiles and the tests pass:
1. **Show the queue** for this CCR: item, action and diff summary. The human must see exactly what will be
   submitted. List only rows whose `status` says checked out by you: the Check In page does not update CCR's
   queue, so items submitted earlier can still appear as uncommitted.
2. **Before writing the hand-off, read [assets/checkin-handoff.md](assets/checkin-handoff.md) and fill it in.**
   It carries the items to tick, the description `<CCR ID>: <CCR title>`, the Perforce **Job** = CCR ID
   (required in a connected BASE), and the author's steps.
   - Connected: the human runs *Source Control → Check In*, diffs, submits, then checks the CCR's Perforce
     Details → Submitted Changes.
   - Disconnected: the human runs *Commit Changes via ItemSet* (Bundle and Upload) with the CCR ID and the
     access token.
3. **Draft, do not submit, the human's next steps:** "Testing Steps Taken in BASE", with the evidence from
   the tests; and **before drafting for the reviewer, read [assets/review-packet.md](assets/review-packet.md)**,
   which carries the packet's sections. The human then runs `markBASEComplete` and gets the review done by
   someone else.

**When the CCR is still In_PREP and the human asks for the planning fields, read
[assets/planning-fields.md](assets/planning-fields.md) first.** It carries the Implementation, Backout and
Testing Plan skeletons, written so another person can run them in any environment.

## Delegating under CCR

A subagent inherits neither the mode nor this skill. In its prompt, say the project is under CCR, give it the
CCR ID, and include `Skill(iris-interop-skills:ccr-workflow)` with the other `Skill(...)` calls. It follows
the same loop and the same Never list: it never submits, and it hands back the items it checked out.

## This plugin's gates under CCR

With `IRIS_INTEROP_SCM=ccr` the disk-first gates invert. A hook cannot reach IRIS, so each one reads the session
transcript, subagents included:
- **`src_before_iris`** denies a put of a document this session has not read. An `iris_doc get` (existing),
  an `iris_doc head` (new) or an `iris_source_control` check-out of it clears it. A check-out made outside the
  session is invisible to it: get the document first.
- **CR-12 is skipped.** The Stop gate lists the documents put this session instead. Reconcile that list with
  the queue yourself (the queue probe): a new class missing from it was never added to source control.
- **`src_drift_guard` is silent.** Never refresh IRIS from a local copy; refresh the local copy from IRIS.
- **The naming rule only advises.** Existing customer classes keep their names: a rename under CCR is a delete
  plus an add, a bigger change and broken production references.
- **Unchanged:** `namespace=` on every call, no class loading through `iris_execute`, the superclass and
  routing rules, TDD, and the conformance pass before declaring done.
