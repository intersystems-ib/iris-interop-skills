---
name: dicom
description: DICOM C-STORE/FIND/MOVE, MWL, PACS, STOW-RS. Routed from interop. Triggers: DICOM, C-STORE, C-FIND, C-MOVE, MWL, PACS, STOW-RS, DICOMweb, modality, AE Title, EnsLib.DICOM.
---

# DICOM on IRIS for Health

DICOM is a protocol family of its own inside Interop. The wiring shape, message
types, and runtime semantics differ from HL7v2 / FHIR / SOAP, so the patterns
below are non-portable from the rest of the skill set. The vendored sample
at `${CLAUDE_PLUGIN_ROOT}/BestPractices/external/workshop-iris-dicom-interop/`
(MIT-licensed snapshot — see `UPSTREAM.md` for SHA) is the canonical reference
for every pattern here.

## When to use this skill

The user mentioned DICOM, a modality, PACS, MWL, C-STORE, C-FIND, C-MOVE, STOW-RS,
DICOMweb, AE Title, association context, or any `EnsLib.DICOM.*` class.

## Status: architecture + wiring only

**Do NOT generate DICOM document handlers (`OnMessage`, `CreateFindResponse`,
tag-tree manipulation) line-by-line from this skill.** Those are byte-level,
SOP-class-specific, and easy to get plausible-but-wrong. Steer the user to:

1. The patterns and wiring shapes below.
2. The vendored sample (`iris/src/DICOM/**/*.cls`) as starting code.
3. The IRIS docs: `https://docs.intersystems.com/healthconnectlatest/csp/docbook/DocBook.UI.Page.cls?KEY=EDICOM`.

## Decision tree

| If the user needs… | Pattern | Inbound class | Outbound class |
|---|---|---|---|
| Modality sends images to IRIS (C-STORE) | **Pattern 1** | `EnsLib.DICOM.Service.TCP` | — |
| IRIS queries / retrieves from a PACS (C-FIND + C-MOVE) | **Pattern 3** | `EnsLib.DICOM.Service.TCP` (for C-MOVE return) | `EnsLib.DICOM.Operation.TCP` |
| IRIS answers a modality's worklist query (MWL, C-FIND server) | **Pattern 2** | `EnsLib.DICOM.Service.TCP` | — (SQL outbound for source data) |
| Imaging device POSTs DICOM over HTTP (STOW-RS / DICOMweb) | **Pattern 4** | Custom `Ens.BusinessService` + `%CSP.REST` | `EnsLib.DICOM.Operation.TCP` (to forward) |
| DICOM tag values must reach an HL7 v2 / FHIR pipeline | **Pattern 5** | — | — (cross-skill) |

## Class taxonomy

| Role | Class |
|---|---|
| Inbound DIMSE listener (TCP, all SOP classes) | `EnsLib.DICOM.Service.TCP` |
| Outbound DIMSE caller | `EnsLib.DICOM.Operation.TCP` |
| Process superclass — orchestrates request/response on the association | `EnsLib.DICOM.Process` |
| Message body — full DICOM dataset (CommandSet + DataSet trees) | `EnsLib.DICOM.Document` |
| Streamed pixel data / large attachments | `EnsLib.DICOM.FileStream` |
| AE pair + SOP class registry | `EnsLib.DICOM.Util.AssociationContext` |
| Abort command (used in `OnError`) | `EnsLib.DICOM.Command.Abort` |

`EnsLib.DICOM.Service.TCP` and `EnsLib.DICOM.Operation.TCP` are **duplex**: a
Service holds the association open and routes incoming documents to a Process
via `DuplexTargetConfigName`; a Process sends outbound documents to an
Operation via `OperationDuplexName`. This bidirectional wiring is what makes
DICOM different from "request → response" Interop and is the most common
source of "why doesn't my BO get called" confusion.

## AE Title configuration — register associations in `OnStart`

Every Service/Operation references a `LocalAET` and `RemoteAET`. Before the
production can accept or initiate associations, each AE pair must be
registered with the SOP classes it supports. The vendored sample does this
in `DICOM.Production.OnStart` (see `iris/src/DICOM/Production.cls`):

```objectscript
if '##class(EnsLib.DICOM.Util.AssociationContext).AETExists("DCM_PDF_SCP","IRIS_PDF_SCU") {
    do ##class(DICOM.Util).CreateAssociation(
        "DCM_PDF_SCP","IRIS_PDF_SCU",
        $lb($$$IMPLICITVRLETRANSFERSYNTAX),
        $lb("Storage"))
}
```

Transfer syntaxes are macros from `EnsDICOM.inc` (`$$$IMPLICITVRLETRANSFERSYNTAX`,
`$$$RAWDATAEXPLICITVRLTLENDIAN`, etc.). SOP class lists use friendly names
(`"Storage"`, `"FIND"`, `"MOVE"`) resolved by `DICOM.Util.CreateAssociation`.
**AE Title mismatch is the #1 first-day failure** — log both sides' AE Titles
in `TraceVerbosity=2` and confirm the pair appears in `AssociationContext`.

## Pattern 1 — C-STORE inbound (with optional PDF extraction)

Modality (or any SCU) opens an association and sends DICOM files. IRIS stores
them, optionally extracts embedded payloads (encapsulated PDF, structured
reports), and forwards metadata downstream.

Wiring:

```
SCU  →  EnsLib.DICOM.Service.TCP (BS, IRIS_PDF_SCU @ port 2010)
        DuplexTargetConfigName=DICOM PDF Process
     →  DICOM.BP.PDFProcess (extends EnsLib.DICOM.Process)
        - validates CommandSet.CommandField = "C-STORE-RQ"
        - extracts embedded PDF from DataSet.EncapsulatedDocument
        - builds custom DICOM.Msg.SaveReport (PatientName, StudyDate, file…)
        - SendRequestAsync to a non-DICOM BO (file/HTTP/DB)
        - CreateStorageResponse → SendRequestAsync back to BS
        - StopPrivateSession to free the association
```

Reference: `iris/src/DICOM/BP/PDFProcess.cls` + `iris/src/DICOM/Msg/SaveReport.cls`.
The pattern of "ack with C-STORE-RSP via the same duplex BS, then async forward
to non-DICOM destinations" is the canonical inbound shape.

## Pattern 2 — Modality Worklist (C-FIND server)

A modality asks IRIS what studies are scheduled. IRIS answers with one or more
C-FIND-RSP messages whose `CommandSet.Status` is `Pending` (65281) for each
worklist entry, followed by one final message with `Status=0` (Success).

Wiring:

```
Modality  →  EnsLib.DICOM.Service.TCP (BS, IRIS_WL @ port 1112)
             DuplexTargetConfigName=DICOM WorkList Process
          →  DICOM.BP.WorkListProcess
             - on C-FIND-RQ: build DICOM.Msg.WorkListReq from DataSet.StudyDate
             - SendRequestSync to HIS WorkList Query (SQL outbound BO)
             - iterate JSON result: SendRequestAsync N intermediate C-FIND-RSP
               with Status=65281 (Pending)
             - SendRequestAsync final C-FIND-RSP with Status=0 (Success)
```

Source data flows via `EnsLib.SQL.Operation.GenericOperation` (MySQL JDBC in the
sample). See `business-operations` for the SQL outbound shape and
the JDBC driver/ELS prerequisites. Reference: `iris/src/DICOM/BP/WorkListProcess.cls`.

> **Note** — the vendored sample wires `EnsLib.JavaGateway.Service` as the JDBC
> bridge. In IRIS 2026.1 this class is deprecated in favour of an External
> Language Server (see `business-operations` §"Java Gateway BO"). New
> work should configure the ELS `%JDBC Server` and reference it via the BO
> setting `JGService` instead of adding a JavaGateway production item.

## Pattern 3 — Query / Retrieve a PACS (C-FIND + C-MOVE)

IRIS is the SCU. It calls a PACS to find studies, then asks the PACS to send
matching images to a registered destination AE — which in this pattern is
another `EnsLib.DICOM.Service.TCP` in the same production.

Wiring:

```
DICOM.BS.QueryService  →  DICOM.BP.QueryProcess
                          OperationDuplexName=DICOM TCP Out (IRIS_QRY_SCU)
                       →  EnsLib.DICOM.Operation.TCP  →  PACS (port 3010)

DICOM.BS.MoveService   →  DICOM.BP.MoveProcess
                          OperationDuplexName=DICOM TCP Out
                       →  PACS issues C-STORE back to IRIS_STORE_SCP @ port 2020
                       →  EnsLib.DICOM.Service.TCP (DICOM Store In)
                          DuplexTargetConfigName=DICOM Store Process
                       →  DICOM.BP.StoreProcess
```

C-MOVE requires **both** AE pairs registered in `OnStart`: SCU↔PACS for the
command channel and PACS↔Store-SCP for the returned C-STORE traffic. The Store
SCP listener is a separate `EnsLib.DICOM.Service.TCP` item. Reference:
`iris/src/DICOM/BS/QueryService.cls`, `MoveService.cls`, `BP/QueryProcess.cls`,
`BP/MoveProcess.cls`, `BP/StoreProcess.cls`.

## Pattern 4 — STOW-RS HTTP receiver (DICOMweb)

DICOMweb stack, not DIMSE. A REST endpoint receives multipart/related uploads,
materialises each part as `EnsLib.DICOM.Document`, then forwards to a DIMSE
outbound. The BS subclasses both `Ens.BusinessService` and `%CSP.REST`:

```objectscript
Class DICOM.BS.RESTService Extends (Ens.BusinessService, %CSP.REST)
XData UrlMap {
<Routes>
    <Route Url="/studies" Method="POST" Call="NewStudy"/>
</Routes>
}
```

Per-part flow:

```
mimeData (Content-Type: application/dicom)
  → EnsLib.DICOM.Document.CreateFromDicomFileStream(mimeData, .doc)
  → doc.SetValueAt($$$Str2MsgTyp("C-STORE-RQ"), "CommandSet.CommandField")
  → doc.%Save()  (assigns an Id usable as the BP payload pointer)
  → msg.DICOMDocumentIdList.Insert(doc.%Id())
SendRequestAsync(msg) → DICOM.BP.StowRsHandlerProcess → DICOM TCP Out → DCM_STORE_SCP
```

Respond `HTTP 202 Accepted` (async forwarding). Reference:
`iris/src/DICOM/BS/RESTService.cls` + `BP/StowRsHandlerProcess.cls`.

The web app for the REST endpoint must be registered separately (CSP web
application + dispatch class). See `business-services` for the
`/csp/<app>/` registration and the `AutheEnabled` bitmask (96/97 values
verified on 2026.1).

## Pattern 5 — DICOM ↔ HL7 / FHIR gateway

The bridging direction never uses DTL alone — DICOM tags are an object tree
accessed by string path (`"DataSet.PatientName"`, `"DataSet.ScheduledProcedureStepSequence[1].Modality"`),
not a flat structure. The pragmatic shape:

1. A DICOM Process (`EnsLib.DICOM.Process` subclass) reads the relevant tags
   in `OnMessage` and builds a **custom message class** (`%Persistent` extending
   `Ens.Request`) carrying the extracted scalars.
2. A standard router (`bpl`) sends the custom message to a DTL
   that produces HL7v2 (`ORM^O01`, `ORU^R01`) or to an HL7-FHIR-DTL stack
   (`HS.FHIR.DTL.*`) producing `ImagingStudy` / `DiagnosticReport`.

Pure DTL inside the DICOM Process is rare and brittle; keep tag extraction in
ObjectScript and let DTL operate on the canonical custom message. Cross-refs:
`messages` (custom message design), `transformations`
(DTL), `bpl` (router), `fhir` (FHIR resource shape).

## Production wiring example (minimal)

A complete sample production lives at `iris/src/DICOM/Production.cls`. The
minimal stanza for a C-STORE listener + duplex Process:

```xml
<Item Name="DICOM PDF In" ClassName="EnsLib.DICOM.Service.TCP" PoolSize="1">
  <Setting Target="Host" Name="DuplexTargetConfigName">DICOM PDF Process</Setting>
  <Setting Target="Adapter" Name="LocalAET">IRIS_PDF_SCU</Setting>
  <Setting Target="Adapter" Name="RemoteAET">DCM_PDF_SCP</Setting>
  <Setting Target="Adapter" Name="IPPort">2010</Setting>
</Item>
<Item Name="DICOM PDF Process" ClassName="DICOM.BP.PDFProcess" PoolSize="1"/>
```

The Service is `PoolSize=1` (TCP listener); the Process is `PoolSize=1` per
concurrent association you expect to serve. **Custom DIMSE Services that are
purely API entry points (like `DICOM.BS.QueryService` invoked from code with
`TestFind()`) use `PoolSize=0`** because they have no listening adapter — the
sample's `QueryService` and `MoveService` follow that convention.

## Sample namespaces inside IRIS

IRIS ships with `DICOMSAMPLES` and `DICOMTOOLKITSAMPLES` namespaces containing
the historical reference productions. They are useful for poking at the class
tree from the management portal, but they are older than the vendored sample
and use less idiomatic 2024-era patterns. **Default starting point: the
vendored sample**, fall back to the in-namespace samples only for tag-level
spelunking.

## Running it end-to-end (upstream lab)

The vendored snapshot here keeps only the ObjectScript **source** (`iris/src/DICOM/`).
The **upstream repo** ships a self-contained runnable lab — `docker-compose.yml`
brings up:

- `iris` (IRIS for Health) with the production pre-installed
- `mysql` (MWL source DB)
- `tools` (dcm4che container with `storescu` / `findscu` / `dcmqrscp` / `stowrs`)

plus a `shared/` volume with sample `.dcm` files, a PDF for embedded-report
generation, and `ae.properties` for the simulator. To run end-to-end tests
without an external PACS, clone `intersystems-ib/workshop-iris-dicom-interop`,
`docker-compose up -d`, and follow its README.

## TLS for DIMSE

Mutual-TLS between SCU and SCP is configured per AE/component, not at instance
level. The upstream repo's `TLS.md` walks through CA + server + client cert
generation with `openssl` and the IRIS-side SSL/TLS Configuration. Cross-ref
to `security` for cert chain validation patterns.

## Common pitfalls

- **AE Title mismatch** — #1 first-day failure; register the pair in `OnStart`
  and verify with `TraceVerbosity=2` — see §"AE Title configuration" above.
- **Transfer syntax negotiation** — sender offers JPEG-lossless, IRIS only
  registered `IMPLICITVRLETRANSFERSYNTAX`. Association is rejected. List every
  syntax you intend to support in the `$lb(...)` passed to `CreateAssociation`.
- **C-MOVE return path not registered** — the destination AE the SCU asks for
  must be a known peer in the SCP's AE table **and** must have a listening
  Service in your production. C-MOVE silently drops if either side is missing.
- **Encapsulated-PDF SOP UID** — embedded PDFs use the `EncapsulatedPDFStorage`
  SOP class (`1.2.840.10008.5.1.4.1.1.104.1`). A `pdf2dcm` invocation with the
  wrong template emits a different SOP UID and the PACS refuses the store.
- **MWL date format** — `DataSet.StudyDate` is DICOM `YYYYMMDD`, not ISO 8601.
  Convert with `$zdateh(value, 5)` before binding to SQL parameters.
- **Pixel data purge** — DICOM messages embed large binary streams. The
  default `Ens.MessageBodyD` purge handles the header but not the stream
  files. Plan a file-stream-aware purge task (`production-lifecycle`).
- **Duplex topology** — forgetting `DuplexTargetConfigName` on the Service or
  `OperationDuplexName` on the Process: the association opens, the document
  arrives, and nothing receives it. The trace shows the document but no
  downstream activity. Both settings are required.
- **`PoolSize=0` vs `1`** — TCP listener Service is `1`. Pure API-call
  Services (no inbound adapter) are `0`. Getting this wrong on the listener
  causes the port to never open.

## When NOT to use this skill — fall back to docs

- Byte-level pixel decoding, windowing, DICOM-rendering pipelines.
- DICOM Structured Report (SR) authoring beyond reading existing reports.
- Advanced DICOMweb (QIDO-RS, WADO-RS Bundle shaping, retrieve-and-render).
- Modality Performed Procedure Step (MPPS) flows.
- Custom DIMSE service profiles outside the Storage / Verification / Q-R /
  MWL set.

For all of the above: IRIS DICOM docs + the vendored sample + the upstream
`dcm4che` documentation.

## See also

- `production-lifecycle` — wiring DICOM components, purge tasks
  for streamed pixel data, `OnStart` patterns.
- `business-services` — when the gateway side is non-DICOM
  (HTTP, file, REST) and for `/csp/<app>/` web-app registration of STOW-RS.
- `business-operations` — SQL outbound for MWL source data, JDBC
  / External Language Server setup.
- `messages` — custom `%Persistent` `Ens.Request` classes
  carrying tags extracted from DICOM into the canonical pipeline.
- `transformations` — DTL on the canonical custom message (NOT
  on `EnsLib.DICOM.Document` directly).
- `bpl` — routers in the bridge half of a DICOM↔HL7/FHIR gateway.
- `fhir` — `ImagingStudy` / `DiagnosticReport` for DICOM→FHIR.
- `security` — TLS configuration for DIMSE mutual auth.

## Reference

- **Local snapshot (canonical):** `${CLAUDE_PLUGIN_ROOT}/BestPractices/external/workshop-iris-dicom-interop/` (frozen, MIT, see `UPSTREAM.md` for SHA)
- **Upstream:** https://github.com/intersystems-ib/workshop-iris-dicom-interop
- **IRIS docs:** https://docs.intersystems.com/healthconnectlatest/csp/docbook/DocBook.UI.Page.cls?KEY=EDICOM
- **dcm4che tools (used by the snapshot's `tools` container):** https://github.com/dcm4che/dcm4che
