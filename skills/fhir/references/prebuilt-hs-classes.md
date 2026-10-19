# Prebuilt `HS.*` / `EnsLib.*` signature cards — HL7v2 ↔ SDA3 ↔ FHIR, and two Interop staples

Read this **while wiring a component that calls a shipped InterSystems class**, not while standing a
namespace up — that is [foundation-install.md](foundation-install.md), a different trigger. The
classes below are build-time: you reach for them inside a DTL, a business process, or a business
operation that is already running in a Foundation namespace.

**Signatures verified live against IRIS for Health community 2026.1** by querying
`%Dictionary.CompiledMethod` (`FormalSpec`, `ReturnType`, `ClassMethod`, `Origin`) in namespace
`APP`, and **re-verified field by field on 2026-10-16** against the same instance. All five classes
are present in `APP`, `HSLIB` and `HSCUSTOM` — measured per namespace rather than inferred from a
total: one `Name IN (<the five>)` query per namespace returned 5 rows in each, echoing `$NAMESPACE`
back so the answer names the namespace that produced it. Controls: `Ens.BusinessOperation` resolved with 352 methods (positive),
and both a nonexistent class and a nonexistent method returned a well-formed empty `content:[]`
(negative) — so an absence here is distinguishable from a dead endpoint, which answers with a blank
body instead.

> **WHAT HOLDS THESE SIGNATURES: nothing. Re-introspect before you ship against them.**
> This file is prose and markdown tables. No tier compiles it, and no check reads it — tier 3 only
> stages `objectscript` fences holding a complete `Class … Extends`, and there is no such fence
> here. Do not read the wording in `foundation-install.md` ("kept verified because tier 3 compiles
> the class below") as applying here; it does not, and it overstates even its own case, because a
> compile pins neither method existence nor arity. The repo has measured that twice:
> `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch04_fhir/tdd-fhirsql-setup-existence.cls` ("a call-through to a missing
> method compiles clean") and `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch06_adapters/tdd-wsdl-reader-signature.cls`
> ("a typed `#Dim` gates neither arity nor even method existence, because ObjectScript resolves
> instance-method calls at run time"). The only instrument that makes a signature claim falsifiable
> is a `%UnitTest` oracle reading `%Dictionary.CompiledMethod.FormalSpec` — seven bank files do it.
> **A follow-up should add one for the cards below; until then, treat every card as a 2026.1
> snapshot and introspect in your own namespace.**

> **INSTRUMENT HAZARD — do not put `ORDER BY` on an OR-of-`LIKE` against `%Dictionary.*`.**
> Measured on IRIS for Health community 2026.1 on 2026-10-16, and it silently truncated two
> population sentences in the first
> version of this very file. The query
> `WHERE parent='EnsLib.HL7.Message' AND (Name LIKE 'Output%' OR Name LIKE '%ToString%' OR Name LIKE '%String%' OR Name LIKE '%Stream%')`
> returns **23** rows. Append `ORDER BY Name` and the identical predicate returns **13** — it drops
> every row whose `Name` sorts before the lower bound of the earliest *anchored* pattern (`Output%`),
> so `ImportFromString`, the three `ImportFrom*Stream`, the three `GetFieldStream*` and the three
> `%SQL*Streams` vanish. Confirmed as a sort-bound effect, not a coincidence: swap the anchor for one
> that sorts early (`A%`) and only the three `%`-prefixed names drop. **The failure returns a
> plausible non-empty subset, so nothing looks wrong.** Use one `LIKE` per query, or `UNION` the
> single-pattern selects (verified to reproduce the true 23), and sort client-side. Two further
> quirks of this catalogue: `Default` and `Unique` are reserved, so select `"_Default"` / `"_Unique"`,
> and stream columns such as `CompiledXData.Data` cannot appear as either operand of `=` (SQLCODE
> -313).

The one reflex this file is here to kill: **guessing whether a shipped method is a class method or an
instance method.** Three of the five cards below turn on exactly that, and the wrong choice fails at
*run* time with `<METHOD DOES NOT EXIST>`, long after the class compiled clean.

## `HS.Gateway.HL7.HL7ToSDA3` — HL7 v2 → SDA3

The supported entry point, and the only member of this class you should call:

| member | shape |
|---|---|
| `GetSDA` | **ClassMethod** `(pRequest As EnsLib.HL7.Message, Output pXML As %Stream.GlobalCharacter, pLogAlerts As %Boolean = 1, pObservationMode As %Boolean = 0, pMultiLineOBXCompatibilityMode As %Boolean = 0, pKeepDuplicateOBXIdentifiers As %Boolean = 0) As %Status` |

- `pXML` is an **output** argument (`*` prefix in the measured `FormalSpec`), declared
  `%Stream.GlobalCharacter`. You pass it by reference and read the SDA3 out of it; the return value
  is only the `%Status`.
- All four trailing arguments carry defaults, so **`GetSDA(msg, .stream)` is a legal call** — you do
  not have to supply the compatibility flags.
- `Super` is `%Library.RegisteredObject`. `Deprecated` and `Internal` are both false (re-queried in a
  fresh call, same result).

**`GetSDA` is the only member to *call*** — but calling is not the only supported way to use this
class; see the callback surface below. Population: 157 methods are visible on the class, of which
**118** have `Origin = HS.Gateway.HL7.HL7ToSDA3`; it has 0 own-origin properties. The remaining 39
are accounted for, so the 118 is a partition and not a filter that might have dropped rows:
`%Library.RegisteredObject` 19, `%Library.SystemBase` 18, empty `Origin` 2. (The first version of
this card said 122; re-derived three ways — `COUNT(*)`, `COUNT(DISTINCT Name)` and `GROUP BY Origin`
— it is 118.) Every own-origin
method other than `GetSDA` is either an HL7-segment callback (`MSH`, `PID`, `PV1`, `OBX`, …) or a
message-type handler (`adta01`, `orur01`, `vxuv04`, …), driven internally by `GetSDA`. A handful are
general-purpose string helpers — `HL7ToHorolog(dt)`, `xmltimestamp(dt)`,
`FormatPhone(country, area, number, extension)`, `formatname(last, first, middle, prefix)`,
`unescape(text)`, `GenerateEncounterNumber()`, all ClassMethods returning `%String`, plus
`ParseADDSegs(pDoc As EnsLib.EDI.Document, pValSpec As %String, Output pStatus As %Status) As %Boolean`
— but they are internals, not a published API, and nothing commits InterSystems to keeping them.

**The segment callbacks ARE a supported extension surface, and that is not a contradiction.** The
2026.2 manual (`HXSDA`) documents the customisation route: create a class extending
`HS.Gateway.HL7.HL7ToSDA3` and implement callbacks named `On<StreamletName>()`. Those callbacks are
real and measured — 15 own-origin **ClassMethods**, all with an **empty `FormalSpec`** (they read
state rather than take arguments):

| callback | | |
|---|---|---|
| `OnAllergy` | `OnAppointment` | `OnDiagnosis` |
| `OnDocument` | `OnEncounter` | `OnLabOrder` |
| `OnMedication` | `OnObservation` | `OnOtherOrder` |
| `OnPatient` | `OnProblem` | `OnProcedure` |
| `OnRadOrder` | `OnVaccination` | `OnBeforeEndContainer` |

So the rule is **do not call anything else; override `On<Streamlet>()` in a subclass instead.** The
distinction matters: the first version of this card filed these 15 under "internals, not a published
API", which would have talked a reader out of the documented way to customise the transform.

> **Two caveats on that route, both measured.** The manual also says to point at your subclass by
> changing an `HL7ToSDA3Class` property. **No property or parameter of that name exists in this
> image** — `CompiledProperty`/`CompiledParameter` on `Name LIKE '%HL7ToSDA3%'` return 0 rows, with
> the instrument controlled (the same query shape does return rows for this class, e.g. `%%OID`), and
> `HS.Gateway.HL7.HL7ToSDA3` is the **only** class under `HS.Gateway.HL7.*` here. The hook exists in
> the product; the name to set it through does not resolve in a community 2026.1 Foundation
> namespace, so locate it in your own version rather than trusting the string. Second, from the
> manual (`AHXDT`, not measured by me): the transform **assumes HL7 2.5.1** — convert other versions
> first — and there is **no** programmatic SDA → HL7 v2 reverse.

> **A sibling class with a confusingly similar name exists and is NOT described here.** A
> `LIKE '%HL7ToSDA%'` scan returned 4 names (`HS.Doc.Mapping.HL7ToSDAMapper`,
> `HS.Doc.Mapping.ImportHL7ToSDAMapping`, this class, and `HS.Hub.Standalone.HL7.HL7ToSDA3`).
> **Measured 2026-10-16: the sibling has no `GetSDA`** — 0 rows, where the same query shape returns
> the row above for this class and a nonexistent method name also returns 0, so the instrument
> distinguishes the two cases. The two classes are **not** interchangeable; do not reach for the
> `Standalone` one expecting this entry point.

## `HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process` — SDA3 → FHIR, as a business process

`Super = Ens.BusinessProcess, HS.HC.Util.Trace.Helper`; `ClassType = persistent`; not abstract. It is
a **business process you configure in a production**, not a utility you call — and not a BP*L*.

The 8 members below are the **complete** own-origin set (population: 832 methods visible, exactly 8
with `Origin` = this class), not a selection:

| member | class method? | shape |
|---|---|---|
| `OnRequest` | **no — instance** | `(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status` |
| `ProcessSDARequest` | **no — instance** | `(pSDAStream, pSessionApplication As %String, pSessionId As %String, pPatientResourceId As %String = "") As %Status` |
| `ProcessFHIRResponse` | no — instance | `(pFHIRResponse As HS.Message.FHIR.Response, ByRef pFHIRSC As %Status, pSchema As HS.FHIRServer.Schema) As %Status` |
| `OnInit` | no — instance | `() As %Status` |
| `CreateAndSendInteropMessage` | no — instance | `(pFHIRObj As %Library.DynamicObject, pSchema As HS.FHIRServer.Schema, pContentType As %String, pFormatter As %JSON.Formatter, pIndentChars As %String, pLineTerminator As %String, pSessionApplication As %String, pSessionId As %String)` — no return type |
| `CreateAndSendFHIRMessage` | no — instance | as above plus `pLocalHostAndPort As %String` after `pSchema` — no return type |
| `GetResourceStream` | **yes** | `(pResourceObj, pFHIRFormat, pFormatFHIROutput, pSchema, pFormatter, pIndentChars, pLineTerminator) As %Stream.Object` |
| `GetHostAndPort` | **yes** | `(Output pHost As %String, Output pPort As %String)` — no return type |

- **`ProcessSDARequest` is an instance method.** `##class(HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process).ProcessSDARequest(…)`
  does not work. `OnRequest` is the entry point the framework calls; `ProcessSDARequest` is the
  SDA-specific worker beneath it.
- `pSDAStream` is declared with **no type** — the measured `FormalSpec` has a bare name. Same for the
  seven arguments of `GetResourceStream`.
- Only `GetResourceStream` and `GetHostAndPort` are class methods.

Its 12 own-origin properties **are the production settings**, with these measured initial expressions:

| setting | initial |
|---|---|
| `TransformClass` (`%Dictionary.Classname`) | `HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR` |
| `TransmissionMode` | `transaction` |
| `FHIRFormat` | `JSON` |
| `ValidResourceRequired` | `1` |
| `FormatFHIROutput`, `FullTransactionResponse`, `OutputToQuickStream` | `0` |
| `CallbackClass`, `FHIREndpoint`, `FHIRMetadataSet`, `FHIRVersion` | empty |
| `TargetConfigName` (`Ens.DataType.ConfigName`) | empty |

## `HS.FHIRServer.Interop.Operation` — the local-outbound FHIR operation

`Super = Ens.BusinessOperation, HS.FHIRServer.Interop.Host`; not abstract; `ClassType` is empty (it is
**not** persistent). Its role alongside `Interop.Service` and `Interop.HTTPOperation` is sketched in
`../assets/production-fhir-facade.cls`.

**This class declares no methods of its own.** That zero is measured, with a control: a query for
`Origin = 'HS.FHIRServer.Interop.Operation'` returned 0 rows, and the *same query shape* grouped by
`Origin` over the same 362-method population returned `HS.FHIRServer.Interop.Host` = 1 and
`HS.HC.Util.Trace.Helper` = 2. So the 0 is a real "declares nothing", not a failed query or a typo.

Consequences, which is the whole reason this card exists:

| member | where it actually comes from | shape |
|---|---|---|
| `DispatchRequest` | **`HS.FHIRServer.Interop.Host`**, *not* this class | instance, `(pInteropRequest As HS.FHIRServer.Interop.Request, Output pInteropResponse As HS.FHIRServer.Interop.Response) As %Status` |
| `OnMessage` | `Ens.BusinessOperation` — **not overridden here** | instance, `(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status` |
| `OnInit`, `OnTearDown` | `Ens.Host` | instance, `() As %Status` |
| `HSTrace` / `BuildTraceRequest` | `HS.HC.Util.Trace.Helper` | `(pCurrentClass, pMethod, pArgList…)`; `HSTrace` instance, `BuildTraceRequest` class method |

- `DispatchRequest` is the only FHIR-specific member, and **attributing it to
  `HS.FHIRServer.Interop.Operation` is wrong about `Origin`.**
- `OnMessage` here is the plain inherited `Ens.BusinessOperation` signature with
  `%Library.Persistent` in and out — this class does not narrow it to the FHIR request/response types.
- The class **does** define its own `XData MessageMap` (`Name = 'MessageMap'`, `Origin` = this class,
  1 row). **Its body is still unstated, and now for a known reason rather than a dead endpoint.**
  Re-run on a live instance 2026-10-16, `Data` comes back as the empty string — and the control that
  makes that interpretable now exists: three other `EnsLib.HL7.*` XData blocks that certainly have
  content (`SearchTable.SearchSpec`, `RuleExtension.Schema`, `RuleExtension.UrlMap`) also report
  `CHARACTER_LENGTH(Data) = 0` over the same path. So **the Atelier REST query path does not
  serialise this stream column at all**; the empty value says nothing about any MessageMap. Read it
  with a different instrument (`iris_doc`, or the class definition itself).
- `ADAPTER` and `INVOCATION` are **inherited, not overridden here** (measured, selecting the reserved
  column as `"_Default"`): `ADAPTER` comes from `Ens.Host` with an **empty** default — this operation
  has no adapter — and `INVOCATION` from `Ens.Host` as `Queue`. The only own-origin parameter is
  `SETTINGS`.

## `EnsLib.HL7.Message` — serialising to a string, and the Import/Output asymmetry

`Super = %Library.Persistent, EnsLib.EDI.BatchDocument, EnsLib.EDI.Segmented, EnsLib.HL7.Util.MsgBodyMethods`;
`ClassType = persistent`.

**`OutputToString` exists, and its shape is not the one a blind guess produces:**

| member | class method? | shape |
|---|---|---|
| `OutputToString` | **no — instance** | `(pSeparators As %String, pSequenceNumber As %String, Output pStatus As %Status, pIOFormatClassname As %String) As %String` |

- It **returns the string**. `ReturnType` is `%Library.String`, **not** `%Status`.
- The `%Status` comes back through the **third argument**, `pStatus`, which is an output argument.
- So the correct call is **`Set str = msg.OutputToString(,, .tSC)`**, then check `tSC`.
- `Set tSC = msg.OutputToString()` is wrong (it assigns the string to a variable named like a status),
  and `##class(EnsLib.HL7.Message).OutputToString(…)` is wrong (it is not a class method).
- No argument has a declared default, so all four are optional by omission only.

The rest of the family, and the asymmetry worth remembering — **`Output*` are instance methods,
`ImportFrom*` are class methods**:

| member | class method? | shape |
|---|---|---|
| `OutputToLibraryStream` | no | `(pLibStream As %Stream.Object, pSeparators As %String, pSequenceNumber As %String, pIOFormatClassname As %String) As %Status` |
| `OutputToIOStream` | no | `(pIOStream As %IO.I.CharacterStream, pSeparators As %String, pSequenceNumber As %String, pFlush As %Boolean = 1, pIOFormatClassname As %String = "") As %Status` |
| `OutputToFile` | no | `(pFilename As %String, pOverwrite As %Boolean, pSeparators As %String, pSequenceNumber As %String, pIOFormatClassname As %String) As %Status` |
| `OutputToDevice` | no | `(pSequenceNumber As %String, pSeparators As %String, pIOFormatClassname As %String) As %Status` |
| `OutputToOldStream` | no | `(pOldStream As %Stream.Object, pSeparators As %String, pSequenceNumber As %String) As %Status` |
| `ImportFromString` | **yes** | `(pString As %String, Output pStatus As %Status, ByRef pConfigItem As %String, pIOFormatClassname As %String) As EnsLib.HL7.Message` |
| `ImportFromLibraryStream` | **yes** | `(pLibStream As %Stream.Object, Output pStatus As %Status, ByRef pConfigItem As %String, pIOFormatClassname As %String) As EnsLib.HL7.Message` |
| `ImportFromIOStream` | **yes** | `(pIOStream As %IO.I.CharacterStream, Output pStatus As %Status = $$$OK, ByRef pConfigItem As %String = "", pIOFormatClassname As %String = "") As EnsLib.HL7.Message` |
| `ImportFromFile` | **yes** | `(pFilename As %String, pDocNum As %Integer = 1, Output pStatus As %Status, ByRef pConfigItem As %String, pIOFormatClassname As %String) As EnsLib.HL7.Message` |
| `ImportFromDevice` | **yes** | `(Output pStatus As %Status, ByRef pConfigItem As %String, pIOFormatClassname As %String) As EnsLib.HL7.Message` |
| `getSegsAsString` | **yes** | `(pId As %String, pMaxLen As %Integer = 10000, pStartOffset As %Integer = 1) As %String` |

Population for that family, **re-derived 2026-10-16 after the `ORDER BY` hazard above was found**:
the four-pattern scan over the class's 649 visible methods returns **23** rows, not the 13 the first
version of this card reported. The 23 are this table's 7 `Output*`/`getSegsAsString` members plus
`OutputHTML` and `OutputHTMLZen` (HTML renderers, both instance, both `%Status`), three
`StoreFieldStream*` setters, three `GetFieldStream*` getters, three `%SQL*Streams` plumbing methods,
`OutputFormattedJSON`, and `ImportFromString`/`ImportFrom*Stream`. The four `ImportFrom*` rows in the
table were never from that scan — `ImportFromFile` and `ImportFromDevice` match none of its four
patterns — they come from a separate by-name query, which is why the table was right while the
sentence describing it was not. `OutputFormattedJSON(pJSONStreamOrAET)` is a class method
**inherited from `Ens.Util.MessageBodyMethods`**, not declared here.

## `Ens.Config.DefaultSettings` — how a default setting is actually created

`Super = %Library.Persistent, %XML.Adaptor`; `ClassType = persistent`; not abstract.

**There is no creator class method.** A deliberately wide scan — every method on the class, all
origins, population 330, whose `Name` matched `%Create%` OR `%Add%` OR `Set%` OR `%New` OR `%Save` OR
`%Setting%` — returns **38** rows, and **none** of them is a create/add/set-a-setting API. (The first
version of this card said 33: that run carried the `ORDER BY` above and so dropped the 5 rows sorting
before `Set`, among them `%GetSetting` and `%ClearSettings`, which this card lists from a separate
query two tables down. The conclusion was right; its stated evidence had a hole in exactly the region
a creator would occupy, so it was re-derived without the sort.) One real limitation remains, and the
scan cannot close it: **`%Import` matches none of the six patterns**, so the sweep never saw the one
creation route this card goes on to recommend. The
`Set`-prefixed hits are compiler-generated property accessors (`SettingNameSet`,
`SettingValueSet`, `SettingNameNormalize`, `EnumerateSettings*Fetch`, …) with an empty `Origin`, i.e.
generated rather than authored.

So you create one **the plain `%Persistent` way**: `%New()`, populate the properties, `%Save()`.
There is no API shortcut to look for, and looking for one is the trap this card closes.

The 8 own-origin properties, with `Required` as measured:

| property | required? |
|---|---|
| `ProductionName` | **required** |
| `ItemName` | **required** |
| `HostClassName` | **required** |
| `SettingName` | **required** |
| `SettingValue` | not required |
| `Description`, `Deployable`, `%DeployablePreModified` | not required |

> **The decisive structural fact: the object ID *is* the 4-tuple.** The class has an index
> `Name = 'IdKey'`, `IdKey = true`, `Final = true`, `Type = key`, over
> `Properties = 'ProductionName,ItemName,HostClassName,SettingName'`. So **re-saving the same
> 4-tuple collides instead of appending a second row** — there is no history of values for one
> setting. `SettingValue` is deliberately *not* part of the key.

The useful class methods that do exist:

| member | shape |
|---|---|
| `%GetSetting` | ClassMethod `(pProductionName As %String, pItemName As %String, pHostClassName As %String, pTargetType As %String, pSettingName As %String, Output pValue As %String) As %Boolean` |
| `%GetMatchCriteria` | ClassMethod `(pProductionName As %String, pItemName As %String, pHostClassName As %String, pTargetType As %String, pSettingName As %String, Output pMatchList As %String) As %Boolean` |
| `%Import` | ClassMethod `(pFileName As %String = "", Output pCount As %Integer, ByRef pIDsImported As %String = "") As %Status` |
| `%Export` | ClassMethod `(pFileName As %String = "", pProductionName As %String = "", pDeployable As %Boolean = "") As %Status` |
| `%ClearSettings` | ClassMethod `(pProduction As %String = "")` — no return type |
| `UpdateProductionModFlags` | ClassMethod `(pProduction As %String = "*")` — no return type |

`%Import` / `%Export` are the other legitimate creation route: export an XML file from one
environment, `%Import(pFileName, .pCount, .pIDsImported)` it into the next.

> **`pTargetType` is an argument with no matching property.** `%GetSetting` and `%GetMatchCriteria`
> both take `pTargetType`, but there is **no `TargetType` property** on the class. That absence is
> measured, not a missed query: asking `CompiledProperty` for `('TargetType','SettingName')` together
> returned exactly one row, `SettingName`. Do not go looking for a property to set it from.
