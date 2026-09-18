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
- `hooks/` — eleven hooks auto-registered via `hooks/hooks.json`: a SessionStart conventions
  bootstrap, a **UserPromptSubmit** topic router (`interop-route`) that names the two or three
  skills the turn actually needs — SessionStart names three FIXED skills before the task is known,
  and its context never reaches a subagent (#218) — two blocking PreToolUse gates (conformance
  gate, src-before-iris), six PostToolUse guards (silent-execute guard, TDD enforcement,
  conformance pre-scan, docker-detect, tdd-first-green, src-drift guard), and one blocking
  **Stop** gate (conformance-stop-gate) that enforces "before declaring done" — see #96 for why an
  advisory nudge was worth 0 invocations in 206 runs.
  The conformance gate also sits on `Write|Edit`, scoped to `.cls` paths only, so an illegal
  identifier is caught before the VS Code sync carries the class into IRIS (#219).
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
- **Hooks are a Claude Code mechanism, and they are INERT on two of the three CLIs the campaign
  measures** (#115). Structurally re-derived over 1292 corpus runs: the SessionStart bootstrap
  appears in 318 of 318 `claude` runs, **0 of 676 `codex`** and **0 of 289 `opencode`** — the single
  `opencode` hit was a run that read a config file quoting the text. `hooks.json` is a plugin
  mechanism; the other two CLIs load the skills and never execute a hook. So every gate in
  `hooks/` — the two PreToolUse denies, the six PostToolUse guards, the Stop gate — is a **no-op for
  958 of 1292 runs**. Two consequences that change how work here is planned: a hook change can only
  be *measured* on the `claude` arm, and pooling the arms dilutes any real effect toward zero; and
  anything that MUST hold on every CLI has to live in a **skill**, not a hook. Where a rule exists
  in both places, say which is the enforcement and which is the fallback.
- **Description geometry is not the lever — do not plan a plugin-wide prose edit** (#127, #128).
  Two independent analyses agree that *how* a description is shaped predicts neither recall nor
  fatal misses: Spearman(prose, recall) = +0.088 and Spearman(triggers, recall) = +0.066, both ~0,
  with matched falsifying pairs (`tdd` 62 prose / 29 trig → 38% recall, against `report-issue`
  65 / 25 → 94%). Every cheap intervention available to us is a geometry intervention — shorten
  this prose, add triggers there, restructure that cell — so the affordable hypothesis is not
  merely unproven, it is measurably **not** the lever. What remains is content-against-prompt: what
  a description *says* relative to the prompts it must match, which is per-skill work with a
  measurement each time, never a rule applied across skills.
- **Every inline ```objectscript fence that is a complete class IS COMPILED** (tier 3,
  `scripts/validate_examples.py --compile`). This exists because the snippets people actually read
  were gated by nothing while the bank was gated and clean — and when the gate was first run, **6
  of 25 did not compile**, including the canonical BS skeleton. Every defect found in the
  2026-09-17 audit lived in that ungated text; none was in the bank.
  - A fence may hold several classes; they are split and compiled separately.
  - A snippet naming a class it does not ship (`MyApp.Msg.SomeRequest`) is reported as a
    **placeholder dependency** and does not fail the tier — illustrative names are legitimate.
  - **What tier 3 does NOT cover, so a clean run is not read as more than it is:** fences holding
    a bare `Method`/`ClassMethod` (no host class, no knowable superclass) and fences holding loose
    statements (no compilation unit). Both are counted and printed on every run — currently 20 and
    33. If you move a rule into one of those, it is ungated again.
  - Practical consequence when writing a snippet: `;` comments are **not** legal at class-member
    level (`Parameter X = "…";  ; note` does not compile — use `//`), and a class needs its body
    braces even in a sketch.
- **Prefer a compiled example to a prose assertion about an API.** Three methods prescribed by
  these skills did not exist — `..ValidateSettings()`, `ExecuteUpdateNull`, `StartTransaction` —
  plus `iris_table_info(schema=…)`. All four read plausibly and none would survive a compile or a
  `%Dictionary.CompiledMethod` lookup. When you name a method, a parameter or a macro, check it
  against the running instance, not memory.
- **In an example's `/// Rule:` header, `§` means THIS deliverable — cite external books with the
  word "section".** C2 resolves every `§N.N` in an example against the headings of
  `BestPractices_Interop_IRIS.md`, with no exception for a book prefix, so `HXFHIRINS §2.3.1`
  fails the gate while `HXFHIRINS section 2.3.1` passes. The existing examples already follow this
  (`ESQL section 8.2.2.1`); it was never written down, and it is one of those rules you discover
  by tripping the check.
- **Component coverage of the gated bank, and the two gaps that remain.** Every core component
  type now has at least one compile-gated example: RecordMap definition and its production wiring
  (§1.7/§1.8), HL7 file intake with the HL7-specific router (§2.10), `%UnitTest.TestProduction`
  (§5.9), typed SQL parameters (§6.4), bare-adapter BS (§6.7), REST inbound (§6.8), SQL inbound
  poll (§6.9) — plus the pre-existing SOAP/CDA/BPL/DTL/rule/alerting set. **Two are deliberately
  NOT gated, and neither is an oversight:**
  - **FHIR — RETRACTED, it is gated now.** 1.11.0 said a FHIR example "could not be compiled by
    CI" because `HS.FHIRServer.*` showed 0 classes. That conclusion was wrong and the check was
    the reason: it was made in `USER`. `HS.*` is not mapped into an ordinary namespace, and the
    image does carry `HSLIB`/`HSSYS`/`HSCUSTOM` — a **Foundation namespace** maps them in and is
    interop-enabled at the same time (`HS.Util.Installer.Foundation.Install()`, HXFHIRINS section
    2.3.1). A Foundation namespace is a strict **superset**: the whole bank and every snippet
    compile in it with byte-identical results, so the gate simply runs there now and FHIR is no
    longer a special case. Third time in three days that a scope-limited lookup was read as
    absence — see the "check it against the running instance" convention above, and note that
    *which namespace* is part of "the running instance".
  - **DICOM** — defers to the vendored MIT snapshot under
    `BestPractices/external/workshop-iris-dicom-interop/`, which is a real working production. That
    was a deliberate choice before this pass and it still holds; a thin hand-written duplicate
    would be worse than a pointer to a complete one.
- **A grep gate guards a spelling, not the rule it is named after — say so at the gate** (#151).
  Verifying a home-grown check in both directions (S5 was) proves that one known-bad input reaches
  its failure path. It does not prove the check recognises every violation of the constraint. Where
  the gate is narrower than the rule, write the gap next to the check, so a clean run cannot be read
  as coverage it does not have.
