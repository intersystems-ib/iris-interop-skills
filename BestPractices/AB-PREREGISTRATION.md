# Pre-registration — does the skill reorganisation change build quality?

Registered **2026-09-19**, against plugin **v1.110.0**, before any arm was run.

This document exists so the result cannot be re-interpreted after the fact. It fixes the arms, the
metric, the unit of analysis, the parser, and the decision rule **in advance**. Anything not written
here before the first run is exploratory and must be reported as exploratory.

Two things prompted it:

- **#337** — 20 skills were over the 500-line budget with no supporting files; they were split, and
  progressive disclosure now has somewhere to disclose *to*. Whether that helped is unmeasured.
- **#365** — 15 of 20 descriptions carry the string `Routed from interop.`, which no user utterance
  can match. Removing it is a plausible improvement in the **untested direction**: #127 measured
  *adding* prose, never removing it.

Counts above are stated once, at a version, and rot from that moment. Re-derive, never trust:

```bash
grep -rlc 'Routed from interop\.' skills/*/SKILL.md | wc -l   # descriptions carrying the string
python3 scripts/validate_skills.py                            # S7 lines, S8 tokens, S9 chars
```

---

## Gate 0 — the manipulation check, which runs FIRST and can cancel everything after it

The reorganisation's whole mechanism is that a model **opens a bundled file when it needs the depth
that was evicted there**. If it never opens one, the mechanism is absent and no A/B on the
reorganisation can show anything — a null result would be uninterpretable, not informative.

**Gate 0 measures the mechanism, not the outcome:** over the runs, how often is a
`skills/*/references/*.md` or `skills/*/assets/*.cls` file read?

- **Evidence already in hand, from the peer session's 6 Ejercicio-3 runs:** Haiku opened a bundled
  file **0 times**; Sonnet **1–2 times**. Both against hundreds of in-transcript mentions.
- **Pass condition:** the opens-per-run rate is high enough that an effect is physically possible.
  Pre-committed threshold: **≥ 1 open per run, in ≥ half of runs, in the arm being tested.**
- **If Gate 0 fails, stop.** Do not run the matrix. The finding is then *"bundled files are not
  reached in this client/model configuration"*, which is a **better** result than a null A/B and
  costs a fraction as much. It also redirects the work: the fix would be inlining or a
  router-level pointer, not more splitting.

Gate 0 is cheap, it is the highest-information step available, and it is the reason this
pre-registration does not open with the expensive design.

---

## Arms

Pinned as branches so the comparison is reproducible and cannot drift while it runs. Each is pinned
by **sha**, not by branch name — a branch moves, a sha does not.

| Label | Content | Pin |
|---|---|---|
| `arm-k7` | v1.110.0 as released — the reorganised skills, `Routed from interop.` present | `3d08aeec1004d4c49f6f0a4367f221472d766837` |
| `arm-m3` | `arm-k7` with `Routed from interop.` removed from every description, nothing else changed | `f42a6dd145ae142d52e047d6964ca2b543068ea2` |

`arm-m3` is a **single-variable** contrast against `arm-k7`. Verify that claim mechanically rather
than trusting this table:

```bash
python3 scripts/verify_arm_single_variable.py bench/arm-k7 bench/arm-m3
# expect: MISMATCHES 0, both controls ok, "single-variable PROVEN". Non-zero exit voids #365's result.
```

**Do not substitute a grep over the diff for this.** The obvious form —
`git diff base arm | grep -v '<the string>'` — **cannot fail**: the transform *removes* the string,
so the `+` lines no longer contain it and the filter only ever tests the `-` side. Measured while
building these arms: that grep reported "single variable" on an arm that had **no commit at all**
and whose content was still identical to the base. The script compares whole trees and carries a
positive control, so a pass means something.

**There is no clean arm for #337.** The only "before" that exists is plugin **1.41.0**, and we are
at **1.110.0** — see §"What this design cannot measure".

Labels are opaque so a human grader cannot see which is which. This is a **weak** blind: the mapping
is in this file, in this repo. It is not the main protection — the primary metric is computed
mechanically from error codes, where grader belief cannot reach. Blinding matters only for the
secondary human-graded outcome, and there the grader must be a different session that has not read
§Arms.

---

## Scenarios

The real GENAI-course work on a real VM, unmodified: **EJERCICIO-3** and **HOSPITAL**. They are the
right bench precisely because they were not written to test this — they are the tasks the plugin
exists to support, with real production items.

Both arms run both scenarios. Runs are **paired on (scenario, model)**; a comparison across models
or across scenarios is not a comparison.

---

## Primary metric

**Invented-API failures per 100 MCP tool calls.**

An *invented-API failure* is a tool result carrying any of:

| Signature | What it means |
|---|---|
| `<CLASS DOES NOT EXIST>` | a class name the model made up |
| `<METHOD DOES NOT EXIST>` | a method that is not on the class |
| `<PROPERTY DOES NOT EXIST>` | a property that is not on the class |
| `SQLCODE -30` | a table name that does not project |
| compile error `#5002` with an undefined-symbol payload | a signature the model invented |

Chosen because it is the failure mode the skills exist to prevent, it is **mechanically countable**,
and it needs no judgement. The denominator is MCP tool calls, so a run that simply does more work
does not look worse.

**Secondary, pre-registered, reported separately and never promoted to primary:**

1. **Bundled-file opens per run** (the Gate 0 quantity, carried through the full matrix).
2. **Conformance-criteria violations at the end state**, scored by `hooks/conformance_prescan.py`
   over the produced classes — mechanical, no grader.
3. **Task completion**, human-graded, blind, on the opaque labels only.

---

## Unit of analysis

**The step, not the run.** A run is a sequence of tool calls; treating a 200-call run as one
observation throws away nearly all of the data and makes any test hopelessly underpowered at the
sample sizes a VM bench can produce.

Consequence that must not be skipped: **steps within a run are not independent.** Report the
per-run rate as the observation for the headline test (paired, by scenario and model), and use the
step-level counts only for descriptive breakdowns. Do not run a chi-square over pooled steps as if
each were independent — that manufactures significance out of run length.

---

## Parser specification

Reusing #340's dedup rule and the failure this project has already committed twice:

1. **Dedup by `tool_use_id`.** A retried or re-rendered call appears more than once in a transcript.
   Counting raw occurrences inflates both numerator and denominator, unequally.
2. **Every signal declares the record type it must sit in, and the parser enforces it.** This is not
   a style preference — it is the rule that two false findings came from ignoring:
   - **Error codes** must come from a **tool result / error field**. A model *discussing* `<CLASS
     DOES NOT EXIST>` in prose is not a failure. An error code inside the output of a `grep` the
     model ran is not a failure either.
   - **Bundled-file opens** must come from a **file-read tool call whose path argument** is under
     `skills/*/references/` or `skills/*/assets/`. A *mention* of the filename in prose is not an
     open. The peer measurement's Haiku result is exactly this distinction: hundreds of mentions,
     zero opens.
   - **Hook/bootstrap evidence** must come from a record that is **neither a tool call nor a tool
     result**. This is the one that produced a filed false finding: a match was found inside the
     output of a `grep` the model ran over a fixture that exists to demonstrate the error.
3. **A raw string search over a transcript is not a measurement** and is not acceptable as the
   parser, for any signal, including the ones whose answer already looks right.
4. **Positive control, required before any count is believed.** Run the parser over a transcript
   known to contain each signal and confirm it reports non-zero. A zero from an untested parser is
   indistinguishable from a zero from a clean run.

---

## Decision rule, committed in advance

- **Gate 0 fails** → stop, report the mechanism finding, do not run the matrix, do not report an
  A/B result of any kind.
- **#365 / `arm-m3`**: adopt the removal if its invented-API rate is **not worse** than `arm-k7` and
  bundled-file opens do not fall. The hypothesis is that the string is *inert*, so **equivalence is
  the success condition** — this is deliberately not a superiority test. If it is inert, the string
  goes on the grounds it was always going on: it cannot match a user utterance and it costs tokens
  in 15 always-loaded descriptions.
- **Worse in either arm** → the change does not ship, and the result is recorded in
  `BestPractices/COVERAGE-MAP.md` so the next person does not re-propose it.
- **Any comparison not listed above is exploratory.** It may be reported, labelled as such, and may
  not drive a ship decision.

---

## What this design cannot measure

Stated now, so a null result is not later sold as evidence of no effect.

1. **The reorganisation itself.** The captured "before" is plugin **1.41.0** against **1.110.0** —
   seventeen releases in one night, including new gates, corrected facts, and new samples. A
   before/after across that gap measures a **release train**. Attributing a delta to the
   restructuring alone would be wrong, and no amount of run volume fixes it. To measure the
   reorganisation you would have to rebuild a same-version arm whose only difference is the split,
   which has not been built and is not pinned here.
2. **Ceiling effects.** If both arms saturate — as an earlier 6-vs-6 codex comparison did at
   6/6 — the design **cannot see an effect**. That is not the same as "there is no effect", and it
   must not be reported as one.
3. **Discoverability in realistic work**, if the prompts name what the skill names. A cued
   selection measures capability, not discovery.
4. **Anything about models or clients not in the matrix.** A rate has a population. A zero from a
   population that never had the opportunity is not a zero.

---

## Ownership

The run store and the bench are the **testing session's**, in a different repo. This document
specifies the protocol and pins the arms; it does not assert what runs exist or have been executed.
Ask for coverage; never infer it. Spend is approved explicitly per run by the user — a pinned arm is
not a started run.
