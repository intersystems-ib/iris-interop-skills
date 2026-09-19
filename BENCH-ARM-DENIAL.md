# `bench/arm-denial` — an experimental arm. **NEVER MERGE THIS BRANCH.**

## What it changes

One thing: rule 1's denial text in `hooks/interop_conformance_gate.py` gains a line asking for
`/// Convention: CONV-Q4X` as the renamed class's first doc comment.

## Why it must not merge

`CONV-Q4X` is **test scaffolding, not a convention**. It exists so a `grep` of the class the model
writes answers one question — *did the text of a gate denial reach the model?* Shipping it would put
a meaningless token into a blocking gate's denial and teach it to real users.

## What it measures, and why this arm exists at all

Gate 0 failed for both models (`BestPractices/AB-PREREGISTRATION.md` §"VERDICT"): `references/` and
`assets/` are picked up 1 time in 44, and the `SKILL.md` body is 100 % on Sonnet but only **27 % on
Haiku**. So for a small model there is currently **no measured channel** that reliably carries
something that cannot fail. The only arm measured at 100 % was the card placed **in the prompt** —
i.e. text already present at the moment of decision.

A gate denial is text that arrives at exactly that moment, without the model choosing to fetch it.
This arm tests whether that property transfers. It is the one remaining untested channel, and it is
the one the "what cannot fail goes in a hook or a gate" recommendation rests on — so that
recommendation is, as of today, **unverified**.

## Design constraints that must hold

1. **The marker is an innocuous convention, never a remediation.** It must not name a way to satisfy
   or avoid the rule. Naming the exemption in denial text hands the agent a one-character bypass —
   measured on CR-15, where the shipped regex would have blocked a correct fire-and-forget call.
2. **Rule 1 is the carrier because it fires on a natural instinct.** Naming a DTL `.Transform.` is
   what a model does unprompted; the plugin exists partly because of it. No contrived task needed.
3. **A malformed-JSON payload is a required control.** The hook ends with
   `return  # allow on parse failure`, so a broken harness and a legitimate allow are *the same
   silence*. Measured: a first attempt at this test fed JSON through `echo`, zsh interpreted the
   `\n` inside the strings, and all three payloads — including two that must deny — came back
   silent. Without the control that reads as "the gate is inert".

## Verified behaviour on this branch

```
malformed JSON                  -> silent      (control: allow on parse failure)
well-formed Pkg.DT.Name put     -> ALLOW       (a conformant class is not gated)
same class named .Transform.    -> DENY        (rule 1, carrying the marker)
BO Extends ...OutboundAdapter   -> DENY        (rule 2, no marker — unchanged)
```

Pin this arm by sha, not by branch name.
