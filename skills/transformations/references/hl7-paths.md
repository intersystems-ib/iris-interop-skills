# HL7 paths, segments and repeating fields

Everything specific to transforming HL7 v2: discovering symbolic field names, the path-resolution decision tree, iterating repeating segments, subtransforms over `EnsLib.HL7.Segment`, and `<foreach>`. Read this only when the transform is HL7.

## Contents

- HL7-specific patterns — fields, segments, paths
- Discovering symbolic field names — never guess them
- Path resolution decision tree (validated empirically on IRIS 2026.1)
- Iterating repeating segments — never bound the loop with `AL1Count`
- `<code>` block vs `<assign>` element
- Pipe-string ↔ list collection
- Subtransform pattern for HL7 repeating segments
- Subtransforms over `EnsLib.HL7.Segment` — declare `sourceDocType`
- `<foreach>` over top-level repeating segments

## HL7-specific patterns — fields, segments, paths

When the BS that produced the HL7.Message assigned `MessageSchemaCategory="2.5"` — the **category
alone**, which combines with MSH-9 to produce the DocType — and you set `sourceDocType='2.5:ADT_A01'`
on the DTL `<transform>` element, IRIS resolves **symbolic field names** at message level. Without
that pairing the DTL has no schema to resolve names against and only numeric paths work.

The two are written differently and it matters: the **setting** takes a category (`2.5`), the
**`sourceDocType`** takes a full DocType (`2.5:ADT_A01`). Putting a DocType in the setting errors —
`<Ens>ErrGeneral: DocType not found for message type 2.5:ADT_A01:ADT_A01`, because the value is
concatenated with MSH-9. See `business-services` §"HL7 Business Service" for the measurement, and
`hl7-schemas` for Ad-hoc messages (Z-segments, custom structures).

**Gated, executed example:**
`../assets/dtl-hl7-symbolic-paths.cls` with its
fixture test `tdd-hl7-fixture-test.cls`. Measured, and the reason that test exists: a DTL compiles
**identically** whether the symbolic path is right or nonsense, so tier 2 is green on both — only
running the transform and asserting an output field separates them.

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

**Both of those failures DO set an error status** — measured on 2026.1:
`msg.GetSegmentAt("OBX(1)", .sc)` leaves `sc` = `ERROR <Ens>ErrGeneral: No segment found at path
'OBX(1)'`, and `msg.GetValueAt("OBX(1):3.2", , .sc)` sets the same kind of error. So this is silent
only if you discard the status — and `GetValueAt`'s status is its **third by-reference argument**,
which is exactly the one a `<code>` block omits. Pass it and check it, and the group trap announces
itself instead of looking like missing data.

One caveat on the tree above: **whether a segment is grouped depends on the message type.** `NK1` is
*top-level* in an ADT_A01, so `GetSegmentAt("NK1(1)")` there returns the object and
`GetValueAt("NK1(1):2.1")` returns the value — the message-level path works. It is `OBX` in an
ORU_R01, and `NK1` in message types that group it, where the path fails. Check the structure before
concluding the path form is at fault.

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

