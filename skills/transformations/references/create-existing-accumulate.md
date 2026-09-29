# `Create=Existing` as the accumulate channel

Depth for `transformations` §"`Create=Existing` as the accumulate channel". The SKILL body carries
the rule and the trap; this file carries the mechanism and the measurement.

Deliverable section: `BestPractices_Interop_IRIS.md` §5.26. Its BPL half is
`bpl` → `references/foreach-accumulate.md`.

## The mechanism

A BPL that calls the same DTL once per `<foreach>` turn needs each call to add to ONE target, not
make a new one. `create='existing'` is how, and it is the same attribute the subtransform case uses.
Read off the generated BPL thread code rather than assumed:

```
Set iscTemp = context.Batch
Set status  = ##class(Example.DT.AppendCycle).Transform(source, .iscTemp, aux)
Set context.Batch = iscTemp
```

The DTL fills the object it was **handed**, so the same OREF comes back and the appends survive the
turn. That is also why the BPL context property must be `instantiate='1'`: handed a null target, the
DTL has nothing to fill.

**`create='new'` compiles identically** and the process then delivers only the last answer, with
nothing in the Event Log. The difference is observable only across two calls, which is why every
assertion in the test below is on state after the SECOND call, and why a `create='new'` mutant is
killed by three of its four tests.

## The artefacts

| file | what it is |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/dtl-append-into-existing.cls` | the accumulating DTL |
| `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/msg-facility-cycle-rsp.cls` | its source — carries the key BACK, see below |
| `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/msg-cycle-batch-req.cls` | the accumulating target |
| `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/tdd-foreach-accumulate.cls` | the assertions |

`DependsOn = (source, target)` on the DTL is not decoration: without it the DTL can compile before
the classes it names and the generator resolves `source.`/`target.` against nothing.

## Do not expect `aux` to carry a value from a BPL

`Ens.BPL.Parser:parseTransform` reads `class`, `source` and `target` only — measured on IRIS for
Health 2026.1 (Build 235U), the whole 31-line method — even though `Ens.BPL.Transform` has an `Aux`
property its code generator emits. `<transform ... aux='…'/>` therefore compiles clean and the DTL
receives `""`, with no error at either end.

Put the value on the source message, or on the target before the transform: with `create='existing'`
the target IS a channel from the process into the DTL. `aux` stays useful for DTLs the router or your
own code calls, where the platform fills it (`aux.RuleReason`, `aux.RuleUserData`).
