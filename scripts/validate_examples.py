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
import urllib.parse
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

FIXTURES = Path(__file__).with_name("atelier_fixtures.json")


def tier0() -> bool:
    """Check the INSTRUMENT before measuring the bank with it.

    Tier 2's verdict is only as good as `parse_failures`, and for one whole family of IRIS
    errors that verdict was silently inverted: the gate printed "compiled clean" for a class
    IRIS had refused (#159). A green tier 2 could not have revealed that -- it IS the thing
    that was wrong -- so the parser gets its own red case, from real captured payloads.

    No IRIS and no network: these are frozen responses, so this runs in CI on every PR while
    the live `--compile` job runs only where an instance exists.

    WHAT THESE FIXTURES DO AND DO NOT PIN DOWN, established by mutating the parser and watching
    which case went red -- not by reading it:

      dependency_5373           carried by the params scan OR the quoted-name extraction
      dependency_console_only   carried by the quoted-name extraction OR `Skipping class`
      unattributed              carried by the reconciliation ALONE

    So the first two survive any SINGLE mechanism being removed and only die when two are
    (mutants M1, M2, M4, M5, M7 all survived; M6 killed both). That redundancy is deliberate
    -- the original defect was three paths failing on the same input at once -- but it means
    a green here does NOT prove each mechanism is individually live. The reconciliation is the
    exception and the one that matters: it is singly covered, and its mutant dies.
    """
    print("Tier 0 -- the compile-result parser\n")
    rep = Report()
    try:
        cases = json.loads(read(FIXTURES))
    except (OSError, ValueError) as exc:
        print(f"  FAIL  fixtures unreadable: {exc}")
        return False

    for name, case in cases.items():
        if name.startswith("_"):
            continue
        got = sorted(parse_failures(case["payload"], set(case["staged"])))
        want = sorted(case["expect"])
        rep.check(f"P-{name}", f"{name} -> {want or 'clean'}",
                  [] if got == want else [f"expected {want}, got {got}"])

    return rep.done("Tier 0")


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
        # The namespace goes in the URL path, so it must be encoded: %SYS and any namespace
        # with a % in it otherwise returns HTTP 400 and gets misreported as "unreachable".
        self.base = f"http://{self.host}:{self.port}/api/atelier/v1/{urllib.parse.quote(self.ns, safe='')}"

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

    def query(self, sql: str):
        return self._call("POST", "/action/query", {"query": sql, "parameters": []})


def preflight() -> bool:
    """Prove the environment is usable BEFORE compiling anything.

    Without this, a misconfigured target produces a uniformly red run that reads as "the
    examples are broken" when it actually means "this IRIS has no Interoperability". That is
    a worse outcome than no CI check at all, because it trains people to ignore the result.
    Each failure below names which of the two it is.
    """
    print("Preflight\n")
    iris = Atelier()
    print(f"  target {iris.base}")

    try:
        ver = iris._call("GET", "")
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
        print(f"  FAIL  cannot reach IRIS: {exc}")
        print("        ENVIRONMENT problem, not an example problem.")
        print("        Check IRIS_HOST / IRIS_PORT / IRIS_USER / IRIS_PASSWORD.")
        return False
    content = (ver.get("result") or {}).get("content") or {}
    dbs = ", ".join(d.get("name", "?") for d in (content.get("db") or [])[:6])
    print(f"  ok    reachable — namespace {content.get('name', iris.ns)} over [{dbs}]")

    try:
        rows = (iris.query(
            "SELECT COUNT(*) AS n FROM %Dictionary.CompiledClass WHERE Name = 'Ens.Director'"
        ).get("result") or {}).get("content") or []
        has_ens = rows and int(list(rows[0].values())[0]) > 0
    except Exception as exc:
        print(f"  FAIL  could not query the dictionary in namespace {iris.ns}: {exc}")
        print("        ENVIRONMENT problem, not an example problem.")
        return False

    if not has_ens:
        print(f"  FAIL  namespace {iris.ns} has no Ens.Director — Interoperability is not enabled")
        print("        ENVIRONMENT problem, not an example problem. Every Ens.* example would")
        print("        fail for the same reason and the run would say nothing about the bank.")
        return False
    print(f"  ok    namespace {iris.ns} is Interoperability-enabled")

    try:
        rows = (iris.query(
            "SELECT COUNT(*) AS n FROM %Dictionary.CompiledClass WHERE Name = 'EnsLib.HL7.Message'"
        ).get("result") or {}).get("content") or []
        has_hl7 = rows and int(list(rows[0].values())[0]) > 0
    except Exception:
        has_hl7 = False

    if not has_hl7:
        print("  FAIL  EnsLib.HL7.Message is absent — this is IRIS, not IRIS for Health")
        print("        ENVIRONMENT problem. Several examples legitimately need the HL7 library;")
        print("        use an irishealth image rather than recording them as failures.")
        return False
    print("  ok    HL7 library present")

    print("\nPreflight: environment is usable\n")
    return True


UNATTRIBUTED = "<unattributed compile errors>"


def _class_candidates(text: str):
    """Every class name a diagnostic mentions, member suffixes stripped.

    A #5373 reads: Class 'A', used by 'B:property:P', does not exist. **A is the class
    that is MISSING and B is the class that FAILED.** Yield both and let `known` decide
    which one was staged — picking one position is how this went wrong before.
    """
    for raw in re.findall(r"'([^']+)'", text):
        yield raw.split(":")[0]
    for raw in re.findall(r"([A-Za-z0-9_.%]+)\.cls", text):
        yield raw


def parse_failures(result: dict, known: set[str]) -> dict[str, str]:
    """Pull class -> first error out of an Atelier compile response.

    VERIFIED against live IRIS 2026.1 on a two-class batch, one deliberately broken.
    The previous version of this function returned {} for that batch — i.e. reported
    "all classes compile" for a class IRIS had refused — on three independent counts:

      1. It read `params[0]` as the failing class. For the whole dependency family of
         errors `params[0]` is the class that is ABSENT, which is never in `known`, so
         it was dropped. The failing class sits in `params[1]` as `B:property:P`.
      2. The `\\.cls` regex found nothing: Atelier diagnostics name classes bare and
         quoted, not with a file extension.
      3. The console line that states the outcome is `Skipping class B`, which carries
         no ERROR token and so was `continue`d past by the ERROR filter.

    Attribution is still best-effort — IRIS's error vocabulary is larger than anything
    verified here — so the GUARANTEE does not rest on it; see the reconciliation below.
    """
    failed: dict[str, str] = {}

    def note(name: str, msg: str) -> None:
        if name in known:
            failed.setdefault(name, " ".join(msg.split())[:220])

    for err in (result.get("status") or {}).get("errors") or []:
        text = err.get("error", "") if isinstance(err, dict) else str(err)
        params = err.get("params") or [] if isinstance(err, dict) else []
        for p in params:
            if isinstance(p, str) and p:
                note(p.split(":")[0], text)
        for cn in _class_candidates(text):
            note(cn, text)

    console = result.get("console") or []
    for line in console:
        # IRIS's own statement that a class did not compile. It carries no ERROR token,
        # so it must be matched BEFORE the ERROR filter below, not after it.
        m = re.search(r"Skipping class ([A-Za-z0-9_.%]+)", line)
        if m:
            note(m.group(1), line)
        if "ERROR" not in line.upper():
            continue
        for cn in _class_candidates(line):
            note(cn, line)
        m = re.search(r"compiling class '([\w.%]+)'", line, re.IGNORECASE)
        if m:
            note(m.group(1), line)

    # RECONCILIATION -- the actual guarantee.
    #
    # Every check above is a pattern match against error text, and a pattern match only
    # ever covers the shapes someone thought of. IRIS independently reports HOW MANY
    # errors it detected, so use that as the oracle: a non-zero count with nothing
    # attributed is an unattributed failure and must fail the run LOUDLY. Returning {}
    # there is precisely what let a class print "Skipping class X" and be recorded clean.
    #
    # Scope, stated so a clean run is not read as more than it is: this catches TOTAL
    # attribution failure only. Errors do not map 1:1 to classes (one class easily
    # produces several), so a partial miss cannot be detected by counting -- but a
    # partial miss still leaves `failed` non-empty, which already fails the build and
    # puts a human in front of the console. The silent-green case is the one closed here.
    detected = 0
    for line in console:
        m = re.search(r"Detected (\d+) error", line)
        if m:
            detected = max(detected, int(m.group(1)))
    if detected and not failed:
        failed[UNATTRIBUTED] = (
            f"IRIS detected {detected} compile error(s) that could not be attributed to "
            "any staged class. Read the console below before trusting this run: "
            + " | ".join(l for l in console if l.strip())[:400]
        )

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
    ap.add_argument("--preflight", action="store_true",
                    help="only check that the IRIS target is usable, then exit")
    ap.add_argument("--update-baseline", action="store_true", help="re-record the expected-clean list")
    args = ap.parse_args()

    if args.update_baseline:
        update_baseline()
        return 0

    if args.preflight:
        return 0 if preflight() else 1

    ok = tier0()
    ok = tier1() and ok
    if args.compile:
        # A failed preflight means the environment is wrong, not the bank. Say which,
        # and do not stage 34 classes into an instance that cannot compile them.
        ok = (preflight() and tier2()) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
