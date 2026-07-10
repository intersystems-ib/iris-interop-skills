---
name: report-issue
description: Optionally PROPOSE opening a GitHub issue for problems found in the deployed setup — best-practice/compliance violations (from conformance-review) or reproducible MCP/skill defects — WITHOUT creating duplicates. Use after a conformance review surfaces confirmed P0/P1 findings, or when a clear, reproducible MCP/skill bug shows up during work and the user wants it tracked. Never auto-files; always dedups against existing issues and asks the user to confirm. Triggers EN: report a bug, open an issue, file this, track this problem. Triggers ES: reportar, abrir una issue, registrar el problema, notificar el bug.
---

# Propose a GitHub issue — deduped, opt-in

This skill turns a confirmed problem into a **draft** issue and proposes it to the user. It exists so the
**deployed** workshop/user can feed real defects back without an analyst in the loop — but it is built to
**not flood the tracker with duplicates**. Three hard rules:

1. **Never create an issue automatically.** Always show the draft and get an explicit "yes" first.
2. **Always dedup first** (open AND closed). If a matching issue exists, propose commenting / 👍 on it
   instead of opening a new one.
3. **One issue per distinct problem, batched.** Group all findings of the same review/run into a single
   issue (a checklist), not one issue per finding. Don't re-file something already filed this session.

## What's reportable

- **Compliance / best-practice** (from `conformance-review`): a *confirmed* P0/P1 finding (CR-1…CR-10).
  Not P2/P3 nits, not unconfirmed/defensible calls.
- **MCP / skill defect**: a *reproducible* tool malfunction in the deployed version — a tool that returns a
  wrong/empty result, an error_code that doesn't match reality, a crash, a skill that misroutes. Must have a
  concrete repro (the exact call + the wrong result), not "it felt off".

If it's a one-off, environmental, or user-code error (the model wrote bad ObjectScript and the tool
correctly reported it), it is **not** reportable.

## Where it goes (target repo)

| Problem | Default target |
|---|---|
| MCP tool defect | the IRIS MCP repo (`intersystems-community/iris-agentic-dev`, or the fork in use) |
| Skill content / routing / hook | the skills repo (`intersystems-ib/iris-interop-skills`) |
| Workshop exercise / material | the workshop repo |

Confirm the target with the user if unsure. Requires the GitHub CLI (`gh`) authenticated in the session.

## The fingerprint (this is what prevents duplicates)

Build a short, **stable** signature and put it in the issue **title** so future searches match. Form:

```
[<area>:<key>] <one-line summary>
```
- MCP defect: `[mcp:<tool>] <error_code or symptom>` — e.g. `[mcp:iris_test] NO_TESTS_FOUND despite passing %UnitTest.TestProduction`
- Compliance:  `[conformance:CR-N] <pattern>` — e.g. `[conformance:CR-2] file Business Service hand-parses rows instead of RecordMap`

Normalize away the volatile bits (class names, ids, timestamps, namespaces) so the same defect from a
different student maps to the **same** fingerprint.

## Workflow

1. **Decide it's reportable** (above). If not, stop.
2. **Dedup** — search open AND closed, by fingerprint key:
   ```bash
   gh issue list --repo <target> --state all --search "in:title <area>:<key>" --limit 20
   ```
   Also try a looser content search. **If a match exists:** show it to the user and offer to add a comment
   (a +1 / extra repro) instead of a new issue. Stop unless the user wants a genuinely new one.
3. **Draft** (don't create yet) — title = the fingerprint line; body =
   - **What** (the symptom) and **expected vs actual**
   - **Repro**: exact tool call / component + the wrong output (sanitized — no credentials, no PII, no
     instance ids/IPs)
   - **Environment**: MCP version (`--version` / serverInfo), IRIS version (`check_config`), platform
   - **Evidence**: 1–2 short excerpts; for compliance, the `file:line` + the CR criterion
   - For a batched review: a **checklist** of all findings in one issue, not many.
4. **Propose to the user**: print the draft + the target, and ask to confirm. **Only on an explicit yes:**
   ```bash
   gh issue create --repo <target> --title "<fingerprint>" --body-file <draft>
   ```
   Then report the issue URL. If the user says no, leave it as a draft note.

## Anti-spam guardrails (non-negotiable)

- Dedup against **closed** issues too (a fixed-then-recurred bug → comment to reopen, don't duplicate).
- **Batch** a review's findings into one issue; never one-per-finding.
- One fingerprint → at most one open issue. If unsure whether it's a dup, **ask** rather than file.
- Sanitize: never put credentials, patient/PII data, instance ids, IPs, or private repo paths in a public issue.
- This skill proposes; the **user decides**. No silent or bulk filing.
