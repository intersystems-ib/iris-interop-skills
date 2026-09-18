---
name: transformations
description: DTL transforms, lookups, HL7 field paths, XSLT for CDA in IRIS Interoperability. Routed from interop. Triggers: DTL, Ens.DataTransformDTL, DTL data transform, transformación DTL, mapear segmentos HL7, subtransform, HL7 field path, XSLT for CDA, Ens.Util.FunctionSet Lookup().
---

# Transformations — DTL, subtransforms, XSLT for CDA

DTL (Data Transformation Language) is the visual mapping editor in IRIS. It compiles to ObjectScript; the compiled class is what runs. For most HL7 and object-to-object transforms, DTL is the right tool. Drop to code only for genuinely procedural logic.

## When to use this skill

The user wants to map data from one message shape to another: HL7 v2.5 → v2.3, custom request → HL7 ADT, CSV record → SQL row payload, etc.

## Decision tree

```
What's the source/target shape?
├── HL7 → HL7
│   ├── Same version, few field changes → DTL with Create=Copy
│   └── Different version or different structure → DTL with Create=New
├── HL7 → custom object (or vice versa) → DTL with Create=New
├── CDA / structured XML → XSLT (more powerful than DTL for XML reshaping)
├── Custom object → custom object, simple → DTL with Create=New
└── Procedural / external lookups / DB calls → ObjectScript (custom code action in DTL,
    or replace DTL entirely with a method on a BP)
```

## Create=New vs Create=Copy vs Create=Existing

| Mode | Target initialised as… | When to use |
|---|---|---|
| **New** | Empty | Different version, different structure, or you want explicit control over every segment. |
| **Copy** | Full copy of source | Same shape, only a few fields change (e.g. add facility code in MSH:6). Most efficient when the structure matches. |
| **Existing** | Whatever the caller passed in | Subtransforms — the caller has already initialised the target and is calling you to mutate part of it. |

Default: **Copy** for same-version HL7, **New** for cross-version or cross-shape. Never default to New "to be safe" — Copy is safer when shapes match because nothing gets accidentally dropped.

## Subtransforms

Use `EnsLib.HL7.Segment` as source/target class for reusable segment-level transforms (e.g. a canonical PID-cleanup transform called from many message-level DTLs). Call from a message-level DTL with a `subtransform` action. Subtransforms run with `Create=Existing` — the parent passes the already-initialised target segment.

## Common DTL actions

- **set** — assign a value or copy a field (`target.MSH.7 = source.MSH.7`).
- **if / else** — conditional. Conditions usually evaluate source fields.
- **switch** — multi-case branching. **First match wins** — order cases by specificity.
- **foreach** — iterate repeating segments/fields. Loop variable is `k1`, nested is `k2`, etc.
- **subtransform** — call another DTL.
- **code** — drop to ObjectScript. Use sparingly. If half your DTL is `code` actions, it shouldn't be a DTL.
- **group** — pure visual organization, no logic effect.

## Lookup tables in DTL

`..Lookup("TableName", source.field, "default-or-empty")` translates codes via a lookup table — note
the **two leading dots**, see the syntax rule below. See `lookup-tables`. Always specify the third
parameter (default value or behaviour on miss) — the default-on-miss is silent and surprising otherwise.

## Calling a utility function — `..Func()` in DTL, `Func()` in a business rule

**This is the single most expensive one-character mistake in a DTL.** The call syntax for the same
utility function differs between the two places you use it:

| Where | Syntax | Example |
|---|---|---|
| **DTL** (`<assign>`, `<if>`, `<code>`, `<trace>`) | **two leading dots** | `..ConvertDateTime(source.X,"%d/%m/%Y","%Y-%m-%d")` |
| **Business rule** (condition, `<when>`) | bare name | `ConvertDateTime(source.X,"%d/%m/%Y","%Y-%m-%d")` |

> "In a business rule, simply refer to the utility function by name, along with any arguments:
> `ToUpper(value)`. In DTL, use two leading dots before the function name, along with any arguments:
> `..ToUpper(value)`."
> — `EBUS § A.2 Usage Differences between Business Rules and DTL`

**A bare call in a DTL compiles clean and throws `<UNDEFINED>` on the first `Transform()`.** There is
no compile error because ObjectScript reads the bare token as a *local variable*, which is legal
syntax and simply undefined at runtime:

```
ERROR #5002: ObjectScript error: <UNDEFINED>Transform+29^MyApp.DT.X.1
  *ConvertDateTime("22/07/1958","%d/%m/%Y","%Y-%m-%d")
```

The `*` before the name is the tell: IRIS is naming an undefined **variable**, not a missing method.

Do **not** "fix" this with `##class(Ens.Util.FunctionSet).ConvertDateTime(...)`. That does run —
which is why it looks like a solution — but it bypasses the function registry and the editor's
function picker, and it is the wrong idiom for a built-in. (For a *custom* FunctionSet it is
the **required** form — see §"Custom DTL functions via FunctionSet subclass".) The Portal's editors generate the `..` form automatically, so a DTL
built in the UI never has this bug; one authored as XML through the MCP is where it bites.

This is also why a DTL needs a `%UnitTest` that actually calls `Transform()`. A compile-only gate
cannot distinguish the two forms — both compile.

## Built-in DTL functions worth knowing

The DTL function picker exposes class methods registered via `Ens.Rule.FunctionSet` and its
subclasses (`Ens.Util.FunctionSet` is a superclass of it). **Use them before dropping to `<code>`** —
they're shorter, testable independently, and visible in the picker. All are shown below in DTL
syntax; drop the `..` in a business rule.

| Function | Use case |
|---|---|
| `..ConvertDateTime(value, in, out, file)` | Date format conversion — see the cheat-sheet below. `in`/`out` both default to `%Q`. The 4th argument only matters for `%f` filename elements. |
| `..Lookup(table, key, default)` | Lookup table consumption (see above). |
| `..In(value, "csv,list")` | Membership test against a comma-separated literal. |
| `..Translate(value, from, to)` | Character-level translation (`$TRANSLATE` semantics). |
| `..Upper`, `..Lower`, `..Length`, `..Find`, `..Piece`, `..Replace` | String primitives — direct `<assign>` instead of `<code>`. |

### Date / timestamp conversion cheat-sheet

`..ConvertDateTime` is the most-used and most re-derived of these. Verified conversions:

| Goal | `in` | `out` | Example |
|---|---|---|---|
| CSV `DD/MM/YYYY` → SQL `DATE` | `%d/%m/%Y` | `%Y-%m-%d` | `22/07/1958` → `1958-07-22` |
| US `MM/DD/YYYY` → SQL `DATE` | `%m/%d/%Y` | `%Y-%m-%d` | `07/22/1958` → `1958-07-22` |
| SQL `DATE` → CSV `DD/MM/YYYY` | `%Y-%m-%d` | `%d/%m/%Y` | `1958-07-22` → `22/07/1958` |
| HL7 TS → SQL `TIMESTAMP` | `%Y%m%d%H%M%S` | `%Y-%m-%d %H:%M:%S` | `19580722143000` → `1958-07-22 14:30:00` |
| SQL `TIMESTAMP` → HL7 TS | `%Y-%m-%d %H:%M:%S` | `%Y%m%d%H%M%S` | `1958-07-22 14:30:00` → `19580722143000` |

Three traps:

- **`%Q` is a full ODBC timestamp, not a date.** It is the *default* for both `in` and `out`, so it
  is easy to reach for — but `..ConvertDateTime(x,"%d/%m/%Y","%Q")` yields
  `1958-07-22 00:00:00.000`, which a `DATE` column will reject or silently truncate. For a date-only
  target use `%Y-%m-%d`.
- **It does not validate the calendar, and a bad value is returned unchanged.** Per `EBUS § A.1`:
  *"If `val` does not match the `in` format, `out` is ignored and `val` is returned unchanged."* So
  `31/02/1958` comes back as `1958-02-31` and free text passes straight through, reaching the column
  and failing at the JDBC bind — far from the DTL that caused it. Per-record validation belongs in
  the DTL (the `Valido`/`ErrorMotivo` pattern below), not in the date function.
- **`ConvertDateTimeToUTC` does not exist** (verified absent on IRIS for Health 2026.1 —
  `<METHOD DOES NOT EXIST>`). For timezone work, look up the actual available API rather than
  guessing a symmetrical name.

The raw ObjectScript equivalent is `$ZDATE($ZDATEH("22/07/1958",4),3)` → `1958-07-22` (format 4 =
`DD/MM/YYYY` in, 3 = `YYYY-MM-DD` out), but prefer `..ConvertDateTime` in a DTL: it is in the picker,
it round-trips through the visual editor, and it does not need a `<code>` block.

## Custom DTL functions via FunctionSet subclass

When the built-ins don't cover the case (custom date format with an error branch, project-specific
normalization, lookups that need post-processing), subclass **`Ens.Rule.FunctionSet`** — not
`Ens.Util.FunctionSet`, which is its superclass. Per `EGDV § 12.1`: only class methods defined in
*your* class become utility functions, and "there is no support for polymorphism, so to be precise,
you must mark these class methods as final".

```objectscript
Class MyApp.UTL.FunctionSet Extends Ens.Rule.FunctionSet
{
ClassMethod ParseFechaDDMMYYYY(value As %String) As %Date [ Final ]
{
    Set d = $ZDATEH(value, 4, , , , , , , -1)
    If d = -1 Quit ""     // policy: empty on bad input; throw if you prefer hard-fail
    Quit d
}

ClassMethod NormalizeKey(value As %String) As %String [ Final ]
{
    // Mask is "*WC" and accents are folded EXPLICITLY -- see the warning below before changing it.
    Set tAccents = "áéíóúàèìòùäëïöüâêîôûñç", tPlain = "aeiouaeiouaeiouaeiouncc"
    Quit $TRANSLATE($ZSTRIP($ZCONVERT(value, "L"), "*WC"), tAccents, tPlain)
}
}
```

**The mask is the whole difficulty, and `$ZSTRIP` masks are validated at RUNTIME — this class
compiles clean whichever one you write, so tier 2 can never catch a wrong one.** This method used to
carry `"*-CWE"` with the comment "strip whitespace/control/diacritics-like". Measured on IRIS for
Health 2026.1 against `"  Diabetica Fria  "`:

| mask | result |
|---|---|
| `*-CWE` | **raises `<FUNCTION>`** — every call, every message |
| `*CWE`, `*E` | `""` — the empty string for *every* input. `E` does not mean "ASCII punctuation"; it strips everything (#114) |
| `*WC` | `DiabeticaFria` — note it removes **internal** whitespace too, not just the ends |
| `<>W` | `Diabetica Fria` — leading/trailing only |

Two consequences worth keeping straight. `<FUNCTION>` at least fails loudly; `""` does not — the
helper returns, every lookup misses, and with a `""` default the DTL rejects every message for a
reason that names the data rather than the mask. And if your keys contain spaces that *matter*, `*WC`
is not the mask you want: use `<>W` to trim only the ends. There is no mask that folds accents, which
is why `$TRANSLATE` does it above.

The canonical version of this note, with the `$ZCONVERT` round-trip that also fails, is
`lookup-tables` §"Two `$ZSTRIP` traps" (#114). It was already correct while this section was wrong;
change one and change the other.

### A custom function is called `##class(...)`-qualified — the opposite of a built-in

This is the exception to the `..Func()` rule above, and the two are easy to swap by mistake:

| Function | DTL syntax | Business rule syntax |
|---|---|---|
| **Built-in** (`Strip`, `ConvertDateTime`, `Lookup`, …) | `..Strip(source.{ID},"<>CW")` | `Strip(source.{ID},"<>CW")` |
| **Your FunctionSet subclass** | `##class(MyApp.UTL.FunctionSet).NormalizeKey(source.{Sex})` | same — fully qualified |

> "It is not enough simply to identify the function; you must also identify the full class name for
> the class that contains the class method for your function. … You need to be aware of this syntax
> variation if you wish to type statements like this directly into your DTL code, rather than using
> the Data Transformation Builder to generate the code."
> — `EGDV § 12.1 Defining Custom Utility Functions`

That last sentence is this plugin's exact situation: authoring DTL XML through the MCP *is* typing
it directly, so the Builder is not there to generate the right form for you.

Once compiled, both functions appear in the DTL function picker and are callable from routing-rule
conditions. Keep **one FunctionSet per project**; don't fragment per DTL. Tests for these helpers are
plain `%UnitTest.TestCase` (no production needed) — fast and isolated.

## Canonical pattern — HL7 v2.5 ADT_A01 → v2.3 ADT_A01

```
Source class: EnsLib.HL7.Message     DocType: 2.5:ADT_A01
Target class: EnsLib.HL7.Message     DocType: 2.3:ADT_A01
Create:       New (versions differ; structure is not identical)

Actions:
  set target.MSH:9 = source.MSH:9
  foreach k1 in source.{PIDgrpgrp(k1)}:
    set target.{PIDgrpgrp(k1).PID:5} = source.{PIDgrpgrp(k1).PID:5}
    ...
  if source.PV1:2 = "I":
    set target.PV1:3 = ..Lookup("FacilityCodes", source.PV1:3, "UNKNOWN")
```

## XSLT for CDA

When transforming CDA documents (HL7 CDA R2 XML), DTL is awkward because of deep nesting and namespaces. **Use XSLT** via the XSLT transform action or a dedicated XSLT BP. Store XSLT files in the project and reference them from the production. Test XSLT outside IRIS first (any XSLT processor) before wiring into the production.

## Testing transformations

1. **Compile** the DTL — IRIS shows compile errors inline.
2. **Test button** in the DTL editor — paste a sample source message, click Transform, inspect the target.
3. The test surface persists the source between runs — convenient, but remember to refresh when changing scenarios.
4. Modified segments in the result are flagged (asterisk or red) — quick visual diff.
5. For HL7, keep a folder of canonical samples (happy-path, edge cases, malformed) and run them all on every DTL change.
6. **Compilation is required before testing** — the test interface runs the compiled class, not the editor state.

## When to drop to ObjectScript code

- Logic that requires a database query (e.g. "look up the patient in our master index").
- Date math beyond simple format conversion.
- Looping over data sources that aren't visible to the DTL (multiple lookup tables intersecting).
- Anything where the DTL would be >50% `code` actions.

In those cases embed a single `code` action that calls a class method — and keep the DTL as the
transform. Do **not** replace it with an imperative method: an `Ens.DataTransformDTL` subclass with
no `XData DTL` still compiles, but the Portal's DTL editor opens nothing (CR-4), and moving the
logic into a hand-written BP `OnRequest` is CR-1 — the P1 finding in `conformance-review`. If the
transform genuinely cannot be declared, that is a design signal worth raising, not a licence to
write it imperatively.

### ObjectScript inside XData is XML text — escape it

A DTL lives in an `XData` block, so everything inside `<code>`, `<assign value=…>` and
`<if condition=…>` is parsed as **XML first, ObjectScript second**. The operators that collide are
exactly the ones ObjectScript uses most:

| ObjectScript | Inside XData |
|---|---|
| `&&` | `&amp;&amp;` |
| `&` | `&amp;` |
| `<`, `<=` | `&lt;`, `&lt;=` |
| `>` | `&gt;` (required inside attribute values) |

```xml
<!-- breaks: ERROR #6301 SAX XML Parser Error: expected entity name for reference -->
<code>Quit:(tipo="")&&(val="")</code>

<!-- works -->
<code>Quit:(tipo="")&amp;&amp;(val="")</code>

<!-- or wrap it, which survives copy-paste and later edits better -->
<code><![CDATA[Quit:(tipo="")&&(val="")]]></code>
```

Worked example, compiled *and executed* against live IRIS 2026.1:
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/dtl-order-to-vendor.cls` (§5.7) —
shows both escaping forms, and its header records the compile-order trap: `Transform` is built by
a generator that resolves `sourceClass`/`targetClass` at generation time, so a DTL compiled in the
same batch as its own message classes can fail with `#5001 <CLASS DOES NOT EXIST>` wrapped in
`#5490`. Compile the messages first, or just compile twice.

**`expected entity name for reference` always means an unescaped `&`.** The parser reports a line and
offset **into the XData stream**, not into your source file, so the numbers will not match your editor
— go looking for the `&`, not for line 10. Measured over a workshop cohort: **16 of 18 students** hit
`#6301`.

The same rule governs routing-rule XData and any hand-written `XData ProductionDefinition` — see `bpl`.

## Where per-record validation belongs — the DTL, with `Valido`/`ErrorMotivo` flags

When an inbound flow must **validate each record and route valid vs invalid differently** (persist the good ones, send the bad ones to an error folder + alert), put the validation **in the DTL**, writing the outcome onto the target message as two properties — `Valido` (`%Boolean`) and `ErrorMotivo` (`%String`) — rather than failing the transform.

Why the DTL and not elsewhere:
- **It's the strongest TDD surface** — a test calls `##class(App.DT.X).Transform(src, .tgt)` and asserts directly on `tgt.Valido` / `tgt.ErrorMotivo`, with no production running.
- **Don't validate in the Record Map / field datatypes.** Strict field types or Record-Map-level rejection drop the record *before* it becomes a routable message — but the requirement is usually "valid records still persist, invalid go to an error sink + alert", which needs every record to survive as a message and branch downstream.
- **Don't scatter it into the routing rule or BP.** The rule/BP then just reads the computed `Valido` flag and branches (e.g. `Valido=1` → DB operation, `Valido=0` → error operation + `SendAlert`). No duplicated logic.

Keep the validation predicates in a reusable `App.UTL.FunctionSet Extends Ens.Rule.FunctionSet` (e.g. `EsDniValido`, `EsFechaValida`, `EsImporteValido`) so the DTL stays declarative and the rules are unit-testable on their own. Call them `##class(App.UTL.FunctionSet).EsDniValido(...)` — custom functions are qualified, built-ins are `..Func()`.

## Common pitfalls

- **Defaulting to Create=New** when source and target shapes match → costly rebuilding of every segment.
- **Forgetting to compile before testing** → the editor lies (runs the previous compiled version).
- **Calling a utility function bare in a DTL** (`ConvertDateTime(...)`, `Lookup(...)`) → compiles
  clean, throws `<UNDEFINED>` on the first `Transform()`. DTL needs `..Func()`; the bare form is the
  *business rule* syntax. See the syntax rule above.
- **`..Lookup()` without a default parameter** → silent "" on miss, hard to debug.
- **Validation lists / `In()` checks that don't tolerate diacritic and case variants** → `"Diabetica"` ≠ `"Diabética"` ≠ `"diabética"`; a hardcoded literal list rejects legitimate input silently. Normalize **both sides** before comparing — see `NormalizeKey` in the FunctionSet section above (called `##class(...)`-qualified); normalized lookup-table keys: `lookup-tables`.
- **Switch cases ordered generic-to-specific** → generic case matches first, specific cases never run.
- **Foreach over the wrong group** in HL7 nested structures (e.g. iterating PIDgrp when you wanted PIDgrpgrp).
- **Bounding a repeating-segment loop with `AL1Count`** → returns `""` on schemas that don't expose it; the loop runs zero times and the transform "succeeds" having processed nothing. See §"Iterating repeating segments" below for the safe pattern.
- **DTL doing DB lookups in `code` actions** that block the BP — move to a method that can be cached.
- **CDA in DTL** — almost always wrong; switch to XSLT.
- **Hand-rolling date conversion in `<code>` blocks** (`$ZDATEH(source.X, 4, , , , , , , -1)` etc.) → prefer `ConvertDateTime` from the function picker, or wrap the logic in a project FunctionSet subclass (see above). Inline `$ZDATEH` with positional empty args is unreadable and not reusable.
- **Treating `$$$LOGINFO(...)` inside a `<code>` action as a "side-effect to remove"** → log calls inside DTL are acceptable. The entry correlates with the message in Visual Trace without an extra routing rule or transform. Promote to a separate rule only when there is a real action (send/transform/store), not just observability.
- **Defaulting to `$$$Text(...)` for error strings** for "future localization" → not required in monolingual projects. Hardcoded literals (Spanish, English, whatever the team works in) are fine. Switch to `$$$Text` only when i18n is an actual requirement.

## HL7-specific patterns — fields, segments, paths

When the BS that produced the HL7.Message assigned `MessageSchemaCategory="<Version>:<MessageType>"` (e.g. `2.5:ADT_A01`) — and you set `sourceDocType='2.5:ADT_A01'` on the DTL `<transform>` element — IRIS resolves **symbolic field names** at message level. Without that pairing the DTL has no schema to resolve names against and only numeric paths work. See `business-services` for the BS-side setup; for Ad-hoc messages (Z-segments, custom structures) see `hl7-schemas`.

### Discovering symbolic field names — never guess them

A guessed HL7 field name returns `""` with `$$$OK`. There is no error, the DTL compiles, the
assertion passes on the empty string, and no real data flows — the same silent-miss shape as
`..Lookup()` without a default. IRIS stores its own internal names and they do **not** match the
HL7 specification's chapter headings, so `AllergenCodeMnemonicDescription` looks right and is not.

Read the real names off the schema before writing the DTL:

```objectscript
For f = 1:1:6 {
    Write "AL1:"_f_" -> "_##class(EnsLib.HL7.Schema).GetFieldNameFromNumber("2.5","AL1",f), !
}
// AL1:1 -> setidal1
// AL1:2 -> allergentypecode
// AL1:3 -> allergencodemnemonicdescript      (type CE — has .text, .identifier, .nameofcodingsystem)
// AL1:4 -> allergyseveritycode
// AL1:6 -> identificationdate
```

Then verify the full path against a real message before you rely on it:

```objectscript
Write msg.GetValueAt("AL1(1):allergencodemnemonicdescript.text")        // "Lactosa"
Write msg.GetValueAt("AL1(1):allergencodemnemonicdescript.identifier")  // "LCT"

// The guesses — no error, no warning, just "":
Write msg.GetValueAt("AL1(1):AllergenCodeMnemonicDescription")          // ""
Write msg.GetValueAt("AL1(1):AllergySeverityCode")                      // ""
```

**`""` with an `$$$OK` status means the PATH did not resolve — check the name, not the data.**

### Path resolution decision tree (validated empirically on IRIS 2026.1)

```
Where is the segment in the schema tree?
├── Top-level singleton (MSH, PID, PV1) → message-level symbolic name works
│   source.GetValueAt("PID:PatientName(1).GivenName")
│   source.GetValueAt("PV1:AssignedPatientLocation.PointOfCare")
│
├── Inside a group (NK1grp/NK1, AL1grp/AL1, etc.) → message-level path
│   GetSegmentAt("NK1(N)")  RETURNS NULL even when the segments exist
│   GetValueAt("NK1(N):3.1") RETURNS EMPTY
│   ⇒  Iterate by INDEX and filter by seg.Name:
│   For i = 1:1:source.SegCount {
│     Set seg = source.GetSegmentAt(i)
│     If '$IsObject(seg) Continue
│     If seg.Name = "NK1" { ... }
│   }
│
└── Once you have the segment object → seg.GetValueAt("3.1") works (NUMERIC paths).
    Whether SYMBOLIC names also work is decided by ONE thing, and it is not the group:
    does the segment have a DocType? A segment obtained from a message INHERITS the
    message's DocType — set msg.DocType and seg.DocType comes back "2.5:OBX" on its own.
```

**Verified on IRIS for Health 2026.1**, same message, same grouped `OBX`, only the message's
DocType changed:

| segment obtained from | `seg.DocType` | `seg.GetValueAt("3.2")` | `seg.GetValueAt("observationidentifier.text")` |
|---|---|---|---|
| a message with **no** DocType | *(empty)* | `Glucose` | `""` |
| a message with `DocType="2.5:ORU_R01"` | **`2.5:OBX`**, inherited | `Glucose` | `Glucose` |

So: **numeric paths always work on a segment; symbolic names work exactly when the segment has a
DocType, which it gets for free from the message.** Being inside a group does not affect this —
the grouped `OBX` above resolves symbolic names fine. What the group *does* break is the
**message-level** path, which is the trap the tree above is really about: on the same message,
`msg.GetValueAt("OBX(1):3.2")` returns `""` and `msg.GetSegmentAt("OBX(1)")` returns no object at
all, while the index-iteration route reaches the very same segment.

Two consequences:

- In a `<code>` block, if your symbolic paths come back empty, check `msg.DocType` **before**
  suspecting the schema or the group. No DocType on the message means no DocType on the segment.
- A segment you construct yourself (`##class(EnsLib.HL7.Segment).%New()` + `ImportFromString`) has
  no message to inherit from, and in testing did not resolve either path — build fixtures from a
  whole message instead (see `tdd` §"HL7 test fixtures").

### Iterating repeating segments — never bound the loop with `AL1Count`

The obvious way to iterate a repeating segment silently does nothing:

```objectscript
Set n = source.GetValueAt("AL1Count")   // returns "" or 0
For i = 1:1:n { ... }                    // loop body never runs, no error
```

`AL1Count` (and the `NK1`/`OBX`/`DG1` analogues) is not exposed by every schema version. Where it
isn't, `GetValueAt` returns `""`, `For i=1:1:""` iterates zero times, and the transform completes
"successfully" having processed zero repeats — the worst failure mode, because nothing surfaces.

The safe pattern is a bounded loop with an `$IsObject` break:

```objectscript
For i = 1:1:20 {
    Set seg = source.GetSegmentAt("AL1("_i_")")
    Quit:'$IsObject(seg)
    // ...
}
```

Applies to any repeating segment — `AL1`, `NK1`, `OBX`, `DG1`. Mention `AL1Count` only as
"verify it exists in your schema version first", never as the default. And when the named path
itself doesn't resolve (segment inside a group — see the decision tree above), fall back to the
`SegCount` + `seg.Name` index iteration, which needs no count either.

### `<code>` block vs `<assign>` element

- `source.{PID:PatientName(1).GivenName}` curly-brace syntax **only works inside DTL `<assign>` elements**, not inside `<code>` blocks. Inside `<code>` use `source.GetValueAt("PID:PatientName(1).GivenName")` instead.

### Pipe-string ↔ list collection

When the source message carries a pipe-separated string (e.g. `Alergias = "Lactosa|Frutos secos"`) and the target wants a tipped collection (`list Of %String`), the DTL pattern is **split with a bounded loop, skipping empty pieces** to avoid the ghost-element trap:

```objectscript
// Split pipe-string -> AlergiasList; "" -> empty list (NOT one empty element)
If source.Alergias '= "" {
  For i = 1:1:$LENGTH(source.Alergias, "|") {
    Set piece = $PIECE(source.Alergias, "|", i)
    If piece '= "" Do target.AlergiasList.Insert(piece)
  }
}
```

The reverse direction (list → pipe-string for back-translation): `Set target.Alergias = ""  For i=1:1:src.AlergiasList.Count() { Set target.Alergias = target.Alergias _ $S(target.Alergias="":"", 1:"|") _ src.AlergiasList.GetAt(i) }`.

### Subtransform pattern for HL7 repeating segments

For AL1, NK1, OBX (etc.) where one segment maps to one item in a collection:

```objectscript
Class MyApp.DT.AL1Subtransform Extends Ens.DataTransformDTL
{
XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Segment' targetClass='Ens.StringContainer' create='new' language='objectscript'>
  <code><![CDATA[
    Set text = source.GetValueAt("3.2")
    If text = "" Set text = source.GetValueAt("3.1")
    Set target.StringValue = text
  ]]></code>
</transform>
}
}
```

Invoke from the main DTL inside the segment-iteration loop:

```objectscript
For i = 1:1:source.SegCount {
  Set seg = source.GetSegmentAt(i)
  If '$IsObject(seg) Continue
  If seg.Name = "AL1" {
    Kill tmp
    Set tSC = ##class(MyApp.DT.AL1Subtransform).Transform(seg, .tmp)
    If $$$ISOK(tSC) && $IsObject(tmp) && (tmp.StringValue '= "") {
      Do target.AlergiasList.Insert(tmp.StringValue)
    }
  }
}
```

### Subtransforms over `EnsLib.HL7.Segment` — declare `sourceDocType`

The subtransform above reads the segment with numeric paths because nothing told it what the
segment *is*. Declaring `sourceDocType` on the `<transform>` element fixes that, and is the form
to prefer — the numeric version is what you fall back to, not what you reach for first:

```xml
<!-- positional: brittle, and nothing in the file says what 3.2 is -->
<transform sourceClass='EnsLib.HL7.Segment' targetClass='Ens.StringContainer' create='new'>
  <assign value='source.{3.2}' property='target.StringValue'/>
</transform>

<!-- symbolic: the DocType gives the segment its schema back -->
<transform sourceClass='EnsLib.HL7.Segment' sourceDocType='2.5:AL1'
           targetClass='Ens.StringContainer' create='new'>
  <assign value='source.{allergencodemnemonicdescript.text}' property='target.StringValue'/>
</transform>
```

`sourceDocType` is the DTL-side way of supplying what a segment would otherwise inherit from its
message (see the table above): the transform receives a bare `EnsLib.HL7.Segment` as `source` and
cannot know its provenance, so declare it. This works for a segment passed in from a group as well
— the discriminator is the DocType, never where the segment sat in the schema. Component names
inside a composite field (`.text`, `.identifier`, `.nameofcodingsystem` on a CE) resolve through
the same path syntax once it is set. Get the field names from `GetFieldNameFromNumber` (above)
rather than guessing them.

### `<foreach>` over top-level repeating segments

When the schema puts the repeating segment **directly** in the MessageStructure — `[~{~2.5:AL1~}~]`
in the definition, not nested in a named group — you do not need a `<code>` block at all. Iterate
declaratively with an empty-parenthesis path:

```xml
<foreach property='k1' key='k2' in='source.{AL1()}'>
  <!-- k1 is the 1-based occurrence index; k2 is unused for a flat segment -->
  <assign value='source.{AL1(k1):3.2}' property='target.SomeField'/>
</foreach>
```

`in='source.{AL1()}'` iterates every occurrence. That is a different shape from
`in='source.{PIDgrpgrp(k1)}'`, which iterates a named **group**.

Inside the loop, `source.{AL1(k1)}` resolves to the individual `EnsLib.HL7.Segment` object, so it
can be handed straight to a subtransform:

```xml
<foreach property='k1' key='k2' in='source.{AL1()}'>
  <subtransform class='MyApp.DT.AL1ToText'
                targetObj='tmp'
                sourceObj='source.{AL1(k1)}'/>
  <if condition='tmp.StringValue &apos;= ""'>
    <true>
      <assign value='$S(target.Alergias="":"",1:target.Alergias_"|")_tmp.StringValue'
              property='target.Alergias'/>
    </true>
  </if>
</foreach>
```

**This form only works when the segment is top-level.** If `AL1` sits inside a named group
(`ALgrpgrp`), `source.{AL1(k1)}` does not resolve — use `source.{ALgrpgrp(k1).AL1}`, or fall back
to the `SegCount` + `seg.Name` iteration above, which needs neither a count nor a resolvable path.

Prefer `<foreach>` when the rest of the transform needs no `<code>` block; reach for the
ObjectScript loop when it already has one.

## Date / numeric type marshalling pitfalls

- **`%Date` (storage = integer day count) ≠ string `YYYY-MM-DD`**. The PostgreSQL JDBC driver throws `StringIndexOutOfBoundsException: begin 0, end 10, length 5` when bound a raw `%Date` integer to a `DATE` column. Convert in the DTL or BO with `$ZDATE(tDate, 3)` before binding.
- **`%TimeStamp` for `xs:dateTime`**: replace the space with `T`. `$TRANSLATE($ZDATETIME($HOROLOG, 3), " ", "T")` produces `2026-05-13T07:13:59`.
- **Canonical message types should hold values as `%String`** when they collect from HL7/REST sources — a typed field receiving free text (`Planta As %SmallInt` ← `"PLANTA3"`) dies with `#7207` and kills the BP; cast in the DTL after extraction. Full datatype rule: `messages`.

## Lab device integration — DT in BOTH directions

When integrating with a lab analyzer / device vendor (Roche, Suitestensa, generic ASTM-over-HL7 bridges, etc.), even directions that look like passthrough usually need a DT. The DT is rarely "translate ADT vendor format to ADT canonical" — it's "snap the vendor's HL7 to the receiver's expectations", which often differ from the standard.

Common patterns observed across customer projects:

- **Field truncation**: the sender emits `MSH-7` as `YYYYMMDDHHMMSS.fff`; the receiver (typically an EMR) rejects the millisecond variant and wants `YYYYMMDDHHMMSS`. Truncate in the DTL.
- **Segment re-ordering**: the receiver keys on segment position. E.g. `SAC` (Specimen And Container) must come **after** `PV1` for one vendor, **before** for another. Re-order in the DTL with explicit segment iteration.
- **Field copying between segments**: the receiver's primary key is in a non-standard field (`PID-2` and `PID-9` copying a technique code carried in `OBR-4` by the vendor). Copy explicitly.

Do **not** assume "vendor A → vendor B" is passthrough without inspecting actual payloads in production. Build the DT per direction, with tests, and check it during commissioning — silent mis-parse is a frequent failure mode.

## ObjectScript inside DTL `<code>` blocks — use the modern try/catch idiom

When dropping to ObjectScript inside a DTL `<code>` activity (or a helper method it calls), wrap the work in try/catch, convert exceptions with `errObj.AsStatus()`, and always return `%Status` — the DTL framework expects it and surfaces errors correctly. Never `Quit <value>` inside the `Try` (`#1043`); standardise new code on `$$$ThrowOnError` rather than wizard-style `$$$ISERR(...)` chains. Full idiom: `unit-tests` §"Error handling inside test methods"; canonical copy-paste class: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/objectscript-trycatch.cls` (§5.4 in `examples/README.md`).

## When NOT to use this skill — fall back to docs

- FHIR resource transformations — different patterns (`HS.FHIR.DTL.*`); see `fhir`.
- Procedural orchestration (multi-step workflows with side effects) — that's a BPL job, see `bpl`.

## See also

- `messages` — define the source and target message classes first; XML projection settings for output shape
- `lookup-tables` — Lookup() function source data
- `hl7-schemas` — when source/target HL7 needs custom Z-segments; escape special characters when building HL7 strings by hand
- `bpl` — when "transformation" is really orchestration
- `fhir` — FHIR DTL patterns (`HS.FHIR.DTL.*`)
- `business-operations` — lab device integration DT both directions; port pair documentation
