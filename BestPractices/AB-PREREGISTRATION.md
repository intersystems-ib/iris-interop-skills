# Pre-registration — does the skill reorganisation change build quality?

Registered **2026-09-19**, against plugin **v1.110.0**, before any arm was run.

This document exists so the result cannot be re-interpreted after the fact. It fixes the arms, the
metric, the unit of analysis, the parser, and the decision rule **in advance**. Anything not written
here before the first run is exploratory and must be reported as exploratory.

Two things prompted it:

- **#337** — 20 skills were over the 500-line budget with no supporting files; they were split, and
  progressive disclosure now has somewhere to disclose *to*. Whether that helped is unmeasured.
- **#365** — **16** of 20 descriptions carried the string `Routed from interop.`, which no user
  utterance can match. Removing it was a plausible improvement in the **untested direction**: #127
  measured *adding* prose, never removing it.
  **SHIPPED 2026-09-21 in v1.121.0, before this arm ran**, by the owner's decision — see `CLAUDE.md`
  §"Conventions for editing skills" for the reasoning. Two things follow. The arms below stay pinned
  at their shas and stay runnable; `arm-m3` now measures a decision already taken rather than gating
  it. And the count was **16, not 15**: `component-map` carried the variant `Routed from interop — `
  with an em dash and no period, so an exact-string search for `Routed from interop.` missed it. The
  15 vs 16 discrepancy in earlier notes is that, not drift.

Counts above are stated once, at a version, and rot from that moment. Re-derive, never trust:

```bash
grep -rl 'Routed from interop' skills/*/SKILL.md | wc -l    # descriptions carrying the string
# The earlier form of this line, `grep -rlc '…interop\.'`, undercounted. TWO INDEPENDENT DEFECTS, and
# fixing either one alone still leaves a wrong number. Measured 2026-09-21 against the v1.119.0 tree,
# where 16 of 20 descriptions carry the string:
#   (a) `-l` AND `-c` together is unspecified, and the two greps on this machine disagree:
#       /usr/bin/grep -lc  -> 36 output lines (a `file:count` line for ALL 20 files PLUS a name line
#                             for each of the 16 that match), so `| wc -l` is neither count
#       the `grep` on PATH -> 16 (clean -l semantics)
#       ...because `grep` in a shell here is a FUNCTION shimming to ugrep 7.8.4, while
#       `find … | xargs grep` execs /usr/bin/grep. The same command text runs two different programs
#       depending on how it is invoked. Every reproduce command in this repo is written as `grep`.
#   (b) the escaped period excluded component-map's variant, `Routed from interop — load it at …`
#       (em dash, no period): 15 instead of 16. This is the defect that actually produced the wrong
#       figure, and it survives fixing (a).
python3 scripts/validate_skills.py                            # S7 lines, S8 tokens, S9 chars
```

---

## Gate 0 — the manipulation check, which runs FIRST and can cancel everything after it

The reorganisation's whole mechanism is that a model **opens a bundled file when it needs the depth
that was evicted there**. If it never opens one, the mechanism is absent and no A/B on the
reorganisation can show anything — a null result would be uninterpretable, not informative.

**Gate 0 measures the mechanism, not the outcome:** over the runs, how often is a
`skills/*/references/*.md` or `skills/*/assets/*.cls` file read?

### VERDICT, 2026-09-20: Gate 0 **FAILED**, and the matrix is cancelled by this document's own rule

Measured by the GENAI-Course session with a *delator* — a 30-line guide card carrying an
unguessable convention marker, so the readout is "did the marker appear in the class the model
wrote", a `grep` with no IRIS in the path. Controls are half the design and both separated
cleanly: card **in the prompt** 5/5 in both models, card **nowhere** 0/4.

| where the card was | Haiku 4.5 | Sonnet 4.6 |
|---|---|---|
| in the prompt *(positive control)* | 5/5 — 100 % | 5/5 — 100 % |
| **inline in `SKILL.md`** | 3/11 — **27 %** | **11/11 — 100 %** |
| `references/` | 0/11 — **0 %** | 0/10 — **0 %** |
| `assets/` | 0/11 — **0 %** | 1/12 — **8 %** |

| contrast | Fisher |
|---|---|
| `inline`: Haiku vs Sonnet | **p = 0.001** |
| Sonnet: `inline` vs both doors | **p < 0.00001** |
| the doors: Haiku vs Sonnet | **p = 1.00 — no difference** |

> ### ⚠ SUPERSEDED 2026-09-21 — for the MECHANISM, not the numbers
>
> **The table above stands; it is the audit's output and it replicates.** What is wrong is point 1
> below, which reads it as a fact about the *tier*. Every door in this experiment was announced
> **passively** (`plantilla en assets/x.md, copiala`, `See [references/x.md](…)`) — the only form
> this repo used at the time. Re-measured on 1.119.0 with the same card in the same file, changing
> only the sentence that points at it:
>
> | pointer wording | Sonnet 4.6 | Haiku 4.5 |
> |---|---|---|
> | passive bullet — reproduces this table's 0 % | **0/6** | — |
> | directive (trigger condition + imperative verb) | **5/6 – 6/6** | 0/6 – 1/6 |
> | same directive line in a project `CLAUDE.md` | 6/6 | 0/6 |
>
> Passive vs directive on Sonnet: **p = 0.0152**. Sonnet vs Haiku across three directive arms,
> 17/18 vs 1/18: **p = 0.00000007**. Path form is irrelevant (relative vs absolute, p = 1.00), so
> an unresolvable relative link is not the explanation either.
>
> So: **on Sonnet the doors are usable when the pointer is an order rather than a mention. On Haiku
> they stay shut either way** — 1 of 18, indistinguishable from the file not existing, while the
> same card in the prompt lands 6/6. Read point 1 below as *"passive mentions are dead for
> everyone"*, and the Haiku half of the third consequence as **confirmed, and now measured on the
> tier it is actually about** rather than borrowed from the body's 27 %.
>
> Provenance: #379 (correction comment), #388 (the bulk fix), #389 (the S8 remedy text). Harness
> `ab_rutas.py` in the TR-26015 bench, 6 reps per arm, both controls separating cleanly in both
> models.

**The conclusion splits in two, and only one half is global.**

1. **The doors are dead for everyone.** `references/` + `assets/` is **1 hit in 44** across both
   models, and the two models do not differ (p = 1.00). Not "Haiku does not open files" — *nobody*
   opens them. This recommendation is model-independent.
2. **The `SKILL.md` body is model-dependent.** Sonnet 11/11; Haiku 3/11. So "the body is a lossy
   channel" is true **for Haiku and false for Sonnet**, and an earlier version of this document
   implied it was general.

**Consequences, which bind work planned from here:**

- Gate 0's pass condition (**≥ 1 open per run in ≥ half of runs**) is missed by both models, so by
  the rule below **the expensive matrix does not run.** A null from it would have been
  uninterpretable; this is the informative result and cost a fraction as much.
- **"What truly cannot fail does not go in `SKILL.md`"** is correct **for Haiku**. For Sonnet, inline
  suffices and a gate is luxury. The channel that reaches both at the moment of decision — a hook's
  injected text, or a gate's denial message — is the only one measured at 100 % for Haiku, and it is
  **untested**: see `bench/arm-denial`.
- **Moving a capability into `references/` is deleting it**, for either model. That is what S8's
  remedy text enforces; this table is the evidence behind it.

This section is the single record of these figures. Everything else in the repo points here rather
than restating them, because a number restated in prose rots and a number with one owner does not.

- **Evidence superseded by the verdict above.**
- **Pass condition:** the opens-per-run rate is high enough that an effect is physically possible.
  Pre-committed threshold: **≥ 1 open per run, in ≥ half of runs, in the arm being tested.**
- **If Gate 0 fails, stop.** Do not run the matrix. The finding is then *"bundled files are not
  reached in this client/model configuration"*, which is a **better** result than a null A/B and
  costs a fraction as much. It also redirects the work: the fix would be inlining or a
  router-level pointer, not more splitting.

Gate 0 is cheap, it is the highest-information step available, and it is the reason this
pre-registration does not open with the expensive design.

---

## Pre-registered decision tree — subtraction round 2

Registered **2026-09-21, before the data exists**, for the GENAI-Course subtraction experiment:
arm **A** (all 20 skills), **B** (the 11 touched), **C** (the 6-skill core), across Haiku and Sonnet,
scored on completion **and** conformance. It is written now for the same reason Gate 0's stop rule
was: a decision rule invented after the number lands is not a decision rule.

### The outcome space, and what each result triggers

| result | reading | pre-committed trigger |
|---|---|---|
| **C ≈ A** | 6 skills produce work as good as 20 on this exercise | Propose the 6-skill core as the default and the other 14 as opt-in. State the scope precisely: *nothing measurable on this exercise by this counter* — not "the additive work was worthless". |
| **C < A, B ≈ A** | 11 is sufficient, 6 is not | Prune to the 11, and name which of the 5 skills dropped in C the gap traces to before pruning anything. |
| **C < A, B < A** | the 20 earn their keep | Stop proposing subtraction. The lever becomes the token programme instead — the skills over the 5k figure, worked down without removing any. |
| **C > A** | loading 20 skills *costs* attention | **Stronger than a tie, and it inverts the default**: pruning stops being merely safe and becomes required. Do not treat this as a surprising tie. |

A comparison not in this table is exploratory, may be reported as such, and may not drive a ship
decision.

### The validity gate that runs BEFORE any row above is read

**A tie is only as strong as the counter**, and for this experiment the counter is measurably
incomplete. Measured in this repo on 2026-09-21, by classifying every gate/hook hit as enforcing or
not — a grep hit is not a check:

| skill removed in C | enforcing representative | what the term hits actually are |
|---|---|---|
| `hl7-schemas` | **none** | the `interop_route.py` regex that *names* the skill; exemption text in `interop_bootstrap.py` and `interop_conformance_gate.py` keeping `DocType` / `MessageSchemaCategory` out of a naming rule; test fixtures. `HL7.Schema` appears in **0** gate or hook files. |
| `messages` | **one — CR-11** | `Class …\.(?:DAT\|MSG)\.… Extends … %Persistent` without a delete cascade. It fires on a property of a payload that **already exists**; it cannot fire if no message class was designed at all. |

So a conformance tie is **blind** to whether removing `hl7-schemas` hurt, and **partially blind** for
`messages`. That is a property of the checks, not of the arms, and no amount of run volume fixes it.

**Consequence, binding on how the result is written up:** a tie must be reported as *"no difference on
the measured dimensions, and the measured dimensions do not include custom HL7 schema authoring, nor
whether a message class was designed at all."* Naming the blind spots is part of the result, not a
footnote to it.

**The cheap fix, if it can be afforded before the run:** add one scenario that *requires* a custom
Z-segment schema, scored on whether the generated schema resolves. Without it, arm C **cannot lose on
`hl7-schemas` by construction** — which makes a tie on that dimension uninformative rather than
reassuring.

### What this design still cannot say

Subtraction measures **breadth**, so it cannot separate "this skill is unnecessary" from "this skill
is necessary but its content is unreachable". Given that `references/` and `assets/` were picked up
1 time in 44 **when every pointer to them was passive** (§"VERDICT" below, and its 2026-09-21
addendum), a skill whose load-bearing material sits behind a door would look removable in **every**
arm. A tie on such a skill is evidence about reach, not about need.

The addendum does not lift this caveat, it dates it: the subtraction runs were executed against
plugin versions whose citations were passive throughout, so their ties carry exactly this ambiguity.
A re-run after the #388 conversion would not — on Sonnet.

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
