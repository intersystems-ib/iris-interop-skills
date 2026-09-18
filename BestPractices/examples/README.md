# Code examples — rule → file index

## Validation

This bank is gated, not reviewed. Before this gate existed, 10 of 18 files did
not compile — across seven releases, because nobody had ever run a compiler over
them.

```sh
python3 scripts/validate_examples.py            # tier 1: structural, ~1s, runs in CI
python3 scripts/validate_examples.py --compile  # tier 2: compile every class on live IRIS
```

**Tier 1** checks the invariants this index depends on: every artefact carries a
`/// Rule:` header, every `§X.Y` resolves to a real heading, one class per `.cls`,
the index and the directory agree in both directions, no class puts its Tipo last,
and no token the audit proved wrong survives outside a comment.

**Tier 2** stages every class into a live IRIS, compiles, compares against
`scripts/examples_baseline.json`, and deletes what it staged. Run it before any
release. It needs `IRIS_HOST` / `IRIS_PORT` / `IRIS_NAMESPACE` / `IRIS_USER` /
`IRIS_PASSWORD` (defaults suit a local dev container).

Adding an example means adding its row here — C4 fails the build otherwise. If it
introduces a class the baseline does not know, review it and re-record with
`--update-baseline`.


This directory hosts standalone code artefacts referenced from
`../BestPractices_Interop_IRIS.md`. The deliverable is the canonical source;
each file here is a verbatim lift (or faithful reconstruction) of a "tricky"
pattern that needs concrete code to reproduce.

Every file carries a header block with:
- **Rule** — the §X.Y reference in the deliverable
- **Validity** — copy of the deliverable's validity tag

If a rule's pattern is fully canonicalised in a public InterSystems-Iberia
GitHub repo, the example is **not** lifted here — see `external-repos.md`.

One `.cls` file = one class, named for the class it defines. Where a rule needs
more than one class to compile, the extra classes ship as **sibling files**
carrying the same `Rule:` §, and are indexed here under that same §. So a rule
can map to a file *set*: read the row that is not marked `Sibling:` first, then
its siblings.

## Rule → file

| Chapter | Rule | File |
|---|---|---|
| §1.11 | RecordMap definition for a delimited CSV intake (the only class you author) | `ch01_production/recordmap-censo.cls` |
| §1.12 | Complete production: prebuilt RecordMap FileService → router → outbound, with Host/Adapter targets | `ch01_production/production-censo-intake.cls` |
| §2.3 | HL7 v2 escape special characters when building messages manually | `ch02_hl7v2/hl7v2-escape-functionset.cls` |
| §1.11 | Routing rule for the RecordMap intake — where the DTL belongs instead of a BS subclass | `ch01_production/routing-rule-censo.cls` |
| §2.10 | HL7 v2 file intake: prebuilt HL7 FileService + the HL7-SPECIFIC router (CR-6) | `ch02_hl7v2/production-hl7-intake.cls` |
| §2.10 | HL7 routing rule: the HL7 assist class + docCategory/docName constraints (CR-5, CR-6) | `ch02_hl7v2/routing-rule-hl7-adt.cls` |
| §2.10 | Sibling: the **two-direction** router test — valid → target AND malformed → `BadMessageHandler`; RUN against a live production (`Example.Tests.Hl7RouterValidation`) | `ch02_hl7v2/tdd-hl7-router-validation.cls` |
| §2.11 | HL7 DTL with **symbolic** field paths — a mistyped path compiles clean and resolves to nothing (`Example.DT.AdtNormalise`) | `ch02_hl7v2/dtl-hl7-symbolic-paths.cls` |
| §2.11 | Sibling: the HL7 fixture test — EXECUTED; its control shows `""` cannot tell a bad path from an empty field (`Example.Tests.Hl7SymbolicPaths`) | `ch02_hl7v2/tdd-hl7-fixture-test.cls` |
| §3.1 | CDA-from-XSD: Persistent + no Relationships + OnDelete Cascade | `ch03_cda/cda-from-xsd-persistence-pattern.cls` |
| §3.1 | Sibling: the `<component>` child class the §3.1 template cascades to (`Example.CDA.Component`) | `ch03_cda/cda-from-xsd-component.cls` |
| §3.2 | Comanda/Resposta inheritance for one-of-N subtypes — the abstract envelope | `ch03_cda/comanda-resposta-inheritance.cls` |
| §3.2 | Sibling: concrete SC1 variant (`Demo.MSG.ComandaSC1`) | `ch03_cda/comanda-resposta-sc1.cls` |
| §3.2 | Sibling: concrete SC2 variant (`Demo.MSG.ComandaSC2`) | `ch03_cda/comanda-resposta-sc2.cls` |
| §3.2 | Sibling: shared envelope header payload (`Demo.MSG.ComandaHeader`) | `ch03_cda/comanda-resposta-header.cls` |
| §3.2 | Sibling: SC1 content payload (`Demo.MSG.SC1Content`) | `ch03_cda/comanda-resposta-sc1-content.cls` |
| §3.2 | Sibling: SC2 content payload (`Demo.MSG.SC2Content`) | `ch03_cda/comanda-resposta-sc2-content.cls` |
| §3.2 | Sibling: BS that picks the concrete Comanda variant (`Demo.BS.ComandaReceiver`) | `ch03_cda/comanda-receiver-service.cls` |
| §3.4 | SOAP carrying CDA / HL7 as MessageBody — the patched generated proxy | `ch03_cda/soap-messagebody-hl7-proxy.cls` |
| §3.4 | Sibling: BO half of the same pattern (`Demo.Vendor.BO.AcceptMessage`) | `ch03_cda/soap-messagebody-hl7-operation.cls` |
| §4.10 | FHIR Facade production wiring (Foundation namespace prerequisite; Facade vs Repository is one ClassName) | `ch04_fhir/production-fhir-facade.cls` |
| §4.10 | Routing rule for the FHIR Facade — msgClass on HS.FHIRServer.Interop.Request | `ch04_fhir/routing-rule-fhir.cls` |
| §5.1 | BS that exposes a SOAP service | `ch05_bpl_dtl/soap-business-service.cls` |
| §5.1 | Sibling: request message of that BS (`Example.MSG.AcceptOrderReq`) | `ch05_bpl_dtl/msg-acceptorder-req.cls` |
| §5.1 | Sibling: response message of that BS (`Example.MSG.AcceptOrderRsp`) | `ch05_bpl_dtl/msg-acceptorder-rsp.cls` |
| §5.2 | Custom inbound adapter for wall-clock schedules — the `..BusinessHost.ProcessInput()` dispatch is the whole point (`Demo.ADP.SchedulerAdapter`) | `ch05_bpl_dtl/adp-scheduler-inbound-adapter.cls` |
| §5.2 | Sibling: the scheduled BS the adapter dispatches into; `pInput` is always null here (`Demo.BS.NightlyExtract`) | `ch05_bpl_dtl/bs-scheduled-cron.cls` |
| §5.2 | Sibling: the dispatch test — RUN, and the control proves the `%Status` cannot be the signal (`Demo.Tests.InboundAdapterDispatch`) | `ch05_bpl_dtl/tdd-inbound-adapter-dispatch.cls` |
| §5.3 | XML projection settings — `XMLIGNORENULL` / `CONTENT` / `OUTPUTTYPEATTRIBUTE` | `ch05_bpl_dtl/xml-projection-settings.cls` |
| §5.4 | ObjectScript try/catch + %Status idiom | `ch05_bpl_dtl/objectscript-trycatch.cls` |
| §5.5 | Async logging via `^IRISTemp.*` + `%SYSTEM.Semaphore` | `ch05_bpl_dtl/async-logger-iristemp-semaphore.cls` |
| §5.6 | Custom BPL — context variables, a sync `<call>`, code-block idiom (`Example.BP.OrderProcess`) | `ch05_bpl_dtl/bpl-order-process.cls` |
| §5.7 | DTL — declared transform, XData escaping, compile-order trap (`Example.DT.OrderToVendor`) | `ch05_bpl_dtl/dtl-order-to-vendor.cls` |
| §5.7 | Sibling: DTL target message, also the `<call>` request type in §5.6 (`Example.MSG.VendorOrder`) | `ch05_bpl_dtl/msg-vendororder.cls` |
| §5.8 | Routing rule — one rule per source msgClass, N `<send>` fan-out (`Example.RUL.OrderRouting`) | `ch05_bpl_dtl/routing-rule-fanout.cls` |
| §5.9 | Canonical `%UnitTest.TestProduction` test for a DTL, with both branches covered | `ch05_bpl_dtl/tdd-testproduction-dtl.cls` |
| §5.10 | Message class design — `%Persistent` leftmost or the message shares `^Ens.MessageBodyD` (`Example.MSG.OrderEvent`) | `ch05_bpl_dtl/msg-persistent-leftmost.cls` |
| §5.10 | Sibling: the only mechanical check for §5.10 — reads `DataLocation`, with a negative control (`Example.Tests.MessageOwnExtent`) | `ch05_bpl_dtl/tdd-message-own-extent.cls` |
| §5.11 | Delete cascade for a `%Persistent` child — `{Address}` not `{ID}`, capture the `%Status`, guard the empty ref (`Example.MSG.PersonReqCascade`) | `ch05_bpl_dtl/msg-persistent-child-delete-cascade.cls` |
| §5.11 | Sibling: the `%Persistent` child that creates the obligation (`Example.DAT.Address`) | `ch05_bpl_dtl/dat-address-persistent.cls` |
| §5.11 | Sibling: the cascade test — RUN, not just compiled, with a negative control (`Example.Tests.DeleteCascade`) | `ch05_bpl_dtl/tdd-delete-cascade.cls` |
| §5.12 | Class-based (non-BPL) `Ens.BusinessProcess` — `pResponseRequired=0` runs the operation and drops the reply (`Example.BP.OrderFulfil`) | `ch05_bpl_dtl/bp-class-based-async.cls` |
| §5.13 | Custom function set, `[ Final ]`, with the six measured call forms in its header (`Example.UTL.FunctionSet`) | `ch05_bpl_dtl/utl-functionset-final.cls` |
| §5.13 | DTL calling BOTH kinds — built-in with `..`, custom with `##class()`; `DependsOn` mandatory (`Example.DT.CensoToMenus`) | `ch05_bpl_dtl/dtl-lookup-and-functions.cls` |
| §5.13 | Sibling: the test — EXECUTED; two of the three wrong call forms are invisible to every tier (`Example.Tests.DtlFunctionForms`) | `ch05_bpl_dtl/tdd-dtl-function-forms.cls` |
| §6.1.1 | `wsp:PolicyReference` (#6447) compile fix | `ch06_adapters/soap-wsdl-policyreference-fix.cls` |
| §6.1.2 | Suppress `xsi:type` for vendor SOAP servers | `ch06_adapters/soap-xsi-type-suppress.cls` |
| §6.1.4 | Drop `REQUIRED=1` from generated SOAP type properties | `ch06_adapters/soap-required-flag-drop.cls` |
| §6.1.4 | Sibling: complex type referenced by the `REQUIRED=1` example (`Example.Vendor.WSC.SAPPatient`) | `ch06_adapters/soap-required-flag-drop-sappatient.cls` |
| §6.1.5 | Downgrade strongly-typed dates/times to `%String` | `ch06_adapters/soap-typed-dates-to-string.cls` |
| §6.1.6 | Override `RESPONSENAMESPACE` to match what the vendor actually returns | `ch06_adapters/soap-response-namespace-override.cls` |
| §6.2 / §12.4 | Per-BO `Alt.SOAP.WebClient` for SOAP tracing | `ch06_adapters/alt-soap-webclient-tracing.cls` |
| §6.4 | Typed SQL parameters via `ExecuteUpdateParmArray` / `ExecuteQueryParmArray` (NULLs, dates, decimals) | `ch06_adapters/sql-bo-typed-parmarray.cls` |
| §6.6 | Java integration via JavaGateway | `ch06_adapters/javagateway-bo.cls` |
| §6.7 | Custom BS with a bare adapter — the case where you DO write the class | `ch06_adapters/bs-file-bare-adapter.cls` |
| §6.8 | REST inbound: `EnsLib.REST.Service`, UrlMap dispatch, CreateBusinessService | `ch06_adapters/bs-rest-inbound.cls` |
| §6.9 | SQL inbound: GenericService poll + the mandatory JGService item + KeyFieldName | `ch06_adapters/production-sql-poll.cls` |
| §6.10 | File passthrough relay — prebuilt service + operation, `Ens.StreamContainer` body, no custom classes (`Example.Productions.FileRelay`) | `ch06_adapters/production-file-passthrough.cls` |
| §6.10 | Sibling: a custom consumer that rewinds BEFORE reading (`Example.BO.ArchiveStream`) | `ch06_adapters/bo-stream-container-consumer.cls` |
| §6.10 | Sibling: the second-read test — EXECUTED, with a negative control (`Example.Tests.StreamContainerRewind`) | `ch06_adapters/tdd-stream-container-rewind.cls` |
| §6.11 | Subclassing a prebuilt service — `##super()` first in `OnInit`; #5478 enforces TYPES, not arity (`Example.BS.CensoWithWarmup`) | `ch06_adapters/bs-recordmap-service-subclass.cls` |
| §6.12 | REST outbound BO — there is **no** `EnsLib.REST.OutboundAdapter`; `Post` takes no URL; capture the `%Status` (`Example.BO.RestOutbound`) | `ch06_adapters/bo-rest-outbound.cls` |
| §7.1 | Canonical `Ens.Alert` circuit, **compiled** — replaces the former `.xml`, whose rule could not compile (`Example.Alerting.Production`) | `ch07_alerting/production-alert-circuit.cls` |
| §7.2 / §12.5 | Alert deduplication FunctionSet (`AlreadyReportedErr` / `AlreadyReportedPerSession`) | `ch07_alerting/alert-dedup-functionset.cls` |
| §11.3 | SAML 2.0 custom security header on a generated SOAP BO | `ch11_security/saml2-custom-security-header.cls` |
| §11.3 | Sibling: request message the SOAP BO's MessageMap keys on (`Demo.SAML.MSG.InvokeReq`) | `ch11_security/saml2-invoke-request.cls` |
| §11.5 | OAuth 2.0 + LDAP server-side broker ⚠️ | `ch11_security/oauth2-server-validate-ldap.cls.xml` |
| §11.7 | SSL/TLS trusted CA chain build (`openssl s_client -servername`) ⚠️ | `ch11_security/ssl-trusted-ca-chain.sh` |
| §13.7 | Credentials migration — walk `Ens.Config.Credentials`, export, re-import | `ch13_migration/credentials-export-reimport.cls` |

## Rules with public-repo canonical sources

The following deliverable rules are best served by reading the public,
maintained version — no local copy here. See `external-repos.md` for URLs.

| Rule | Why no local copy |
|---|---|
| §2.6 HL7 v2 in XML form | Canonical: `intersystems-ib/Healthcare-HL7-XML` (actively maintained) |
| §11.1 SAML 2.0 charset fix | Canonical: `intersystems-ib/SAML-COS` (built specifically to address the bug) |
| §11.4 SAML 1.1 wrapper for e-prescription | Canonical: `intersystems-ib/SAML11-COS` |
| §7.1 | Alert routing rule — the link that makes the Ens.Alert circuit actually fire | `ch07_alerting/alert-routing-rule.cls` |
| §9.1 Deployment tool | Canonical: `PYDuquesnoy/IRIS-Interop-Deployment` |

## ⚠️ Rows that are indexed but NOT compiled

**Two artefacts in this index are checked by no tier, and the ⚠️ on their rows says so at the point
of the claim rather than in a footnote nobody reaches.** (This was three until v1.21.0, when the
§7.1 alert circuit was converted to a compiled class — and the conversion immediately found that its
rule could not compile at all.) Tier 2 stages `.cls` files only, and
`examples_baseline.json` holds class names — so an `.xml` export and a `.sh` script are indexed,
counted in the artefact total, and compiled by nothing:

| artefact | why no tier sees it |
|---|---|
| `ch11_security/oauth2-server-validate-ldap.cls.xml` | an XML **class export** — the `.cls.xml` suffix is not `.cls` |
| `ch11_security/ssl-trusted-ca-chain.sh` | a shell script; there is no shell tier |

This matters because these are not small: the §11.5 OAuth artefact is the largest non-`.cls` item
left in the bank. Tier-1 **C8** does reach the `.xml` files (it is why the alert
circuit's dangling rule name was caught), so they are not *entirely* unchecked — but nothing
compiles them, and a green run must not be read as saying otherwise. Tracked in
`../COVERAGE-MAP.md` (wave item S14 converts the OAuth artefact into a gated `.cls`; S2 did the alerting one in v1.21.0).

## Rules without code (process / architecture / version-specific)

Several deliverable rules are pure guidance with no code component:
naming convention (§1.1), reserved package names (§1.2), namespace split criteria (§1.3),
configuration-source precedence (§1.4), FHIR Façade architecture (§4.1–4.8),
version-specific notes (§14.*), etc. They are not represented here; read the deliverable directly.

## What's explicitly NOT here (and why)

- ~~No BPL, DTL or routing-rule example.~~ **Closed — issue #91 is closed and this bullet was
  stale.** Every clause of it had become false: the bank ships one BPL
  (`ch05_bpl_dtl/bpl-order-process.cls`), one DTL (`ch05_bpl_dtl/dtl-order-to-vendor.cls`) and
  **five** standalone routing-rule classes (`ch01_production/routing-rule-censo.cls`,
  `ch02_hl7v2/routing-rule-hl7-adt.cls`, `ch04_fhir/routing-rule-fhir.cls`,
  `ch05_bpl_dtl/routing-rule-fanout.cls`, `ch07_alerting/alert-routing-rule.cls`) — not "only the
  one inside `alert-circuit-production.xml`". It is called out rather than deleted because a
  *stale* "NOT here" entry is the worst kind: a reader checking whether a sample exists is told it
  does not, and stops looking 40 lines above the row that indexes it.
  The narrower gaps that remain here are tracked per-item in `../COVERAGE-MAP.md`: the only DTL is
  object→object, so nothing demonstrates **symbolic HL7 field paths** (map item S5), and of these
  seven artefacts only the DTL has a `%UnitTest` — `ch05_bpl_dtl/tdd-testproduction-dtl.cls`, the
  one test in the bank that has been *run and mutation-checked* rather than merely compiled.
- **Non-interop chapters removed on 2026-05-13.** The deliverable's original §8 (Performance & sizing), §10 (Mirroring/HA/backups), and most of §13 (generic IRIS migration) were trimmed. The corresponding `examples/ch08_performance/`, `ch10_mirror_backup/`, and parts of `ch13_migration/` were deleted in the same pass. This directory now focuses on **IRIS Interoperability** patterns only.
