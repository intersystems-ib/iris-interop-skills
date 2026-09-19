# RecordMap — file intake

Everything specific to `EnsLib.RecordMap.Service.FileService` and the `XData RecordMap` block: the schema the validator accepts, fixed-width, programmatic construction, generating the `.Record` class, testing the parser, and FTP/FTPS. Read this only when the intake is a RecordMap.

## Contents

- Record Mapper — file gotchas
- Authoring the `XData RecordMap` block — the exact schema the validator accepts
- Fixed-width instead of delimited
- Building the RecordMap programmatically — `recordTerminator` must be hex-escaped
- Generating the Record Map (the `.Record` class + GetObject) — **a plain compile does NOT do this**
- Testing the parser — feed `GetObject` bytes in the map's encoding
- FTP / FTPS instead of a local file

## Record Mapper — file gotchas

When using `EnsLib.RecordMap.Service.FileService` with a generated Record Map class:

- **Line terminators are compiled in**: the Record Map's `recordTerminator` is **baked into the generated `.Record` class** at compile time. Default is CRLF (`&#xD;&#xA;`). CSVs produced on Unix or by many ETL pipelines are LF-only (`&#xA;` = `$char(10)`). Set the terminator to match the **actual** input file — and **recompile the Record Map** after changing it. The runtime reads the compiled value, not the editor state.
- **After ANY Record Map edit, recompile**: Studio F7, Management Portal "Compile", or `iris_compile` via MCP. A stale `.Record` class silently uses the previous definition; symptom is "edit had no effect".
- **Charset**: set the adapter's `Charset` setting to `UTF-8` explicitly when headers/values contain non-ASCII characters (`ñ`, tildes). Platform-default charset may differ and produces header names that don't match field names ("Acompañante" header read as "AcompaÃ±ante" → mapping fails).
- **Quoted fields with embedded delimiters**: configure the Record Map's `Quote Character` (typically `"`) so the parser respects RFC-4180 quoting. `"García, hijo"` is one field with a literal comma; a `$PIECE`-by-comma hand-rolled parser corrupts it.
- **Use the pre-built `FileService` class directly** — declare `ClassName="EnsLib.RecordMap.Service.FileService"` on the production item and set the `RecordMap`, `FilePath`, `Charset`, and `HeaderCount` settings (the last three on target `Adapter`; `RecordMap`, `HeaderCount`, `TargetConfigNames` on target `Host`). Don't subclass unless you genuinely need to override behaviour. See the canonical pattern above for the subclass case (custom BS that wraps Record Mapper output into a project-specific message).

**The BS and BO are already written — the only class you author is the RecordMap itself.** Writing
an `Ens.BusinessService` subclass for a RecordMap flow is always wrong: the file adapter, the poll
loop and the per-record dispatch are all in the prebuilt service.

| Role | Prebuilt IRIS class | Configure |
|---|---|---|
| BS, file inbound | `EnsLib.RecordMap.Service.FileService` | `RecordMap`, `TargetConfigNames`, `HeaderCount` (Host); `FilePath`, `Charset` (Adapter) |
| BS, FTP inbound | `EnsLib.RecordMap.Service.FTPService` | same, plus the FTP adapter settings |
| BS, batch file | `EnsLib.RecordMap.Service.BatchFileService` | same |
| BO, batch file out | `EnsLib.RecordMap.Operation.BatchFileOperation` | `RecordMap`, plus the file adapter settings |

The one class you create is the `EnsLib.RecordMap.RecordMap` subclass — authored as the XData block
below, or built programmatically, then put through `GenerateObject` (both covered further down).
Subclass the prebuilt service only to wrap the mapped record into a project-specific message, which
is what the canonical pattern at the top of this skill shows — and then `##super()` in `OnInit()` is
mandatory.

> **Compiled worked examples** (gated by `validate_examples --compile`): the RecordMap
> definition `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch01_production/recordmap-censo.cls`, wired into a complete production at
> `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch01_production/production-censo-intake.cls`. For a genuine bare-adapter BS:
> `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/bs-file-bare-adapter.cls`. For REST inbound:
> `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/bs-rest-inbound.cls`.

### Authoring the `XData RecordMap` block — the exact schema the validator accepts

This is the **only** part you write by hand. Everything else in the class — `GetObject`,
`PutObject`, `GetRecord`, `PutRecord`, `GetGeneratedClasses`, `getType`, `Parameter OBJECTNAME`
and the whole `.Record` class — is written by the generator (next section). Write the skeleton
plus the XData, generate, then `iris_doc get` the result back.

A delimited CSV (comma-separated, UTF-8, LF line endings, `"` quoting), verbatim from a working
production:

```objectscript
Class MyApp.RecordMap.Censo Extends EnsLib.RecordMap.RecordMap [ Not ProcedureBlock ]
{

XData RecordMap [ XMLNamespace = "http://www.intersystems.com/Ensemble/RecordMap" ]
{
<Record xmlns="http://www.intersystems.com/Ensemble/RecordMap"
        name="MyApp.RecordMap.Censo"
        type="delimited"
        char_encoding="UTF-8"
        recordTerminator="&#xA;"
        targetClassname="MyApp.RecordMap.Censo.Record"
        escaping="quote"
        escapeSequence="&quot;">
  <Separators>
    <Separator>,</Separator>
  </Separators>
  <annotation>Censo de pacientes leído desde CSV.</annotation>
  <Field name="ID"     datatype="%String" />
  <Field name="Nombre" datatype="%String" />
  <Field name="Planta" datatype="%String" />
</Record>
}

}
```

**`fieldSeparator` is the trap that costs the most attempts.** For `type="delimited"` the
attribute must be **absent**. Setting it to the obvious `fieldSeparator=","` fails with:

```
ERROR <EnsRecordMap>ErrInvalidRecordProp: Invalid value for property 'fieldSeparator' in Record of type delimited
```

which reads as "your value is malformed" but actually means "this property must not be set for
this type at all". The IRIS validator is explicit — anything that is not `fixedwidth` must leave
it empty:

```objectscript
If '(..type = "fixedwidth") {
    If ..fieldSeparator '= "" Quit $$$ERROR($$$EnsRecordMapErrInvalidRecordProp, ..type, "fieldSeparator")
```

The separator for a delimited record goes in `<Separators>`, as one `<Separator>` element per
nesting level (one element for a flat CSV).

| What gets written | What the schema wants |
|---|---|
| `fieldSeparator=","` / `separator=","` attribute | **omit it**; use `<Separators><Separator>,</Separator></Separators>` |
| `<Field type="%String"/>` | `datatype="%String"` |
| `<Field>` outside `<Record>` | every `<Field>` nested inside `<Record>`; a `<Record>` with none fails `#5661 Collection property 'EnsLib.RecordMap.Model.Record::Contents' is required` |
| `<RecordMap>` as the root element | the root is `<Record>` |
| `recordTerminator="\n"` | an XML entity: `&#xA;` (or `&#10;`) for LF, `&#xD;&#xA;` for CRLF |
| `[ DependsOn = MyApp.RecordMap.Censo.Record ]` on the first write | leave it off until the `.Record` exists — otherwise `#5373 Class '…Record', used by '…:dependson', does not exist` and the class is skipped. The generator adds it. |

**`targetClassname` is the class the generator will create**, and it is free — it does not have to
be `<RecordMap class>.Record`. Both conventions are in production use: a `.Record` suffix on the
map's own name (`MyApp.RecordMap.Censo` → `MyApp.RecordMap.Censo.Record`), or a sibling package
(`MyApp.RecordMap.Invoice` → `MyApp.Record.Invoice`). `name` is the record's identifier; it commonly
mirrors either the map class or `targetClassname`.

**On `xmlns`**: the `XMLNamespace` on the `XData` header is what matters. Repeating it as
`xmlns=` on `<Record>` is optional — hand-written maps routinely omit it and generate fine, and
the generator adds it when it rewrites the block, which is why classes read back from IRIS show
it. Both `http://www.intersystems.com/recordmap` and
`http://www.intersystems.com/Ensemble/RecordMap` are accepted.

### Fixed-width instead of delimited

`type="fixedWidth"` — **camelCase**. No `<Separators>`; every `<Field>` carries `position` (1-based,
absolute within the record) and `width`. A production-shaped invoice record — absolute offsets, a
600-char line, a trailing `FILLER` — with identifiers genericised:

```objectscript
Class MyApp.RecordMap.Invoice Extends EnsLib.RecordMap.RecordMap
{

XData RecordMap [ XMLNamespace = "http://www.intersystems.com/recordmap" ]
{
<Record name="MyApp.Record.Invoice" type="fixedWidth" recordTerminator="&#10;" targetClassname="MyApp.Record.Invoice">
  <Field name="TipoReg"       datatype="%String" position="1"   width="3"  />
  <Field name="NumFactura"    datatype="%String" position="4"   width="15" />
  <Field name="NumAlbaran"    datatype="%String" position="19"  width="15" />
  <Field name="FechaFactura"  datatype="%String" position="34"  width="8"  />
  <Field name="NumLinea"      datatype="%String" position="594" width="7"  />
</Record>
}

}
```

Positions are absolute and must be contiguous with the widths — field N starts at
`position(N-1) + width(N-1)`. Gaps you don't care about still need a field; the common idiom is a
trailing `FILLER` that pads the record to its declared length (600 chars here).

**Multi-record-type files** (a header type, N detail types, a trailer — discriminated by a type
code at a fixed offset) need **one RecordMap class per record type**, not one map with variants.
Before reaching for `EnsLib.RecordMap.Service.ComplexBatchFileService`, know that it — like
`BatchFileService` — emits **one message per whole file**, not one per logical sub-batch. If you
need a message per invoice/episode/block, no native ARM service does that: write a custom BS that
reads the lines and assembles the sub-batch itself.

### Building the RecordMap programmatically — `recordTerminator` must be hex-escaped

The XData block above is one way to author the map. The other is to build an
`EnsLib.RecordMap.Model.Record` in code and call `SaveToClass()`. That route has one trap that is
silent, produces `$$$OK`, and corrupts data:

```objectscript
Set rec.recordTerminator = "\x0a"      // LF-terminated files
Set rec.recordTerminator = "\x0d\x0a"  // CRLF-terminated files
```

**Always the `\xHH` hex-escape form — never a literal byte, never empty.**
`EnsLib.RecordMap.Generator.getLogicalChars()` turns the stored value into the ObjectScript
expression `chunkRecord` uses as the record boundary, and the literal forms do not survive the
`SaveToClass` → XML round-trip:

| What you set | What is stored | What `chunkRecord` splits on |
|---|---|---|
| left empty | `$char(32)` — the portal's default | **every space** |
| literal `\r\n` in the XML | the XML parser normalises CRLF → LF | `$char(10)` only |
| `$Char(13,10)` assigned directly | lost in the round-trip | not what you meant |
| `"\x0d\x0a"` | `"\x0d\x0a"` | CR+LF, as intended |

The empty case is the one that costs a morning: the boundary becomes a space, so
`Alergias = "Frutos secos|Marisco"` is silently truncated at `Frutos`. Status is `$$$OK`, there is
no error, and the row count still looks plausible.

### Generating the Record Map (the `.Record` class + GetObject) — **a plain compile does NOT do this**

The Record Map's `<Map>.Record` class **and** the `GetObject`/`PutObject`/`GetRecord`/`PutRecord` method bodies are written by the **wizard / generator into the source**, exactly like a generated SOAP client. A normal `iris_compile` (or `iris_doc put` with `compile=true`) of a Record Map class that contains only the XData block compiles green but produces **no working `GetObject`** — at runtime the FileService dies with `<METHOD DOES NOT EXIST>GetObject ... ^EnsLib.RecordMap.Service.Base.1`.

When the Portal wizard is not available (MCP / headless), generate via the official API **wrapped in
a `[SqlProc]`** — `iris_execute`'s objectgenerator mode silently no-ops class-generating calls
(verified on IRIS 2026.1). This is one instance of the general pattern; the rule, the skeleton and
the other APIs that need it are in `interop` §"Headless bootstrap — running the calls `iris_execute` cannot":

```objectscript
ClassMethod GenerateRecordMap(pRM As %String) As %String [ SqlProc ]
{
    Set sc = ##class(EnsLib.RecordMap.Generator).GenerateObject(pRM)
    Quit $Select($$$ISOK(sc): "ok", 1: "FAIL:"_$system.Status.GetErrorText(sc))
}
```

Invoke with `SELECT Pkg.Bootstrap_GenerateRecordMap('Pkg.RecordMap.X')` — schema `Pkg`, function
`Bootstrap_GenerateRecordMap`. (Careful with that name: the WHOLE package goes to underscores —
`Pkg.UTL.Bootstrap` is schema `Pkg_UTL`, never `Pkg.UTL`. See `interop` §"Calling a `[SqlProc]`".)

**When you build the map in code, put `SaveToClass` and `GenerateObject` in the SAME `[SqlProc]`.**
Splitting them so that only `GenerateObject` is wrapped defeats the purpose: `iris_execute` reports
`"GenerateObject OK target=…"`, the class compiles, and `GetObject` is still never written —
`<METHOD DOES NOT EXIST>GetObject` at the first record.

```objectscript
ClassMethod BuildCensoMap() As %String [ SqlProc ]
{
    Do $System.OBJ.Delete("MyApp.RM.CensoCsv", "-d")
    Do $System.OBJ.Delete("MyApp.RM.CensoCsvMap", "-d")
    Set rec = ##class(EnsLib.RecordMap.Model.Record).%New()
    // ... name, targetClassname, type, fieldSeparator, Fields ...
    Set rec.recordTerminator = "\x0a"                      // hex-escape, never a literal byte
    Set sc = rec.SaveToClass()
    Quit:$$$ISERR(sc) "SaveToClass: "_$system.Status.GetErrorText(sc)
    Set sc = ##class(EnsLib.RecordMap.Generator).GenerateObject("MyApp.RM.CensoCsvMap", .tTarget)
    Quit:$$$ISERR(sc) "GenerateObject: "_$system.Status.GetErrorText(sc)
    Quit "OK target="_tTarget
}
```

`GenerateObject`'s later arguments (flags, qualifiers, the generated-class list) are version
dependent — resolve them with `docs_introspect(class_name="EnsLib.RecordMap.Generator")` against the
running instance rather than copying a signature. Notes:
- `GenerateObject` errors `#5768 Class already exists` if the `.Record` already exists — delete it first, then regenerate.
- **`GetObject` lives on the RecordMap class, not on `.Record`.** Verifying with
  `##class(Pkg.RecordMap.X.Record).GetObject(...)` raises the same `<METHOD DOES NOT EXIST>` as
  a missing generation, and sends you chasing the wrong cause. Check
  `##class(Pkg.RecordMap.X).GetObject(...)`, or assert on the existence of the `.Record` class.
- The generated `.Record` extends `(%Persistent, %XML.Adaptor, Ens.Request, EnsLib.RecordMap.Base)` with `Parameter INCLUDETOPFIELDS = 1`. It IS the source class for the routing rule and DTL.
- **Disk is the source of truth**: after generating, `iris_doc get` both the Record Map class (now carrying the method bodies) and the `.Record`, and write them to `src/` — the generated code must be committed, not just live in IRIS. Regenerate whenever you edit the XData.

### Testing the parser — feed `GetObject` bytes in the map's encoding

Instantiating the generated `.Record` and setting properties tests nothing about parsing. To
exercise the real parser, push a line through `GetObject` **on the RecordMap class**. Two ways, and
the encoding is the part that bites:

```objectscript
/// Simplest and most faithful: hand it a filename. GetObject opens the file ITSELF,
/// with the map's encoding -- exactly what the File service does at runtime.
Method TestParseFromFile()
{
    Set line = "3003,"_$Char(193)_"ngel,"_""""_"Garcia, hijo"_""""   ; Ángel + a quoted comma
    Set fs = ##class(%Stream.FileCharacter).%New()
    Set fs.TranslateTable = "UTF8", fs.Filename = "/tmp/censo-test.csv"
    Do fs.WriteLine(line)
    Do $$$AssertStatusOK(fs.%Save())

    Do $$$AssertStatusOK(##class(Pkg.RecordMap.Censo).GetObject("/tmp/censo-test.csv", .obj))
    Do $$$AssertEquals(obj.Nombre, $Char(193)_"ngel", "accent survives")
    Do $$$AssertEquals(obj.Planta, "Garcia, hijo",    "quoted comma stays one field")
}

/// In-memory: the stream's encoding must MATCH the map's, because Write() encodes at
/// write time. %IO.StringStream defaults to "Native", which is the whole trap.
Method TestParseFromStream()
{
    Set st = ##class(%IO.StringStream).%New()
    Set st.CharEncoding = "UTF-8"          ; <- the one line that matters; map says UTF-8
    Do st.Write(line_$Char(10))
    Do st.Rewind()
    Do $$$AssertStatusOK(##class(Pkg.RecordMap.Censo).GetObject(st, .obj))
    Do $$$AssertEquals(obj.Nombre, $Char(193)_"ngel")
}
```

**Why the accent turns into `?` if you skip that line.** The generated `GetObject` sets the encoding
from the map itself — it is in the generated source:

```objectscript
Do pStream.Open(tFilename,,pTimeout,"UTF-8", .tStatus)   ; a FILENAME is opened as UTF-8
...
Set pStream.CharEncoding = "UTF-8"                       ; and any stream is forced to the map's encoding
```

So the parser never needed help. What goes wrong is upstream of it: `%IO.StringStream` defaults to
`CharEncoding = "Native"`, so `Write()` encodes your wide characters as **Native** bytes, and
`GetObject` then reads those bytes back as **UTF-8**. Mismatch, and `Á` arrives as `?` (`$c(63)`)
with no error anywhere — the status is `$$$OK` and only the assert fails. Measured on IRIS for
Health 2026.1:

| Test input | `obj.Nombre` |
|---|---|
| wide chars → default (`Native`) stream | `?gel` — `$c(63)` |
| wide chars → stream with `CharEncoding="UTF-8"` | `Ángel` ✅ |
| `$ZCVT(line,"O","UTF8")` → default stream | `Ángel` ✅ |
| plain wide chars → real UTF-8 **file** → `GetObject(filename)` | `Ángel` ✅ |
| `$ZCVT(...)` → real UTF-8 **file** | `Ãngel` — `$c(195)`, **double-encoded** |

**Do not reach for `$ZCVT` as the general fix.** It works only for the one case where the stream is
left `Native` — it is hand-encoding to compensate for a stream you mis-declared — and on a correctly
encoded file it double-encodes and corrupts, as the last row shows. Declare the encoding once
instead; it applies to every field and cannot be forgotten halfway down a line.

**Build accented literals with `$Char(...)`** (`Á`=193, `á`=225, `í`=237, `ñ`=241, `ó`=243) rather
than pasting accented characters into the `.cls` — the class source encoding in transit through
`iris_doc put` is not something to rely on, and a mangled literal in the *test* looks exactly like a
parser bug.

### FTP / FTPS instead of a local file

The spec often calls for the CSV to arrive over **FTPS**, while you develop/test against a **local folder**. The two use **different service classes** — you cannot just change a setting:

- `EnsLib.RecordMap.Service.FileService` — local/mounted folder (adapter `EnsLib.File.InboundAdapter`).
- `EnsLib.RecordMap.Service.FTPService` — FTP/FTPS (adapter `EnsLib.FTP.InboundAdapter`); for TLS set the adapter `SSLConfig` to an SSL/TLS configuration name plus `FTPServer`/`FTPPort`/`Credentials`.

Both share the **same `RecordMap`** and should point at the **same Router**. Pattern when the spec mandates FTPS but no FTPS server exists yet: register **two BS items at the same Router** — the `FTPService` one (`Enabled="false"`, faithful to the spec) and a `FileService` one (`Enabled="true"`, for local drop-a-file verification). This keeps the solution spec-compliant and testable without inventing infrastructure.

#### FTPS against a real server — `MLSD=1`, and `FileSpec` becomes a regex

The FTP adapter's directory listing is **`LIST <FileSpec>`** — e.g. `LIST *.csv` — and it expects
the *server* to expand the glob. `vsftpd`, IIS and `curl` do; `pyftpdlib` and others treat the
pattern as a literal path and answer `550 Invalid argument`. The symptom is misleading: what you
actually see is an **`Unexpected SSL EOF`** on the data channel, which sends you diagnosing TLS.
TLS is fine — the transfer never started, because the listing failed.

The working configuration against a non-globbing server:

1. Set **`MLSD=1`** on the adapter. IRIS then lists the directory with `MLSD` (no pattern) and
   filters client-side.
2. **With `MLSD=1`, `FileSpec` is evaluated as a REGULAR EXPRESSION, not a glob.** Use
   `.*\.csv`; keeping `*.csv` fails with `#8311 Syntax error in regexp pattern`. This reversal is
   the part nobody guesses.
3. IRIS still issues `LIST <pattern>` for `getSize`, so the server must at least tolerate the
   command.

TLS client side: create the SSL configuration with `Security.SSLConfigs.Create(name, .props)`
using `Type=0` (client) and `VerifyPeer=0` for a self-signed certificate, then point the
adapter's `SSLConfig` at it — the adapter does AUTH TLS + PROT P from there.

The two facts worth remembering, because neither is discoverable from the error messages: *"SSL
EOF" can mean a failed LIST, not a TLS problem*, and *`FileSpec` flips from glob to regex when
`MLSD=1`*.

