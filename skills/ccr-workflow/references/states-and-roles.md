# CCR states and roles: what the agent may do, and when

## Roles

| Role | Who | Does |
|---|---|---|
| **Author** | The human driving the session, together with the agent, as one author | Plans, implements in BASE, submits (check-in or upload), documents the testing, runs the author's transitions |
| **Agent** | Claude, acting as the author's IRIS user | Drafts, checks out, edits, tests, prepares the hand-off. Never submits, transitions or reviews. |
| **Peer reviewer** | Another person, never the author | Reviews the change and passes or fails the review |
| **Authorizer** | A named person from the owning organization or the customer | Authorizes moves to TEST and LIVE, and closure |

## States, in the default flow

`In_PREP` → (markPREPComplete) → `In_BASE` → (markBASEComplete) → `BASE_Pending_Peer_Review` → (passPeerReview)
→ `BASE_Complete` → moves to TEST, then UAT or LIVE, each with its own "In_", peer-review and complete states
→ `Closed`.

| State | The agent may | The agent must not |
|---|---|---|
| `In_PREP` | Draft the Implementation, Backout and Testing Plans (`assets/planning-fields.md`) and the CCR description. Read code to plan. | Check out or edit anything in BASE. The human completes PREP and runs `markPREPComplete`. |
| `In_BASE` | The full loop: check out, refresh, edit, compile, test, undo the untouched items, prepare the check-in or bundle, draft "Testing Steps Taken in BASE" and the review packet. | Submit, upload or run `markBASEComplete`. |
| `BASE_Pending_Peer_Review` | Fix review findings **when the human asks**. Uploads are still accepted in this state. Draft the answers to the reviewer. | Review, pass or fail the review, or widen the scope. |
| `BASE_Complete` and later (TEST, UAT, LIVE, Closed) | Read-only help: explain the Transport Log, draft transition notes and deployment checks. | Any change in any environment. TEST, UAT and LIVE deployments are human actions with their own credentials. |

## Warnings that mean stop

Stop and escalate to the human on any of these, and never work around them:
- "Conflicts predicted"
- "Prerequisite CCR detected"
- "Misalignment…"
- any orange or red Perforce message

"CCR may allow progression" does not mean it *should* progress.

## Scope

- One CCR is one functional change: "little and often".
- An improvement noticed along the way becomes a proposed new CCR (title plus one line), not an extra item.
- If the change turns out bigger than its planning fields describe, stop and tell the human. The plans may
  have to be revised, and that is a human decision.
