# Errors, warnings and unexpected answers

| Symptom | Meaning | Do |
|---|---|---|
| `SCM_CHECKOUT_FAILED` whose text starts with `CMD: p4 edit` | Connected BASE: the client tools echoed the p4 command, and the MCP read that echo as an error (iris-interop-dev#418) | `action=status`. If this user holds the item, carry on; otherwise report the text. |
| `success:true` after a "yes", but `status`, the queue or Perforce shows no change | The CCR action failed. The MCP (0.25) reads only the first output line, which is always blank with CCR, and drops the error (iris-interop-dev#418). | Report it to the human with the item name and action. Do not retry blindly. The cause is visible only by running the action in the IDE or an IRIS session. |
| `SCM_NO_OUTPUT` on a check-out or execute | The first output line was blank or a NOTICE, so the action code was not read | `action=status` or `menu`, then retry once at most |
| A yes/no question whose message is a URL containing `action=Login` | No valid Perforce login for this IRIS user; CCR wants its login page | Answer **no**. Ask the human to log in to Perforce, then re-check the ticket (`probes.md`). |
| A check-out dialog saying "Changes to '<env>' should only be made for critical debug purposes" | This is TEST, UAT or LIVE, not BASE | Answer **no** and stop |
| `Unexpected action code 2` (or 3) | The action is a page in the CCR UI: check-in, commit, diff, controls, file history | Hand it to the human with the item name |
| `ERROR #5865` or a rejected put | The item is not checked out by this user | Check it out (loop steps 2 and 3), refresh, redo the edit on the fresh copy |
| `Cannot save item - <reason>` | The CCR hook refused the save; the item is usually locked by another user | Stop and report the owner. Do not try another path to write it. |
| `Warning: file … is currently checked out by <client>` | Another Perforce workspace has the file open | Stop and report it |
| "Upload not allowed, record is in state <X>" | The CCR is not In_BASE or BASE_Pending_Peer_Review | Tell the human; the transition is theirs |
| "Invalid Token" | Wrong access token. The UI's `dev<CCR>-…` label is not the token. | The human re-copies the *Access Token* from Perforce Details |
| "Invalid System" | The CCR belongs to another system, or this is the wrong namespace | Stop; re-check `Org` and `Sys` against the CCR |
| "Failed communication test with CCR Server", `#6059`, `#6085 … certificate verify failed` | Network, proxy or TLS between IRIS and the CCR server | Report it with the `CCRServer` value. Do not change SSL or server settings yourself. |
| "Conflicts predicted", "Prerequisite CCR detected", "Misalignment…", any orange or red Perforce message | CCR-level risks | Stop and escalate. Never work around them. |
| `IrisDevTmp.*` rows in the queue | MCP scratch classes were captured by the hooks | Report them; the human decides whether to revert them |
| An item in the queue that is not on the plan | Scope leak (an extra check-out or an accidental edit) | Undo it if untouched; otherwise ask the human |
