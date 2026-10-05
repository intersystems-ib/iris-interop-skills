# Disconnected BASE

A disconnected BASE has no direct Perforce access. The CCR client tools package the changed items into an
**ItemSet** and upload it to the CCR server, which submits it to Perforce on the CCR's behalf. `Disconnected()`
returns 1, or 2 when the BASE is permanently disconnected. The loop (check-out, refresh, edit, test, undo the
untouched) is the same as in a connected BASE. Only the commit differs.

## Bundle and Upload: done by the human

1. *Source Control → Commit Changes via ItemSet*. In older client tools it is *Show CCR Controls → Bundle
   ItemSet*.
2. The screen lists the uncommitted queue. Its filters (Source, Changed By, CCR) are **display only**: they do
   not limit what is bundled. The human ticks the items explicitly after looking at each diff.
3. The human enters the **CCR ID** and the **Access Token** from the CCR's Perforce Details, then clicks
   *Bundle and Upload Changes*.
4. The CCR server validates:
   - the token;
   - that the CCR exists;
   - the CCR **state** (upload is allowed only in `In_BASE` or `BASE_Pending_Peer_Review`);
   - that the CCR's **system** matches this BASE's system.

The agent prepares the item list and description exactly as for a connected check-in
(`assets/checkin-handoff.md`, ignoring the Job line). It does not bundle or upload.

## Access tokens

- The token authorizes uploads to one CCR. Treat it like a password: never ask for it in the chat, and never
  write it to a file or to memory.
- The value next to the CCR in some UI lists (for example `dev<CCR>-<server>`) is **not** the access token.
  The token is the field labelled *Access Token* under Perforce Details.

## Read-only checks that need no token

- `ItemSet.WSCanUpload(<CCR>, Org, Sys)` asks the CCR server whether uploads are allowed now. It returns OK,
  or the reason, for example "record is in state In_PREP. The CCR must be in In_BASE or
  BASE_Pending_Peer_Review." See `probes.md`.
- `Configure^%buildccr` runs the same call at its end with a dummy CCR (`PING9999`) as a communication test.
  The CCR server used is `$$CCRServer^%buildccr`: the InterSystems CCR server unless the instance overrides
  it. On a test instance, check it before any call.

## Scripted bundle: not for the agent

`%Studio.SourceControl.ItemSet.Bundle(pInteractive=0, …)` can bundle, and upload, without the UI. Do not call
it: the upload is a human, CCR-scoped decision, and the diff review happens in the Bundle screen.
