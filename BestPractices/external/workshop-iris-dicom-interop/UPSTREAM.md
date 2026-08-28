# Upstream snapshot

This directory is a **frozen snapshot** of a third-party MIT-licensed
repository, vendored here so the workshop is offline-friendly and so the
canonical reference survives if the upstream disappears.

| Field | Value |
|---|---|
| Upstream URL | https://github.com/intersystems-ib/workshop-iris-dicom-interop |
| License | MIT (see `LICENSE` in this directory) |
| Snapshot commit SHA | `75dcf2f30102432fe41086d86d5e3c9521c45144` |
| Upstream commit date | `2026-03-09T15:30:25+01:00` |
| Snapshot taken | 2026-05-14 |
| Cited by skill | `skills/dicom/SKILL.md` (skill id `iris-interop-skills:dicom`) |
| Cited by docs | `BestPractices/examples/external-repos.md` |

## Contents — source-only subset

This snapshot is **not** the full upstream tree. It keeps only the **ObjectScript
source** that the `iris-interop-skills:dicom` skill (`skills/dicom/SKILL.md`) cites
as canonical reference:

- `iris/src/DICOM/**` — Production, Processes (`BP/`), Services (`BS/`), messages
  (`Msg/`) and `Util` for the five DICOM wiring patterns.
- `LICENSE` and this `UPSTREAM.md`.

The **runnable lab** (`docker-compose.yml`, the `mysql`/`tools` containers, the
sample `.dcm` files and PDF under `shared/`, the TLS/PKI material and `TLS.md`,
the use-case images, and the `README.md`) was **removed** to keep the plugin
small. Get the full lab from the upstream repo when you want to run it
end-to-end.

## Modification policy

**Read-only.** Do not edit files inside this tree. Treat it as a vendored
artefact. If you need to extend or correct the sample, fork the upstream
repo and refresh this snapshot, do not mutate the local copy in place.

## Refresh policy

Frozen. Refresh manually by re-cloning when upstream evolves and the
workshop needs the newer content:

```powershell
Remove-Item -Recurse -Force BestPractices/external/workshop-iris-dicom-interop
git clone https://github.com/intersystems-ib/workshop-iris-dicom-interop.git BestPractices/external/workshop-iris-dicom-interop
Remove-Item -Recurse -Force BestPractices/external/workshop-iris-dicom-interop/.git
```

A fresh clone brings the **full** upstream tree — after cloning, re-prune to the
source-only subset (keep `iris/src/DICOM/**` + `LICENSE`; drop `shared/`, `img/`,
`mysql/`, `tools/`, the Dockerfiles, `docker-compose.yml`, `README.md`, `TLS.md`).
Then update the SHA and date in this file.

## Why a snapshot rather than a submodule

A `git submodule` re-introduces the failure mode this snapshot is meant
to prevent: if the upstream repo disappears or moves, `git submodule
update --init` fails and the workshop becomes uninstallable. A frozen
snapshot trades disk size (small — few MB) for resilience.

## Attribution

The MIT `LICENSE` file in this directory preserves attribution to the
upstream authors. Code snippets quoted in the workshop skill cite the
source file by relative path inside this snapshot.
