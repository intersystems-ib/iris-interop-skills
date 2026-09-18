# Coverage map — canonical samples the plugin still needs

> **Status: living document. Multi-day project.** Update the ledger below as items land; do not
> rewrite the wave tables — they are the audit's output and their detail is the point. This exists
> so that building a sample is *following a recipe*, not re-deriving which sample is needed and why.

## How to use this

1. **Read the two systemic caveats** at the bottom of this header before picking anything up. They
   change what a green gate means for several items.
2. **Work a wave in order.** Wave 0 first — 16 of its items are not samples at all, and several
   remove a defect that a new sample would merely sit beside.
3. **Every new sample needs four things**, or it cannot reach COVERED: a `.cls` under
   `BestPractices/examples/` that compiles (tier 2), a row in `examples/README.md` (C4), a
   resolvable `/// Rule: §N.N "…"` header (C2 — and `§` means THIS deliverable; cite external books
   with the word "section"), and at least one skill pointing at it via `${CLAUDE_PLUGIN_ROOT}/…`.
4. **Rows marked ⚠ were corrected by review.** Read §"Review corrections" before building them —
   several are built on a premise the plugin itself contradicts.
5. **Record what you closed** in the ledger, with the release it shipped in.

## Progress ledger

| Closed | Item | Shipped in |
|---|---|---|
| ✅ | 3 dangling `BusinessRuleName` in `.cls` productions (`CensoRouting`, `AdtRouting`, `FhirRouting`) — rules written | v1.14.0 |
| ✅ | 4th dangling rule in `alert-circuit-production.xml` (`Example.Alerting.RUL.AlertRouter`) — rule written | v1.14.0 |
| ✅ | **N14** — tier-1 **C8**: production settings must resolve to a shipped class or an item in the same production, over `.cls` **and** `.xml` | v1.14.0 |
| ✅ | Wave 1 **S1** — HL7 routing rule with HL7 assist + `docCategory`/`docName` (CR-5, CR-6) | v1.14.0 |
| ✅ | **N2** — duplicate §1.7/§1.8/§1.9 headings (mine renumbered to §1.11/§1.12/§1.13) | v1.14.0 |
| ✅ | **N11** — `soap-bo` `%DeleteId({ID})` → `{Payload}` | v1.14.0 |
| ✅ | `snippets()` silent overwrite on duplicate class name — now fails and names the pair | v1.14.0 |
| ✅ | tier-1 **C9**: ratchets the ungated-fence counts, after the prose figure in `CLAUDE.md` was found stale (said 33, was 34) | v1.14.2 |
| ✅ | `update_snippet_baseline()` was dead code that would have clobbered any other baseline key — now merges | v1.14.2 |
| ⬜ | **NEW (not in any wave below): the Foundation-namespace recipe in `fhir/SKILL.md` is the fence C9 caught — loose statements, so no tier compiles it.** Its class names (`HS.Util.Installer.Foundation.Install`, `HS.FHIRServer.Installer.InstallNamespace` / `InstallInstance`) were verified live against IRIS for Health 2026.1 on 2026-09-18 and are all real — but only a `.cls` in the bank would keep them that way. | — |
| ✅ | **N1** — the stale "No BPL, DTL or routing-rule example yet" paragraph. Every clause was false (1 BPL, 1 DTL, **5** rules) and issue #91 is closed | v1.15.0 |
| ✅ | **N3** — `alerting`'s inline function set was a defective fork of the gated file (bare `%Ensemble("SessionId")`, `kill …(day-1)`); replaced by a pointer + both traps named | v1.15.0 |
| ✅ | **N4** — `transformations`' `$ZSTRIP` mask. **Re-measured:** `"*-CWE"` raises `<FUNCTION>`; `"*CWE"`/`"*E"` return `""` for every input; `"*WC"` also strips **internal** whitespace (that last one was in neither skill) | v1.15.0 |
| ✅ | **N5** — `MyApp.Msg.` → `MyApp.MSG.`, **10 sites not 1**. `bpl`'s rule constraint and `business-operations`' `MessageMap` both named a class that did not exist, which matches nothing silently. Took tier 3 from 23/26 to 26/27 clean | v1.15.0 |
| ✅ | **N6** — `dicom`'s `NewStudy()` was `Quit $$$OK`: the endpoint 200s every POST and discards every study. Implemented, plus the `DICOM.MSG.StowRsReq` it needs, both now compiled | v1.15.0 |
| ✅ | **N7** — bare `[SqlProc]` wrapped in `MyApp.Bootstrap`; bare members 20 → 19 | v1.15.0 |
| ✅ | **N8** — `MyApp.Search.HL7` → `MyApp.Search.Hl7Adt` (C5 rejects a Tipo-last name; C5 never ran over snippets) | v1.15.0 |
| ✅ | **N9** — customer package name removed (5 sites) **and** the "verbatim from a running production" provenance line, per the vendor-neutral rule | v1.15.0 |
| ✅ | **N12** — all three cross-skill contradictions, each settled against the running instance: `GetValue` **does not exist** (it is `%GetValue`, 3rd arg is by-ref `pExists`, not a default); `bpl` taught the package-**qualified** rule call that cannot parse (`#5490`) and omitted `Document.`; `MessageSchemaCategory="2.5:ADT_A01"` **errors** — the category is concatenated with MSH-9, giving `2.5:ADT_A01:ADT_A01` | v1.15.0 |
| ✅ | `business-operations`' typed-SQL sketch was a loose fragment naming an unverified `$$$SqlDate`; replaced by a pointer at the gated bank file, whose `$$$Sql*` macros tier 2 does compile | v1.15.0 |
| ✅ | **N13** — the three indexed-but-uncompiled artefacts (`.xml`, `.cls.xml`, `.sh`) now carry ⚠️ on their own README rows | v1.15.0 |
| ✅ | 4 gate defects found while doing the above: a `///` prefix was split off its class and dropped; an `Include` was **always** orphaned (so `$$$Str2MsgTyp`/`$$$Sql*` fences compiled without it); an **indented** class fence was silently counted as a fragment; tier 3 left `Ens_Config.SearchTableProp` rows behind, so any SearchTable **rename** failed with `PropCollision` naming a deleted class | v1.15.0 |
| ✅ | **N15** — **tier 2b** compiles `BestPractices/external/**` with its own baseline. Surveyed first: all **19** classes compile clean today, so gating was free. Deliberately NOT added to tier 1 — **0 of 19** carry a `/// Rule:` header, so C1 would fail all of them and greening it would mean editing vendor source. Count correction: the audit said "21 classes / 1738 lines"; measured twice independently it is **19 classes / 1934 lines** | v1.15.1 |
| ✅ | **N16** — `scripts/issue_fingerprint.py` + `scripts/test_issue_fingerprint.py`, wired into the `test-hooks` CI job. **Not** a pytest: this repo's harnesses are stdlib-only so CI needs no dependencies, and matching that beat following the map's wording. The tests caught **4 real bugs** in the helper before it shipped | v1.15.1 |
| ✅ | **Wave 0 COMPLETE** (v1.15.1) | — |
| ✅ | Wave 1 **S3** — `msg-persistent-leftmost.cls` + `tdd-message-own-extent.cls`, new deliverable **§5.10**, and the **4 bank message classes that taught the shared-extent shape are fixed**. Measured: `(%Persistent, Ens.Request)` → own extent; `(Ens.Request, %Persistent)` and bare `Ens.Request` → `^Ens.MessageBodyD`. All three compile clean, so tier 2 was green on all three. Test mutation-checked: passes as shipped, fails on both wrong orders | v1.16.0 |
| ✅ | Wave 1 **S4** — `msg-persistent-child-delete-cascade.cls` + `dat-address-persistent.cls` + `tdd-delete-cascade.cls`, new deliverable **§5.11**. **The row's premise was wrong:** it said `%SerialObject` "has no such method" — measured, `%DeleteId` DOES exist on `%SerialObject`, compiles, and returns `#5753 Cannot instantiate abstract class` at runtime, which the snippet's `Do` then **discarded**. Found a 4th defect the map never listed: an unguarded trigger makes childless carriers undeletable. Test RUN and mutation-checked against all three | v1.17.0 |
| ✅ | **Class-based (non-BPL) `Ens.BusinessProcess`** — the corrections' second unproposed component type ("the whole map treats BP as BPL"). `bp-class-based-async.cls` + deliverable **§5.12**. Verified in a RUNNING production, both variants: with `pResponseRequired=0` the operation runs and returns, `OnResponse` is **never entered**, and the BP completes successfully — the reply is dropped in silence. With `1`, all four callbacks fire. Also left the container clean: a probe production from a failed first attempt had been left RUNNING and was found and stopped | v1.19.0 |
| ✅ | **Pass-through / `Ens.StreamContainer`** — the corrections' third unproposed component type, and the one S2 depends on. `production-file-passthrough.cls` + `bo-stream-container-consumer.cls` + `tdd-stream-container-rewind.cls` + deliverable **§6.10**. Confirmed first: **0 hits** for `Ens.StreamContainer` in `skills/` and 0 in the bank. Executed: `read1=[line-1] read2=[] afterRewind=[line-1]` — a second read returns "" with no error, which is how a relay writes an EMPTY output file from a run that reported success. Also gave `component-map` its **first bank pointer** (it cited zero) | v1.20.0 |
| ✅ | Wave 1 **S2** — `production-alert-circuit.cls` replaces the §7.1 `.xml`, and `alert-routing-rule.cls` now carries the real dedup conditions. **The conversion found the XML was unloadable**: both its dedup conditions used the package-qualified FunctionSet form. Compiled both ways — bare `AlreadyReportedPerSession()=1` COMPILES, `##class(...).AlreadyReportedPerSession()=1` FAILS with `<Ens>ErrParsingExpression`/`ErrInvalidToken`. Its own header told the reader to `$system.OBJ.Load()` it | v1.21.0 |
| ✅ | tier-1 **C10** — a rule's `<send target>` must resolve to an item in the production it names, and a non-empty `production=` must be shipped. Building it immediately found `routing-rule-fanout` naming `Example.Production`, which does not exist (all shipped ones are `Example.Productions.*`) | v1.21.0 |
| ✅ | Wave 1 **S5** — `dtl-hl7-symbolic-paths.cls` + `tdd-hl7-fixture-test.cls` + deliverable **§2.11**. The fixture dependency of S1/S12/S36. Measured: a DTL compiles **identically** with a correct or a nonsense symbolic path, so tier 2 is green on both. The map said a guessed name returns `""` with `$$$OK`; **measured it is subtler** — an invalid path returns `""` with an ERROR status, a valid-but-empty field returns `""` with OK, and the two-arg `GetValueAt(path)` everyone writes DISCARDS the only discriminator. Also: `ImportFromString` leaves DocType EMPTY; the component is `.IDNumber`, not `.ID` | v1.22.0 |
| ✅ | A **fourth** site of the `MessageSchemaCategory` colon-form defect — `transformations:322` — found while writing S5. v1.15.0 fixed three; this one survived | v1.22.0 |
| ✅ | **Name HL7 segments and fields, never number them** (user-requested policy). Promoted in the deliverable §2.11, `transformations` (new §"Name the field, do not number it"), `hl7-schemas`, `bpl`, `component-map`, `unit-tests` — and applied to the bank: the gated HL7 rule now compares `{MSH:MessageType.MessageCode}`, not `{MSH:9.1}`. Measured mapping table, plus three rules: you **cannot mix** (`{MSH:MessageType.1}` is invalid), names are case-insensitive, and `GetFieldNameFromNumber` is authoritative but returns **empty for repeating fields** | v1.23.0 |
| ✅ | **Wave 1 premise verification pass** — every remaining row's checkable claim measured on a live instance before building. Found **3 wrong** (`interop` says `Ens_Config.Item` is not queryable — it IS; the review correction that followed from it is void; `component-map`'s `Post(.resp,url,body)` takes no URL) and **1 stale** (S7) and **1 mis-stated arity** (S13). Confirmed S9, S10, S8. Recorded as §"Wave 1 follow-on", with a dependency-ordered execution list | v1.24.0 |
| ✅ | Wave 1 **S12** — `tdd-hl7-router-validation.cls`, the two-direction router test, RUN against a live production. **The conversion found the bank's own productions could not express the second direction:** `BadMessageHandler` named the SAME item the rule sends valid messages to, in BOTH `Hl7Intake` and `CensoIntake`. Measured before the fix: valid, unknown-type and malformed messages ALL routed to `BO.AdtOut`. After adding distinct sinks: valid → `BO.AdtOut` with no alert, both bad shapes → `BO.AdtBad` with an alert | v1.25.0 |
| ✅ | tier-1 **C11** (BadMessageHandler must not be a rule `<send>` target) and **C12** (no `--` inside an XML comment, #6301). C11 found the second collision immediately; C12 exists because I hit the `--` trap `hl7-schemas` documents and it cost a tier-2 round trip, presenting as an unrelated DTL failure | v1.25.0 |
| ✅ | Wave 1 **S6** — `utl-functionset-final.cls` + `dtl-lookup-and-functions.cls` + `tdd-dtl-function-forms.cls` + deliverable **§5.13**. All **six** call forms compiled AND run: in a DTL a built-in takes `..` and a custom function takes `##class()`; in a business RULE the same custom method takes **bare** and `##class()` fails at compile. The contexts are **opposite**. The bare form in a DTL is the dangerous one — compiles clean, `<UNDEFINED>` only when a message flows | v1.26.0 |
| ✅ | **`DependsOn` is mandatory on a DTL** — measured: same batch, no DependsOn FAILS, with it all compile. `dtl-order-to-vendor` shipped without it for releases and failed the moment an unrelated error perturbed the batch. Fixed, and tier-1 **C13** now enforces it | v1.26.0 |
| ✅ | Wave 1 **S10** — `bs-recordmap-service-subclass.cls` + deliverable **§6.11**. **Both the row AND the review correction were wrong** about #5478: measured, the ARITY is not enforced (dropping `pHint` compiles), the argument **types** are, and `pHint` by value instead of ByRef also compiles. `Ens.BusinessService` enforces nothing at all. The genuinely silent half is `##super()`: `%Dictionary.CompiledMethod.Origin` shows `RecordMap.Service.Standard` and `HL7.Service.FileService` define their OWN `OnInit`, so an override without `##super()` replaces real setup and compiles clean | v1.27.0 |
| ✅ | tier-1 **C14** — an `OnInit` override on a prebuilt `EnsLib.*` host must call `##super()`. It fired on the BASELINE: `ch03_cda/soap-messagebody-hl7-operation.cls` had shipped overriding `EnsLib.HL7.Operation.SOAPOperation.OnInit` without it, and that class defines its own `OnInit` (Origin = itself). Fixed | v1.27.0 |
| ✅ | Wave 1 **S11** — `bo-rest-outbound.cls` + deliverable **§6.12**. **All three of the row's premises were wrong, and a fourth error surfaced:** `EnsLib.REST.OutboundAdapter` **does not exist** — named in `component-map`, `soap-bo` and `business-operations`, twice as the first choice. Measured: every REST outbound host (`EnsLib.REST.Operation`, `.GenericOperation`, `EnsLib.HTTP.GenericOperation`) declares `EnsLib.HTTP.OutboundAdapter`. Also: `Post` takes **no URL** (`PostURL` takes it first); narrowing the `Adapter` property gives **no** compile-time checking (all four variants compile); and a non-2xx **does** fail the `%Status` — so the risk is a caller discarding it, not a lenient adapter | v1.28.0 |
| ✅ | Wave 1 **S9** — `sql-bo-batch-transaction.cls` + deliverable **§6.13**. Premise confirmed (no `StartTransaction`), and one refinement: `SetAutoCommit`/`Commit`/`Rollback` all originate in `EnsLib.SQL.Common` (**portable**) while the `Transact(type)` I found in the verification pass originates in `EnsLib.SQL.CommonJ` — **JDBC only**. `business-operations` said the API was "whole"; narrowed to "portable" | v1.29.0 |
| ✅ | Wave 1 **S7**, RE-SCOPED per V4 — the row contrasted a working `NormalizeKey` against "the tier-3-green broken one", which wave-0 N4 fixed in v1.15.0, and v1.26.0 then shipped the working version. What was still missing was a lookup against an **actually-loaded table**: `tdd-lookup-normalize.cls`, and §5.13 extended. Measured: normalised key → `DIA` with `exists=1`; raw key → `""` with `exists=0`; and via the FunctionSet the raw key returns the **DEFAULT** (`UNKNOWN`) — a plausible code, not an error. Also pinned: a genuinely empty `DataValue` returns `""` with `exists=1`, so only `exists` separates a miss from an empty value | v1.30.0 |
| ✅ | Wave 1 **S15** — `drift-report-disk-vs-namespace.cls` + deliverable **§1.14**. Premise confirmed EXACTLY: `Continue:$Extract(k, 1, n) '= (pPkg _ ".")` gives `#1012: Expected EOL or spaces` and the unspaced form compiles — a postconditional ends at the first space. Both lies executed: unmounted `src` → `ONLY IN IRIS: <class>`; wrong prefix → **`in sync`** having compared nothing, so an empty comparison and a clean one are indistinguishable. It had lived as **bare `ClassMethod`s** no tier compiled — bare fences 19 → 18 | v1.31.0 |
| ✅ | Wave 1 **S13** — `unittest-sqlproc-result-reader.cls` + deliverable **§5.14**. Row said "3-arg `DebugRunTestCase`": measured it takes **five** and **persists nothing at all** — no rows in `%UnitTest_Result.*`, `^UnitTest.Result` not even defined. `RunTest(suite, qspec)` with `^UnitTestRoot` does. The defect reproduced EXACTLY: every method gets a trailing `LogMessage` assert with Status=1, so an assert-scanner returns **`passed=2 failed=0`** for a case whose own Status is 0 — and **`passed=0 failed=0`** when nothing ran. Read `TestMethod.Status` | v1.32.0 |
| ✅ | Wave 1 **S8** — `production-preflight-validator.cls` + deliverable **§1.15**, buildable as originally written once V2 established `Ens_Config.Item` IS queryable. All three defects measured: it returned `OK` from three not-found paths; it matched the generic router class only, never the HL7 one; and `TOP 1` picked **`Ens.Alert`** in BOTH gated productions — including the HL7 one, where the real router exists and is a different class. Verdict is now three-valued and `OK` carries its counts | v1.33.0 |
| ✅ | **The corrected validator found a real defect on its first run:** FIVE of six gated productions carried an `Ens.Alert` item with **no** `BusinessRuleName` — which captures every `Ens.AlertRequest` and drops it, strictly worse than omitting the item. All five removed; tier-1 **C15** now refuses it | v1.33.0 |
| ✅ | Wave 1 **S16** — `tdd-destination-assert.cls`, the API that makes **CR-13 performable**. The row said `interop` and `bpl` contradicted each other about `Ens_Config.Item` and "nothing compiles either"; V2 settled it (the table IS queryable) and this ships the read. Both routes asserted to agree. Three distinctions pinned, all executed: `Target` is half the destination (Host vs Adapter, silent when wrong); an **absent** setting reads identically to an empty one, so found/not-found is the signal; and the read needs a REGISTERED production, so zero items means "I read nothing". `NameDestination()` is public so a reviewer can perform CR-13 in one call | v1.34.0 |
| ✅ | Wave 1 **S14** — `oauth2-server-validate-ldap.cls`, a **subclass** of `%OAuth2.Server.Validate`, replacing the 207-line `.cls.xml` copy that no tier compiled. The row's `%syLDAP` worry is void: `Include %syLDAP` **alone** resolves in an application namespace (`$$$LDAPSUCCESS`=**0** — so `If tErr` is the error test — `$$$LDAPSCOPESUBTREE`=2, `$$$LDAPPORT`=389, `$$$LDAPOPTXTLSCACERTFILE`=24578), and all **13** `%SYS.LDAP` methods called exist with the arities used. The copy's real cost, measured: it overrode `SupportedClaims` with `quit ""` — **6 claims → 0** — and declared a **five**-formal `ValidateUser` against the vendor's six. That stale signature compiles clean as a subclass, raises nothing when the server calls it with six arguments, and returns a plausible boolean; `use2fa` can then only ever read 0, with a positive control (a 6-formal override setting it to 1) proving the flag CAN carry. Also found by reading the vendor source: `password=""` means "already authenticated, skip the check" upstream and "**bind anonymously and succeed**" against LDAP, so the same convention inverts. **The bank's last `.cls.xml` is gone — C8 has no XML left to inspect** | v1.35.0 |
| ✅ | **Wave 1 COMPLETE** (v1.35.0) | — |
| ✅ | Wave 2 **S24** — `tdd-convertdatetime-cheatsheet.cls` + deliverable **§5.16**. The five-row "Verified conversions" table had nothing executing it; **all five rows are exactly right** and now have an oracle. What the table did not say is the shape of failure: `ConvertDateTime` validates the field RANGES and never the CALENDAR, so `31/02/1958` → `1958-02-31`, `29/02/2023` → `2023-02-29` and `31/04/1958` → `1958-04-31` are **reformatted into well-formed non-dates**, while `32/01`, `31/13`, `00/01`, `99/99/9999` and free text are **returned unchanged** — two silent modes with different signatures, and the first survives a regex. Forced a correction to `transformations`: the "raw ObjectScript equivalent" is **not equivalent** — `$ZDATEH` refuses 31 February with `<ILLEGAL VALUE>` where `ConvertDateTime` invents a date. Also pinned: `%Q` is the default for BOTH format arguments, so `ConvertDateTime(x)` returns `x` unchanged. Suite RUN (6/6), mutation-checked five ways, read back with the v1.37.0-fixed reader | v1.38.0 |
| ✅ | Wave 2 **S29** — `msg-maxlen-boundaries.cls` + `tdd-maxlen-truncation.cls` + deliverable **§5.15**. The row asked whether a bare `%String` truncates or rejects; **it rejects on every path and nothing is silent** (`%Save` `#7201`, `%ValidateObject` `#7201`, SQL `INSERT` `SQLCODE=-104`, and the in-memory value keeps all 100 chars). `MAXLEN=""` put under a compiler for the first time — it was the prescribed mitigation with **zero** occurrences in the bank. Found a **second ceiling** no prose had noticed: 3,600,000 chars save fine, but at `$$$MaxStringLength` (3,641,144) `%ValidateObject` says **OK** while `%Save` fails `#5002 <MAXSTRING>` inside generated `%SaveData` — the validator and the saver disagree. Suite RUN (8/8) and mutation-checked five ways, each reddening exactly its own test | v1.37.0 |
| ✅ | **The S13 reader shipped a documented call that could not match** — found by using it on S29's run. `Verdict('Example.Tests.X')` is the form its own doc comment prescribed, and the ID is `<instance>||<suite>||<case>`, so a bare class name is a prefix of nothing: it answered "NO RESULTS … nothing was persisted" for a run that had just passed **8 of 8**. Worse than an error — it sends you to fix a working runner. Also found: `MAX(ID)` picks the wrong run because the ID is a **string** (`'9||…'` > `'13||…'`), and results **accumulate**, so an unscoped reader summed five runs as `methods=40` with a reverted mutation still red. Reader now matches `TestCase.Name`, scopes to `CAST($PIECE(ID,'||',1) AS INTEGER)` DESC, and is positive-controlled (mutated → `FAILED: … (1 of 8)`, shipped → `PASSED 8/8`). §5.14 extended | v1.37.0 |
| ✅ | **Wave 2 premise verification pass** — all **13** rows measured before building any. Found **3 needing correction** (S17's `SaveToClass` is on `EnsLib.RecordMap.Model.Record` with arity 0, not on the RecordMap class, and `GenerateObject` is on a third class; S29's "silently truncates" is **wrong on both halves** — a bare `%String` REJECTS with `#7201` on `%Save`, `%ValidateObject` and SQL `INSERT`, and keeps the full value in memory; S24 confirmed but worse — `ConvertDateTime` reformats `29/02/2023` into `2023-02-29`, an invalid date made to look well-formed) and **10 confirmed exact**, with the measured names recorded so no row is re-derived. Recorded as §"Wave 2 follow-on" with a dependency-ordered list. **The S29 correction was applied in the same release**, at `messages` (2 sites) and `soap-bo` (1) — and deliberately NOT at `business-services:368`, which describes a different mechanism (a RecordMap separator defaulting to `$char(32)`) and is right as written | v1.36.0 |
| ✅ | **Custom inbound adapter** (the corrections' "belongs in wave 1" item, proposed by no wave row) — `adp-scheduler-inbound-adapter.cls` + `bs-scheduled-cron.cls` + `tdd-inbound-adapter-dispatch.cls` under §5.2. Confirmed first: `Ens.InboundAdapter` had **0 hits** in `skills/` and 0 in the bank. Adapter executed and mutation-checked — dispatch removed → `dispatched=0` with `sc=OK`; schedule check removed → fires always. Found on the way: an `Ens.BusinessService` subclass **cannot be `%New()`d** (returns `""`, silently), and `BusinessHost` accepts a non-BS stand-in, which is what makes the adapter testable at all | v1.18.0 |
| ⬜ | everything else below | — |

**Bank as of v1.15.0: 47 compile-gated classes, 50 artefacts. Tier 1: 9 checks. Tier 3: 29 fences
staged, 28 clean (1 illustrative placeholder), plus 19 bare members and 33 loose fragments that no
tier compiles — the last two ratcheted by C9 rather than described in prose. Tier 2b: 19/19 external. Tier 1 is **10** checks as of v1.21.0.**
**Wave 0 is complete.**

## Two systemic caveats — read before planning from any wave

**1. Tier 2 compiles; it never runs.** Every `%UnitTest` sample proposed below gates its API names,
superclass and assertion *shape* — not its outcome. Where a sample's whole value is the executed
assertion, say so in its header and pair it with a release-step run. The one gated test that has
been *run and mutation-checked* is `ch05_bpl_dtl/tdd-testproduction-dtl.cls`; copy its header
convention.

**2. This map audits missing SAMPLES, not missing FACTS.** It cannot surface a fact the skills never
raise, because there is no gap for an auditor to find. Worked example from the same week: on IRIS
for Health *every* interop-enabled production needs a **Foundation namespace** (AFNS) — the plugin
said nothing about it anywhere, and no sample-coverage audit would have found that. When a wave item
feels thin, ask what the skill fails to *say*, not only what it fails to *show*.

## Provenance

Produced by a 12-agent audit (10 auditors × 2 skills, one synthesiser, one adversarial critic) over
all 20 skills, then corrected by the critic and spot-verified by hand against the repo. Claims
independently re-checked before this was committed: `[SqlProc]` in zero compiled artefacts; `##super`
in exactly one example (and that one teaches the exemption); neither `FunctionSet` marked `[Final]`;
pointer coverage 29/43 at audit time; 3 of 4 dangling `BusinessRuleName` in `.cls`. The first
synthesis ran on a truncated payload (6 of 20 skills) and was re-run from cache — this document is
the full-coverage version.

---

## The waves

## Verdict

The bank is **43 compile-gated classes across 9 chapters, cited by 14 of 20 skills** — and six skills (`component-map`, `conformance-review`, `dicom`, `interop`, `lookup-tables`, `report-issue`) cite **zero** bank examples, while four more cite exactly one. Measured against what the skills actually prescribe, coverage is thinner than the file count suggests: **59 distinct canonical samples are missing or ungated**, 16 of them P0. The shape of the gap is consistent and is the shape this repo's own history warns about — the gate is green on the wrong things. Four of the five gated productions set `BusinessRuleName` to a rule class **that does not exist anywhere in the repo** (`Example.RUL.AdtRouting`, `Example.RUL.CensoRouting`, `Example.RUL.FhirRouting`, `Example.Alerting.RUL.AlertRouter`; only `Example.RUL.OrderRouting` ships) and tier 2 compiles all four clean, because a setting value is a string. All four message classes in the bank extend `Ens.Request` alone — the exact form the `messages` skill calls necessary-but-not-sufficient — so the vetted model teaches the shared-extent shape. Zero bank artefacts contain `SearchTableClass`, `ResponseTimeout`, `docCategory`, `..Lookup(`, `TSTART`, or `MAXLEN = ""`; `FailureTimeout` appears once and only in the one file tier 2 skips; `##super` appears once and only in the comment explaining when you *don't* need it. The two largest security/alerting artefacts (§7.1 alert circuit, §11.5 OAuth+LDAP, 207 lines of auth code) are indexed in the README and compiled by nothing, because `validate_examples.py:448` skips every non-`.cls`. **Wave 0 below is free and should ship first: nine of those items are text or rename fixes, not samples at all.**

---

## Wave 0 — the right answer is NOT a new sample (16 items, ~1 day)

These cost nothing to build and several of them remove a defect that a new sample would merely sit next to.

| # | Action | Why it beats a sample |
|---|---|---|
| N1 | Delete/replace the "**No BPL, DTL or routing-rule example yet**" paragraph in `examples/README.md` | It is stale — §5.6/§5.7/§5.8 rows exist 40 lines above it. A reader checking COVERED condition 2 is told the sample does not exist. |
| N2 | Dedupe deliverable headings **§1.7/§1.8/§1.9** (lines 142/150/158 vs 175/195/211) | Tier-1 C2 passes either way; a human cannot tell which section a `/// Rule: §1.7` header means. Blocks clean anchoring for three wave-2 samples. |
| N3 | Cut `alerting/SKILL.md:64-93` to a pointer at the gated `alert-dedup-functionset.cls` | The fence is a **stale fork** that compiles clean in tier 3 (`MyApp.UTL.AlertFilterFunctions` is in `snippets_baseline.json`) and carries two defects the bank version fixed: bare `%Ensemble("SessionId")` → `<UNDEFINED>` → **alert lost**, and a `kill …(day-1)` that leaks every quiet day for ever. No gate compares a snippet to its bank counterpart. |
| N4 | Fix `transformations/SKILL.md:157-160` `MyApp.UTL.FunctionSet` `$ZSTRIP` mask | Tier-3 green on a helper that (per `lookup-tables:81-90`, measured on 2026.1) raises `<FUNCTION>` on every message or returns `""` for every input. Masks are validated at runtime; the compile gate can never catch this. Pairs with S7. |
| N5 | Fix placeholder casing in `business-services/SKILL.md:717-731` (`MyApp.Msg.*` → `MyApp.MSG.*`) | The adapterless-BS fence is already a complete class; the casing makes tier 3 excuse it as a #5373 placeholder dependency instead of compiling it. **Cheapest coverage win in the repo.** |
| N6 | Complete the `DICOM.BS.RESTService` fence (`dicom/SKILL.md:171-192`) | Already inside tier 3 and green — but it is a hollowed copy whose `NewStudy()` is `Quit $$$OK`. Copy it and the endpoint 200s every POST and discards every study. |
| N7 | Wrap `interop/SKILL.md:228` bare `[SqlProc]` ClassMethod in a host class | Moves one of the 20 ungated bare members inside tier 3 with no new bank file. |
| N8 | Rename snippet `MyApp.Search.HL7` (Tipo-last) | C5 would reject it in the bank; tier 3 runs no naming check over snippets, so the gate that would catch it never sees it. |
| N9 ⚠ | Rename snippet `REDSA.RecordMap.Ifa` → `Example.RecordMap.Invoice` | Customer-identifying package name now recorded in `snippets_baseline.json`, against CLAUDE.md's vendor-neutral rule. |
| N10 | **No action — auditor correction.** `fhir/SKILL.md:56` already cites `ch04_fhir/production-fhir-facade.cls` | The `fhir` P0 ("skill points at no bank example") is already closed. The remaining FHIR gap is the dangling rule class (S34). |
| N11 | Fix `soap-bo/SKILL.md:78-83` — `%DeleteId({ID})` → `%DeleteId({Address})` | `{ID}` is the carrier row's id, not the payload reference: it deletes an unrelated row. The gated `messages` fence has it right. The ungated copy is the wrong one. |
| N12 ⚠ | Reconcile the three cross-skill API contradictions by hand | `component-map:44` `%GetValue(tbl,v)` vs `lookup-tables:25` `GetValue(t,k,.v)`; `bpl:121` bare-name FunctionSet call vs `transformations:276` qualified; `business-services:648` `Version+MessageType` vs the gated production's bare `2.5`. BANNED-token enforcement iterates **bank artefacts only**, so wrong prose survives a clean tier 1 forever. |
| N13 ⚠ | At the §7.1 and §11.5 README rows, **write the gap at the gate** (CLAUDE.md #151) | Both are non-`.cls` and compiled by nothing. Until S2/S14 land, the index must not read as coverage it does not have. |
| N14 | Add a tier-1 check: production `BusinessRuleName` / `TargetConfigNames` / `DuplexTargetConfigName` must resolve to a shipped class or to one of the production's own item names | Worth more than any single sample here: it catches all **four** dangling rule names at once, and the DICOM snapshot's broken duplex return path. |
| N15 | Extend tier 2 over `BestPractices/external/**` with its own baseline (or state the non-gating at the `dicom` pointer) | 21 classes / 1738 lines that `dicom` calls "the canonical reference for every pattern here", compiled by no tier and frozen read-only. It has already drifted twice (deprecated JavaGateway item; a duplex target naming an item that does not exist). |
| N16 | Put the `report-issue` helpers in `scripts/` + a pytest, not in the bank | `.sh`/`.py` can never satisfy COVERED (tier 2 is `.cls`-only, `examples_baseline.json` holds class names). A bank row for them would be indexed non-coverage. |

---

## Wave 1 — the silent-failure set (16 samples / 22 files, all P0)

Everything here has `silent_failure: true`. The failure mode in every case is a component that starts green and does nothing, or a check that returns OK having looked at nothing.

| # | File(s) | Skills served | Pins down | CI | Depends on |
|---|---|---|---|---|---|
| S1 | `ch02_hl7v2/routing-rule-hl7-adt.cls` | component-map, bpl, hl7-schemas, conformance-review (CR-5/CR-6) | `EnsLib.HL7.MsgRouter.RuleAssist` + `…RoutingEngine` pairing, `docCategory`/`docName` as accepted constraint names, `Document.{MSH:9.1}` surviving the `evaluateRuleDefinition` generator. **Zero `docCategory` hits in the bank**; the only gated rule is the generic-assist one whose own header says HL7 needs the other pair. Silent: wrong assist matches nothing, router reports no error, messages go nowhere. Closes the dangling `production-hl7-intake.cls:48`. | ✅ | — |
| S2 | `ch07_alerting/production-alert-circuit.cls` + `ch07_alerting/alert-routing-rule.cls` | alerting, component-map, conformance-review (CR-3) | Converts the §7.1 XML into the gate. Item name literally `Ens.Alert`, sink BO `MessageMap` on `Ens.AlertRequest`, `AlertOnError=1` on runtime items / `0` on the alert path, finite `FailureTimeout`. The rule half settles bare-vs-`##class()` FunctionSet calls in rule conditions — **#5490 is a compile-time generator failure, so the gate can adjudicate it**, and today the plugin ships both spellings. Silent: an empty/non-matching alert rule routes nothing; the production is green precisely when it can no longer tell you anything. | ✅ | reuses gated `Demo.FilterAlerts.FunctionSet` |
| S3 | `ch05_bpl_dtl/msg-persistent-leftmost.cls` + `tdd-message-own-extent.cls` | messages, interop | `Extends (%Persistent, Ens.Request)` — leftmost wins. The wrong order compiles, projects SQL and reads properties back correctly, so a compile certifies nothing; the test reads `DataLocation` and asserts `^Example.MSG.<Name>D`, not `^Ens.MessageBodyD`. **All 4 bank message classes are the wrong shape today** (verified), one with a header defending it. | ✅ | ⚠️ needs a message-design heading |
| S4 ⚠ | `ch05_bpl_dtl/msg-persistent-child-delete-cascade.cls` + `dat-address-persistent.cls` + `tdd-delete-cascade.cls` | messages, soap-bo, conformance-review (CR-11) | `%DeleteId` on a **%Persistent** child (the gated fence pair compiles a trigger calling `%DeleteId` on a `%SerialObject`, which has no such method), `{Address}` trigger-field spelling, `Foreach = row/object`. Silent: `Ens.Util.Tasks.Purge` removes the header, child rows accumulate "with no error and nothing in the Event Log". Also exposes `validate_examples.py:549` keying snippets by class name — `MyApp.MSG.PersonReq` is defined twice and one is silently overwritten. | ✅ | ⚠️ message-design heading; N11 |
| S5 | `ch02_hl7v2/dtl-hl7-symbolic-paths.cls` + `ch02_hl7v2/tdd-hl7-fixture-test.cls` | transformations, component-map, tdd, hl7-schemas | Symbolic HL7 field paths under `sourceDocType='2.5:ADT_A01'`: a guessed name "returns `""` with `$$$OK`… the assertion passes on the empty string". The test carries the **negative control** (the plausible CamelCase guess must return `""`) plus `ImportFromString` as a *classmethod*, `$Char(13)` separators, DocType assigned after import. The bank's only DTL is object→object in an HL7-first plugin. | ✅ stock 2.5 schemas | — (is itself the fixture dependency of S1, S12, S36) |
| S6 | `ch05_bpl_dtl/dtl-lookup-and-functions.cls` + `utl-functionset-final.cls` | transformations, lookup-tables, component-map, bpl | `..Func()` vs bare — "the single most expensive one-character mistake in a DTL", and the skill itself says a compile-only gate cannot distinguish them: only a test that calls `Transform()` can. Also `..Lookup(…,default)` returning the default rather than `""`, the qualified form for custom functions, and `[Final]` (**both gated FunctionSets mark nothing Final**, contradicting the rule the skill quotes). | ✅ test seeds its own rows in `OnBeforeAllTests` | anchors at existing §5.7 |
| S7 | `ch05_bpl_dtl/lookup-normalize-functionset.cls` (+ test) | lookup-tables, transformations | The working `NormalizeKey` against the tier-3-**green** broken one. A silent empty key makes every `..Lookup()` miss, and with a `""` default every valid code either throws `InvalidDieta` or ships empty downstream. | ✅ compiles; assertion needs a run | N4; ⚠️ **deliverable has zero lookup-table content** |
| S8 ⚠ | `ch01_production/production-preflight-validator.cls` (+ positive control) | bpl, production-lifecycle | The plugin's own pre-restart gate, which today **returns "OK" from three not-found paths** and whose router `SELECT` matches `EnsLib.MsgRouter.RoutingEngine` only (never an HL7 router) with a `TOP 1` that can pick `Ens.Alert`. Embedded `&sql` makes `Ens_Config.Item` and its columns compile-verified. Ship with a known-bad production that must return ISSUES before an OK is believed. | ✅ | ⚠️ new heading |
| S9 ⚠ | `ch06_adapters/sql-bo-batch-transaction.cls` | business-operations, bpl | `SetAutoCommit(0)` **is** the transaction start (there is no `StartTransaction` — a method these skills prescribed and that did not exist), restore-after-Catch guarded by a flag set only on success, and not overwriting your `%Status` with the rollback's. Silent: a `Quit` leaves the transaction open on a `StayConnected` connection and the next message inherits it. Zero `TSTART`/autocommit artefacts in the bank. | ✅ compiles without a DSN | author from a `%Dictionary.CompiledMethod` read |
| S10 ⚠ | `ch06_adapters/bs-recordmap-service-subclass.cls` | business-services, conformance-review (CR-14) | `##super()` **first** in `OnInit` on a real prebuilt host, and the 3-arg `OnProcessInput` (#5478, compile-enforced; 8 of 18 students hit it). The bank's single `##super` is a comment explaining the case where it is *not* needed. Also adjudicates whether gated `Demo.Vendor.BO.AcceptMessage` is a real CR-14 violation or a false positive of the prescan regex. | ✅ | — |
| S11 | `ch06_adapters/bo-rest-outbound.cls` | component-map, business-operations | `..Adapter.Post(.resp,url,body)` arity against the URL-as-setting shape, the **narrowing** `Property Adapter As EnsLib.HTTP.OutboundAdapter` (without it the call is late-bound — proved by gated `Demo.SAML.BO.SoapClient` compiling clean on three adapter members that do not exist on its declared type), and the non-2xx → fail-the-`%Status` path. Silent: 4xx/5xx with an OK `%Status` marks the message Completed while the far end rejected it. | ✅ | ⚠️ needs §6.10 |
| S12 | `ch02_hl7v2/tdd-hl7-router-validation.cls` | hl7-schemas, tdd | The two-direction assertion: a real message routes **and** a malformed one reaches the `BadMessageHandler`. Case 1 alone "passes on a router that validates nothing" — the plugin's signature defect, in the plugin's own test layer. | ⚠️ compiles; CI does not run it | S5 fixture; already-gated `Example.Productions.Hl7Intake` |
| S13 | `ch05_bpl_dtl/unittest-sqlproc-result-reader.cls` | unit-tests, conformance-review (CR-7) | The `$LISTGET` **method-node** reader against the assert-scanning sibling that reported `passed=2 failed=0` for a class %UnitTest printed `**FAILED**` for — plus the 3-arg `DebugRunTestCase` and a legal qualifier string. Ship with the CR-7 "legacy fallback, prefer `iris_test`" banner so a bank file is not read as a recommendation. | ✅ trivial | — |
| S14 ⚠ | `ch11_security/oauth2-server-validate-ldap.cls` (replacing the `.cls.xml`) | security | Puts **207 lines of auth code** under a compiler for the first time: 3 `%syLDAP` macros, ~10 `%SYS.LDAP` classmethod names/arities, `%OAuth2.Server.Properties` types. Flags two things the header does not: `ValidateClient` returns 1 unconditionally (**any** client secret accepted, tokens issue, nothing logged), and it is a *copy* of `%OAuth2.Server.Validate` (re-patch on every upgrade) where the skill prescribes a *subclass*. | ⚠️ **VERIFY FIRST** — `IncludeCode %syLDAP,%syLDAPFunc,%sySite` may not resolve outside `%SYS`. If it does not, declare non-coverage; do not ship it ungated. | — |
| S15 | `ch01_production/drift-report-disk-vs-namespace.cls` | production-lifecycle | The end-of-every-build check, as a compilation unit — its earlier form shipped **broken** (`#1012` on `Continue:…`) while the bank stayed clean. Both directions: an unmounted `src` reports every class ONLY IN IRIS; a wrong package prefix reports `in sync` having compared nothing. Say at the file that the `%ExecDirect` string is outside the compiler's reach. | ✅ | ⚠️ new heading |
| S16 ⚠ | `ch05_bpl_dtl/tdd-destination-assert.cls` | conformance-review (CR-13), tdd | The one API that makes CR-13 performable ("read, not assumed") — where `interop:176` says `Ens_Config.Item` is **not** queryable (SQLCODE -30) and `bpl:142` queries it. One of them is wrong and nothing compiles either. Assert a file BO's `FilePath` on an already-baselined production, so no external DB is needed. | ✅ | shares the settings-read API with S23 — build together |

**Wave 1 totals: 16 samples, 22 files. CI-blocked: 1 (S14, pending include-resolution check). Heading-blocked: 6 (S3, S4, S7, S8, S11, S15).**

---

## Wave 2 — P1 silent failures, core spine (13 samples)

| # | File(s) | Skills | Pins down | CI |
|---|---|---|---|---|
| S17 | `ch01_production/recordmap-generate-bootstrap.cls` | business-services, interop | `[SqlProc]` on the method (missing → `-149 <PRIVATE METHOD>`, "does not look like one"), `%String` return not `%Status` (a returned `%Status` is lost in HTTP CodeMode — failure indistinguishable from success), `SaveToClass`+`GenerateObject` **atomic in one method** (split → "GenerateObject OK" green with `GetObject` unwritten), `"\x0a"` terminator, and the verified `SELECT Example_UTL.Bootstrap_…` projection spelling. `SqlProc` appears **51 times across 11 skills and in zero compiled artefacts**. | ✅ |
| S18 | `ch01_production/tdd-recordmap-getobject-encoding.cls` | business-services, tdd | `GetObject` on the **map** class not `.Record` (wrong one raises the same `<METHOD DOES NOT EXIST>` and sends you chasing the wrong cause) and `CharEncoding="UTF-8"` on the test stream (default Native returns `?gel` with `$$$OK`; the obvious `$ZCVT` repair double-encodes a correct file). Use `$CLASSMETHOD` + a `%Dictionary.CompiledMethod` existence assert so it stages before the generator has run. | ✅ (dep S17) |
| S19 | **extend** `ch02_hl7v2/production-hl7-intake.cls` + `searchtable-hl7-adt.cls` + `tdd-searchtable-rows-landed.cls` | message-search-debug, component-map | "A search table indexes nothing until it is assigned" — `SearchTableClass`, `Target="Host"`, on service *and* operation, never on a router. **Zero `SearchTableClass` in the bank.** The test is the positive control separating "no data" from "not indexed", and pins the `p.PropId … AND p.ClassExtent` join (the `p.ID = st.PropId` form compiles, returns zero, and reads as missing data). Silent: a `PropId` query returning zero reads as "that patient was never here". | ✅ (⚠️ §12.6 needed for the standalone files; the two extra `<Setting>` lines need nothing) |
| S20 ⚠ | `ch02_hl7v2/production-hl7-mllp.cls` | component-map, bpl, alerting | MLLP Host/Adapter split, a literal `ReplyCodeActions` override (default leaves application NACKs as suspended messages that "look like errors but aren't"), a **finite** `FailureTimeout` (default `-1` = infinite retries; the bank's only `FailureTimeout` is in the file tier 2 skips) and `ResponseTimeout` (0 hits in the bank) with BO < BP ordering. | ✅ (⚠️ N2 first) |
| S21 | `ch05_bpl_dtl/bpl-flow-sync-aggregate.cls` | bpl | `<flow>`/`<sync>` pairing and where aggregation reads responses — the shape `bpl:75` recommends and `bpl:318` forbids improvising, with no template anywhere. Silent: an async `<call>` never awaited lets the process reach its end activity and complete **green** with responses unprocessed. | ✅ |
| S22 ⚠ | `ch01_production/production-lifecycle-helper.cls` (restart + recovery ladder merged) | production-lifecycle | The wait-for-Running loop **attached to the call** (`StartProduction` returns before Running) and the ladder order: status first, classify the refusal, head-check the class, `Recover` vs `Clean` vs stop-that-name. Silent: `action=recover` answers `{"state":"Running","success":true}` on a Suspended production. 105 start refusals across 18/18 students. | ✅ — but method existence is **not** compile-checked (`IDKeyExists()` precedent); verify each against `%Dictionary.CompiledMethod` |
| S23 | `ch01_production/default-settings-audit.cls` | interop, production-lifecycle | `Ens.Config.DefaultSettings` class/property names + an orphan report: every SDS row whose `ItemName`/`HostClassName` matches no item in the production. The archetypal never-read setting. The current verification is "confirm it shows **blue** in the portal" — a colour, in a UI, for a headless plugin. | ✅ §1.4 exists; precedent `credentials-export-reimport.cls` |
| S24 | `ch05_bpl_dtl/tdd-convertdatetime-cheatsheet.cls` | transformations | The five-row "Verified conversions" table, which has nothing behind it. A value that does not match `in` is **returned unchanged**, so `31/02/1958` becomes `1958-02-31` and free text passes through to fail at the JDBC bind, far from the DTL that caused it. This is the oracle that catches the next `ConvertDateTimeToUTC`-shaped prose error. | ✅ trivial |
| S25 | `ch05_bpl_dtl/lookup-bootstrap-sqlproc.cls` (+ accessor method) | lookup-tables, component-map | Embedded `&sql` makes `Ens_Util.LookupTable (TableName, KeyName, DataValue)` compile-verified, and the file carries the transaction bracket the skill prescribes at `:258` and its own snippet omits — during a non-transactional reload every lookup returns `""` with no error. The accessor method settles the three-way contradiction (`GetValue` 3-arg byref / `%GetValue` 2-arg / `FunctionSet.Lookup`). | ✅ (⚠️ lookup heading) |
| S26 | `ch06_adapters/bo-local-object-save.cls` (+ persistent target) | business-operations, component-map | The shape `business-operations` recommends most strongly ("the cleanest BO has no adapter at all") and that no BO in the bank demonstrates — all five carry an adapter. No `Parameter ADAPTER`, MessageMap dispatch, and the `%Status` from `%Save()` **returned, not discarded**. Silent: unchecked save, message Completed, row never written. | ✅ trivial |
| S27 | `ch05_bpl_dtl/tdd-fixture-cleanup-onafteralltests.cls` (fold into S28 if built together) | tdd | Exact `OnBeforeAllTests`/`OnAfterAllTests` names **and signatures**: a misspelled or mis-signatured lifecycle callback compiles and is simply never invoked — the wrong-target setting, transposed to a callback. Cleanup never runs; the next run asserts against stale rows and goes green over them. The bank's only test class has neither callback. | ✅ |
| S28 | `ch05_bpl_dtl/tdd-eventlog-integration-test.cls` | tdd | The shape of the array `GetEventLog` fills. Every skeleton bounds its loop with `For i=1:1:$G(Log)`; if the top node is not the count the body never executes — which, written as an absence assert ("no error was logged"), passes vacuously. | ✅ compiles; CI does not run it |
| S29 | `ch05_bpl_dtl/tdd-maxlen-truncation.cls` | messages, soap-bo | Settles whether a bare `%String` **silently truncates** on `%Save` (asserted twice, in two skills) or rejects with `#7201`. If the run contradicts the skills, **the skills change** — that is the value. Zero `MAXLEN = ""` in the bank, so the prescribed mitigation appears in no compiled artefact. | ✅ (⚠️ no MAXLEN heading) |

---

## Wave 3 — P1 silent failures, protocol & platform periphery (12 samples)

| # | File(s) | Skills | Pins down | CI |
|---|---|---|---|---|
| S30 | `ch02_hl7v2/schema-bootstrap-sqlproc.cls` (custom category carried in `XData`) | hl7-schemas | `EnsLib.HL7.SchemaXML.Import/.Export` and the `^EnsHL7.Schema`/`^EnsHL7.Description` kill pair — the **only** headless schema path, and its plausible neighbour `EnsLib.HL7.Util.SchemaDocument` is recorded as not existing. `RemoveSchema` is the only guard against a re-import that overwrites without cleaning (a renamed segment lingers; the category *looks* re-imported). Carrying the category XML as XData puts the grammar under a compiler that a `.xml` file could never reach. | ✅ — the fence's hardcoded `C:\` path must become a parameter (C6 BANNED) |
| S31 | `ch02_hl7v2/tdd-hl7-schema-registration.cls` | hl7-schemas, tdd | `ResolveSegNameToStructure(cat,"","ZAL",.sc)` / `ResolveSchemaTypeToDocType` arity, and `ZAL:1` vs the group-prefixed path (a DTL `<assign>` that silently yields empty). Forces a superclass declaration — the fence tells the reader to paste into `%UnitTest.TestCase`, which the plugin's own non-negotiable rule forbids. | ✅ (dep S30) |
| S32 | `ch12_monitoring/resend-edit-and-resend.cls` | message-search-debug | `ResendDuplicatedMessage` signature and the clone-then-`pNewBody` order — `docs_introspect` returns `{"methods":[]}` for it, so a compile is the only check available. Silent: a plain resend **shares** the original body, so editing it to "fix" the message rewrites what the original said; the trace stays coherent and the audit trail now lies. | ✅ (⚠️ chapter 12 ends at §12.5) |
| S33 | `ch07_alerting/tdd-alert-dedup.cls` + `ch07_alerting/bo-fail-on-demand.cls` | alerting | Replaces a 6-step manual procedure that needs an SMTP server and a human mailbox. First-call-0 / second-1 / **new-bucket-0** (the positive control), and `AlreadyReportedPerSession()` returning 0 rather than throwing `<UNDEFINED>` outside a host process. The fixture BO pins that an `OnMessage` **returning** `$$$ERROR` is what makes `AlertOnError` emit `Ens.AlertRequest`. Silent: an inverted guard suppresses every alert, and a suppressed alert stream is indistinguishable from a healthy production. | ✅ (dep S2) |
| S34 | `ch04_fhir/rul-fhir-routing.cls` + `ch04_fhir/bp-fhir-request-quickstream.cls` | fhir | Closes the dangling `Example.RUL.FhirRouting` on the newest gated production, and pins that a FHIR DTL works on the Request's **QuickStreamId, not on properties** — the skill's only transformation cross-ref implies property mapping. | ✅ FHIRFOUNDATION |
| S35 ⚠ | `ch06_adapters/production-soap-inbound.cls` | soap-bo | `EnableStandardRequests` on `Target="Adapter"` — the Portal accepts `Target="Host"` silently and the first call dies with `<Ens>ErrSOAPNotEnabled`, naming the setting but not the target. Plus item `Name` = the web-service FQCN or URL dispatch cannot resolve the WSDL. **Zero `EnableStandardRequests` in the bank.** | ✅ wires the already-gated `Example.BS.MyService` |
| S36 ⚠ | `ch06_adapters/soap-bo-typed-adapter.cls` + 2 message siblings | soap-bo | The canonical SOAP BO fence is a complete class that is **absent from `snippets_baseline.json`** — waved through by the #5373 exemption. Puts the narrowing `Property Adapter As EnsLib.SOAP.OutboundAdapter` and `..Adapter.WebServiceURL` (1 occurrence in the entire repo) under a compiler. | ✅ — the siblings must ship or it repeats the exemption |
| S37 | `ch06_adapters/http-manual-envelope-bo.cls` | soap-bo, business-operations | `SendFormDataArray` with explicit `pFormVarNames=""` (the two skills prescribe 3-arg and 6-arg forms of the same call), `Data.Rewind()` before `Read` (without it the response reads **empty with `$$$OK`**), `StatusCode` read inside a `Try` (MultiDim), and SOAP booleans arriving as `"true"`/`"false"` so a `=1` test is false for every response. | ✅ **only with the narrowed Adapter property** — otherwise the call stays late-bound and unchecked |
| S38 | `ch02_hl7v2/dtl-hl7-repeating-segments.cls` + `Example.DT.Al1ToText` | transformations, component-map | Every version of this pattern is currently outside the gate (loose fragments + ```xml fences). The test must assert **three** repeats landed — the positive control the zero-iteration form cannot pass. "The transform completes successfully having processed zero repeats — the worst failure mode, because nothing surfaces." Must show the group fallback (`GetSegmentAt("NK1(N)")` returns empty, no error). | ✅ (dep S5) — **rename constraint:** must not collide with snippet `MyApp.DT.AL1Subtransform` |
| S39 | `ch11_security/ssl-config-verifypeer-assert.cls` | security | Step 1 of §11.7 — "Server Certificate Validation = Require" — the point of the section and the only step with no artefact. With validation `None` the handshake succeeds, everything is green and the peer is unauthenticated for ever. Needs an *executable* assertion because an operator can flip it back by hand after deploy. | ⚠️ **VERIFY** `Security.SSLConfigs` visibility from the gate namespace (%SYS-scoped) |
| S40 | `ch15_dicom/dicom-mwl-date-functionset.cls` | dicom | `$ZDATEH(value, 5)` for `YYYYMMDD` and the missing `-1` error-trap argument. Wrong code → the modality's worklist comes back empty (or no C-FIND response at all) while IRIS shows a green production with the query in the trace. **Best cost/value in DICOM**: pure core ObjectScript, no `EnsLib.DICOM`, compiles on community today. | ✅ code — ⚠️ **the deliverable has no DICOM chapter, so C2 fails until one exists** |
| S41 | `ch15_dicom/production-dicom-onstart-associations.cls` | dicom | `CreateAssociation(pCallingAET, pCalledAET)` is **wire direction** — the skill's two examples use opposite orders and state no rule — and the verify step: a SOP friendly name matching nothing saves a context with **zero presentation contexts** and returns `$$$OK`, after which `AETExists()` is true so the OnStart guard never retries. | ⚠️ **VERIFY** `EnsLib.DICOM.*` + `EnsDICOM.inc` in the gate namespace; DICOM chapter required |

---

## Wave 4 — P2, worth gating once waves 1–3 land (18 samples)

Grouped, one line each. All compile on the community image unless flagged.

- `ch05_bpl_dtl/dtl-fill-both-representations.cls` — *messages + transformations (deduped).* Legacy pipe-string and typed list both filled; a Rich message with only the list reaches the legacy BO as an empty string, silently.
- `ch01_production/dtl-censo-validate-flags.cls` — *transformations.* Validate per record in the DTL, not in RecordMap field types: a record dropped at map level never becomes a message, so Visual Trace shows **nothing at all**. Reuses two already-gated artefacts.
- `ch05_bpl_dtl/msg-list-collection-child-table.cls` — *messages.* Projected child-table naming (`SCHEMA.Class_Property`). Loud (`SQLCODE -30`) but cost 12 round-trips in one cohort.
- `ch05_bpl_dtl/bpl-scope-catchall-compensation.cls` — *bpl.* `<scope>`/`<catchall>`/`<compensationhandler>` occur nowhere in the plugin. A catchall that logs and falls through returns `$$$OK`: a failed downstream call becomes a completed BP with a green trace.
- `ch05_bpl_dtl/tdd-testproduction-bpl.cls` — *bpl, tdd.* Assert returned field **values** and `Ens_Util.Log` rows, not `$IsObject(resp)` — the gated snippet goes green if the BPL returns any object, including a default-constructed one with every `<call>` failed.
- `ch01_production/task-definition-scheduled-bs.cls` + `ch01_production/purge-task-schedule.cls` — *business-services, production-lifecycle, message-search-debug (deduped).* `%SYS.Task.Definition` (not `%SYS.TaskSuper`, which survives an existence check and has no `OnTask`), `PoolSize=1` **and** synchronous calls, and the unverified `NumDaysToKeep` spelling — same species as two existing BANNED findings.
- `ch11_security/soap-inbound-basic-auth.cls` — *business-services.* `OnPreWebMethod` default-deny. The fence's body has no `Quit` at all; copying it fails loud, but the **plausible repair** (`Quit $$$OK`) yields an endpoint that authenticates nothing while looking authenticated.
- `ch06_adapters/sql-adapter-headless-probe.cls` — *business-operations, tdd (deduped).* Adapter `%New()`/`OnInit`/`Disconnect` + `[SqlProc]`, and the JGService precondition whose `<INVALID OREF>` names neither the BO, the adapter, nor JGService. Declare `#Dim` so typos are compile errors.
- `ch06_adapters/path-from-setting-and-runtime.cls` — *conformance-review.* `InstallDirectory` is on `%SYSTEM.Util`, **not** `%Library.File` — asserted in exactly one line in the whole plugin. Must be **exercised**, not merely compiled: the wrong class compiles and fails at runtime.
- `ch03_cda/msg-with-dat-serial-payload.cls` — *conformance-review (CR-9/CR-11).* The `.DAT` package CR-11 makes the default fix has **zero instances** in the bank; all eight `%SerialObject` classes sit in `.MSG.`/`.WSC.`.
- `ch06_adapters/soap-wsdl-reader-generate.cls` — *soap-bo.* `%SOAP.WSDL.Reader.Process` arity behind a typed `#DIM`, turning a version-pinned existence claim into a standing gate.
- `ch11_security/oauth2-client-pkce.cls` — *security + fhir (deduped).* Does **not** inherit the FHIR blocker: `%SYS.OAuth2.*` is core IRIS. A server that never enforces `code_challenge` still issues a token — the integration looks finished and the protection is absent.
- `ch04_fhir/fhirsql-setup-existence-test.cls` — *fhir.* Must be a `%Dictionary.CompiledClass/CompiledMethod` lookup, **not** a call-through: tier 2 excuses `#5373` as a placeholder dependency, so a class calling a nonexistent HS method passes.
- `ch04_fhir/fhir-bundle-transaction-guard.cls` — *fhir.* Scope strictly to validating `Bundle.type` (a `batch` Bundle satisfies the prose and breaks the guarantee); never re-implement transaction semantics.
- `ch15_dicom/production-dicom-query-retrieve.cls` — *dicom.* The duplex wiring is a **quartet**, not a pair, and the snapshot's own response leg names an item that does not exist. Pairs with N14.
- `ch15_dicom/bp-mwl-findresponse-sequence.cls` — *dicom.* N Pending then **exactly one** `Status=0`, including for zero rows; omit it and the modality hangs while IRIS logs N successful sends. ⚠️ DICOM chapter + `EnsLib.DICOM` verification.
- `ch05_bpl_dtl/msg-with-generated-storage.cls` — *interop.* **Contested.** Shows the legitimate post-export `Storage Default` block (zero `^Storage ` blocks in the bank today, and five headers explaining why). Counter-risk: a bank file containing a Storage block invites copy-paste into a new class, which the first half of the same rule forbids, and a BANNED token cannot tell the two cases apart.
- `ch01_production/tdd-namespace-guard-test.cls` — *interop.* **Prefer three added lines in the gated `tdd-testproduction-dtl.cls`** over a new file. Converts "21/21 calls with the schema default USER, 8/8 tests green, nothing in the required namespace" into a red. Honest limit: a sample cannot pin a tool-call parameter — it can only make the wrong-namespace run fail loudly.

---

## Wave 5 — declined: prose suffices, or a sample cannot pin it (17 items)

Recording these so a later pass does not re-derive them as gaps.

**Prose is already the denser artefact**
- Identifier `_`/#5559 rule (`interop`, `messages`) — the illegal spelling **cannot compile**, so a bank file can only show the legal one, which all 43 classes already model. Enforcement belongs in the PreToolUse conformance gate (inert on 2 of 3 CLIs — that is an argument about *where* the rule lives, not for a sample).
- CR-8 REST fields typed `%String` — one-line typing rule, wrong type fails loud.
- `bo-file-putline.cls` — bad path errors the message, which sits visibly in the queue; two near-identical file operations already gated.
- `msg-dicom-tags-request.cls` — the message-class shape is gated several times; only the tag strings are DICOM-specific, and those are data.
- `bo-hl7-onrequest-signature.cls` — a wrong `OnRequest` signature fails loudly at dispatch; most of the work is a host class that teaches nothing new.
- `production-future-flow-items.cls` — the rule is complete in prose and its failure is `<CLASS DOES NOT EXIST>` at load; compiling a production **does not resolve item ClassNames**, so the sample would prove nothing.
- `unittest-smoke-testproduction.cls` — a `.cls` cannot pin the value of a global. The real instrument is a positive control in the harness (a deliberately bad `^UnitTestRoot` that must yield zero tests).
- `tdd-boundary-rejection-test.cls` — one macro swap; fold a boundary method into the existing §5.9 test instead of adding a file.
- SAML assertion self-containment test — would reimplement the scope deliberately delegated to `intersystems-ib/SAML-COS`, and its green would not transfer to the partner path.
- `issue-fingerprint-cases.md` — a bad fingerprint produces a visible duplicate issue someone closes.

**A sample is structurally impossible or would be indexed non-coverage**
- `BUILD-ORDER-template.md` — a manifest, not a compilation unit.
- `lookup-seed-genero.csv` — `.csv` carries no `/// Rule:` header and can never enter `examples_baseline.json`. Either drop the two filenames the skill advertises, or let the gated bootstrap SqlProc be the canonical seed.
- `hl7-custom-category.xml` as a standalone bank file — would sit in the bank as text no compiler reads, the state tier 3 exists to eliminate. Carry it as `XData` inside S30 instead.
- `zauthenticate-ldap-expiry` — a `%SYS` `.mac` routine; `.mac` is not in `ARTEFACT_SUFFIXES` and tier 2 is `.cls`-only. **Ship a declared non-coverage row** next to FHIR/DICOM instead.
- `xslt-cda-transform.xsl` — the risk lives outside IRIS, where the skill's own advice sends you; an `.xsl` would be structurally indexed and compile-gated by nothing.
- CR-12 namespace↔src parity — a two-sided tool procedure, not a compilation unit. Belongs in `scripts/` with a test, or in the src-drift hook.
- §6.1.3 `urn` namespace prefix — **the mechanism is unidentified in both the skill and the deliverable.** Do not write a sample on a guess: resolve `%SOAP.WebClient` against a live instance, or declare the non-coverage. An instruction that names an outcome with no method is how an agent invents `..Adapter.%Client.NamespacePrefix`.

---

## Counts and CI flags

| Wave | Samples | Files | All silent-failure or P0/P1? |
|---|---|---|---|
| 0 — not samples (fixes, renames, gate checks) | 16 actions | — | n/a — do first |
| 1 — silent-failure set | **16** | **22** | yes, all P0 |
| 2 — P1, core spine | **13** | ~17 | yes |
| 3 — P1, periphery | **12** | ~16 | yes |
| 4 — P2 | **18** | ~20 | silent in 13 of 18 |
| 5 — declined | 17 | 0 | — |
| **Total new samples proposed** | **59** | **~75** | |

**Cannot be compiled by CI on the community image (explicit flags):**

1. **`ch11_security/oauth2-server-validate-ldap.cls` (S14)** — `IncludeCode %syLDAP,%syLDAPFunc,%sySite` may be `%SYS`-only. Check `%Library.Routine`/`%Dictionary.CompiledClass` in the gate namespace **before** authoring. If it does not resolve: declared non-coverage, not a bank file.
2. **`ch11_security/ssl-config-verifypeer-assert.cls` (S39)** — `Security.SSLConfigs` is `%SYS`-scoped; same check, same fallback.
3. **All four `ch15_dicom/*` samples (S40, S41, wave 4 ×2)** — double-blocked: `EnsLib.DICOM.*`/`EnsDICOM.inc` presence in the gate namespace is unverified, **and the deliverable has no DICOM chapter**, so tier-1 C2 rejects any `/// Rule: §15.x` header today. S40 alone (`$ZDATEH`) needs no DICOM class and clears as soon as a heading exists.
4. **Every non-`.cls` artefact** — `.sh`, `.py`, `.csv`, `.xsl`, `.xml`, `.md`. `validate_examples.py:448` skips them and `examples_baseline.json` holds class names only, so **they can never reach COVERED as defined**. This already affects two *shipped* rows (§7.1, §11.5).
5. **Systemic, applies to all 14 test samples above:** tier 2 **compiles and never runs**. Every `%UnitTest` oracle here gates its API names, superclass and assertion shape — not its outcome. Where a sample's whole value is the executed assertion (S3, S7, S12, S29, S33, S38), say so in its header and pair it with a release-step run, or the green means less than it looks.

**Ordering note.** Build S5 (HL7 fixture) and S23/S16 (production-settings reader) early: four other samples depend on them. Build N14 (the `BusinessRuleName`-resolves check) before wave 1 ships, or S1, S2 and S34 will close three dangling names while the check that would have caught them still does not exist.

---

## Wave 1 follow-on — premises VERIFIED against a live instance, 2026-09-18

S4's premise was false and S5's was half-right, so before building any more of Wave 1 each
remaining row's checkable claim was measured on IRIS for Health 2026.1. **Where this section and a
wave row disagree, this section wins** — and where it disagrees with §"Review corrections", it wins
there too, for the rows named below.

### Corrections found by the verification pass

| # | Claim as written | Measured |
|---|---|---|
| **V1** | `interop` §"is it a table at all": `Ens_Config.Item` is **not a queryable table** (`SQLCODE -30`) | **False — it IS a table.** `SELECT Name, ClassName FROM Ens_Config.Item WHERE Production='<Pkg>.Production'` returns the items, and the count agrees exactly with `tProd.Items.Count()`. The `-30` comes from querying the **class** name (`Ens.Config.Item` → `Table 'CONFIG.ITEM' not found`) — the dots→underscores rule, not a missing table. `Ens_Config.Setting` and `Ens_Util.Queue` genuinely are `-30`; the row lumped them together. **Corrected in `interop` at v1.24.0.** The real hazard is worse than an error: the table is populated for REGISTERED productions, so an uncompiled/undeployed one reads as **0 rows**, which looks like "no items". |
| **V2** | §"Review corrections": S8/S16/S22 must be rewritten against the object API because embedded `&sql` on `Ens_Config.Item` is a compile-time failure | **Void — the reasoning rests on V1.** The table exists, so the `&sql` compiles and works. `bpl:163/178/222` was RIGHT all along, and `bpl:182`'s `##class(Ens.Config.Item).%OpenId(routerItem)` is correct too: it selects `ID`, not a name. Build S8/S16/S22 as originally written. |
| **V3** | `component-map`: `..Adapter.Post(.resp, url, body)` | **Wrong twice.** `Post(*pHttpResponse, pFormVarNames, pData...)` takes **no URL** — it comes from the adapter's `URL` setting. The URL-taking variant is `PostURL(pURL, *pHttpResponse, …)`, URL **first**. The form as written passes the URL as form-var names. **Corrected at v1.24.0**; S11 must assert the arity. |
| **V4** | S7: contrast the working `NormalizeKey` against "the tier-3-**green** broken one" | **Stale.** That broken snippet was fixed in v1.15.0 (wave-0 N4) — `"*-CWE"` raised `<FUNCTION>` and is now `"*WC"` + `$TRANSLATE`. The sample is still worth building; the contrast it was framed around no longer exists in the repo. |
| **V9** | S14: `ValidateClient` returns 1 unconditionally — "**any** client secret accepted, tokens issue, nothing logged" — written as a defect the copy introduced | **Not the copy's doing.** Read out of `%Dictionary.MethodDefinition`, the VENDOR body of `%OAuth2.Server.Validate::ValidateClient` is exactly `Set sc=$$$OK` / `Quit 1`, and the copy reproduces it verbatim. The five copied lines change no behaviour; their cost is ownership (re-diff on every upgrade), not permissiveness. The default does mean this hook accepts every client — but that is IRIS's shipped default, because client authentication happens against the client secret in the server configuration, not here. The defects the copy really introduced are both elsewhere and both measurable: `SupportedClaims` emptied 6 → 0, and a five-formal `ValidateUser` against the vendor's six. Built as a subclass at v1.35.0, which inherits the vendor version of both. |
| **V5** | S13: "the 3-arg `DebugRunTestCase`" | **Wrong arity.** Measured: `DebugRunTestCase(testsuite, testcase, qspec, testmethod, &userparam)` — **5** parameters. And measured separately: it ran without error while writing **no rows** to `%UnitTest_Result.TestMethod`, so it yields no verdict to read back — a zero there is indistinguishable from a pass. S13 must account for that. |

### Premises confirmed (build as written)

| # | Row | Confirmed |
|---|---|---|
| **V6** | S9 | There is **no** `StartTransaction`. `EnsLib.SQL.OutboundAdapter` has `SetAutoCommit(pAutoCommit=1)`, `Commit()`, `Rollback()` — and also `Transact(type)`, which the row does not mention. |
| **V7** | S10 | `EnsLib.RecordMap.Service.FileService.OnProcessInput(pInput As %Stream.Object, *pOutput, &pHint)` is **3-arg**, as the row says, and `OnInit()` exists to `##super()` from. |
| **V8** | S8 | The defect is real and is the router `SELECT`: `ClassName = 'EnsLib.MsgRouter.RoutingEngine'` matches the generic router **only**, never `EnsLib.HL7.MsgRouter.RoutingEngine`, and `TOP 1` picks arbitrarily among several. |

### Suggested order for the rest of Wave 1

Dependency- and cost-ordered, cheapest verified win first:

1. **S12** — HL7 router validation test. Unblocked by S5's fixture (v1.22.0), which it reuses directly.
2. **S6** — `..Func()` vs bare in a DTL. Pure compile-vs-run contrast; the fixture pattern is settled.
3. **S10** — RecordMap service subclass: `##super()` first, 3-arg `OnProcessInput` (V7 confirmed).
4. **S11** — REST outbound BO; must assert the `Post`/`PostURL` arity from V3.
5. **S9** — SQL batch transaction (V6 confirmed; include `Transact`).
6. **S7** — lookup normalisation (re-scoped per V4).
7. **S15** — drift report, disk vs namespace.
8. **S13** — `%UnitTest` result reader (re-scoped per V5; the reader is *more* needed now that `DebugRunTestCase` is known to produce no rows).
9. **S8** and **S16** — both now buildable as originally written (V2), using `Ens_Config.Item`.
10. **S14** — last: the OAuth/LDAP artefact, and per §"Review corrections" ship the **subclass**, never a copy of vendor source.


## Wave 2 follow-on — premises VERIFIED against a live instance, 2026-09-18

Wave 1's pass paid for itself (3 wrong, 1 stale, 1 mis-stated arity out of 8 rows), so the same was
done for all **13** Wave 2 rows before building any of them. **Where this section and a wave row
disagree, this section wins.** Three rows need correcting; the other ten are buildable as written,
with the measured names below so nobody re-derives them.

### Corrections

| # | Claim as written | Measured |
|---|---|---|
| **W1** | S17: "`SaveToClass`+`GenerateObject` **atomic in one method**", implying both sit on the RecordMap class | **Right about the pairing, wrong about where they live — and they are on two DIFFERENT classes.** `EnsLib.RecordMap.RecordMap` has neither. Measured: `EnsLib.RecordMap.Model.Record::SaveToClass()` — **arity 0**, on the *Model* class — and `EnsLib.RecordMap.Generator::GenerateObject(pRecordMap, &pTargetClassname, &pStructure=1)`. So the bootstrap method really does have to reach into two places, which strengthens the row's point rather than weakening it. `SaveToClass` also exists on `Ens.Config.Production` and `EnsLib.RecordMap.Model.ComplexBatch` with different signatures — do not pattern-match the name. |
| **W2** | S29: "settles whether a bare `%String` **silently truncates** on `%Save` or rejects with `#7201`" | **It rejects, on every path measured, and NOTHING is silent.** 50 chars saves and reads back 50; 51 gives `ERROR #7201`. Also measured, same property: `%ValidateObject()` alone → `#7201`; SQL `INSERT` → `SQLCODE=-104 Field 'Bare' … failed validation`; and the in-memory value after `Set` is the **full 100 chars**, not truncated. `MAXLEN=""` given 5000 chars saves all 5000. So the mitigation the skills teach is right and the failure mode they describe is wrong, at three sites: `messages:314` ("silently truncated on `%Save` (no error, the data is just gone)"), `messages:320`, `soap-bo:53`. **Two things deliberately NOT swept in.** `business-services:368` ("`Alergias = "Frutos secos\|Marisco"` is silently truncated at `Frutos`") is a **different mechanism** — a RecordMap separator defaulting to `$char(32)`, so the value splits at a space — and stands exactly as written. And the SOAP/XML **import** path was not measured, so whether a wizard-generated property truncates on deserialization is still open; the correction must not claim it. |
| **W3** | S24: a value that does not match `informat` is **returned unchanged**, so `31/02/1958` becomes `1958-02-31` | **Confirmed, and worse than stated. (Refined at v1.38.0: "no validation at any point" was itself too strong — it validates the field RANGES and never the CALENDAR. `32/01/1958`, `31/13/1958` and `99/99/9999` are all returned UNCHANGED; only day 1–31 with month 1–12 is reformatted. Two silent failure modes, not one.)** `ConvertDateTime(value, informat="%Q", outformat="%Q", outf)`, 4 args, on `Ens.Util.FunctionSet` (and ~10 other FunctionSets). Measured: `31/02/1958` → `1958-02-31`; `29/02/2023` → `2023-02-29` (**2023 is not a leap year**); `not a date` → unchanged; an already-ISO `1958-02-31` → unchanged. So a malformed date is not merely passed through, it is *reformatted into a well-formed-looking invalid date*, which is harder to spot downstream than free text. `ConvertDateTimeToUTC` confirmed absent (0 matches) — `transformations:131` already says so, correctly. |

### Premises confirmed (build as written, using these names)

| # | Row | Confirmed |
|---|---|---|
| **W4** | S20 | Exact. `FailureTimeout` InitialExpression = **-1**, origin `EnsLib.HL7.Operation.Standard`; `ReplyCodeActions` = **""**, origin `EnsLib.HL7.Operation.ReplyStandard`. One refinement the row does not state and should use: `ResponseTimeout` = **30** lives on the **adapter** (`EnsLib.HL7.Adapter.TCPOutboundAdapter`) while `FailureTimeout` lives on the **host** — the Host/Adapter split the row wants to teach, sitting right there in the two timeouts it already names. |
| **W5** | S25 | Exact. `Ens.Util.LookupTable` properties are `TableName`, `KeyName`, `DataValue`, and `Ens_Util.LookupTable` is queryable (30 rows present in the gate namespace). |
| **W6** | S23 | Exact. `Ens.Config.DefaultSettings` = `ProductionName`, `ItemName`, `HostClassName`, `SettingName`, `SettingValue`, `Deployable`, `Description`. |
| **W7** | S22 | The whole ladder exists on `Ens.Director`: `RecoverProduction`, `CleanProduction`, `RestartProduction`, `StopProduction`, `GetProductionStatus`, `UpdateProduction`, `IsProductionRunning`. |
| **W8** | S27 | `OnBeforeAllTests` / `OnAfterAllTests` are on `%UnitTest.TestCase` with **no formal parameters** (Origin `%UnitTest.TestCase`, inherited unchanged by `%UnitTest.TestProduction`). The row's "names **and signatures**" is therefore a real hazard: there is no argument to get wrong, so the only way to break it is the spelling. |
| **W9** | S28 | `GetEventLog(type="all", name="", baseId, &v, *New)` — **5** parameters, on `%UnitTest.TestProduction`. |
| **W10** | S19 | Both halves. `SearchTableClass` is a real setting on **29** `EnsLib.HL7.*` classes (services and operations, InitialExpression `""` throughout), and the bank contains **zero** occurrences of it. |
| **W11** | S26 | A `Ens.BusinessOperation` subclass with **no** `Parameter ADAPTER` compiles clean — the adapter-less shape the row wants is legal, as `business-operations` claims. |
| **W12** | S18 | `GetObject` is defined on `EnsLib.RecordMap.RecordMap` and on all seven `EnsLib.RecordMap.Service.*` classes, and **not** on `EnsLib.RecordMap.Base` — which is what the generated `.Record` class extends. So "call it on the map class, not `.Record`" is correct about where it lives. |
| **W13** | S21 | `Ens.BPL.Flow` and `Ens.BPL.Sync` both exist as `Ens.BPL.Activity` subclasses. The attributes to write the sample against: `Ens.BPL.Call` carries `Async` (%Boolean), `Name`, `Target`; `Ens.BPL.Sync` carries `Calls` (the named calls awaited), `Type` (default **"all"**), `Timeout`, `AllowResync` (default 0). The silent failure the row describes is exactly a `<call async="1">` whose name appears in no `<sync calls="…">`. |

### Suggested order for Wave 2

Corrections first where they are cheap, and the two rows that change a skill early, so the skill text
is right before anything is built on it:

1. **S29** — settles a failure mode asserted at three skill sites (W2). Cheapest measurement already
   done; the work is the artefact plus the three corrections.
2. **S24** — same shape, one skill, and the oracle is a table of measured conversions (W3).
3. **S25** — lookup bootstrap; names confirmed exact (W5).
4. **S23** — SDS orphan report; names confirmed exact (W6).
5. **S19** — search table assignment + the positive control separating "no data" from "not indexed".
6. **S26** — the adapter-less BO (W11), which no bank artefact demonstrates.
7. **S27** + **S28** — the two `%UnitTest` lifecycle/verdict rows; the row itself suggests folding them.
8. **S21** — BPL `<flow>`/`<sync>` (W13).
9. **S17** + **S18** — the RecordMap pair, S17 rewritten against the two real classes (W1, W12).
10. **S22** — lifecycle helper (W7).
11. **S20** — MLLP, last: it is the largest, and W4 gives it a second teaching point to fold in.


## Review corrections — apply these before building a ⚠ row

The adversarial critic found these after the map was written. Where the map and this section
disagree, **this section wins**.

### Rows built on a premise the plugin contradicts

- **S8, S16, S22 — rewrite against the object API.** `interop/SKILL.md:221` states flatly that
  `Ens_Config.Item` is **not a queryable table** (`SQLCODE -30`): items are embedded objects inside
  the production's XData, and the route is `##class(Ens.Config.Production).%OpenId(…)` then iterate
  `tProd.Items`. These rows promise that embedded `&sql` makes `Ens_Config.Item` "compile-verified"
  and flag themselves ✅ CI. Embedded `&sql` against a nonexistent table is a **compile-time**
  failure, so as written they fail tier 2 rather than verifying anything. `bpl/SKILL.md:161`
  compounds it with `##class(Ens.Config.Item).%OpenId()` on an embedded object — fold that
  contradiction into **N12**, which omits it, and note that C8 cannot see it.
- **S14 — do not copy vendor source.** The proposal is `Alt.OAuth2.Server.Validate`, a verbatim copy
  of `%OAuth2.Server.Validate`. `ch06_adapters/alt-soap-webclient-tracing.cls:8-14` refuses exactly
  this for `Alt.SOAP.WebClient`: *"It is vendor source; the example bank cannot carry it."* Ship the
  LDAP validation as the **subclass** the skill already prescribes — compiles, carries no vendor
  source, sidesteps the `%syLDAP` include question.

### Mis-ranked

- **S35 is not a silent failure.** The map's own cell says the first call dies with
  `<Ens>ErrSOAPNotEnabled`, *naming the setting*. Loud-but-misdirecting. Demote or relabel.
- **S10 is half-loud.** #5478's 3-arg `OnProcessInput` is **compile-enforced**, so that half is not
  silent. Only the missing `##super()` half is. Keep the sample, drop the P0-silent framing on the
  signature half.
- **Wave 4 `soap-inbound-basic-auth` (§6.3 `OnPreWebMethod`) is P0 and should swap with S14.** Both
  are "auth that authenticates nothing"; this one is cheaper and unblocked — §6.3 exists, the host
  class `EnsLib.SOAP.Service` is already gated (`Example.BS.MyService`), and it needs no `%SYS`
  include check. S14 is the CI-blocked one.
- **S20 needs a verify-first flag.** `ResponseTimeout` has **0 hits in `skills/`**, not just the
  bank — §1.9 names the settings only in Spanish portal labels, so there is no prose to pin. And
  `ResponseTimeout` is an **adapter** setting while `FailureTimeout` is a **Host** setting; a sample
  putting both on `Target="Host"` reproduces the never-read-setting defect. Resolve both targets
  against the live adapter before authoring.

### Component types the map never proposes — all three prescribed, none in bank or skills

- **Custom inbound adapter.** §5.2 already prescribes `Demo.ADP.SchedulerAdapter` for wall-clock
  triggers, and `grep "Extends Ens.InboundAdapter"` over `skills/` returns **zero** — no skill
  teaches the shape. Silent failure is textbook: an `OnTask` that evaluates its cron match and
  returns `$$$OK` without calling `..BusinessHost.ProcessInput()` leaves the service green, ticking
  and producing nothing for ever. §5.2 exists and `ADP` is in `TIPOS`, so no heading work.
  **Belongs in wave 1.**
- **Class-based `Ens.BusinessProcess` (non-BPL).** `bpl:78` recommends it when BPL gets unreadable;
  `tdd:581` records that it returns `""` with no error; CR-1 is a rule *about* the shape. The bank
  has only `Ens.BusinessProcessBPL`. Silent: an `OnRequest` that calls `SendRequestAsync` and
  returns `$$$OK` completes the process before the reply arrives, so `OnResponse` is never reached
  and the trace shows a completed BP. **The whole map treats "BP" as "BPL".**
- **Pass-through / `Ens.StreamContainer`.** Zero hits in `skills/` and zero in the bank, while
  `production-lifecycle:308,351` wires `EnsLib.File.PassthroughOperation` as the canonical alert
  sink — which S2 depends on. The commonest relay shape in the field, undocumented and unmapped.

(Lower value, recorded so it is not re-derived: Managed Alerts `Ens.Alerting.*` — 0 hits anywhere;
§2.9 ordered synchronous chain — no example.)

### Factual

- **Three fence classes are off `snippets_baseline.json`, not one** — `MyApp.BO.WeatherService`
  (S36's target), `MyApp.BO.WriteCensusToSQL` and `MyApp.BS.RestEntry`. They fail as placeholder
  dependencies, so **the tier-3 green over the SQL-BO fence is not a green at all** — matters to S9.
- **Three shipped non-`.cls` rows, not two**: §7.1 `.xml`, §11.5 `.cls.xml`, **and §11.7
  `ssl-trusted-ca-chain.sh`**. **N13** must cover §11.7 too — and for a shell script the right
  remedy is a declared non-coverage row, not a future sample.
- **N9: keep renamed snippets in `MyApp.*`.** `Example.RecordMap.Invoice` moves a snippet into the
  **bank's** namespace, where tier 3 hard-fails on any snippet∩bank collision and C7 resolves
  `Example.` pointers out of the deliverable. `MyApp.RecordMap.Invoice` is the same fix with no
  collision surface.

### Sound, no correction needed

All 34 distinct `${CLAUDE_PLUGIN_ROOT}` pointers across the 20 skills resolve on disk. The
zero-citing (6) and single-citing (4) skill counts, 43 classes / 9 chapters, the
`FailureTimeout`-appears-once claim, and the zero counts for `SearchTableClass` / `docCategory` /
`TSTART` / `..Lookup(` / `MAXLEN = ""` all check out as stated.
