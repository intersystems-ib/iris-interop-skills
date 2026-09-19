# `Ens.MessageHeader.Status` — the nine codes

Read from the platform's own enum, `Ens.DataType.MessageStatus` (`VALUELIST`/`DISPLAYLIST` on
IRIS for Health 2026.1), not from memory:

| value | display | terminal? | what it means at rest |
|---|---|---|---|
| 1 | Created | no | header written, not yet queued — a stall here is a dispatch problem |
| 2 | Queued | no | waiting for its target's job. Normal in flight; **at rest it never arrived** |
| 3 | Delivered | no | handed to the target, no completion recorded yet |
| 4 | Discarded | **yes** | dropped on purpose — by a router with no matching rule, or a purge |
| 5 | Suspended | **yes** | parked by a human or by `Ens.Alert` handling; someone must resume it |
| 6 | Deferred | no | deliberately postponed by the host; legitimate, but it is not progress |
| 7 | Aborted | **yes** | the session was torn down under it |
| 8 | **Error** | **yes** | the one everybody greps for |
| 9 | **Completed** | **yes** | the only terminal SUCCESS |

**Why the review anchors on "not 9" rather than on `8`.** Four codes are terminal and only one of
them is success. A count of `Status=8` reports zero on a production that discarded, suspended or
aborted its traffic instead of erroring on it, and those three are just as dead. Three of the nine
(`2`, `3`, `6`) are unremarkable while a flow is running and are evidence of a stall when nothing is
running — so the count is worth taking twice if the production is live.

**What is not a finding.** A BO failing against a real unique constraint is the constraint doing its
job; `business-operations` says auditing that as a defect is wrong. The finding CR-17 describes is
that nobody counted the headers before declaring the work complete.
