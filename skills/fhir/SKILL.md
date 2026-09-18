---
name: fhir
description: FHIR Facade/Repository, OAuth PKCE, R4 Bundles. Routed from interop. Triggers: FHIR, Façade, Repository, OAuth2 PKCE, R4 Bundle, SMART-on-FHIR, FHIR SQL Builder, recurso FHIR.
---

# FHIR on IRIS for Health

FHIR work on IRIS splits along **two architectural patterns**. Picking the wrong one is the most expensive mistake — it dictates data ownership, sync model, and operational scope.

## When to use this skill

The user mentioned FHIR, a Façade, a Repository, OAuth2 PKCE, Bundle resources, SMART-on-FHIR, or FHIR SQL projection.

## Prerequisite — a FOUNDATION namespace. Nothing below works without it

**Do this before the decision tree, not after the first `<CLASS DOES NOT EXIST>`.** `HS.*` is not
mapped into an ordinary namespace: in `USER`, `HS.FHIRServer.Interop.Operation` does not exist, so
every reference reads as a typo and the reflex is to hunt for the real class name. There isn't one
— the namespace is wrong. And `Ens.Director` resolves either way, so "the namespace is
interop-enabled" is **not** the same answer.

AFNS, opening line: *"Every interoperability-enabled production needs a special
interoperability-enabled namespace called a foundation namespace."* On IRIS for Health and Health
Connect this is how an interop namespace is initialised at all — it is not a FHIR-specific step.
(On plain IRIS there is no `HS.*` and no Foundation concept; see `interop` §"Foundation namespaces".)

**Check, with the discriminator being whether the table exists at all:**

```
iris_query(namespace="<NS>", query="SELECT Name, Type, Activated FROM HS_Util_Installer.ConfigItem")
  Foundation  -> a row, Type='Foundation', Activated=1
  plain       -> SQLCODE -30, Table 'HS_UTIL_INSTALLER.CONFIGITEM' not found
```

**Create or convert — the same call does both** (AFNS sections 2 and 3):

```
iris_execute(namespace="HSLIB", code="Do ##class(HS.Util.Installer.Foundation).Install(""<NS>"")")
```

Then the FHIR server itself, per HXFHIRINS section 2.3.1:

```objectscript
 Set $namespace = "<NS>"
 Do ##class(HS.FHIRServer.Installer).InstallNamespace()
 Do ##class(HS.FHIRServer.Installer).InstallInstance("/csp/healthshare/<ns>/fhir/r4",
     "HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy", $lb("hl7.fhir.r4.core@4.0.1"))
```

Two things that surprise people afterwards: `Install()` also creates a
`<NS>PKG.FoundationProduction`, so a production you did not write shows up in
`iris_production(action=status)`; and if you use SDA3 transformations you must import the SDA3
schema separately (AFNS section 4, Management Portal → Health → *namespace* → Schema Documentation).

Worked, compile-gated example of the interop wiring:
`${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch04_fhir/production-fhir-facade.cls`

## Decision tree — Façade vs Repository

| If… | Use |
|---|---|
| Data has a system of record outside IRIS (EMR, HIS, lab system) and must stay there | **Façade** |
| Data is born in FHIR shape (mobile app, partner API) and IRIS owns it | **Repository** |
| Data is born elsewhere but needs SQL/Power BI/Tableau projection in FHIR shape | Repository + **FHIR SQL Builder** |
| Multiple existing repositories aggregate into a virtualized FHIR endpoint | Façade with multiple back-ends |

**Default to Façade** for healthcare integrations with an existing EMR. Repository is a heavier commitment — IRIS becomes the source of truth for those resources, with all the operational consequences (backup, sizing, retention).

## Pattern 1 — FHIR Façade

The Façade keeps FHIR as the public API contract; the actual data is owned by the back-end system. IRIS translates FHIR requests into back-end calls (HL7, REST, SOAP, SQL) and vice versa. **No dual-write, no reconciliation.**

Reference flow for mobile-data ingestion into an EMR:

```
device → vendor mobile app
       → Google Health Connect / Apple HealthKit
       → custom mobile app
       → HTTPS + OAuth2 + PKCE → IRIS-for-Health (FHIR Façade + OAuth2 server)
       → REST / SOAP → EMR
```

The Façade is a first-class deployment mode in IRIS for Health. Use it when the EMR (or other system) is the authoritative store and FHIR is the integration contract with external clients.

## Pattern 2 — FHIR Repository (DataLake)

IRIS for Health includes a native FHIR Repository. Use it when:

- The data is born in FHIR shape (no upstream system of record).
- You want to replace an ETL → Data Warehouse pipeline with HL7v2 → FHIR repo → consumer-via-FHIR. Downstream systems that speak FHIR natively (some BI tools, CRM platforms) can query directly; SQL consumers go through the FHIR SQL Builder.

When converting HL7v2 to FHIR resources for the repository, expect to handle the design questions the IRIS FHIR Repository does not solve out of the box:

- SMART-on-FHIR layering for application authorization.
- FHIR validation enforcement (profile conformance at write time).
- Patterns for inserts/updates with linked resources (avoid duplicate-Observation insertion on retries).
- Profile and Extension creation, IG Publishing workflow.
- Resource versioning support — verify IRIS version capability.
- Anonymisation requirements before exposing for analytics.

These are project-scoped decisions, not skill content — flag them to the user when scoping.

## OAuth 2.0 for FHIR

### Mobile clients — use Authorization Code Grant **with PKCE**

For mobile FHIR clients (native iOS/Android apps, hybrid apps), use the OAuth 2.0 `Authorization Code Grant Type with PKCE extension`.

- Do **not** use `client_credentials` — that's machine-to-machine (no user identity).
- Do **not** use the implicit grant — deprecated.

PKCE protects the authorization code from interception during the redirect on a mobile device (where the redirect is to a custom URI scheme an attacker app could hijack).

Server-side IRIS OAuth configuration patterns are in `security`.

## Privacy-preserving identity on a public FHIR Façade

When the FHIR server is on the public Internet, minimise the PHI IRIS holds:

1. The back-end system (EMR) generates a **per-program patient identifier** (UUID, opaque ID, program-scoped email).
2. The opaque ID is shared with IRIS (for OAuth authentication) and with the patient (who keys it into the mobile app at enrolment).
3. IRIS only ever sees the opaque ID; it never receives the patient's real medical record number, name, or DOB from the EMR.

This minimises attack surface and reduces GDPR scope (the public FHIR endpoint stores no directly-identifying data).

## Wire shape — Bundle of Patient + Observations

The canonical shape sent from a mobile client to a FHIR Façade is a single FHIR `Bundle` containing:

- One `Patient` resource carrying the per-program identifier.
- A collection of `Observation` resources (one per measurement).

Send the Bundle as a transaction so all-or-nothing semantics apply server-side.

## FHIR version

**FHIR R4** is the default for new work. Anything older (DSTU2, STU3) on this corpus is legacy — flag for upgrade when encountered.

Verify the IRIS for Health version supports R4 façade mode before scoping; older IRIS versions need an upgrade as a prerequisite (see SOW out-of-scope below).

## FHIR SQL Builder

When the FHIR repository must also be queryable by SQL tools (ANSI SQL, Power BI, Tableau, analysts who don't speak FHIRPath), use the **FHIR SQL Builder**.

It projects FHIR repository data to custom SQL schemas **without moving the data** — the FHIR resources remain canonical; the SQL view is a projection.

Pipeline:

```
IRIS for Health FHIR Repository
  → FHIR SQL Builder analysis engine
  → custom SQL projection tables
  → Builder Client UI (define / refine projections)
```

Design driver: match expressions (a FHIRPath subset). Example: filter `Patient.identifier` arrays where `system='http://hospital.smarthealthit.org'` so only one identifier value gets projected into a flat `patient_mrn` column.

Setup pattern:

- Docker-based deployment recommended for early evaluation.
- Populate via `HS.HC.FHIRSQL.Utils.Setup` in the `HSLIB` namespace.
- Admin UI at `/csp/fhirsql/index.csp`.

Verify GA status against current IRIS for Health release notes — this was originally introduced as an early-access feature.

## FHIR Façade SOW out-of-scope checklist

Most customer escalations on a FHIR Façade project come from one of these items being assumed by the wrong party. Build them into every SOW explicitly:

1. **TLS server certificate** (from a CA). Must be requested in advance; lead times can be weeks.
2. **Hardware** (or cloud instance sizing).
3. **Maintenance & support phase** (post go-live).
4. **IRIS license**. Verify the existing license can absorb the new namespace, or budget for a license amendment.
5. **IRIS upgrade** if the current version doesn't support FHIR R4 Façade.
6. **EMR-side API**. The customer's developer must expose it; IRIS calls it. This is the single most common escalation source.

## Operational requirements for a public FHIR Façade

Four monitoring concerns must be wired before go-live:

1. Listing of registered users (program enrolment trail).
2. Listing of users + the data they submitted (for support and audit).
3. Errors in observation reception (per-resource validation failures).
4. OAuth login error log (failed authentications, by user and reason).

These map to standard Interop alerting (`alerting`) plus a couple of FHIR-specific dashboards.

## Common pitfalls

- **Choosing Repository when Façade would do** — locks IRIS into being the system of record for data that has an authoritative home elsewhere. Hard to reverse.
- **Implicit grant or `client_credentials` for mobile clients** — wrong grant type. Auth code + PKCE is the only correct choice.
- **Holding PHI on a public FHIR Façade** — defeats the privacy-preserving design. Use opaque per-program identifiers.
- **Skipping the SOW out-of-scope checklist** — the EMR API not being ready on go-live day is the single most common escalation.
- **Hardcoding FHIR DSTU2/STU3** in 2024+ work — default to R4 unless a partner contract pins an older version.
- **Treating FHIR SQL Builder as GA without checking** — verify against current release notes; it was introduced as an early-access feature.

## When NOT to use this skill — fall back to docs

- Building the actual FHIR resources line-by-line (use the IRIS for Health FHIR docs).
- Profile + Extension authoring with the IG Publisher (outside IRIS scope).
- SMART-on-FHIR application registration UX (client-side concern).
- DICOM-to-FHIR conversion (combine this skill with `dicom`, which is currently a stub).

## See also

- `security` — OAuth 2.0 server setup, SSL/TLS chain, SAML when partner systems require it.
- `business-services` — REST inbound BS as the FHIR endpoint entry point.
- `transformations` — DTL for HL7v2 → FHIR resource shape (`HS.FHIR.DTL.*` reference).
- `production-lifecycle` — namespace strategy (FHIR typically lives in its own namespace).
- `alerting` — wiring the four mandatory FHIR-Façade monitoring concerns.
