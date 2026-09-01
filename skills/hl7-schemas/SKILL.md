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
   <Setting Target="Host" Name="MessageSchemaCategory">MyApp_2.5:ADT_A01</Setting>
   ```

8. **In the DTL**: declare `sourceDocType='MyApp_2.5:ADT_A01'` on `<transform>`. Symbolic field names now resolve for both standard fields (PID, PV1) and the custom ones (ZPI).

## Cookbook — MCP-friendly import via XML + SqlProc

When the Portal UI isn't available (working entirely via MCP, headless CI, scripted environment refresh), the canonical path is:

1. Author the schema as a **standalone XML file** (root `<Category>`, see format below).
2. Call `##class(EnsLib.HL7.SchemaXML).Import(file, .pCategoryImported)` from a SqlProc wrapper.
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

### Verification (paste into a `%UnitTest.TestCase`)

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

### Canonical worked-example shape

A complete custom-schema artefact set has three parts, all source-controlled on disk:
- **Schema source** — e.g. `PharmacySchema.xml`, an `EnsLib.HL7.Schema` export defining the custom category, its `ORM_O01` message structure and the `ZAL` Z-segment.
- **Import/Export/Remove SqlProcs** — `ImportSchema`, `ExportSchemaXML`, `RemoveSchema` on a bootstrap class, so the schema is reproducible via MCP instead of portal-only.
- **Verification tests** — a `%UnitTest` class that asserts the category exists and that its stored structure references the custom segment (see the `ZAL` assertion above).

## When custom schema is NOT necessary

If the messages are standard ADT_A01 v2.5 — no Z-segments, no overridden fields — just assign `MessageSchemaCategory="2.5:ADT_A01"` and don't author a custom category. Defining `MyApp_2.5` as an empty copy of `2.5` adds maintenance burden with no benefit, and version upgrades won't auto-propagate to your "custom" category.

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
- **`MessageSchemaCategory="2.5"` without `:MessageType`** — DTLs lose symbolic field-name resolution and fall back to numeric paths (`PID:3.1` instead of `PID:PatientIdentifierList(1).ID`). Always combine: `Version:MessageType` (e.g. `2.5:ADT_A01`).
- Building HL7 strings by hand without escaping special characters → segment-structure corruption at the receiver.

## See also

- `messages` — the message class that wraps schema-validated content
- `transformations` — DTL DocTypes draw from these schemas
- `business-services` — BS schema-version setting
- `production-lifecycle` — deployment bundle and what travels with it (and what doesn't)
