# Gathering N responses into one target — the `<foreach>` accumulate pattern

Depth for `bpl` §"Canonical routing / BPL shapes". Read this before writing the loop; the SKILL body carries
the choice (which shape) and the one trap that must not be missed, this file carries the mechanism.

Deliverable section: `BestPractices_Interop_IRIS.md` §5.26. Template:
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/bpl-foreach-accumulate.cls`.
Process input: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/msg-cycle-req.cls`.
Assertions: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/tdd-foreach-accumulate.cls`.

## Which shape

| | branches | order | join |
|---|---|---|---|
| `<flow>` / `<sync>` (§5.19) | written at **authoring** time | parallel | `<sync calls='a,b'>` by call NAME |
| `<foreach>` (this) | driven by the **data** | sequential | accumulated into one target |

A facility list that arrives *in the request* cannot be a `<flow>`: you would have to know N when you
wrote the XML.

## The four things that make it work

Three of them are silent when wrong.

1. **`instantiate='1'` on the target context property.** `create='existing'` hands the DTL the object
   the process is holding; handed a null one it has nothing to fill.
2. **`action='append'` on the response assign.** `set` keeps only the last answer.
3. **`<scope>` INSIDE the `<foreach>`.** One failed call becomes a recorded skip and the loop goes on.
   A `<faulthandlers>` outside the loop ends the process on the first failure.
4. **`create='existing'` on the DTL.** `transformations` presents this attribute for *subtransforms*
   only. Same attribute, second use: it is what lets one DTL be called once per turn and ADD each
   time.

Why (4) works, read off the generated thread code rather than assumed:

```
Set iscTemp = context.Batch
Set status  = ##class(Example.DT.AppendCycle).Transform(source, .iscTemp, aux)
Set context.Batch = iscTemp
```

The DTL fills the object it was handed, so the same OREF returns and the appends survive the turn.
**`create='new'` compiles identically** and the process then delivers only the last answer, with
nothing in the Event Log — so the difference is observable only across two calls, which is why every
assertion in the test beside it is on state after the SECOND call.

## Why `aux` is not the way to pass the key

`aux` looks supported from every direction. It **is** documented for DTLs — the third argument of
`Transform()`, filled by the router for a rule's `<send transform>` (`aux.RuleReason`,
`aux.RuleUserData`, `aux.RuleActionUserData`) — and `Ens.BPL.Transform` carries an `Aux` property
whose own comment reads *"the name of the auxiliary value passed to the Transform() method"*, which
its code generator emits and its XML writer writes back.

**`Ens.BPL.Parser:parseTransform` reads three attributes.** Measured on IRIS for Health 2026.1
(Build 235U), the whole 31-line method:

```
Set tTransform.Class  = ^||%ISC.Ens.BPLData(..Key,pIndex,"a","class")
Set tTransform.Source = ^||%ISC.Ens.BPLData(..Key,pIndex,"a","source")
Set tTransform.Target = ^||%ISC.Ens.BPLData(..Key,pIndex,"a","target")
```

No `aux`, and no variant of it among the attribute names the parser reads for any BPL element. So
`<transform class='…' source='…' target='…' aux='context.Key'/>` compiles clean and generates
`Transform(source, .iscTemp, "")`. No compile error, no runtime error — a DTL line reading `aux`
produces empty output while everything else about the transform works. That is how it was found:
every item appended correctly and the key column blank.

**A missing BPL feature, not a broken documented one.** The BPL `<transform>` element documents only
`class`, `source` and `target`, in both the BPL reference and *Developing BPL Processes*, and the
Portal BPL editor has no field for it either.

### Carry the value instead, in this order

1. **On the source message**, echoed back by the operation —
   `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/msg-facility-cycle-rsp.cls` carries
   `FacilityCode` for exactly this reason.
2. **On the target, before the `<transform>`.** With `create='existing'` the DTL receives that same
   object, so the target is a declarative channel from the process into the DTL.
3. **Keep `aux` for DTLs called from a routing rule or from code**, where the platform fills it.
