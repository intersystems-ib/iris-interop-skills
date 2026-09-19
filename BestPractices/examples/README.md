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
| §1.14 | Drift check, disk vs namespace — the `#1012` postconditional trap, and the two ways the report lies (`Example.UTL.DriftReport`) | `ch01_production/drift-report-disk-vs-namespace.cls` |
| §1.15 | Pre-flight validator — three-valued verdict, every router matched, and `TOP 1` picked `Ens.Alert` (`Example.UTL.PreflightValidator`) | `ch01_production/production-preflight-validator.cls` |
| §1.16 | System Default Settings orphan report — host **∪ adapter** settings | `ch01_production/default-settings-audit.cls` |
| §1.16 | Sibling: the run, whose key assertion is that adapter settings are NOT flagged | `ch01_production/tdd-default-settings-audit.cls` |
| §1.17 | RecordMap `.Record` generation bootstrap — idempotent, and it names what is wrong | `ch01_production/recordmap-generate-bootstrap.cls` |
| §1.17 | Sibling: the run that found the bank's own RecordMap was never generated | `ch01_production/tdd-recordmap-getobject-encoding.cls` |
| §1.18 | Production lifecycle helper — the ladder, and verdicts that read the STATE back | `ch01_production/production-lifecycle-helper.cls` |
| §1.18 | Sibling: the run — `RecoverProduction()` returns OK from Stopped | `ch01_production/tdd-production-lifecycle.cls` |
| §1.19 | MLLP production — the Host/Adapter split, with three defaults overridden | `ch02_hl7v2/production-hl7-mllp.cls` |
| §1.20 | Scheduled work via `%SYS.Task.Definition` — the dispatch line, and why not `%SYS.TaskSuper` | `ch01_production/task-definition-scheduled-bs.cls` |
| §1.21 | Fixture: a RecordMap with `%Integer` and `%Date` fields, to show what the type does and does not do | `ch01_production/recordmap-typed-fields-fixture.cls` |
| §1.21 | The message a validating transform produces — raw text, a verdict, and a boolean beside it | `ch01_production/msg-censo-validated.cls` |
| §1.21 | Validate per record in the DTL: flag and route, never reject by omission | `ch01_production/dtl-censo-validate-flags.cls` |
| §1.21 | Oracle: pins parse-vs-validate per datatype, the unchecked field count, and the flagging transform | `ch01_production/tdd-censo-validate-flags.cls` |
| §1.20 | Scheduling the purge task — `NumberOfDaysToKeep`, and `TypesToPurge` defaulting to events | `ch01_production/purge-task-schedule.cls` |
| §1.20 | Oracle: the spelling with a positive control, the two silent defaults, and a real task round-trip | `ch01_production/tdd-scheduled-task.cls` |
| §1.19 | Its rule (a `production=` attribute pins a rule to one production) | `ch02_hl7v2/routing-rule-hl7-mllp.cls` |
| §1.19 | Sibling: the sweep — every setting's Target vs where the property lives | `ch02_hl7v2/tdd-mllp-setting-targets.cls` |
| §1.15 | Sibling: naming the destination by READING it (CR-13) — value, `Target` and found/not-found (`Example.Tests.DestinationAssert`) | `ch05_bpl_dtl/tdd-destination-assert.cls` |
| §2.3 | HL7 v2 escape special characters when building messages manually | `ch02_hl7v2/hl7v2-escape-functionset.cls` |
| §1.11 | Routing rule for the RecordMap intake — where the DTL belongs instead of a BS subclass | `ch01_production/routing-rule-censo.cls` |
| §2.10 | HL7 v2 file intake: prebuilt HL7 FileService + the HL7-SPECIFIC router (CR-6) | `ch02_hl7v2/production-hl7-intake.cls` |
| §2.10 | HL7 routing rule: the HL7 assist class + docCategory/docName constraints (CR-5, CR-6) | `ch02_hl7v2/routing-rule-hl7-adt.cls` |
| §2.10 | Sibling: the **two-direction** router test — valid → target AND malformed → `BadMessageHandler`; RUN against a live production (`Example.Tests.Hl7RouterValidation`) | `ch02_hl7v2/tdd-hl7-router-validation.cls` |
| §2.11 | HL7 DTL with **symbolic** field paths — a mistyped path compiles clean and resolves to nothing (`Example.DT.AdtNormalise`) | `ch02_hl7v2/dtl-hl7-symbolic-paths.cls` |
| §2.11 | Sibling: the HL7 fixture test — EXECUTED; its control shows `""` cannot tell a bad path from an empty field (`Example.Tests.Hl7SymbolicPaths`) | `ch02_hl7v2/tdd-hl7-fixture-test.cls` |
| §2.12 | HL7 search table with **symbolic** paths, and the assignment that makes it index | `ch02_hl7v2/searchtable-hl7-adt.cls` |
| §2.12 | Sibling: the run — four join shapes, and the DocType-less silent miss | `ch02_hl7v2/tdd-searchtable-rows-landed.cls` |
| §2.13 | Headless HL7 schema bootstrap — grammar in `XData`, and the two-global removal | `ch02_hl7v2/schema-bootstrap-sqlproc.cls` |
| §2.13 | Sibling: the run — resolution arities, and the base-fallback that looks like success | `ch02_hl7v2/tdd-hl7-schema-registration.cls` |
| §2.14 | Repeating-segment DTL — index loop, and PID needs it too in a grouped message | `ch02_hl7v2/dtl-hl7-repeating-segments.cls` |
| §2.14 | The per-repeat sub-transform (`EnsLib.HL7.Segment` → `Ens.StringContainer`) | `ch02_hl7v2/dtl-obx-to-text.cls` |
| §2.14 | Sibling: the `list Of` target one entry per repeat lands in | `ch02_hl7v2/msg-obs-summary.cls` |
| §2.14 | Sibling: the run — asserts THREE repeats, not the absence of an error | `ch02_hl7v2/tdd-hl7-repeating-segments.cls` |
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
| §4.11 | FHIR DTL over a QuickStreamId — `<assign>`ing the id is a reference copy; the body needs a `<code>` block | `ch04_fhir/dtl-fhir-redact-quickstream.cls` |
| §4.12 | Refuse a Bundle that is not a `transaction` — `batch` is accepted by the server and is not atomic | `ch04_fhir/fhir-bundle-transaction-guard.cls` |
| §4.12 | Oracle: seven type values, plus a drift alarm on the shipped `DefaultBundleProcessor` branching | `ch04_fhir/tdd-fhir-bundle-transaction-guard.cls` |
| §4.13 | Existence test by dictionary lookup — a call-through to a missing method compiles clean | `ch04_fhir/fhirsql-setup-existence-test.cls` |
| §4.13 | Oracle: five `#5373` compile probes, the FHIR SQL signature drift alarm, and the two comma guards | `ch04_fhir/tdd-fhirsql-setup-existence.cls` |
| §4.11 | BP that edits a FHIR payload — `$IsObject(%OpenId(...))` not `%ExistsId`, and one new stream per request | `ch04_fhir/bp-fhir-request-quickstream.cls` |
| §4.11 | Oracle: no payload property, `%ExistsId` lies, `%Save()` does not flush | `ch04_fhir/tdd-fhir-quickstream-payload.cls` |
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
| §5.13 | Sibling: the lookup proof — loads a real table and shows the normalised key HITS while the raw one returns the default (`Example.Tests.LookupNormalize`) | `ch05_bpl_dtl/tdd-lookup-normalize.cls` |
| §5.14 | Reading a `%UnitTest` verdict from a SqlProc — `TestMethod.Status`, not assert-scanning, which reports `passed=2 failed=0` for a FAILED case (`Example.UTL.UnitTestResult`) | `ch05_bpl_dtl/unittest-sqlproc-result-reader.cls` |
| §5.15 | Message `%String` boundaries — bare (50), sized, and `MAXLEN=""` | `ch05_bpl_dtl/msg-maxlen-boundaries.cls` |
| §5.15 | Sibling: the run that settles reject-vs-truncate, and the second ceiling | `ch05_bpl_dtl/tdd-maxlen-truncation.cls` |
| §5.16 | `ConvertDateTime` oracle — all five documented rows, both silent failure modes, and the `$ZDATEH` non-equivalence | `ch05_bpl_dtl/tdd-convertdatetime-cheatsheet.cls` |
| §5.17 | Lookup bootstrap — transaction-bracketed, `SQLCODE`-checked, row-count asserted | `ch05_bpl_dtl/lookup-bootstrap-sqlproc.cls` |
| §5.17 | Sibling: the run proving a non-transactional reload leaves a partial table | `ch05_bpl_dtl/tdd-lookup-bootstrap.cls` |
| §5.18 | %UnitTest fixture lifecycle + the `GetEventLog` window floor (S27+S28 folded) | `ch05_bpl_dtl/tdd-lifecycle-and-eventlog.cls` |
| §5.19 | BPL `<flow>`/`<sync>` fan-out template — the shape `bpl` forbids improvising | `ch05_bpl_dtl/bpl-flow-sync-aggregate.cls` |
| §5.21 | BPL `<scope>`/`<catchall>` — a handler that logs and falls through completes the process GREEN | `ch05_bpl_dtl/bpl-scope-catchall-compensation.cls` |
| §5.22 | A collection's child table is projected only if asked — and `array` and `list` default oppositely | `ch05_bpl_dtl/msg-list-collection-child-table.cls` |
| §5.22 | Oracle: each absence asserted next to a presence from the same query, plus the `element_key` type split | `ch05_bpl_dtl/tdd-list-collection-projection.cls` |
| §5.23 | Oracle: asserts that `tdd`'s two weak assertions BOTH pass on a BPL whose every `<call>` failed | `ch05_bpl_dtl/tdd-testproduction-bpl.cls` |
| §5.23 | Fixture, deliberately carrying the §5.21 defect so the assertion gap is demonstrable | `ch05_bpl_dtl/bpl-scope-swallow-fixture.cls` |
| §5.23 | Fixture: the swallowing and propagating BPLs in one production, so the contrast is asserted | `ch05_bpl_dtl/production-bpl-assertions.cls` |
| §5.24 | A message holding the same data as a typed list AND a legacy delimited string | `ch05_bpl_dtl/msg-dual-representation.cls` |
| §5.24 | The transform that fills both — `Serialize()` before `$ListToString`, and rejects a delimiter collision | `ch05_bpl_dtl/dtl-fill-both-representations.cls` |
| §5.24 | Oracle: pins the empty side, the OREF-as-scalar trap, the lossy collision, and that the empty guard is inert | `ch05_bpl_dtl/tdd-fill-both-representations.cls` |
| §5.21 | Oracle: the BP's own header is 8 (Error) only because the catchall sets `status` | `ch05_bpl_dtl/tdd-bpl-scope-catchall.cls` |
| §5.21 | Fixture: the BPL plus a target that fails on demand, reusing `Example.BO.FailOnDemand` | `ch05_bpl_dtl/production-bpl-scope.cls` |
| §5.19 | The audit that makes an un-awaited async call loud | `ch05_bpl_dtl/utl-bpl-sync-audit.cls` |
| §5.19 | Sibling: the run, incl. the false clean a line-based scan produced | `ch05_bpl_dtl/tdd-bpl-sync-audit.cls` |
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
| §6.13 | SQL batch in one transaction — autocommit IS the start; flag-guarded restore; keep the rollback's status out of yours (`Example.Adapters.BO.SqlBatchTransaction`) | `ch06_adapters/sql-bo-batch-transaction.cls` |
| §6.14 | The adapter-less BO — local `%Persistent` save, status **returned** | `ch06_adapters/bo-local-object-save.cls` |
| §6.14 | Sibling: the run — three silent modes, and the filtered count that hid one | `ch06_adapters/tdd-local-save-status.cls` |
| §6.15 | Manual HTTP envelope BO — 3-arg vs 6-arg, and booleans that fail both polarities | `ch06_adapters/http-manual-envelope-bo.cls` |
| §6.15 | Sibling: the run, against a real HTTP response | `ch06_adapters/tdd-http-response-reading.cls` |
| §6.16 | Typed SOAP BO — client class from configuration, and the trade-off | `ch06_adapters/soap-bo-typed-adapter.cls` |
| §6.16 | Sibling: the request the MessageMap keys on | `ch06_adapters/msg-forecast-request.cls` |
| §6.16 | Sibling: the response, whose boolean stays a `%String` on purpose | `ch06_adapters/msg-forecast-response.cls` |
| §6.16 | Sibling: the run — closes the last placeholder-dependency exemption | `ch06_adapters/tdd-soap-bo-adapter-wiring.cls` |
| §6.17 | SOAP inbound service in **adapter mode** (keeps the inherited adapter) | `ch06_adapters/soap-inbound-adapter-service.cls` |
| §6.18 | Resolve a path from a Setting — `InstallDirectory` is on `%SYSTEM.Util`, and an absolute value escapes the tree | `ch06_adapters/path-from-setting-and-runtime.cls` |
| §6.19 | Inbound SOAP Basic auth: `OnPreWebMethod` must deny with `ReturnFault`, since a returned `%Status` is discarded | `ch06_adapters/soap-inbound-onprewebmethod-auth.cls` |
| §6.19 | Fixture: a production must be running AND its item named after the class, or the guard never executes | `ch06_adapters/production-soap-authguard.cls` |
| §6.19 | Oracle: real SOAP POSTs, positive control first; mutation 1 reopens the hole for an uncredentialed caller | `ch06_adapters/tdd-soap-onprewebmethod-deny.cls` |
| §6.20 | `%SOAP.WSDL.Reader.Process` behind one call site — a typed `#Dim` documents, it does not gate | `ch06_adapters/soap-wsdl-reader-generate.cls` |
| §6.20 | Oracle: the formal spec from the dictionary, a generation run from a local file, and the `MakeBusinessOperation` differential | `ch06_adapters/tdd-wsdl-reader-signature.cls` |
| §6.21 | Headless SQL connection probe via `[SqlProc]` — `Connect()` not `OnInit()`, and `Do` not `Set` on `Disconnect` | `ch06_adapters/sql-adapter-headless-probe.cls` |
| §6.21 | Oracle: pins raise-vs-status for both `JGService` states, both DSN routes, and `Disconnect`'s void return | `ch06_adapters/tdd-sql-adapter-headless.cls` |
| §6.18 | Oracle: the wrong class compiles and dies at run time, and both escape routes are refused | `ch06_adapters/tdd-path-from-setting.cls` |
| §6.17 | The production wiring both modes, with the FQCN item-name exception | `ch06_adapters/production-soap-inbound.cls` |
| §6.17 | Sibling: the run — which target the setting belongs on, and why | `ch06_adapters/tdd-soap-inbound-targets.cls` |
| §7.1 | Canonical `Ens.Alert` circuit, **compiled** — replaces the former `.xml`, whose rule could not compile (`Example.Alerting.Production`) | `ch07_alerting/production-alert-circuit.cls` |
| §7.2 / §12.5 | Alert deduplication FunctionSet (`AlreadyReportedErr` / `AlreadyReportedPerSession`) | `ch07_alerting/alert-dedup-functionset.cls` |
| §7.4 | Oracle for the whole circuit — first/second/different-message, the per-session guard outside a host process, and the purge | `ch07_alerting/tdd-alert-dedup.cls` |
| §7.4 | Fixture: a BO that fails on demand, so `AlertOnError` can be exercised | `ch07_alerting/bo-fail-on-demand.cls` |
| §7.4 | Fixture: an `Ens.AlertRequest` recorder standing in for the email operation | `ch07_alerting/bo-alert-recorder.cls` |
| §7.4 | Fixture: the `Ens.Alert` rule with the dedup guards in front of the send | `ch07_alerting/rul-alert-dedup-fixture.cls` |
| §7.4 | Fixture: the §7.1 circuit made startable — no SMTP, no adapters, no ports | `ch07_alerting/production-alert-dedup-fixture.cls` |
| §11.3 | SAML 2.0 custom security header on a generated SOAP BO | `ch11_security/saml2-custom-security-header.cls` |
| §11.3 | Sibling: request message the SOAP BO's MessageMap keys on (`Demo.SAML.MSG.InvokeReq`) | `ch11_security/saml2-invoke-request.cls` |
| §11.5 | OAuth 2.0 + LDAP server-side broker — a **subclass** of `%OAuth2.Server.Validate` | `ch11_security/oauth2-server-validate-ldap.cls` |
| §11.7 | SSL/TLS trusted CA chain build (`openssl s_client -servername`) ⚠️ | `ch11_security/ssl-trusted-ca-chain.sh` |
| §11.13 | Executable check for §11.7 step 1 — `VerifyPeer` via a `New $Namespace` hop to `%SYS` | `ch11_security/ssl-config-verifypeer-assert.cls` |
| §11.14 | Client-side PKCE: IRIS's only PKCE method is Private, so verifier and base64url challenge are yours | `ch11_security/oauth2-client-pkce.cls` |
| §11.14 | Oracle: a cross-checked digest vector, the three illegal Base64 characters, and the challenge/verifier mix-up | `ch11_security/tdd-oauth2-client-pkce.cls` |
| §11.13 | Oracle: every verdict, the live read, and what dropping `New $Namespace` costs | `ch11_security/tdd-ssl-verifypeer.cls` |
| §12.6 | Resend vs edit-and-resend — clone the body first, or the original message is rewritten | `ch12_monitoring/resend-edit-and-resend.cls` |
| §12.6 | Oracle: two headers over one body row, and an edit visible through the original | `ch12_monitoring/tdd-resend-edit-and-resend.cls` |
| §12.6 | Fixture: two queued sinks, no adapters, for the resend tests | `ch12_monitoring/production-resend-fixture.cls` |
| §12.6 | Fixture: a terminal BO that keeps a receipt, so delivery can be asserted | `ch12_monitoring/bo-message-sink.cls` |
| §13.7 | Credentials migration — walk `Ens.Config.Credentials`, export, re-import | `ch13_migration/credentials-export-reimport.cls` |
| §15.4 | DICOM MWL date FunctionSet — `$ZDATEH` format 5 and the ninth-slot error trap | `ch15_dicom/dicom-mwl-date-functionset.cls` |
| §15.5 | DICOM association registrar — verify the presentation-context COUNT, and repair a context that saves clean with none | `ch15_dicom/utl-dicom-association-registrar.cls` |
| §15.6 | Query/retrieve wired as four legs — the retrieved images arrive on a third inbound service | `ch15_dicom/production-dicom-query-retrieve.cls` |
| §15.6 | The duplex partner every DICOM service and operation needs, shared by three items | `ch15_dicom/bp-dicom-leg.cls` |
| §15.6 | Oracle: four distinct legs, every duplex name resolves, read through the item OBJECT | `ch15_dicom/tdd-dicom-query-retrieve.cls` |
| §15.5 | DICOM production registering its AE pairs from `OnStart`, with the pairs in one place | `ch15_dicom/production-dicom-onstart-associations.cls` |
| §15.5 | Oracle: an empty context validates and saves, `AETExists` lies, and the production/OnStart titles must agree | `ch15_dicom/tdd-dicom-onstart-associations.cls` |
| §15.4 | Sibling: the run, whose central assertion is the off-by-one the first draft made | `ch15_dicom/tdd-dicom-mwl-date.cls` |

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

**One artefact in this index is checked by no tier, and the ⚠️ on its row says so at the point
of the claim rather than in a footnote nobody reaches.** (This was three until v1.21.0, when the
§7.1 alert circuit was converted to a compiled class — and the conversion immediately found that its
rule could not compile at all; two until v1.35.0, when the §11.5 OAuth artefact became a compiled
subclass and the conversion found that the copy it replaced had emptied the server's claim list and
was written against a five-parameter `ValidateUser` the vendor has since grown a sixth formal on.)
Tier 2 stages `.cls` files only, and `examples_baseline.json` holds class names — so a `.sh` script
is indexed, counted in the artefact total, and compiled by nothing:

| artefact | why no tier sees it |
|---|---|
| `ch11_security/ssl-trusted-ca-chain.sh` | a shell script; there is no shell tier |

There are no `.xml` class exports left in the bank, so tier-1 **C8** — which reached inside them,
and is why the alert circuit's dangling rule name was caught — now has nothing to inspect here. What
remains uncompiled is one shell script, and a green run must not be read as covering it. Tracked in
`../COVERAGE-MAP.md` (S14 converted the OAuth artefact in v1.35.0; S2 did the alerting one in
v1.21.0).

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
