# External canonical repositories

When the deliverable cites a public InterSystems-Iberia (or PYD-personal) GitHub
repo as the **canonical** version of a pattern, the local example is intentionally
omitted to avoid drift. The repo is the maintained version; reconstruct from the
notes only if the repo is unreachable.

## External-repo snapshots — convention

When a Skill upgrade vendors a third-party repo as a frozen local reference
(for offline workshops, or to harden against the upstream disappearing), the
snapshot lives at `BestPractices/external/<repo-name>/`
with:

- the upstream tree, minus the nested `.git` directory (snapshot, not submodule)
- the original `LICENSE` preserved (required for attribution)
- an `UPSTREAM.md` marker documenting upstream URL, license, SHA at clone time,
  clone date, and refresh policy

The snapshot is committed to this workshop repo. **Refresh = re-clone**, not
in-place edit. So far one such snapshot exists (DICOM, below); SAML-COS,
SAML11-COS, Healthcare-HL7-XML, and the deploy-tool repos remain
fetch-on-demand without a local snapshot.

## SAML

### `https://github.com/intersystems-ib/SAML-COS`

**Canonical for:** §11.1 (SAML 2.0 — native `%SAML` charset bug).

ObjectScript implementation of SAML 2.0 designed to address the Latin-1 charset
bug in the native `%SAML.Assertion` (rejected by a regional health authority's
document exchange with a SOAP fault whenever the assertion contains any
non-Latin-1 character).

Replaces the older 2017–2019 workaround that generated the SAML assertion via
external Java code (a regional SAML module, or a custom JAR via JavaGateway).

### `https://github.com/intersystems-ib/SAML11-COS`

**Canonical for:** §11.4 (SAML 1.1 wrapper for the e-prescription service).

A national e-prescription service requires SAML 1.1 in the SOAP header.
Native Ensemble `%SAML` is 2.0-only. This package was built by InterSystems
Iberia by copying `%SAML` and adapting:

- Namespace `urn:oasis:names:tc:SAML:1.0:assertion`
- `AssertionID` instead of `ID`
- `MajorVersion` / `MinorVersion` instead of `Version`
- `Issuer` is a string attribute, not a `NameID` element
- Subject moves into the StatementList
- `%XML.Security.Signature` cloned to `SAML11.XML.Security.Signature` so
  `GetNodeById` matches `AssertionID` instead of `ID`
- **GUID-style AssertionIDs are rejected by the service**; use a fixed-format ID
  like `_23f8a4ad91cd56ff7715912dd6ab072f`
- In `SAML11.AttributeValue`, suppress the `xsi:type` attribute (emitting it
  triggers a 1.1 validation error)

## HL7 v2 in XML form

### `https://github.com/intersystems-ib/Healthcare-HL7-XML`

**Canonical for:** §2.6 (HL7 v2 in XML form), §3.4 (SOAP carrying HL7).

Public InterSystems-Iberia helper package for converting HL7 v2 into XML form
and back. Useful when you need to carry HL7 v2 inside a SOAP MessageBody or
store it as XML in a non-IRIS system.

Originally an internal helper package carried from project to project before it
was published; the public repo is now the maintained version — use it, not a
copy pasted out of an old project tree. Install via
`zpm "install healthcare-hl7-xml"`.

Test fixtures shipped with the package (cited as templates in the deliverable):

- `2.5_OBX5-ST.hl7.xml` — typical OBX-5 string-type result
- `2.5_ORMO01.hl7.xml` — order entry
- `ITB_ADTA01-EscapeField.hl7.xml` — ADT with field-escape characters
  (notorious bug source in custom parsers)
- `ITB_OBX5.hl7.xml` — alternate OBX-5
- `ITB_ORU-Inmutable.hl7.xml` — observation result with the "immutable" rule
- `ITB_ORUR01-FT.hl7.xml` — ORU-R01 with formatted-text segments

## DICOM interop

### `https://github.com/intersystems-ib/workshop-iris-dicom-interop`

**Canonical for:** DICOM-interop reference patterns (mentioned in Appendix B);
cited by the `iris-interop-skills:dicom` skill (`skills/dicom/SKILL.md`) for all
five wiring patterns (C-STORE inbound, MWL server, Q/R, STOW-RS,
DICOM↔HL7/FHIR gateway).

Workshop / reference implementation for DICOM interop on IRIS for Health.
Not tied to a specific §-rule in the deliverable; useful as starting point
when a customer needs DICOM-to-HL7 or DICOM-to-FHIR conversion.

**Local snapshot:** `BestPractices/external/workshop-iris-dicom-interop/`
(frozen at SHA `75dcf2f3...`, clone date 2026-05-14, MIT; see `UPSTREAM.md`
in the snapshot directory for the full record).

## Deployment tool

### `https://github.com/PYDuquesnoy/IRIS-Interop-Deployment`

**Canonical for:** §9.1 (deployment tool lineage).

A deploy tool that evolved across several customer projects into the
open-source `PYDuquesnoy/IRIS-Interop-Deployment`.

Open-source, **not** InterSystems-supported. Stores per-environment values in
an `InteropTools_CFG.ConfigurationSites` table with columns
`ValueDEV / ValueDEVLOCAL / ValuePRE / ValuePROD`. Export produces 4 files:
`.xml` (classes), `.prd` (production cfg), `.sit` (site cfg), `.vxm` (virtual docs).
Import auto-backups, imports, recompiles, restarts production, prints rollback
command.

## How to consume these from a Claude Skill

Treat the repos as **fetch-on-demand** sources. The deliverable's rule body
contains enough to know which repo, and which file within it, to retrieve.

If a Skill needs to reproduce a SAML 1.1 wrapper, the right move is:

1. Pull `intersystems-ib/SAML11-COS` from GitHub.
2. Read the deliverable §11.4 for the constraints (fixed-format ID,
   suppress `xsi:type` on `AttributeValue`, etc.).
3. Use the public repo as the canonical implementation; only fall back to
   reconstructing the pattern from the deliverable if the repo is unreachable.
