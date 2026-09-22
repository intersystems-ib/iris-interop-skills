# iris-interop-skills

A standalone plugin of **20 skills** for building InterSystems IRIS For Health
Interoperability productions with Claude, plus a best-practices + worked-examples
bank under `BestPractices/`. Start at the `interop` router; load `component-map`
right after it to pick the right component/adapter for the task at hand.

## Objective and target models

**The objective** is to improve an LLM's capacity to **design, implement and test IRIS
Interoperability productions** — following best practices, and leveraging the IRIS
Interoperability components, tools and prebuilt artefacts that already exist rather than
hand-rolling replacements for them.

**The initial target agent and LLM is Claude Sonnet.** Some best effort should be made to stay
compatible with other LLMs and agents:

- **Claude Haiku**
- **OpenAI Codex + Sol**
- **OpenCode + OpenRouter + DeepSeek v4 Flash**

Two measured facts bound what "best effort" can mean, and both are about *where* guidance has to
live rather than what it says:

- **The hook layer does not reach two of the three secondary targets.** The SessionStart conventions
  bootstrap fired in **0 of 676 codex runs** and **0 of 289 opencode runs**, against 318/318 on
  Claude (#115). So anything a non-Claude agent must know has to be reachable from a skill body — a
  hook, a router injection, or a gate denial is a Claude-only channel in practice.
- **Bundled files are read only when the `SKILL.md` *orders* them read — and only on Sonnet.**
  The earlier figure (`skills/*/references/` + `skills/*/assets/` picked up **1 time in 44**) was
  measured entirely against **passive** citations — `See [references/x.md](…)`, `Worked example:
  assets/y.cls` — which is what essentially every skill here uses. Re-measured on 1.119.0, same card
  in the same `assets/` file, 6 runs per arm, changing only the sentence that points at it
  (#379, #388, 2026-09-21):

  | how the `SKILL.md` announces the file | Sonnet 4.6 | Haiku 4.5 |
  |---|---|---|
  | *(positive control: card pasted in the prompt)* | 6/6 | 6/6 |
  | *(negative control: card nowhere)* | 0/6 | 0/6 |
  | passive bullet — the wording the old figure measured | **0/6** | — |
  | directive section, relative path | **5/6** | 0/6 |
  | directive section, absolute path | 6/6 | 1/6 |
  | same directive line in a project `CLAUDE.md` | 6/6 | 0/6 |

  Passive vs directive on Sonnet: **p = 0.0152**. Sonnet vs Haiku across the three directive arms,
  17/18 vs 1/18: **p = 0.00000007**. **Path form is irrelevant** (relative 5/6 vs absolute 6/6,
  p = 1.00), so an unresolvable relative link is *not* why the tier looked dead.

  **A pointer that works has three parts — a trigger condition, an imperative verb, and what the
  reader gets:** *"Before writing a DTL, read `<path>`. It carries the minimal XData that compiles
  and the four failures that give no readable error."* Drop the trigger or the verb and it measures
  zero. Reading implies using: across the re-measured arms, marker-in-output, a real `Read` call,
  and marker-in-transcript agreed 12 of 12 — there is no "opened it and ignored it" mode.

  **On Haiku the tier stays dead either way**: 1 of 18 with a directive pointer, indistinguishable
  from the file not existing (p = 1.00 vs the negative control) even though the same content in the
  prompt lands 6/6. For a small model, moving a needed capability behind a file still deletes it.

Delivery through the `SKILL.md` body is likewise **model-dependent**: 100 % on Sonnet against
27 % on Haiku. Optimising the body for Sonnet is therefore the right default, and Haiku's lower rate
is useful as an early detector of a body that has grown past what a smaller model will read — it is
not a reason to contort the design.

**What this means for placement.** On Sonnet, `references/` and `assets/` are usable storage as long
as every pointer is directive — that is what funds an eviction under the S8 ratchet. On Haiku, and
for anything that truly cannot fail on any model, the only channels that hold are a hook or a gate
denial. Table and provenance: `BestPractices/AB-PREREGISTRATION.md` §"VERDICT".

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
  advisory nudge was worth 0 invocations in 206 runs. It blocks on three things: **CR-12**
  (a class put into IRIS with no file on disk), **CR-15** (a hand BP whose `SendRequestAsync` leaves
  `pResponseRequired` at 1 with no `OnResponse` — measured to terminate every reply with `#5003`),
  and "the conformance pass never ran". CR-15's predicate is **imported** from
  `conformance_prescan.py`, never restated: the advisory layer and the enforcing layer must not be
  able to disagree about what fires.
  The conformance gate also sits on `Write|Edit`, scoped to `.cls` paths only, so an illegal
  identifier is caught before the VS Code sync carries the class into IRIS (#219).
- **Required user setting:** raise the skill-listing budget (`skillListingBudgetFraction: 0.03`,
  `skillListingMaxDescChars: 2048`) in `~/.claude/settings.json` so `interop`/`tdd` don't get evicted.
- `BestPractices/` — the worked-example bank the skills cite:
  - `BestPractices_Interop_IRIS.md` — patterns tagged Validity/Severity.
  - `COVERAGE-MAP.md` — **the work-list for new samples. Read it before authoring one.** A
    12-agent audit of all 20 skills against the bank: 59 missing or ungated canonical samples in
    six waves, with what each would pin down, its severity, whether CI can compile it, and what it
    depends on. Wave 0 is 16 items where the right answer is NOT a new sample. It carries a
    progress ledger — update it when something lands, and do not rewrite the wave tables. Rows
    marked ⚠ were corrected by adversarial review; read §"Review corrections" before building one.
    The point of the document is that building a sample should be following a recipe, not
    re-deriving which sample is needed and why.
  - `examples/` — runnable artefacts indexed in `examples/README.md`, gated by
    `scripts/validate_examples.py` (tier 1 structural in CI; `--compile` against a
    live IRIS before a release). Adding an example means adding its README row.
  - `external/workshop-iris-dicom-interop/` — vendored MIT DICOM snapshot. **Compiled by tier 2b**
    since 1.15.1 (19 classes, `scripts/external_baseline.json`) — `dicom` calls it "the canonical
    reference for every pattern here" and until then no tier touched it, which is how it drifted
    twice. Deliberately **not** subject to tier 1: none of the 19 files carries a `/// Rule:`
    header, so C1 would fail all of them and greening it would mean editing vendor source. A tier-2b
    failure means the mirror and the IRIS version disagree — re-sync upstream, never patch the
    mirror.
- `.claude-plugin/` — `marketplace.json` + `plugin.json` (this repo is both a
  single-plugin marketplace and the plugin itself; plugin `source` is the repo root).
  **A release bumps the version in BOTH files — three fields: `plugin.json:version`,
  `marketplace.json:metadata.version`, `marketplace.json:plugins[0].version`.** `validate_skills.py`
  **S10** fails the build when they disagree, or when any of the three is missing (a manifest that
  states no version cannot be compared, and an equality test over what is left would pass). It exists
  because `plugin.json` reached **1.120.0** while `marketplace.json` still advertised **1.54.0** — 70
  tags of drift from 2026-09-18, because the release step bumped one file and nothing compared them.
  The marketplace field is what the listing shows, so this is the version a user sees.

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
- **Don't add PROSE to a `description:`; trigger words are free** (#127). Two arms on the `alerting`
  probe, codex, the same sixty filler words in each. Raw counts as #127 reports them, not derived
  percentages — the deltas here were restated once and drifted:

  | probe | control | +60 PROSE | +60 TRIGGERS |
  |---|---|---|---|
  | NEGATIVE — passing = stayed silent | 100/111 (90%) | **77/100 (77%)**, −13.1 pt, p=0.014 | 92/100 (92%), null |
  | POSITIVE — passing = fired | 109/120 (91%) | 91/100 (91%), +0.2 pt, **p=1.000** | 94/100 (94%), null |

  Prose costs 13 points of precision and buys nothing measurable in recall — **a tax, not a dial**.
  One caveat #127 pre-registered and that still binds: the positive probe sits near a ceiling, so its
  null is decisive against the dial only in the direction of a *fall*.
  **This licenses not-adding, not shortening**: the probe measured *adding* 60 words, and whether
  removing words is symmetric is untested. So a description edit still needs a before/after
  (#126, #127) — with **one decided exception, 2026-09-21 (#365, v1.121.0)**: the string
  `Routed from interop.` was removed from all **16** descriptions that carried it, by the owner's
  decision, *without* waiting for `bench/arm-m3` to run. The reasoning is recorded rather than
  implied: the string cannot match any user utterance (it names an internal routing relationship, and
  no one types it), it cost ~84 tokens in every session, and #127's own finding is that description
  *shape* predicts neither recall nor fatal misses. `bench/arm-m3` is still pinned and still runnable
  — it now measures a shipped decision instead of gating one. This exception is for a string that
  cannot match; it does not license shortening prose that can.
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
    statements (no compilation unit). If you move a rule into one of those, it is ungated again.
    - **Tier 1's C9 ratchets both counts** against `ungated` in `scripts/snippets_baseline.json`
      (read the counts from that file — restating them here is what rotted last time, twice):
      growth fails the build, a drop only prints "progress".
      Re-record deliberately with `--update-baseline`, never to make a red go away.
    - C9 exists because this figure was carried in this file as prose and **rotted**. It read 33
      for four releases while the truth was 34, and the single fence that made the difference was
      the 1.13.0 Foundation-namespace recipe — the most load-bearing fact added that week landed
      in the one fence shape no tier compiles, and nothing noticed. A count nobody asserts is not
      a measurement.
  - Practical consequence when writing a snippet: `;` comments are **not** legal at class-member
    level (`Parameter X = "…";  ; note` does not compile — use `//`), and a class needs its body
    braces even in a sketch.
- **Prefer a compiled example to a prose assertion about an API.** Three methods prescribed by
  these skills did not exist — `..ValidateSettings()`, `ExecuteUpdateNull`, `StartTransaction` —
  plus `iris_table_info(schema=…)`. All four read plausibly and none would survive a compile or a
  `%Dictionary.CompiledMethod` lookup. When you name a method, a parameter or a macro, check it
  against the running instance, not memory.
- **…but `%Dictionary.CompiledMethod` UNDERSTATES an index-generated method — the one known hole in
  the rule above** (v1.49.0, coverage-map X14). `EnsLib.DICOM.Util.AssociationContext` carries an
  index named `AET`, and that index generates eight methods — `AETExists`, `AETDelete`, `AETOpen`,
  `AETCheck`, `AETSQLExists` and three more. **Every one reports `FormalSpec = ''` and
  `ClassMethod = False`.** Both are wrong: measured, `AETExists("a","b")` returns 0 and `AETExists()`
  throws `<UNDEFINED>` — it takes two arguments and is callable as a classmethod. So a dictionary
  lookup answered "takes no arguments" about a method that requires two, and a finding was published
  on that before it was caught. Whenever a name looks like `<IndexName><Verb>`, look the index up in
  `%Dictionary.CompiledIndex` and **call the method** rather than trusting its signature. The same
  applies to the `IDKeyExists()` family on any `%Persistent` class.
- **A `%Dictionary.*` query with a bad column name returns ZERO ROWS, and the error is only in
  `status.summary`.** `SELECT Name, Generated FROM %Dictionary.CompiledMethod …` gives
  `SQLCODE -29, Field 'GENERATED' not found` — there is no `Generated` column — and a helper that
  prints `result.content` without the status shows an empty list, which reads as "nothing matches".
  That produced three confident wrong conclusions in one session, including "this class carries no
  index" about a class that does. **Print `status.summary` on every query that comes back empty**, and
  treat an unexpected zero as a failed query until the status says otherwise. Related:
  a clean zero needs a positive control.
- **A mutation harness killed mid-run leaves the MUTANT on disk, and every later "baseline" is the
  mutant.** The loop writes a mutation, runs the suite, and restores in a `finally` — a Bash-tool
  timeout (exit 143) kills it before the `finally`, and the next run's `finally` then restores the
  file to *the mutant it read as the original*, making it permanent. Measured on S32 (v1.57.0):
  `Set pClone = tBody.%ConstructClone()` stayed on disk as `Set pClone = tBody`, and three rounds of
  diagnosis went into explaining a `%ConstructClone` that was never being called — five A/B probes all
  showed correct cloning, and a wrong "measured" comment got written into the artefact on the
  strength of the mutant's behaviour. **When a green baseline goes red, read the file under test
  before forming any hypothesis** (new files are untracked, so there is no `git diff` to save you).
  Give the harness a pre-flight: each anchor present exactly once, the mutant text absent OUTSIDE the
  anchor (mutants are often substrings of their own anchor, and may legitimately appear elsewhere in
  the file — tag those), and a sha compared before and after the whole run. Run it backgrounded with
  a long timeout, never in the foreground against the 2-minute default.
- **`%UnitTest.TestProduction::TestControl()` is a TEST METHOD, not a hook.** Its inherited body
  starts the production named by `PRODUCTION`, waits `MINRUN` seconds (default 10) and then STOPS it.
  Test methods run in name order, so `TestControl` goes first and everything after it runs against a
  production that has just been shut down. Every suite in the bank overrides it to `Quit $$$OK`,
  which is right — but a suite that actually needs a live production must then start one itself, in
  `OnBeforeAllTests`, and wait for `Ens.Director.IsProductionRunning()` rather than trusting
  `StartProduction`'s return. Without that, every call fails `<Ens>ErrProductionNotRunning` while
  `IsProductionRunning()` answers 1 from outside the run.
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
  - **DICOM** — the vendored MIT snapshot under
    `BestPractices/external/workshop-iris-dicom-interop/` is still the canonical END-TO-END reference,
    and tier 2b compiles it. But "DICOM defers entirely to the snapshot" stopped being true in wave 4:
    `examples/ch15_dicom/` now carries **10 compile-gated artefacts** for the narrower measured traps
    (§15.4-§15.7), each with its `%UnitTest` sibling, and `dicom` cites them. A thin hand-written
    duplicate of the whole workshop would still be worse than pointing at it; a gated sample of one
    trap is not a duplicate.
- **A grep gate guards a spelling, not the rule it is named after — say so at the gate** (#151).
  Verifying a home-grown check in both directions (S5 was) proves that one known-bad input reaches
  its failure path. It does not prove the check recognises every violation of the constraint. Where
  the gate is narrower than the rule, write the gap next to the check, so a clean run cannot be read
  as coverage it does not have.
