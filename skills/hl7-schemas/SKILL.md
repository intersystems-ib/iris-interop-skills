---
name: hl7-schemas
description: Custom HL7 v2 schemas, Z-segments, schema editor. Routed from interop. Triggers: custom HL7 schema, esquema HL7, Z-segment, DocType, schema editor, schema category, v2.x, ER7, segmento personalizado.
---

# Custom HL7 Schemas

Custom HL7 v2 schemas are how IRIS accommodates partner messages that deviate from the published HL7 standard — Z-segments, missing required segments, extended fields. Schemas live in **schema categories** in the namespace; the schema editor is in the Management Portal.

This skill covers when to author a custom schema, the canonical workflow, and two operational gotchas (auto-export to SCM and escaping when building messages by hand) that have caused silent loss-of-work across multiple customer projects.

## When to use this skill

The user mentioned: custom HL7 schema, Z-segment, custom DocType, schema editor, schema category, importing a v2.x dictionary, or modifying a built-in schema (e.g. extending PID with site-specific fields).

## What this skill currently knows

- HL7 schemas live in **schema categories** in IRIS. Built-in categories are read-only (`2.3`, `2.5`, `2.5.1`, etc.). To customize, **create a new category** that *inherits from* a built-in category and adds/overrides only the changed pieces.
- Custom segments (Z-segments, e.g. `ZIN`) are added to a custom category. Field structure (data types, lengths, optionality, repetition) is defined in the schema editor.
- A custom DocType (e.g. `MyHospital_2.5:ADT_A01`) lets you reference the customized message structure from BS/BP/BO and DTL.
- Schemas are **deployable artefacts** — they go in the production export bundle (but NOT auto-exported to source control; see below).
- DTLs reference DocTypes. Changing a schema can break DTLs that reference removed/renamed elements.

## When a custom schema is required

When a partner emits ER7 messages that deviate from the published HL7 standard — e.g. a `SQM_S25` / `SRM_S25` missing the standard `RGS` segment, or a `ZPI` segment carrying site-specific patient preferences — define a custom schema based on the closest standard version (typically v2.5), redefine only the affected messages, and point the BS's `MessageSchemaCategory` at the custom schema.

This is the only way to make DTL field-name resolution work for the non-standard fields. Without a custom schema, DTL falls back to numeric paths and the BS may reject messages it can't validate against the standard.

## Schemas are NOT auto-exported to source control — HIGH severity

Custom HL7 schemas edited via the Management Portal are stored **in the namespace**, not on disk. They are **not auto-exported** by git-source-control or VS Code's ObjectScript export. After every edit:

1. Export the schema explicitly from the portal to the SCM root.
2. Commit the exported file alongside the related class changes.

Failure to export is a **silent loss-of-work risk**: on the next namespace refresh (DB restore, container rebuild, environment refresh from PROD baseline), the in-portal edits disappear and nobody notices until a message fails to parse weeks later.

This is the single most common cause of "the schema used to work, then it disappeared" reports. Make schema export a step in the PR checklist for any commit that includes schema-affecting work.

## What this skill does NOT yet do

- Generate custom schema XML from a plain-English description of the customization.
- Diff two schema versions and identify breaking changes for downstream DTLs.
- Automate the export-on-save flow (which would close the loss-of-work risk above).

## How to proceed

Two viable paths — pick by environment:

- **Management Portal (UI)**: Interoperability → Build → HL7 Schema Editor. Add the Z-segment / modified structure, save, then *export to SCM* (the loss-of-work risk above).
- **MCP / scripted (no UI)**: author the canonical XML on disk and call `EnsLib.HL7.SchemaXML.Import(file, .imported)` via a SqlProc. See the **MCP cookbook** below — this is the only path that works when the only access to IRIS is MCP tooling.

After either path, recompile every DTL referencing the affected DocType — broken references surface at compile time.

## Cookbook — Ad-hoc schema for non-standard ADT_A01

Use case: receiving ADT_A01 messages that include a custom `ZPI` segment carrying patient preferences not in standard 2.5, plus an extended PID with extra components in PID.39.

1. **Management Portal → Interoperability → Build → HL7 Schema Editor**.
2. **New category**: name it `MyApp_2.5` (suffix the version it derives from — readable, version-traceable).
3. **Base on** the built-in `2.5` category — gets all built-in message structures as starting point.
4. **Add the Z-segment**: New Segment Structure → `ZPI` → declare each field (name, datatype, repetition, length). For composite types, define data structures first (under "Data Structures" tab).
5. **Override the message structure**: Open `ADT_A01` (inherited from 2.5), make a copy under `MyApp_2.5`, edit the segment list to insert `ZPI` at the right position. Mark optional/required, repeating count.
6. **Save** — IRIS compiles the schema. New DocType becomes `MyApp_2.5:ADT_A01`.
7. **Assign to the BS** (see `business-services`):

   ```xml
   <Setting Target="Host" Name="MessageSchemaCategory">MyApp_2.5</Setting>
   ```

   The **category only** — never `MyApp_2.5:ADT_A01`. The service concatenates this value with MSH-9
   to build the DocType, so a colon here yields `MyApp_2.5:ADT_A01:ADT_A01` and resolves nothing.
   Step 8's `sourceDocType` is a different thing and *does* take the full `category:structure`.

8. **In the DTL**: declare `sourceDocType='MyApp_2.5:ADT_A01'` on `<transform>`. Field names now
   resolve for both standard fields (PID, PV1) and the custom ones (ZPI).

**And then use them.** Addressing fields by NAME rather than position is the point of assigning a
schema at all — `{PV1:PatientClass}`, not `{PV1:2}`; `{MSH:MessageType.MessageCode}`, not `{MSH:9.1}`.
A positional path is correct and unreadable, and HL7 work is reviewed by eye. Measured on 2026.1:
you **cannot mix** the two (`{MSH:MessageType.1}` is invalid), names are case-insensitive, and
`##class(EnsLib.HL7.Schema).GetFieldNameFromNumber(category, segment, number)` is the authoritative
way to find a name — though it returns **empty for repeating fields** (`PID:3`, `PID:5`, `OBX:5`),
which is when the Schema Editor is the answer. Full table in `transformations` §"Name the field, do
not number it" and deliverable §2.11.

> **It is a floor, not a ceiling — and the first argument is a CATEGORY.** Measured on 2026.1:
> `GetFieldNameFromNumber("2.5","PID",n)` returns a name for 1, 2, 7, 8, 18 and **empty** for 3, 5
> and 11 — the repeating fields. Empty does **not** mean the field has no usable name:
> `[PID:PatientName().FamilyName]` and `[PID:PatientIdentifierList().IDNumber]` both resolve, and the
> function reports neither. So when it returns empty, try a path before falling back to a number.
> Also: pass `"2.5"`, **not** the DocType `"2.5:ADT_A01"` — a DocType returns empty for *every* field,
> which looks exactly like the repeating-field case.

## Cookbook — MCP-friendly import via XML + SqlProc

When the Portal UI isn't available (working entirely via MCP, headless CI, scripted environment
refresh), the canonical path is the **headless bootstrap** pattern — `interop` §"Headless bootstrap — running the calls `iris_execute` cannot" carries the rule
and the generic skeleton; the schema-specific steps are:

1. Author the schema as a **standalone XML file** (root `<Category>`, see format below).
2. Call `##class(EnsLib.HL7.SchemaXML).Import(file, .pCategoryImported)` from a SqlProc wrapper.
   Re-importing an edited schema **overwrites but does not clean**: a segment you renamed or removed
   lingers in the category. Remove the category first — the `RemoveSchema` companion below exists
   for exactly that, and is the schema equivalent of deleting a `.Record` before regenerating it.
3. Verify with `EnsLib.HL7.Schema.ResolveSegNameToStructure(...)` / `ResolveSchemaTypeToDocType(...)`.

### Anti-pattern — do NOT do this

Subclassing `EnsLib.HL7.Util.SchemaDocument` with an `XData` block of the schema does **not** work in IRIS 2026.1 — that superclass does not exist (the chain that does exist is `EnsLib.HL7.SchemaDocument` and `EnsLib.HL7.SchemaXML`, neither intended as a subclass anchor). The class will fail to compile and the schema will never register. Use XML + Import instead.

### Canonical XML format

Root element is `<Category>` (NOT `<Schema>`). Discover the exact shape by exporting any standard category once: `##class(EnsLib.HL7.SchemaXML).Export("2.3.1", "C:\Temp\std.xml")`. Key shapes you must match:

```xml
<?xml version="1.0" encoding="UTF-8"?>

<Category name="PharmacySchema" base="2.3.1" description="...">

  <!-- A Z-segment, or any custom segment.  Each field is a SegmentSubStructure
       with piece=N (the HL7 field index, 1-based). NOT <Field>. -->
  <SegmentStructure name='ZAL' description='Allergy Identified Z-segment'>
    <SegmentSubStructure piece='1' description='Allergy Identified' datatype='ST'
                         max_length='10' required='O' ifrepeating='0'/>
  </SegmentStructure>

  <!-- The message structure is a SINGLE tilde-separated definition string,
       NOT nested <Segment> elements. Square brackets [~..~] = optional,
       curly braces {~..~} = repeating, <~A~|~B~> = choice. -->
  <MessageStructure name='ORM_O01'
    definition='MSH~[~ZAL~]~[~{~NTE~}~]~[~PID~[~PD1~]~...~{~ORC~[~&lt;~OBR~|~RXO~&gt;~...~]~}'/>

  <MessageType name='ORM_O01' structure='ORM_O01'/>

</Category>
```

Notes:
- `base` makes the category *inherit* from a built-in (you only override what changes). Without `base`, it's a standalone category and inherits nothing.
- Inside `definition='...'`, encode `<` as `&lt;` and `>` as `&gt;` (they're real XML attribute content).
- `required` = `'R'` (required) or `'O'` (optional). `ifrepeating` = `'0'` or `'1'`.
- A `<MessageType>` linking the message-type name to its structure is required for DTLs that reference `PharmacySchema:ORM_O01` to resolve.

> **`ADT_A01` is legal as DATA and illegal as an IDENTIFIER.** It is fine in
> `MessageSchemaCategory`, a DocType, this XData and a `Lookup()` key; it is not fine in a class
> or member name, where `_` is the concatenation operator and produces the misleading
> `#5559 … non-matching {} or ()`. `Pkg.DT.ADT_A01ToMenuReq` → `Pkg.DT.AdtA01ToMenuReq`. See
> `interop` §"Invariants when writing ANY ObjectScript class".

### Extending an inherited MessageStructure — prefix every base segment `N.N:`

`base="2.5"` makes the category inherit, but the moment you **override** a MessageStructure you are
re-declaring the whole definition string, and every segment in it is re-resolved against **your**
category. A bare `PID` in that string means "PID as defined here" — and your category does not
define one. So each segment that comes from the base must carry the `category:` prefix; only the
segments you are adding go unprefixed.

```xml
<!-- WRONG: the base segments look local. Some resolve from the base by luck,
     others silently do not, and nothing errors at import time. -->
<MessageStructure name='ADT_A01' definition='MSH~EVN~PID~{~NK1~}~PV1~[~{~AL1~}~]~[~ZDI~]'/>

<!-- RIGHT: base segments prefixed, only the new Z-segment bare. -->
<MessageStructure name='ADT_A01'
  definition='2.5:MSH~[~{~2.5:SFT~}~]~2.5:EVN~2.5:PID~[~2.5:PD1~]~[~{~2.5:ROL~}~]~[~{~2.5:NK1~}~]~2.5:PV1~[~2.5:PV2~]~[~{~2.5:DB1~}~]~[~{~2.5:OBX~}~]~[~{~2.5:AL1~}~]~[~2.5:DRG~]~[~2.5:PDA~]~[~ZDI~]'/>
```

An unprefixed segment resolves against the *current* category; where it is not defined there, IRIS
falls back silently rather than erroring — so the failure surfaces later, as an unreadable path in
a DTL, exactly like the placement trap below.

**Do not type the base definition by hand.** Read it out of the live schema and append to it, so it
stays correct when the IRIS version moves the base schema underneath you:

```objectscript
// The real v2.5 ADT_A01 definition, as this instance has it
Set base = $Get(^EnsHL7.Schema("2.5","MS","ADT_A01"))
// Append the custom segment, then paste the result into definition='...'
Set extended = base _ "~[~ZDI~]"
Write extended, !
```

Hand-typing the string is how a segment goes missing from the middle of a 14-segment definition
without anyone noticing.

### Where you place the segment in the definition decides how you address it — HIGH severity

The `definition` string is not just a validity rule; it *is* the path grammar. Put the
Z-segment at the top level and it is `ZAL:1`. Put the same segment inside a repeating
group and that path stops resolving — and nothing tells you, because
`ResolveSchemaTypeToDocType` still returns the DocType and the DTL still compiles.

Measured on IRIS 2026.1, same message and same category, only the placement changed:

| placement in `definition` | path that reads field 1 |
|---|---|
| top level — `…~}~}~[~ZAL~]~[~DSC~]` | `ZAL:1` |
| inside the repeating order group — `…~[~{~OBX~…~}~]~[~{~ZAL~}~]~…` | `PIDgrpgrp(1).ORCgrp(1).ZAL(1):1` |

Two traps in the nested form:

- **The group prefix is mandatory.** Plain `ZAL:1` returns `""` with
  `<Ens>ErrGeneral: No segment found at path 'ZAL'` — the same error a *missing* category
  produces, so it reads like the schema never imported when in fact it imported fine.
- **So is the repetition index.** `PIDgrpgrp(1).ORCgrp(1).ZAL:1` also fails; only
  `ZAL(1)` resolves. A segment inside `{~…~}` is always subscripted.

In a DTL this surfaces as a target property that is simply empty — `<assign>` with an
unresolvable source path is not a compile error. Confirm the path before writing the
transform:

```objectscript
// The segment is present either way — this is only a check that it parsed,
// NOT the way to read it (that is the character-counting shortcut in disguise).
Write msg.GetSegmentAt(5).Name, " ", msg.GetSegmentAt(5).GetValueAt(1), !
// The real question: does the path you are about to put in the DTL resolve?
Set tSC = $$$OK
Write msg.GetValueAt("ZAL:1", , .tSC), " ", $System.Status.GetErrorText(tSC), !
```

Do **not** write `$G(msg.GetValueAt("ZAL:1"))` to be safe here — `$GET` forces property syntax, so it
fails with `<PROPERTY DOES NOT EXIST> GetValueAt` on a method that works unwrapped. Guard the object
(`$IsObject`) instead; see `message-search-debug`.

Prefer top-level placement for a trailing Z-segment unless the partner's own
specification genuinely nests it — the path stays short, and DTL authors in the visual
editor get `ZAL:…` rather than a four-part group path.

### SqlProc wrapper

```objectscript
/// MCP-friendly: import the custom schema from a fixed path on disk.
ClassMethod ImportSchema(pFile As %String = "") As %String [ SqlProc ]
{
    If pFile = "" Set pFile = "C:\path\to\src\Hospital\HL7\PharmacySchema.xml"
    If '##class(%File).Exists(pFile) Quit "schema_xml_not_found: " _ pFile
    Set tImportedCat = ""
    Set sc = ##class(EnsLib.HL7.SchemaXML).Import(pFile, .tImportedCat)
    If $$$ISERR(sc) Quit "schema_import_FAIL: " _ $system.Status.GetErrorText(sc)
    Quit "schema_imported category=" _ tImportedCat
}

/// Companion: idempotency before re-import (drop category from the globals).
ClassMethod RemoveSchema(pCategory As %String) As %String [ SqlProc ]
{
    If pCategory = "" Quit "category_required"
    If $Data(^EnsHL7.Schema(pCategory))=0 Quit "category_not_present"
    Kill ^EnsHL7.Schema(pCategory)
    Kill ^EnsHL7.Description(pCategory)
    Quit "category_removed " _ pCategory
}

/// Diagnostic: dump an existing category so you can see the canonical format.
ClassMethod ExportSchemaXML(pCategory As %String, pFile As %String) As %String [ SqlProc ]
{
    Set sc = ##class(EnsLib.HL7.SchemaXML).Export(pCategory, pFile)
    If $$$ISERR(sc) Quit "export_FAIL: " _ $system.Status.GetErrorText(sc)
    Quit "export_ok file=" _ pFile
}
```

Invoke via MCP: `SELECT Hospital.Bootstrap_ImportSchema() AS r`.

### Verification part 1 — the schema is REGISTERED (paste into a `%UnitTest.TestCase`)

```objectscript
Method TestZALResolves()
{
    Set tStatus = $$$OK
    Set tStruct = ##class(EnsLib.HL7.Schema).ResolveSegNameToStructure(
        "PharmacySchema", "", "ZAL", .tStatus)
    Do $$$AssertStatusOK(tStatus)
    Do $$$AssertNotEquals(tStruct, "", "ZAL is registered")
}

Method TestDocTypeAndZALInStructure()
{
    Set tStatus = $$$OK
    Set tDT = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType(
        "PharmacySchema", "ORM_O01", .tStatus)
    Do $$$AssertStatusOK(tStatus)
    Do $$$AssertNotEquals(tDT, "", "PharmacySchema:ORM_O01 resolves")

    // Walk the compiled structure global to confirm ZAL appears in ORM_O01.
    Set tHit = 0, tKey = ""
    For  { Set tKey = $Order(^EnsHL7.Schema("PharmacySchema", tKey))
           Quit:tKey=""
           If $G(^EnsHL7.Schema("PharmacySchema", tKey, "ORM_O01")) [ "ZAL" {
               Set tHit = 1 Quit } }
    Do $$$AssertTrue(tHit, "ORM_O01 storage mentions ZAL")
}
```

### Verification part 2 — the schema is CORRECT (registration is not structure)

**The tests above prove the category loaded. They do not prove a real message parses against it.**
A schema that compiles, registers, and resolves its Z-segment can still have the wrong segment
*order*, and the natural unit test does not notice:

```objectscript
Set obj = ##class(EnsLib.HL7.Message).ImportFromString(msg, .sc)
Do obj.DocTypeSet("MyApp_2.5:ADT_A01")
Do $$$AssertEquals(obj.GetValueAt("AL1(2):3.2"), "Frutos secos")   // PASSES
```

`ImportFromString` + `DocTypeSet` + `GetValueAt` **read fields; they do not enforce the message
structure**. A message whose `NK1` arrives after the `AL1` repetitions — a real and common
sending-system variance — passes every assertion above while the schema's `MessageStructure` says
`NK1` may only appear before `PV1`. The failure then surfaces in production, in the routing engine:

```
ERROR <EnsEDI>ErrMapSegUnrecog: Unrecognized Segment 8:'NK1' found after segment 7 (AL1(3))
```

This is the concrete mechanism behind "a schema that compiles is not a correct schema" above.

#### The trap: the router does not validate by default

Routing an HL7 message through `EnsLib.HL7.MsgRouter.RoutingEngine` only checks structure when the
router's **`Validation`** setting is non-empty — and it is **initialised to an empty string**, which
means *skip validation and route everything*:

> "If you specify an empty string as the `Validation` property value, the message router skips
> validation and routes all messages. When you create a new HL7 routing process in the Management
> Portal, the **Validation** setting is initialized to an empty string."
> — `EHL72 § Settings for HL7 Routing Processes — Validation`

So "I sent it through the router and nothing complained" proves nothing on a default router. Set the
flags deliberately on the router item:

| `Validation` | Meaning |
|---|---|
| *(empty)* — **the default** | No validation. Every message routes. |
| `dm` | DocType present + **segment order** validated. The minimum that catches a wrong `MessageStructure`. |
| `dm-z` (= legacy `1`) | As `dm`, but trailing Z segments not in the schema are tolerated. |
| `dmf` | As `dm` plus full field validation (order, required, size, datatype, code tables). |
| `0` | Legacy spelling of empty. |

Documented validation order: **(1)** the message has a `DocType`, **(2)** segment order, **(3)**
fields — and without the `-x` flag it stops at the first failure. Note the docs' own caveat: *"A
message can pass validation and not conform exactly to the schema definition depending on the
Validation flags specified."*

A failed message goes **only** to the `BadMessageHandler`; if none is configured, the error is
logged and the message is sent nowhere. That is the assertion your test wants.

#### The recipe

TDD a custom schema's *structure* by driving a real message end-to-end through a router whose
`Validation` is set, and assert on the outcome — not by parsing in isolation:

```xml
<Item Name="Router.Adt" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine" Category="MyApp">
  <Setting Target="Host" Name="Validation">dm</Setting>
  <Setting Target="Host" Name="BadMessageHandler">BO.BadMessages</Setting>
  <Setting Target="Host" Name="BusinessRuleName">MyApp.RUL.RoutingAdt</Setting>
</Item>
```

Then assert **both** directions, which is what makes the test meaningful:
1. a message in the order the sender really emits **routes to its target** (proves the schema accepts
   the real-world variance), and
2. a deliberately malformed one **lands on the `BadMessageHandler`** (proves validation is actually
   on — without this, case 1 passes on a router that validates nothing).

Keep the registration tests above as well: they localise the failure to "schema didn't load" rather
than "message didn't route", which are different bugs.

### Canonical worked-example shape

A complete custom-schema artefact set has three parts, all source-controlled on disk:
- **Schema source** — e.g. `PharmacySchema.xml`, an `EnsLib.HL7.Schema` export defining the custom category, its `ORM_O01` message structure and the `ZAL` Z-segment.
- **Import/Export/Remove SqlProcs** — `ImportSchema`, `ExportSchemaXML`, `RemoveSchema` on a bootstrap class, so the schema is reproducible via MCP instead of portal-only.
- **Verification tests** — a `%UnitTest` class that asserts (a) the category exists and its stored
  structure references the custom segment (the `ZAL` assertions above), and (b) a real message in
  the sender's actual segment order routes through a router with `Validation="dm"`, while a
  malformed one reaches the `BadMessageHandler`. (a) alone cannot see a wrong `MessageStructure`.

> **Compiled worked example** of the surrounding wiring — prebuilt `EnsLib.HL7.Service.FileService`,
> `MessageSchemaCategory`, and the HL7-specific router with `Validation="dm"`, which is what
> actually checks segment order: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch02_hl7v2/production-hl7-intake.cls`.

## When custom schema is NOT necessary

If the messages are standard ADT_A01 v2.5 — no Z-segments, no overridden fields — just assign `MessageSchemaCategory="2.5"` and don't author a custom category. Defining `MyApp_2.5` as an empty copy of `2.5` adds maintenance burden with no benefit, and version upgrades won't auto-propagate to your "custom" category.

## Escaping special characters when building HL7 v2 strings by hand

IRIS auto-escapes HL7 v2 special characters (`| ^ ~ \ &`) when **it** generates the message — for example, a system-generated NACK. When you **manually** build an HL7 message (a custom NACK inside a BP catch, a hand-rolled MSH from ObjectScript), you must escape these characters yourself, plus CR and LF:

| Raw | Escaped |
|---|---|
| `|` | `\F\` |
| `^` | `\S\` |
| `~` | `\R\` |
| `\` | `\E\` |
| `&` | `\T\` |
| `<CR>` | `\X0D\` |
| `<LF>` | `\X0A\` |

Without escaping, a `|` inside a free-text field collapses the segment structure and the receiver gets a malformed message.

Helper FunctionSet pattern (`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch02_hl7v2/hl7v2-escape-functionset.cls`) is portable — copy into your namespace, expose `FormataTextPerHL7v2(text)` and the inverse `DesformataTextDesdeHL7v2(text)`, call from BPs and DTLs.

## Pitfalls to surface

- **Edits not exported to SCM** → silent loss-of-work on environment refresh. Always export after every schema edit (covered above; called out twice because it's that common).
- Editing a built-in category instead of creating a custom one → upgrades will overwrite changes.
- Removing a field from a custom schema while DTLs still reference it → DTL compile fails (good — but at runtime if you slip).
- Forgetting that schema categories are **per-namespace** — same name in different namespaces are unrelated.
- **`MessageSchemaCategory="2.5:ADT_A01"` — a DocType where a category belongs.** This entry used to
  say the opposite (that a bare `2.5` loses symbolic resolution and you must "always combine
  `Version:MessageType`"). Measured on 2026.1 via the service's own resolution step,
  `EnsLib.HL7.Schema.ResolveSchemaTypeToDocType()`:

  | value | MSH-9 | result |
  |---|---|---|
  | `2.5` | `ADT_A01` | DocType `2.5:ADT_A01`, `$$$OK` — symbolic paths resolve |
  | `2.5` | `ADT_A08` | DocType `2.5:ADT_A01` — a DocType names the **structure**, not the trigger event |
  | `2.5:ADT_A01` | `ADT_A01` | `<Ens>ErrGeneral: DocType not found for message type 2.5:ADT_A01:ADT_A01` |

  The setting is **concatenated** with MSH-9, so the colon form cannot resolve at all — it does not
  "pin" the structure, it fails. Both spellings look interchangeable because both are `a:b`: a
  **DocType** is `category:structure` and belongs in `sourceDocType` / `DocTypeSet()`; a **schema
  category** is the left half alone and is what `MessageSchemaCategory` takes.
- **`--` inside an XML comment breaks the schema import.** `<!-- accepts what the hospital sends -- unpatched -->`
  fails with `ERROR #6301: SAX XML Parser Error: '--' sequence is illegal in comment`. The schema XML is
  parsed strictly (it is an XML rule, not an IRIS quirk); use an em-dash or a second comment instead.
- **Testing a custom schema by parsing alone** → `ImportFromString` + `DocTypeSet` + `GetValueAt`
  never checks segment order, so a wrong `MessageStructure` ships green. See "Verification part 2".
- **Assuming the HL7 router validates** → its `Validation` setting defaults to empty, which routes
  everything unchecked. Set `dm` on the router you rely on for validation.
- Building HL7 strings by hand without escaping special characters → segment-structure corruption at the receiver.

## See also

- `messages` — the message class that wraps schema-validated content
- `transformations` — DTL DocTypes draw from these schemas
- `business-services` — BS schema-version setting
- `production-lifecycle` — deployment bundle and what travels with it (and what doesn't)
