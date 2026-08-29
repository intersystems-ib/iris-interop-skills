---
name: lookup-tables
description: Lookup tables for code translation in DTL/BPL. Routed from interop. Triggers: lookup table, tabla de búsqueda, code map, Lookup(), Ens.Util.LookupTable, CSV codes, traducción de códigos, normalización.
---

# Lookup Tables

Lookup tables are per-namespace key/value stores consumed by DTL `Lookup()`, BPL conditions, and routing rules. They are the canonical place for code translation (department → facility, source-system code → standard code, gender flag → display value) and for validation lists that change without a code release.

This skill covers when to use a table, the canonical authoring + loading patterns, refresh strategies for tables sourced from an external master data system, and the `Lookup()` default-parameter pitfall.

## When to use this skill

The user wants to map source codes to target codes — e.g. internal department code → external facility code, source-system gender code → standard gender code, lab analyte code → LOINC.

## What this skill currently knows

- Lookup tables are **per-namespace** key/value stores (`Ens.Util.LookupTable`).
- Created via **Management Portal → Interoperability → Build → Data Lookup Tables**.
- Loaded from **CSV** (`Filename` column → `Key`, `Description` column → `Value`) or **manually**.
- Consumed in DTL via `Lookup("TableName", source.field, default)` — third parameter is what to return on miss.
- Also accessible from ObjectScript via `##class(Ens.Util.LookupTable).GetValue("TableName", key, .value)`.
- Lookup tables **export with the production** — they're part of the deploy bundle.

## When to use a lookup table vs. an inline switch / if

- **Many entries** (>5–10 mappings) → lookup table.
- **Mappings change without code release** (business owner edits via portal) → lookup table.
- **2–3 mappings, hardcoded business rules** → inline switch in DTL is fine.
- **Mappings come from an external master data source** → consider periodic refresh from that source (custom job) rather than manual maintenance.

## Cookbook — case-and-tilde-insensitive validation lookup

The first validated pattern: replace a hardcoded validation list with a lookup table, normalizing the key so users can type with or without accents and in any case.

**Scenario**: a CSV carries a `Dieta` field. Valid values: `Basal`, `Diabética`, `Hipocalórica`, `Astringente`, `Sin Sal`, `Triturada`, `Macrobiótica`, `Líquida`. Users in DEV typed `Diabetica` (no tilde), so the DTL's hardcoded validation list ended up duplicating each entry (with and without tildes) and still missed `DIABETICA` (uppercase). Antipattern — replace with a lookup.

### 1. Author the table

Create `DietasValidas` via **Management Portal → Interoperability → Build → Data Lookup Tables**. Or load from CSV:

```csv
Key,Value
basal,Basal
diabetica,Diabética
hipocalorica,Hipocalórica
astringente,Astringente
sinsal,Sin Sal
triturada,Triturada
macrobiotica,Macrobiótica
liquida,Líquida
```

The **Key column is normalized** (lowercase, no accents, no whitespace); the **Value column is the canonical display form**. Storing the canonical form lets you both validate (key match) and rewrite (use the value) in one lookup.

### 2. Centralize the normalization

Add a helper to your project's `FunctionSet` subclass (see `transformations` for the pattern):

```objectscript
ClassMethod NormalizeKey(value As %String) As %String [ Final ]
{
    Set tAccents = $CHAR(225,233,237,243,250,241,224,232,236,242,249,252)  // áéíóúñàèìòùü
    Set tPlain   = "aeiounaeiouu"
    // $ZCONVERT(..,"L"): lowercase
    // $ZSTRIP "*WC": strip whitespace and control characters
    // $TRANSLATE: fold accents. Keep the policy here, not at call sites.
    Quit $TRANSLATE($ZSTRIP($ZCONVERT(value, "L"), "*WC"), tAccents, tPlain)
}
```

| input | result |
|---|---|
| `Diabética` | `diabetica` |
| `"  DIABÉTICA  "` | `diabetica` |
| `Diabetica` | `diabetica` |

**Two `$ZSTRIP` traps, both measured on IRIS 2026.1 (#114).** They are worth stating because the
obvious-looking mask is the broken one:

- **`-` is not a `$ZSTRIP` action character.** Any mask containing it — `"*-CWE"`, `"*-CW"`, `"*-E"`
  — raises `<FUNCTION>`, so a DTL calling the helper fails on every message. (`*'ANU`, the
  apostrophe-negation form, throws here too.)
- **`E` does not mean "ASCII punctuation".** It strips *everything*: `$ZSTRIP(x,"*CWE")` and
  `$ZSTRIP(x,"*E")` both return the empty string for every input. That failure is silent — the
  helper returns, every lookup misses, and with the DTL below's `""` default every message throws
  `InvalidDieta` instead. Prefer `"*WC"` and fold accents explicitly.

Do not reach for the `$ZCONVERT(..., "O", "UTF8")` / `$ZCONVERT(..., "I", "Latin1")` round trip to
strip accents. Measured leg by leg on 2026.1, it fails **twice, in two different ways**:

| step | result |
|---|---|
| `$ZCONVERT("Diab"_$CHAR(233)_"tica", "O", "UTF8")` | `DiabÃ©tica` — len 10, codes 195,169. **No error.** |
| `$ZCONVERT(<that>, "I", "Latin1")` | **`<ILLEGAL VALUE>`** |
| the composite, as usually written | **`<ILLEGAL VALUE>`** |

The throw is the easy half — you find out. The first leg is the dangerous one: on an
already-internal string it silently re-reads the UTF-8 bytes as single characters, and if you ever
use it alone the double-encoded value propagates straight into the lookup key. `$TRANSLATE` above is
self-contained and testable.

### 3. Use from DTL

```xml
<assign property='target.TipoDieta'
        value='..Lookup("DietasValidas", ##class(MyApp.Util.FunctionSet).NormalizeKey(source.Dieta), "")' />
<if condition='target.TipoDieta=""'>
  <true>
    <code>
      <![CDATA[
      Throw ##class(%Exception.General).%New("InvalidDieta", 5002, , "Dieta desconocida '"_source.Dieta_"'")
      ]]>
    </code>
  </true>
</if>
```

Two effects in one go: invalid dietas raise (empty lookup → empty value → throw), and valid-but-mis-cased dietas are rewritten to the canonical form for the destination.

### 4. Test the lookup independently

The `NormalizeKey` helper is a plain class method — test with `%UnitTest.TestProduction` (see `tdd` — even pure helpers; the TestProduction superclass costs nothing extra and standardizes the runner). The lookup itself (the table content) is exported with the production; add an integration assert that "every entry in the legacy hardcoded list resolves to a non-empty value via `NormalizeKey + Lookup`" so future edits to the table can't silently drop entries.

## Cookbook — loading lookups via MCP (no portal access)

**Reach for the typed tools first.** Two exist for exactly this job, and neither needs a class:

| tool | actions | use it for |
|---|---|---|
| `iris_lookup_manage` | `get`, `set`, `delete`, `list_keys`, `list_tables` | one row at a time, and discovering what tables exist |
| `iris_lookup_transfer` | `export`, `import` | a whole table as IRIS lookup XML |

```xml
<lookupTable>
  <entry table="GeneroSOAP" key="M">1</entry>
  <entry table="GeneroSOAP" key="F">2</entry>
</lookupTable>
```

> **`import` REPLACES the table — it does not merge.** `iris_lookup_transfer` requires `table`, and
> passes it to `Ens.Util.LookupTable.%Import` as `pForceTableName`. IRIS's own documentation for
> that parameter: *"If `pForceTableName` is specified then the particular Lookup Table will be
> **replaced if it exists** by the entries being imported."* `%Import` does have a merge mode — it
> is what you get by omitting that parameter — but the tool makes `table` mandatory, so **merge is
> not reachable through it.** Import a partial table and you delete every row you left out.

### When you need SQL instead

Row-by-row `iris_lookup_manage(action="set")` is fine for a handful of entries; for a few hundred,
direct SQL into `Ens_Util.LookupTable` from a `[SqlProc]` is still the most compact option:

```objectscript
ClassMethod ImportLookups() As %String [ SqlProc ]
{
    &sql(DELETE FROM Ens_Util.LookupTable WHERE TableName IN ('GeneroSOAP','PlantaSOAP'))
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES ('GeneroSOAP','M','1'))
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES ('GeneroSOAP','F','2'))
    &sql(INSERT INTO Ens_Util.LookupTable (TableName, KeyName, DataValue) VALUES ('PlantaSOAP','1','P1'))
    // ... more rows ...
    Quit "OK"
}
```

Invoke from MCP: `SELECT MyApp_Bootstrap_ImportLookups()`. Idempotent because of the prior `DELETE`. Place the SqlProc in your project's `Bootstrap` class so it lives next to other workshop-setup helpers and ships in the same `.cls` file as the rest of the setup.

**Why a SqlProc rather than a loose `iris_execute` with `&sql`** — and the reason is not the one
this skill used to give (#119). The inserts **do** persist; what breaks is the error check. The MCP
rewrites `&sql(...)` into a `%SQL.Statement` call and binds its status to a generated local
(`sqlSQLCODE1`, `sqlSQLCODE2`, …), never to the bare `SQLCODE` the idiom expects. So:

```objectscript
&sql(INSERT INTO Ens_Util.LookupTable ...)
If SQLCODE<0 { ... }        // <UNDEFINED> — and the INSERT already succeeded
```

fails *after* the write went through, which reads exactly like a failed insert and invites you to
retry or abandon a load that actually worked. Tracked as intersystems-ib/iris-interop-dev#145.
Inside a compiled `[SqlProc]` the macro is handled by the class compiler, `SQLCODE` is set the
normal way, and the idiom behaves.

Verify with: `SELECT TableName, COUNT(*) FROM Ens_Util.LookupTable WHERE TableName LIKE 'YourPrefix%' GROUP BY TableName`.

### Verification — `%UnitTest` against the table content

Treat the table as data that ships with the production. A short test class asserts the rows you committed are present after `ImportLookups()` runs. The runner uses the `Ens.Util.FunctionSet.Lookup` semantics so the assert reflects what the DTL would see (an unknown key returns `""`):

```objectscript
Class MyApp.Tests.Lookup.GeneroPlanta Extends %UnitTest.TestProduction
{
Parameter PRODUCTION = "MyApp.Production";
Method TestControl() As %Status { Quit $$$OK }

ClassMethod Lookup(pTable As %String, pKey As %String) As %String [ Private ]
{
    Quit ##class(Ens.Util.FunctionSet).Lookup(pTable, pKey, "")
}

Method TestGeneroMtoOne()  { Do $$$AssertEquals(..Lookup("GeneroSOAP","M"), "1") }
Method TestGeneroFtoTwo()  { Do $$$AssertEquals(..Lookup("GeneroSOAP","F"), "2") }
Method TestUnknownKeyEmpty() {
    Do $$$AssertEquals(..Lookup("GeneroSOAP","X"), "", "Unknown key → empty")
}
}
```

Pin every row the DTL relies on — that way a future edit that drops or renames a key breaks the test immediately instead of silently emitting wrong target codes.

## Canonical worked-example shapes

Three typical lookup shapes — all MCP-loaded via a `Bootstrap.ImportLookups()` SqlProc and consumed from DTLs in the same production:

- **Code mapping** (`GeneroSOAP`) — gender code translation, e.g. `M→1`, `F→2`. The smallest useful shape: a flat 1:1 value map driven from a `DTLLookup`.
- **Code-to-structured-value** (`PlantaSOAP`) — floor-number to building code, e.g. `1→P1`, `2→P2`, …, `7→Edificio2-P7`. Same shape, but the target value carries structure the DTL parses. Keep a **CSV source** (`genero_csv_to_soap.csv`, `planta_csv_to_soap.csv`) versioned alongside the SqlProc so a future portal re-import has a canonical source.
- **Normalization map** (`ClinicNames`) — collapse vendor-specific names to canonical codes, e.g. `ABCCLINIC→ABC`, `XYZCLINIC→XYZ`. Consumed from an `ADT_A06→ADT_A02` DTL to rewrite the receiving-facility code.

Pin every row a DTL relies on with a `%UnitTest` (see the assertion pattern above) and use the closest shape as a starting template when adding a new lookup.

## Naming conventions

Apply the canonical naming convention (xref `interop` §"Naming convention") to lookup tables. The table **name** should describe the mapping clearly enough that a reader of a DTL knows what's being translated without opening the table.

| Pattern | Example | When |
|---|---|---|
| `<SourceCode>To<TargetCode>` | `IcoDepartmentToHl7Facility` | One-to-one code translation between two systems. |
| `<Domain>Valid` | `DietasValid` | Validation list (with normalization applied on the key). |
| `<Domain><Use>` | `ICD10ShortDescription` | Reference data lookups (returns descriptive text from a code). |

Prefix is optional but consistent. Avoid generic names (`Codes`, `Translation`, `Lookup`) — they hide what's being mapped and accumulate unrelated entries.

## Refresh patterns for externally-sourced lookups

When a table's content lives in an authoritative external system (an HR table, a master patient index, a SAP code table), three refresh strategies — pick by latency requirement:

| Strategy | How | When |
|---|---|---|
| **On-demand re-import** | Operator runs the `Import` SqlProc when notified of external change. | Updates are infrequent (monthly+) and a documented manual step is acceptable. |
| **Scheduled refresh job** | A scheduled BS reads from the external system (SQL adapter, REST, file) and rewrites the table inside one transaction. | Updates are predictable (daily / weekly) and a few hours' lag is fine. |
| **Trigger-based refresh** | An external event (file drop, webhook, message) triggers a BS that updates the affected entries. | Near-real-time updates required; the external system can send a signal. |

In all three: rewrite **atomically** — `DELETE WHERE TableName='X'` + bulk `INSERT` inside one transaction, never row-by-row in place. Mid-flight DTL `Lookup()` calls then see either fully-old or fully-new content, never a partial state.

For SQL-sourced refreshes, use `ExecuteQueryParmArray` with explicit SQL types — see `business-operations` for the parameter-array pattern that avoids the long-class-name `<SUBSCRIPT>` failure mode.

## `Lookup()` default parameter — silent miss vs explicit miss

`Lookup("TableName", key)` returns empty string on miss. `Lookup("TableName", key, "DEFAULT")` returns `"DEFAULT"` on miss. Pick deliberately:

- **Default = `""`** (empty) is correct only if downstream logic treats empty as "no mapping" and handles it explicitly.
- **Default = `"<UNKNOWN>"`** (or any sentinel) makes misses visible in downstream messages and easier to grep for.
- **Default = a fallback business value** (e.g. `Lookup("Department", code, "GENERIC")`) makes the DTL tolerant of new source codes — but hides the issue until someone reports wrong routing.

Pair the lookup with an explicit miss check when validation matters:

```xml
<assign property='target.Code'
        value='..Lookup("DepartmentMap", source.code, "")' />
<if condition='target.Code=""'>
  <true>
    <code>
      <![CDATA[
      Throw ##class(%Exception.General).%New("InvalidDept", 5003, , "Unknown department '"_source.code_"'")
      ]]>
    </code>
  </true>
</if>
```

This raises on miss instead of silently propagating an empty value.

## What this skill does NOT yet do

- Generate seed CSV from a description.
- Auto-detect when an inline switch would be cleaner than a table.
- Diff two table versions to identify breaking changes for downstream DTLs.

## Pitfalls to surface

- `Lookup()` without the third parameter → silent empty string on miss, hard to debug.
- One giant lookup table for unrelated mappings → break into purpose-specific tables.
- Loading lookup tables manually in DEV but forgetting to ship the CSV with the deploy bundle → empty tables in TEST/PROD.

## See also

- `transformations` — primary consumer via `Lookup()` in DTL
- `bpl` — also consumes lookups in routing rules and BPL conditions
- `production-lifecycle` — lookup tables are part of the production export
- `business-operations` — `ExecuteQueryParmArray` pattern for SQL-sourced refresh jobs
- `interop` — §"Naming convention"
