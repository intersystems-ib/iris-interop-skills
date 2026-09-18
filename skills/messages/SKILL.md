---
name: messages
description: Message class design (Ens.Request+%Persistent, HL7, SOAP). Routed from interop. Triggers: message class, mensaje, Ens.Request, Ens.Response, %Persistent, HL7 message, request/response, definir mensaje, message body.
---

# Messages — the foundational building block

Messages are the **first thing to design** in any IRIS Interoperability production. They're the request/response types of every Business Process and Business Operation, and the response of Business Services. Get them wrong and you propagate damage through every component.

## When to use this skill

The user is about to (or should be about to) define what data flows between components. Triggers: "I need a message for X", "request class for the BO", "what should the BS send", "definir el mensaje".

## Decision tree

```
Is the data HL7 v2.x?
├── YES → Use EnsLib.HL7.Message directly. Do NOT subclass for storage.
│         DocType (e.g. "2.5:ADT_A01") sets structure.
└── NO
    ├── Is it a SOAP request/response from a WSDL?
    │   ├── YES → Use the SOAP wizard. It generates message classes from WSDL.
    │   │         Wizard outputs are usually %SerialObject for the payload,
    │   │         wrapped in an Ens.Request/Response carrier.
    │   └── NO
    │       └── Custom payload → persistent message (see below)
    │           └── Any property an object rather than a scalar?
    │               → see "Complex properties" below — the sub-object's
    │                 class type is a decision, not a detail.
```

## Canonical pattern — custom persistent message

A custom message in IRIS Interoperability inherits **both** `%Persistent` **and** `Ens.Request` (or
`Ens.Response`) — **and the order matters**. `%Persistent` goes **first**:

```objectscript
Class MyApp.MSG.PatientCensusRequest Extends (%Persistent, Ens.Request)
{
Property PatientId As %String;
Property AdmissionDate As %TimeStamp;
Property Department As %String(MAXLEN=80);
}
```

### Why `%Persistent` must be leftmost

**Gated example and the only mechanical check:**
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/msg-persistent-leftmost.cls` and its
test `…/tdd-message-own-extent.cls`. The test was mutation-checked — it passes as shipped and
**fails** when the superclass order is reversed, which no other check in that repo does.


IRIS treats the **leftmost superclass as primary**, and the primary superclass is what drives
storage. `Ens.Request` is *already* persistent — it inherits `Ens.MessageBody`, which owns
`^Ens.MessageBodyD` — so putting it first makes your message inherit that **shared** extent. Listing
`%Persistent` merely somewhere in the list is necessary but **not sufficient**; only being *first*
makes IRIS generate its own `DataLocation`/`IdLocation`/`IndexLocation`/`StreamLocation`.

Measured on IRIS for Health 2026.1 — two classes identical but for the order of their superclasses:

| `Extends` clause | resulting `data_global` |
|---|---|
| `(Ens.Request, %Persistent)` | `^Ens.MessageBodyD` — **shared with every other message body** |
| `(%Persistent, Ens.Request)` | `^MyApp.MSG.PatientCensusRequestD` — own extent ✅ |

Both compile, both project an SQL table, and both read and write their properties correctly, so
nothing in the build or the tests distinguishes them. What the shared extent costs you is
searchability by property, independent purge/retention, and a message table that grows with every
other body class in the namespace.

The `%Persistent`-first form is still a fully-fledged message: `%Extends("Ens.Request")` and
`%Extends("Ens.MessageBody")` both remain true, and it saves, reopens and routes normally.

Do **not hand-author** a `Storage` block. IRIS generates the storage definition on first compile
— from the primary superclass, which is the whole point above. Writing one yourself makes
`iris_doc(mode=put)` refuse with `STORAGE_STRIP_BLOCKED` until `allow_storage_regeneration: true`
is passed; the guard is protecting generated storage, so the fix is to leave the block out, not to
pass the flag.

**The GENERATED `Storage Default` block is a different thing and is not a defect.** In a disk-first
flow, a VS Code / Atelier export writes it back into the `.cls` after the first successful compile,
and it re-materialises on every subsequent export. `iris_doc` accepts it silently
(`storage_stripped: false`) precisely because it is byte-identical to what IRIS generates. Do not
delete it: removing it only sends you round the loop — rewrite clean, export, the block returns.

The test is **what the block names**, not whether it is present: globals that are the class's own
extent (`^Pkg.MSG.NameD` / `^Pkg.MSG.NameI` for `Pkg.MSG.Name`) are the generated default and are
fine. A **custom global map** — globals that are not this class's own extent — is the thing the rule
is about, and the thing the guard refuses.

Pair Request with a Response class extending `(%Persistent, Ens.Response)` — same leftmost rule. If the operation is fire-and-forget, return `Ens.Response` directly — no custom Response class needed.

**Identifiers are letters and digits only — never `_`.** `_` is the concatenation operator, so
`Property patient_id As %String;` cannot parse — and the error is actively misleading:
`ERROR #5559: ... could not be parsed correctly, possibly due to non-matching {} or () characters`.
The braces are fine; the name isn't. If you see #5559, check class/property/method/parameter names
for underscores before touching a brace. Use PascalCase (`PatientId`, `ResultValue`). External JSON
keys that do carry underscores are read via `%Get`/`%Set` on a `%DynamicObject` — see
`business-services`.

## Complex properties — what class for an object inside a message

The canonical example above is all scalars. As soon as a property is an **object** — an `Address`
inside a `Person`, a `Coverage` inside a `Claim` — you are choosing a storage model, and the wrong
choice fails silently months later.

**Default to `%SerialObject`.** `Address` has no life of its own: it isn't queried on its own, isn't
shared between messages, and dies with its `Person`. A `%SerialObject` serialises **inline into the
message's own row**, so purging the message takes the address with it. Nothing else to wire.

Name it per the existing convention (`interop`, naming table): internal `%SerialObject` data classes
go in the **`.DAT`** sub-package.

```objectscript
Class MyApp.DAT.Address Extends (%SerialObject, %XML.Adaptor)
{
Property Calle    As %String(MAXLEN = 200);
Property Ciudad   As %String(MAXLEN = 100);
Property CodPostal As %String(MAXLEN = 10);
}

Class MyApp.MSG.PersonReq Extends (%Persistent, Ens.Request)
{
Property Nombre  As %String(MAXLEN = 100);
Property Address As MyApp.DAT.Address;   // embedded — purged with the message
}
```

**Switch to `%Persistent` only for a reason.** There are four, and "it felt more real" is not one:

| Situation | Type | What else is required |
|---|---|---|
| Value object, owned by one message (`Address`, `Contact`, `Amount`) | `%SerialObject` | Nothing — purge is automatic |
| **Shared** by several messages, or referenced after the message is purged | `%Persistent` | Delete cascade on the carrier (below) |
| Must be **queried on its own** (SQL, `message-search-debug`, reporting) | `%Persistent` | Delete cascade + indexes |
| **Recursive** (`Component` containing `Component` — CDA sections) | `%Persistent` | Delete cascade — a recursive `%SerialObject` won't even compile (cyclic reference) |
| **Large** (>100 KB serialised) and retained in volume | `%Persistent` | Delete cascade — keeps `Ens.MessageBodyD` from bloating |

### If it is `%Persistent`, the delete cascade is not optional

A `%Persistent` sub-object gets **its own row**. `Ens.Util.Tasks.Purge` deletes `Ens.MessageHeader`
and the message row — it does **not** know about the child. The child rows accumulate forever, with
no error and nothing in the Event Log; you find out when the table is the biggest thing in the
namespace.

The cascade goes on the class that **references** the object — the message — not on the child:

**Gated, executed example — use it instead of retyping this:**
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/msg-persistent-child-delete-cascade.cls`
with its child `dat-address-persistent.cls` and test `tdd-delete-cascade.cls`.

The snippet that used to sit here was wrong in two ways that both compiled, and they are worth
knowing because they are the natural things to write:

It declared `Property Address As MyApp.DAT.Address` with a comment claiming "%Persistent in this
variant", and a `Trigger DeleteCascade [ Event = DELETE, Foreach = row/object ]` whose body was
`Do ##class(MyApp.DAT.Address).%DeleteId({Address})`. Both defects:

- **The child it names is `%SerialObject`** (see the class above), not `%Persistent`. Measured on
  2026.1: `%DeleteId` *does* exist on `%SerialObject`, so this compiles, and at runtime it returns
  `ERROR #5753: Cannot instantiate abstract class`. A serial child has no rows of its own to leak,
  so the trigger was solving a problem that did not exist by a means that could not work.
- **`Do` discards the `%Status`.** That is what makes it silent: the call fails, the status is
  thrown away, the trigger reports success and the parent delete proceeds. Use `Set tSC = …` and
  act on it.

The gated version also carries the guard this one lacks: the reference is optional, `%DeleteId("")`
errors, and an unguarded trigger therefore makes childless carriers **undeletable** — the trigger
added to help a purge is what stops it.


Equivalent alternatives: override `%OnDelete` on the message and clean the references explicitly, or
— for parent-child hierarchies generated from an XSD — declare `OnDelete = Cascade` on the link (see
the CDA-from-XSD section below).

This is the same rule the SOAP wizard case runs into; `soap-bo` covers the wizard-specific angle
(it generates `%SerialObject` payloads and never generates the trigger for you).

## Canonical pattern — HL7 message

Don't create a class. Use `EnsLib.HL7.Message` everywhere a message body is referenced:

```objectscript
Method OnRequest(pRequest As EnsLib.HL7.Message, Output pResponse As Ens.Response) As %Status
```

The DocType (e.g. `2.5:ADT_A01`) controls structure; it's set on the BS adapter or assigned in a DTL.

## Canonical pattern — SOAP-wizard messages

SOAP wizard output: payload classes typically `%SerialObject` (embedded, no separate storage) — the same default as any hand-written sub-object. For very complex SOAP messages — e.g. a CDA wrapped in SOAP, with deeply recursive structures — switch the payload to `%Persistent` so each instance gets its own storage and the recursion doesn't blow up `Ens.MessageBodyD`, and add the delete cascade per **Complex properties** above. The wizard does not generate the trigger for you.

## CDA-from-XSD persistence pattern

When importing CDA documents into ObjectScript classes from the XSD via the XML Schema Wizard, the only combination that works reliably:

- **Persistent** — required so CDA instances persist alongside Ensemble messages.
- **No Relationships** — the wizard's `Relationships=1` option causes XML serialisation to take ~60 seconds per CDA, unusable in production.
- **`OnDelete = Cascade`** on the parent-child links — so purging an Ensemble message also purges the CDA child rows; otherwise orphaned rows accumulate forever.

Alternatives that **fail**:

- `Serializable` (the default `%SerialObject` choice for the wizard) — produces a cyclic-reference compile error when a CDA `Component` recursively contains `Component`.
- Persistent with Relationships — slow XML serialisation as above.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch03_cda/cda-from-xsd-persistence-pattern.cls`.

**Export what the wizard generated.** A CDA XSD produces dozens of classes, all of them written
straight into the namespace — the source-of-truth gate never sees them, because the wizard does
not go through `iris_doc(mode=put)`. `iris_doc(mode=get)` the generated package and write it to
`src/` before doing anything else; the three settings above are edits *on top of* generated code,
and losing them means re-deriving them from a 60-second serialisation failure. Same rule for
SOAP-wizard output (`soap-bo`) and for the RecordMap generator (`business-services`).

**Stylesheet security note**: the standard HL7 CDA stylesheet (`cda.xsl`) had multiple security holes before April 2014 — XSS via `nonXMLBody` rendered inside an `<iframe>`, illegal table attributes (`onmouseover`), image URIs to hostile sites. Use only the patched version from the HL7 Structured Documents Working Group.

## Comanda / Resposta inheritance for one-of-N payload subtypes

When a schema defines an envelope type whose actual content is one of N subtypes (e.g. `Comanda` whose body is one of `Comanda_SC1`, `Comanda_SC2`, ..., or an abstract `Order` with concrete `LabOrder` / `RadiologyOrder` subclasses), make the generated wrapper class **abstract** and create concrete subclasses for each variant. The BS instantiates the concrete class based on inspection of the inbound payload.

This unlocks two things:

1. The DataTransform Wizard sees concrete types and proposes correct field mappings per variant.
2. Routing rules can constrain by `msgClass` to dispatch the variants to different processors.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch03_cda/comanda-resposta-inheritance.cls`.

## SOAP envelope carrying HL7 / CDA as MessageBody

When a partner's WSDL specifies a custom `acceptMessage(message)` operation with the HL7 ER7 text in a string field — **not** the standard `EnsLib.HL7.Util.SOAPClient` shape — customise the wizard-generated SOAP proxy:

- Change the parameter from `%String` to `%Stream.GlobalCharacter` (HL7 messages exceed string limits routinely).
- Copy `EnsLib.HL7.Operation.SOAPOperation` as the BO base.
- Override `..Adapter.WebServiceClientClass` to point to the custom proxy.
- Override the invoked method: `..Adapter.InvokeMethod("acceptMessage", ...)` instead of the wizard's default `Send`.

Same pattern applies for SOAP-carrying-CDA (e.g. `<publicarDocument>` with a `<ClinicalDocument xmlns="urn:hl7-org:v3">` directly in the SOAP Body parameter).

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch03_cda/soap-messagebody-hl7-proxy.cls`.

## XML projection — three settings to know

When a message class is projected to XML (SOAP payloads, REST XML responses, file-exported documents), three settings control output behaviour:

| Setting | Effect | When to set |
|---|---|---|
| `XMLIGNORENULL = 1` (class-level, NOT property-level) | Empty-string properties appear as empty elements (`<Field/>`) instead of being omitted. | When the partner schema requires the elements to be present even when empty. **Caveat**: for `list Of <T>` collections where every item is empty, the list element is still omitted — there is no clean way to force its presence except manual XML manipulation. |
| `CONTENT = "STRING"` on a `%Stream.GlobalCharacter` property | Wraps content in `<![CDATA[...]]>`. | When the payload is XML you don't want re-escaped (e.g. CDA inside a SOAP envelope). |
| `CONTENT = "ESCAPE"` on a `%Stream.GlobalCharacter` property | XML-escapes the text. | For free-text fields that may contain `<` or `&`. |
| `OUTPUTTYPEATTRIBUTE = 0` (class-level on SOAP proxy) | Suppresses `xsi:type` attributes on every element. | When the partner SOAP server rejects messages with `xsi:type` (some SAP, some vendor servers — see `soap-bo` §"Vendor rejects `xsi:type` attributes"). |

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/xml-projection-settings.cls`.

## Common pitfalls

- **Custom message without `%Persistent`** → bodies stored in `Ens.MessageBodyD`, unsearchable by property, slow to purge.
- **`%Persistent` present but NOT leftmost** (`Extends (Ens.Request, %Persistent)`) → same outcome as
  omitting it: the message still shares `^Ens.MessageBodyD`, because IRIS takes the leftmost
  superclass as primary and `Ens.Request` is already persistent. Nothing fails — it compiles, the
  SQL table projects, the properties read back — so only `iris_table_info` reveals it. Write
  `Extends (%Persistent, Ens.Request)`.
- **Hand-written `Storage` block** → `iris_doc` refuses the write (storage guard). See §**Canonical pattern — custom persistent message**.
- **Subclassing `EnsLib.HL7.Message`** → almost always wrong; HL7 is structurally defined by DocType, not by class hierarchy.
- **Putting business properties on the carrier instead of the payload** in SOAP scenarios → wizard regeneration overwrites them.
- **Missing pair**: Request without matching Response when the operation is synchronous and the BP expects a typed response.
- **Forgetting indexes** on properties used by `message-search-debug` — message search is fast only on indexed properties.
- **An object property typed `%Persistent` "to be safe", with no delete cascade** → child rows survive every purge and the table grows forever, silently. See §**Complex properties** for the `%SerialObject`-vs-trigger fix.
- **Recursive properties on a `%SerialObject`** → cyclic-reference compile error. See §**Complex properties** (row 4) and the CDA section.
- **Adding `SourceFilename` / `SourceLine` to a Record Mapper message** → the mapper never fills them; propagate provenance from the BS adapter instead — see `business-services`.

## Testing / how to verify

After compiling the message class:

1. From the MCP server, run a class compilation and confirm no errors.
2. Open the Management Portal → System Explorer → Classes; confirm the class has its **own** SQL projection / storage definition (not inheriting `Ens.MessageBodyD`).
3. Smoke test: create one instance with `%Save()`, confirm it persists in the message-class-specific table, not in `Ens.MessageBodyD`.

## Polymorphic extension pattern — growing a canonical message without breaking consumers

When a second consumer needs **richer** data than the original canonical (e.g. an existing flow uses `MenuRequest` with `Alergias` as a pipe-string, and a new SOAP/REST destination wants `Alergias` as a typed `list of %String`), **don't replace the canonical** — extend it with a subclass:

```objectscript
Class MyApp.MSG.MenuRequest Extends (%Persistent, Ens.Request)
{
Property PacienteId As %String(MAXLEN = 20) [ Required ];
Property Nombre     As %String(MAXLEN = 100) [ Required ];
Property Alergias   As %String(MAXLEN = 500);   // pipe-separated, legacy consumers read this
// ... other 3.1 properties ...
}

Class MyApp.MSG.MenuRequestRich Extends MyApp.MSG.MenuRequest
{
Property AlergiasList            As list Of %String(MAXLEN = 100);   // typed collection
Property AlergiasAcompananteList As list Of %String(MAXLEN = 100);
Property AcompananteNombre       As %String(MAXLEN = 100);
Property TieneAcompanante        As %Boolean [ InitialExpression = 0 ];
}
```

Then DTLs that produce `MenuRequestRich` **fill both** representations — `target.Alergias = "A|B|C"` AND `Insert` each into `target.AlergiasList`. Legacy consumers (the JDBC BO) keep reading the inherited string field; new consumers (SOAP/REST BO) read the typed list. The routing rule uses two `<send target>` lines pointing at the relevant BOs — polymorphism handles dispatch.

Trade-off: one place to remember "fill both forms when producing Rich". Win: existing tests stay green, no message class duplication, the canonical grows monotonically.

## `%String` for fields that collect from HL7/REST sources

A canonical message that takes values from HL7 segments or REST JSON should declare **almost everything as `%String`**. Typing `Planta As %SmallInt` and then receiving `"PLANTA3"` from `PV1:3.1` or `"P3"` from a lookup produces `ERROR #7207: Datatype value 'PLANTA3' is not a valid number` and terminates the BP. Convert/validate in the DTL **after** extraction, not via property datatype.

Strict types like `%SmallInt`, `%Integer`, `%Boolean`, `%Date` are fine for fields that are populated programmatically (`req.PacienteId = ...` from controlled code) but risky for fields populated from external sources. `%String` plus runtime validation gives clearer error messages and decouples the canonical from upstream surprises.

## `%String` length — the `MAXLEN=50` trap (and `MAXLEN=""` for big text)

A **bare `%String` defaults to `MAXLEN=50`**, and a longer value is **rejected, not truncated**.
Measured on IRIS for Health 2026.1, one property, four paths: 50 chars saves and reads back 50; 51
gives `ERROR #7201`; `%ValidateObject()` on its own gives the same `#7201`; an SQL `INSERT` gives
`SQLCODE=-104 … failed validation`; and after `Set`, the in-memory value still holds all 100 chars.
**Nothing is silently discarded** — which is why the fix is to read the `#7201` you already have
rather than to go hunting for missing text. This routinely bites canonical messages carrying free
text: addresses, clinical notes, HL7 `OBX`/`NTE` text, JSON blobs, base64.

Two boundaries on that measurement, because the word "silent" has been wrong here before. It covers
the object and SQL persistence paths only: whether a **SOAP/XML import** truncates on
deserialization is a different path and is **not** measured. And a value cut short at a *separator*
is an unrelated mechanism — see `business-services` on a RecordMap separator defaulting to
`$char(32)`, which really is silent.

- Give every text-ish property an explicit length: `As %String(MAXLEN=200)` (size it to the source).
- For "as large as a string can be", use **`As %String(MAXLEN="")`** — unbounded, capped at the IRIS string ceiling of **~3.6 MB** (3,641,144 chars). No penalty for declaring it.
- Past ~3.6 MB, or for genuinely large/streamed payloads, switch the property to **`%Stream.GlobalCharacter`** (see the XML-projection and SOAP-envelope patterns above).
- **`MAXLEN=""` has a second ceiling, below the string ceiling.** Measured: 3,600,000 chars save and
  read back intact, but at exactly `$$$MaxStringLength` (3,641,144) `%ValidateObject()` returns **OK**
  while `%Save()` fails `#5002 <MAXSTRING>` from inside generated `%SaveData` code — an error that
  names a routine, not your property. The validator and the saver disagree, so "it validates" is not
  "it stores". Switch to a stream well before the ceiling rather than at it.

Worked examples (compiled, and the test is run and mutation-checked):
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/msg-maxlen-boundaries.cls` and
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch05_bpl_dtl/tdd-maxlen-truncation.cls`.

> **SOAP Wizard / WSDL caveat.** When a WSDL declares a string **without a length facet**, the message class the SOAP wizard auto-generates can come out with a **bounded `%String` (the 50 default)** for that property — so a longer value fails validation the moment the message is saved. After running the wizard, **review the generated payload classes and widen** the affected properties to `%String(MAXLEN="")` (or `%Stream.GlobalCharacter` for large content). See `soap-bo`. Whether the SOAP *deserializer* rejects or quietly shortens before any save is a separate path and is unmeasured — widen the property and the question does not arise.

## Collections — `list Of` for typed multi-valued fields

For HL7 repeating fields (AL1*, NK1*), REST JSON arrays, or any multi-valued source, the canonical's property is `list Of %String(MAXLEN=N)` (or `list Of <ObjectClass>`). The DTL fills the list with `Insert`. Persistence storage is automatic. SQL projection generates a child table `<Parent>_<PropertyName>` for queries like:

```sql
SELECT COUNT(*) FROM <Pkg>_Msg.<Parent>_AlergiasList WHERE <Parent> = :id
```

**The child table lives in the parent's schema — that is the half people guess wrong.** The schema
follows the normal class→table rule (package dots become `_`, last dot separates schema from
table), and the property name is appended to the *table*: class `COCINA.MSG.MenuRecibido` with
`Property Alergias As list Of %String` projects to `COCINA_MSG.MenuRecibido_Alergias` — not
`COCINA.MenuRecibido_Alergias` (a guess that cost one workshop cohort 12 straight
`SQLCODE -30 Table not found` round-trips). Before querying a projected table you did not just
create, confirm the name with `iris_table_info` (or `Agent(subagent_type="iris-interop-skills:introspect-dont-guess")` — an
agent, not a skill; with no agent tool, follow `interop` §"Resolving real names") — one call
answers it.

Don't substitute a pipe-string property for a typed collection if downstream consumers want collection semantics — the conversion belongs in the DTL one time, not in every consumer.

For `list Of <ObjectClass>`, the `<ObjectClass>` follows the same rule as any object property — see
**Complex properties**: `%SerialObject` unless one of the four reasons applies, and a delete cascade
if it ends up `%Persistent`. A collection multiplies the leak: N orphaned child rows per message
instead of one.

## When NOT to use this skill — fall back to docs

- Designing FHIR resources (use `HS.FHIR.*` patterns — different from generic Interop messages).
- Designing message classes for non-Interoperability contexts (plain `%Persistent`, no `Ens.Request` inheritance).
- DICOM messages — see `dicom` (stub).

## See also

- `business-services` — what the BS will produce as a message
- `business-operations` — what the BO consumes as request and returns as response
- `hl7-schemas` — when the HL7 message needs a custom Z-segment schema
- `soap-bo` — SOAP wizard customisations, including `xsi:type` suppression and other generated-proxy patches
- `fhir` — FHIR resources are not generic Interop messages; different rules apply
- `message-search-debug` — where the purge that exposes a missing delete cascade actually runs
- `production-lifecycle` — `Ens.Util.Tasks.Purge` belongs in the production from day one
