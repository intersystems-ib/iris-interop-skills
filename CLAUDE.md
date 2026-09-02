# iris-interop-skills

A standalone plugin of **20 skills** for building InterSystems IRIS For Health
Interoperability productions with Claude, plus a best-practices + worked-examples
bank under `BestPractices/`. Start at the `interop` router; load `component-map`
right after it to pick the right component/adapter for the task at hand.

## Skills system

When working on anything IRIS Interoperability, invoke the `interop` router skill.
It assumes an IRIS MCP server (e.g. **`iris-agentic-dev`** or the streamlined **`iris-interop-dev`** fork) is enabled (hard dependency). Tool names are identical, so the skills work with either.

**Messages are the foundational building block** — design the message class before
BS/BP/BO (except when the SOAP Wizard or the Record/Complex Record Mapper *generates*
the message). The `interop` router skill enforces this and points to the right
sibling skill for each task. Always load `iris-interop-skills:tdd` as a companion.

## Layout

- `skills/*/SKILL.md` — the 20 skills. Each is a single `SKILL.md`.
  The router (`interop`) refers to its siblings by their **plugin-qualified id**
  `iris-interop-skills:<name>` (e.g. `iris-interop-skills:messages`), not by bare
  name or path — a bare `Skill("messages")` errors with "Unknown skill".
- `agents/*.md` — four bundled subagents (`interop-builder`, `deploy-smoke-test`,
  `introspect-dont-guess`, `conformance-reviewer`) that auto-register on install. MCP-server-agnostic (no server pinned).
- `hooks/` — nine hooks auto-registered via `hooks/hooks.json`: a SessionStart conventions
  bootstrap, two blocking PreToolUse gates (conformance gate, src-before-iris), five PostToolUse
  guards (silent-execute guard, TDD enforcement, conformance pre-scan, docker-detect,
  tdd-first-green), and one blocking **Stop** gate (conformance-stop-gate) that enforces
  "before declaring done" — see #96 for why an advisory nudge was worth 0 invocations in 206 runs.
- **Required user setting:** raise the skill-listing budget (`skillListingBudgetFraction: 0.03`,
  `skillListingMaxDescChars: 2048`) in `~/.claude/settings.json` so `interop`/`tdd` don't get evicted.
- `BestPractices/` — the worked-example bank the skills cite:
  - `BestPractices_Interop_IRIS.md` — patterns tagged Validity/Severity.
  - `examples/` — runnable artefacts indexed in `examples/README.md`, gated by
    `scripts/validate_examples.py` (tier 1 structural in CI; `--compile` against a
    live IRIS before a release). Adding an example means adding its README row.
  - `external/workshop-iris-dicom-interop/` — vendored MIT DICOM snapshot.
- `.claude-plugin/` — `marketplace.json` + `plugin.json` (this repo is both a
  single-plugin marketplace and the plugin itself; plugin `source` is the repo root).

## Conventions for editing skills

- Skills reference the worked examples via `${CLAUDE_PLUGIN_ROOT}/BestPractices/…`
  so the path resolves whether the plugin is installed from the marketplace or the
  repo is cloned and opened as a project. Keep that prefix when adding references.
- Keep skills **self-sufficient**: a referenced example must travel inside this repo
  (under `BestPractices/`). No pointers to files outside the repo.
- This public edition carries **no customer-identifying provenance**. Don't
  reintroduce client/site names, internal document names, or real endpoints when
  editing — keep examples vendor-neutral (`Demo.*` package names, `example.org`
  hosts, generic descriptors).
- **Don't add PROSE to a `description:`; trigger words are free** (#127). Measured on the
  `alerting` probe cells, codex / `gpt-5.6-luna`, n=100 per cell: 60 filler words added to the
  prose half cost **13.3 points of precision** (90.3% → 77.0%, p=0.006) and bought
  **+0.7 points of recall** (90.3% → 91.0%, p=1.000). The identical 60 words added to the
  `Triggers:` list cost nothing on either side (+1.7 precision, +3.7 recall, both null). Prose
  broadens the match surface without improving it — a tax, not a dial.
  **This licenses not-adding, not shortening**: the probe measured *adding* 60 words, and whether
  removing words is symmetric is untested. Existing descriptions stay as they are until an arm
  measures the removal direction, and any description edit still needs a before/after (#126, #127).
