#!/usr/bin/env python3
"""Validation suite for the BestPractices example bank.

Wrong examples are worse than no examples: they are what an agent copies, and a
broken one propagates into every production built from it, silently. Before this
existed, nobody had ever run a compiler over the bank -- 10 of 18 files did not
compile, across seven releases.

Two tiers:

  Tier 1  structural   no IRIS, ~1s. Runs in CI on every push.
  Tier 2  compile      needs a live IRIS. Stages every class, compiles it,
                       compares against the recorded baseline, cleans up.

    python3 scripts/validate_examples.py              # tier 1
    python3 scripts/validate_examples.py --compile    # tier 1 + tier 2

Exit code is non-zero if any check fails, so it works as a gate.

CALIBRATION NOTE -- read before adding a check. A noisy gate gets muted, and a
muted gate is worse than none. Every rule here is deliberately the narrow form:

  * C5 asserts no class name *ends* in a Tipo, rather than requiring every class
    to carry one. `Example.CDA.ClinicalDocument` and `Example.Vendor.WSC.SAPClient`
    are legitimately Tipo-less; `Example.MyService.BS` was the real defect (#91).
  * C6 ignores comment lines. The bank *teaches* several of these tokens as
    anti-patterns, and the anonymised `<initials><date>` marker is a documented
    convention (S6.1.7), not leftover vendor cruft. A first draft of this check
    flagged 3 files and was wrong all 3 times.

Tune a new rule against the whole corpus before committing it.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BANK = REPO / "BestPractices" / "examples"
DOC = REPO / "BestPractices" / "BestPractices_Interop_IRIS.md"
README = BANK / "README.md"
BASELINE = Path(__file__).resolve().parent / "examples_baseline.json"

ARTEFACT_SUFFIXES = (".cls", ".xml", ".sh")
TIPOS = ("BS", "BP", "BO", "DT", "DTS", "RUL", "MSG", "DAT", "ADP", "UTL", "HL7")

# Tokens the audit proved wrong. Each entry: (regex, why).
# Matched only against non-comment lines -- see the calibration note above.
BANNED = [
    (r"\bAs\s+%SOAP\.Security\s*$", "%SOAP.Security is a package, not a class -- use %SOAP.Security.Header"),
    (r"\bEnsLib\.Email\.", "no such package -- it is EnsLib.EMail (capital M)"),
    (r"\bSendAlertOnError\b", "not a real property -- the Ens.Host setting is AlertOnError"),
    (r'ADAPTER\s*=\s*"EnsLib\.RecordMap\.Service\.', "that is a Business Service, not an adapter -- Extend it instead"),
    (r"\$SYSTEM\.Semaphore\.(Signal|Wait)\b", "%SYSTEM.Semaphore has no Signal/Wait -- use Increment/Decrement on an instance"),
    (r"\b%SYS\.TaskSuper\b", "internal-only superclass with no OnTask -- subclass %SYS.Task.Definition"),
    (r"\bEns\.Rule\.Definition\b.*\bExtends\b.*\bRule\b\.", "rule classes are <Pkg>.RUL.<Name>"),
    (r"[A-Z]:\\\\|[A-Z]:\\", "hardcoded absolute Windows path -- parametrise it as a Setting"),
    (r"\bINTEGRACIONS>", "leftover namespace prompt from a customer transcript"),
]

COMMENT_PREFIXES = ("///", "//", "#", "<!--", "rem ")


class Report:
    def __init__(self) -> None:
        self.failures: list[tuple[str, str]] = []
        self.checks_run = 0

    def check(self, cid: str, title: str, bad: list[str]) -> None:
        self.checks_run += 1
        if bad:
            for item in bad:
                self.failures.append((cid, item))
            print(f"  FAIL  {cid}  {title}  ({len(bad)})")
            for item in bad[:12]:
                print(f"          {item}")
            if len(bad) > 12:
                print(f"          ... and {len(bad) - 12} more")
        else:
            print(f"  ok    {cid}  {title}")

    def done(self, tier: str) -> bool:
        if self.failures:
            print(f"\n{tier}: {len(self.failures)} problem(s) across {self.checks_run} checks\n")
            return False
        print(f"\n{tier}: all {self.checks_run} checks pass\n")
        return True


def artefacts() -> list[Path]:
    return sorted(
        p for p in BANK.rglob("*")
        if p.suffix in ARTEFACT_SUFFIXES or p.name.endswith(".cls.xml")
    )


def rel(p: Path) -> str:
    return str(p.relative_to(BANK))


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def is_comment(line: str) -> bool:
    s = line.strip()
    return any(s.startswith(c) for c in COMMENT_PREFIXES)


def class_names(text: str) -> list[str]:
    return re.findall(r"^Class\s+([A-Za-z0-9_.%]+)", text, re.M)


def doc_headings() -> set[str]:
    return set(re.findall(r"^#+\s*(\d+\.\d+(?:\.\d+)?)", read(DOC), re.M))


# --------------------------------------------------------------------------
# Tier 1 -- structural
# --------------------------------------------------------------------------

def tier1() -> bool:
    print("Tier 1 -- structural\n")
    r = Report()
    files = artefacts()
    files = [f for f in files if f.name != "README.md"]
    heads = doc_headings()
    readme = read(README)
    doc = read(DOC)

    r.check("C1", "every artefact carries a /// Rule: header",
            [rel(f) for f in files if "Rule:" not in read(f)[:500]])

    unresolved = []
    for f in files:
        for ref in sorted(set(re.findall(r"§(\d+\.\d+(?:\.\d+)?)", read(f)))):
            if ref not in heads:
                unresolved.append(f"{rel(f)} -> §{ref} is not a heading in the deliverable")
    r.check("C2", "every §ref resolves to a real doc heading", unresolved)

    r.check("C3", "one class per .cls file (keeps every example one loadable unit)",
            [f"{rel(f)} defines {len(class_names(read(f)))}"
             for f in files if f.suffix == ".cls" and len(class_names(read(f))) != 1])

    missing_row = [rel(f) for f in files if f.name not in readme]
    dangling = [
        path for path in set(re.findall(r"`(ch\d+[^`]+\.(?:cls|xml|sh|cls\.xml))`", readme))
        if not (BANK / path).exists()
    ]
    r.check("C4", "README index and the directory agree, both ways",
            missing_row + [f"README row points at missing file: {p}" for p in dangling])

    tipo_last = []
    for f in files:
        for cn in class_names(read(f)):
            if cn.rsplit(".", 1)[-1] in TIPOS:
                tipo_last.append(f"{rel(f)} -> {cn} puts the Tipo last; use <Pkg>.<Tipo>.<Name>")
    r.check("C5", "no class name ends in a Tipo (#91)", tipo_last)

    banned_hits = []
    for f in files:
        for n, line in enumerate(read(f).splitlines(), 1):
            if is_comment(line):
                continue  # the bank documents several of these as anti-patterns
            for pattern, why in BANNED:
                if re.search(pattern, line):
                    banned_hits.append(f"{rel(f)}:{n} -- {why}")
    r.check("C6", "no token the audit proved wrong (comments exempt)", banned_hits)

    broken_links = []
    for path in re.findall(r"\*\*Example\.\*\*\s*`examples/([^`]+)`", doc):
        if not (BANK / path).exists():
            broken_links.append(f"deliverable cites examples/{path}, which does not exist")
    r.check("C7", "every 'Example.' pointer in the deliverable resolves", broken_links)

    print(f"  {len(files)} artefacts, {sum(1 for f in files if f.suffix == '.cls')} classes")
    return r.done("Tier 1")


# --------------------------------------------------------------------------
# Tier 2 -- compile against a live IRIS
# --------------------------------------------------------------------------

class Atelier:
    """Minimal Atelier REST client -- stdlib only, so CI needs no dependencies.

    This is a test harness, not production code: the plugin's own rule is that
    interop work reaches IRIS through the MCP. A CI job has no MCP, so the gate
    talks to the same REST API the MCP itself uses.
    """

    def __init__(self) -> None:
        self.host = os.environ.get("IRIS_HOST", "localhost")
        self.port = os.environ.get("IRIS_PORT", "43080")
        self.ns = os.environ.get("IRIS_NAMESPACE", "APP")
        user = os.environ.get("IRIS_USER", "_SYSTEM")
        pwd = os.environ.get("IRIS_PASSWORD", "SYS")
        token = base64.b64encode(f"{user}:{pwd}".encode()).decode()
        self.auth = f"Basic {token}"
        self.base = f"http://{self.host}:{self.port}/api/atelier/v1/{self.ns}"

    def _call(self, method: str, path: str, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(f"{self.base}{path}", data=data, method=method)
        req.add_header("Authorization", self.auth)
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())

    def put(self, name: str, source: str):
        return self._call("PUT", f"/doc/{name}?ignoreConflict=1",
                          {"enc": False, "content": source.splitlines()})

    def compile(self, names: list[str]):
        return self._call("POST", "/action/compile?flags=cuk", names)

    def delete(self, name: str):
        return self._call("DELETE", f"/doc/{name}")


def parse_failures(result: dict, known: set[str]) -> dict[str, str]:
    """Pull class -> first error out of an Atelier compile response.

    Errors arrive in `status.errors` as dicts whose `params[0]` names the routine
    and whose `error` text embeds `<Class>.cls`. The console echoes them too. Both
    are scanned, because a class-level failure and a routine-level failure do not
    always surface in the same place.
    """
    failed: dict[str, str] = {}

    def note(name: str, msg: str) -> None:
        if name in known:
            failed.setdefault(name, " ".join(msg.split())[:220])

    for err in (result.get("status") or {}).get("errors") or []:
        text = err.get("error", "") if isinstance(err, dict) else str(err)
        params = err.get("params") or [] if isinstance(err, dict) else []
        if params and isinstance(params[0], str):
            note(params[0], text)
        for cn in re.findall(r"([A-Za-z0-9_.%]+)\.cls", text):
            note(cn, text)

    for line in result.get("console") or []:
        if "ERROR" not in line.upper():
            continue
        for cn in re.findall(r"([A-Za-z0-9_.%]+)\.cls", line):
            note(cn, line)
        m = re.search(r"compiling class '([\w.%]+)'", line)
        if m:
            note(m.group(1), line)

    return failed


def tier2() -> bool:
    print("Tier 2 -- compile against live IRIS\n")
    sources: dict[str, str] = {}
    for f in artefacts():
        if f.suffix != ".cls":
            continue
        text = read(f)
        names = class_names(text)
        if len(names) == 1:
            sources[names[0]] = text

    iris = Atelier()
    print(f"  target {iris.base}")
    print(f"  staging {len(sources)} classes\n")

    staged: list[str] = []
    ok = False
    try:
        try:
            for cn, src in sources.items():
                iris.put(f"{cn}.cls", src)
                staged.append(cn)
        except (urllib.error.URLError, urllib.error.HTTPError) as exc:
            print(f"  CANNOT REACH IRIS: {exc}")
            print("  set IRIS_HOST / IRIS_PORT / IRIS_NAMESPACE / IRIS_USER / IRIS_PASSWORD")
            return False

        # Compile twice on purpose. A DTL's Transform method is built by a generator
        # that resolves sourceClass/targetClass at generation time, so a DTL compiled
        # in the same batch as its own message classes can fail with
        #   #5001 <CLASS DOES NOT EXIST>  >  #5490 Error running generator
        # even though those classes are in the batch. It is an ordering artefact, not
        # a defect: the second pass succeeds unchanged. Only pass 2 is authoritative --
        # anything that compiled in pass 1 is skipped as up-to-date, so what pass 2
        # still reports is a genuine, persistent failure.
        docs = [f"{cn}.cls" for cn in sources]
        iris.compile(docs)
        failed = parse_failures(iris.compile(docs), set(sources))

        clean = sorted(set(sources) - set(failed))
        baseline = json.loads(read(BASELINE)) if BASELINE.exists() else {}
        expected = set(baseline.get("expected_clean", []))
        regressions = sorted(expected & set(failed))
        newly_clean = sorted(set(clean) - expected)

        print(f"  compiled clean : {len(clean)} / {len(sources)}")
        if failed:
            print(f"  failed         : {len(failed)}")
            for cn, err in sorted(failed.items()):
                flag = "REGRESSION vs baseline" if cn in expected else "not in baseline"
                print(f"      {cn}  [{flag}]")
                print(f"        {err}")
        if newly_clean:
            print(f"  new since baseline: {', '.join(newly_clean)}")
            print("  -> re-record with --update-baseline once reviewed")

        ok = not failed
    finally:
        left = []
        for cn in staged:
            try:
                iris.delete(f"{cn}.cls")
            except (urllib.error.HTTPError, urllib.error.URLError):
                left.append(cn)
        msg = f"  cleanup        : {len(staged) - len(left)} deleted"
        if left:
            msg += f", {len(left)} LEFT BEHIND: {left}"
        print(msg)

    print(f"\nTier 2: {'all classes compile' if ok else 'FAILED'}\n")
    return ok


def update_baseline() -> None:
    sources = []
    for f in artefacts():
        if f.suffix == ".cls":
            sources += class_names(read(f))
    BASELINE.write_text(json.dumps({
        "_comment": "Classes expected to compile clean. Any of these failing is a "
                    "regression and fails the build. Update only with a verified run.",
        "expected_clean": sorted(sources),
    }, indent=2) + "\n", encoding="utf-8")
    print(f"baseline recorded: {len(sources)} classes -> {BASELINE.name}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--compile", action="store_true", help="also run tier 2 against a live IRIS")
    ap.add_argument("--update-baseline", action="store_true", help="re-record the expected-clean list")
    args = ap.parse_args()

    if args.update_baseline:
        update_baseline()
        return 0

    ok = tier1()
    if args.compile:
        ok = tier2() and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
