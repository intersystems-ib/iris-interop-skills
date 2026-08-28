---
name: transformations
description: DTL transforms, lookups, HL7 field paths, XSLT for CDA. Routed from interop. Triggers: DTL, transformación, data transform, mapear, subtransform, HL7 field path, XSLT, CDA, Lookup().
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

`Lookup("TableName", source.field, "default-or-empty")` translates codes via a lookup table. See `lookup-tables`. Always specify the third parameter (default value or behaviour on miss) — the default-on-miss is silent and surprising otherwise.

## Built-in DTL functions worth knowing

The DTL function picker exposes class methods registered via `Ens.Util.FunctionSet` and its subclasses. **Use them before dropping to `<code>`** — they're shorter, testable independently, and visible in the picker.

| Function | Use case |
|---|---|
| `ConvertDateTime(value, sourceFormat, targetFormat)` | Date format conversion. Default for parsing DD/MM/YYYY → `%Date` is `ConvertDateTime(source.X, "%d/%m/%Y", "%Q")` — clearer than a `<code>` block with `$ZDATEH`. |
| `Lookup(table, key, default)` | Lookup table consumption (see above). |
| `In(value, "csv,list")` | Membership test against a comma-separated literal. |
| `Translate(value, from, to)` | Character-level translation (`$TRANSLATE` semantics). |
| `Upper`, `Lower`, `Length`, `Find`, `Piece`, `Replace` | String primitives — direct `<assign>` instead of `<code>`. |

## Custom DTL functions via FunctionSet subclass

When the built-ins don't cover the case (custom date format with an error branch, project-specific normalization, lookups that need post-processing), subclass `Ens.Util.FunctionSet`:

```objectscript
Class MyApp.Util.FunctionSet Extends Ens.Util.FunctionSet
{
ClassMethod ParseFechaDDMMYYYY(value As %String) As %Date [ Final ]
{
    Set d = $ZDATEH(value, 4, , , , , , , -1)
    If d = -1 Quit ""     // policy: empty on bad input; throw if you prefer hard-fail
    Quit d
}

ClassMethod NormalizeKey(value As %String) As %String [ Final ]
{
    Quit $ZSTRIP($ZCONVERT(value, "L"), "*-CWE")    // lowercase + strip whitespace/control/diacritics-like
}
}
```

Once compiled, `MyApp.Util.FunctionSet.ParseFechaDDMMYYYY(...)` and `NormalizeKey(...)` appear in the DTL function picker and are callable from routing-rule conditions. Keep **one FunctionSet per project**; don't fragment per DTL. Tests for these helpers are plain `%UnitTest.TestCase` (no production needed) — fast and isolated.

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
    set target.PV1:3 = Lookup("FacilityCodes", source.PV1:3, "UNKNOWN")
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

Keep the validation predicates in a reusable `App.UTL.FunctionSet Extends Ens.Util.FunctionSet` (e.g. `EsDniValido`, `EsFechaValida`, `EsImporteValido`) so the DTL stays declarative and the rules are unit-testable on their own.

## Common pitfalls

- **Defaulting to Create=New** when source and target shapes match → costly rebuilding of every segment.
- **Forgetting to compile before testing** → the editor lies (runs the previous compiled version).
- **Lookup() without a default parameter** → silent "" on miss, hard to debug.
- **Validation lists / `In()` checks that don't tolerate diacritic and case variants** → `"Diabetica"` ≠ `"Diabética"` ≠ `"diabética"`; a hardcoded literal list rejects legitimate input silently. Normalize **both sides** before comparing — see `NormalizeKey` in the FunctionSet section above; normalized lookup-table keys: `lookup-tables`.
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
    Symbolic names at segment level (seg.GetValueAt("Relationship.Identifier")) do
    NOT resolve reliably when the segment is in a group — stick to numeric paths
    on the segment.
```

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
