#!/usr/bin/env python3
"""validate_signatures: the signature cards ARE the oracle, checked against a live IRIS.

Closes #425. skills/fhir/references/prebuilt-hs-classes.md records the measured shape of five
shipped InterSystems classes. Nothing held those claims: the file is prose and markdown tables, no
tier compiles it, and a compile would not help anyway. The repo measured that twice --
BestPractices/examples/ch04_fhir/tdd-fhirsql-setup-existence.cls (a call-through to a missing method
compiles clean) and ch06_adapters/tdd-wsdl-reader-signature.cls (a typed #Dim gates neither arity nor
method existence, because ObjectScript resolves instance-method calls at run time). So a signature
claim is falsifiable only by reading %Dictionary.CompiledMethod back.

WHY THE DOCUMENT IS PARSED INSTEAD OF A JSON BASELINE. The defect being prevented is "the prose a
reader follows no longer matches the instance". A baseline file beside the document can agree with
IRIS while the document rots -- the same across-layers split this repo has hit before, where fixing
the layer you found makes the siblings look MORE trustworthy. Parsing the human table makes the text
itself load-bearing: there is one copy of each claim and the gate reads the copy the reader reads.

WHY A %UnitTest CLASS WAS *NOT* THE DELIVERABLE, though #425 proposed one. Nothing in this repo's CI
runs a %UnitTest suite -- measured: no RunTest, no ^UnitTestRoot, no %UnitTest.Manager anywhere in
scripts/ or .github/workflows/. Seven bank files already carry FormalSpec oracles and tier 2 only
*compiles* them. An eighth would have been compiled-but-never-run, i.e. exactly the instrument this
document warns is insufficient. The %UnitTest form remains the right thing for a READER to run in
their own namespace; it is the wrong thing to gate this repo with.

THE FAILURE MODE THIS GUARDS ITS OWN PARSER AGAINST. A markdown parser that stops recognising rows
reports FEWER checks and still exits 0 -- a silently wrong zero, which is the dominant bug shape in
this repo's history. Three defences, all mandatory:
  1. EXPECTED counts below are asserted. Parse fewer (or more) gated rows than declared and the run
     FAILS, naming the drift. A parser regression cannot present as a pass.
  2. A row that looks like a signature row but does not parse is a FAILURE, never a skip.
  3. Every exclusion is PRINTED with its reason, so what is not gated is visible rather than absent.

INSTRUMENT HAZARD, inherited from the document and non-negotiable here: never put ORDER BY on an
OR-of-LIKE against %Dictionary.* -- the sort drops every row before the first anchored pattern and
returns a plausible non-empty subset. This script issues one `Name IN (...)` per class and never
sorts in SQL. See the memory of 2026-10-16: 23 rows became 13 with the sort appended.

Usage:
    IRIS_PORT=44080 IRIS_NAMESPACE=APP python3 scripts/validate_signatures.py
    python3 scripts/validate_signatures.py --self-test     # parser fixtures, no IRIS
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

DOC = Path(__file__).resolve().parent.parent / "skills" / "fhir" / "references" / "prebuilt-hs-classes.md"

# The provenance line in the document names the version it was measured on. If the connected
# instance is a different one, the cards are not wrong -- they are UNVERIFIED, and that is a
# different thing to report. Bumping the image means re-measuring and editing that line.
EXPECTED_VERSION = "2026.1"

# Declared populations. These are the parser's own positive controls (defence 1 above).
EXPECTED_GATED = 33        # member claims carrying a parseable signature, by card:
#   HS.Gateway.HL7.HL7ToSDA3                1  (GetSDA)
#   HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process   8  (the complete own-origin set)
#   HS.FHIRServer.Interop.Operation         6  (all inherited -- the point of that card)
#   EnsLib.HL7.Message                     12  (OutputToString + the Output/Import family)
#   Ens.Config.DefaultSettings              6  (the class methods that do exist)
# A row naming two members counts twice: '| `OnInit`, `OnTearDown` |' is two claims.
EXPECTED_CALLBACKS = 15    # the On<Streamlet>() roster
EXPECTED_CARDS = 5         # ## headings naming a class

# ---------------------------------------------------------------------------
# IRIS, over the Atelier REST query endpoint.
# ---------------------------------------------------------------------------


class Iris:
    def __init__(self) -> None:
        self.host = os.environ.get("IRIS_HOST", "localhost")
        # 52773 is IRIS's own default and what CI sets. It is deliberately NOT 43080: on this
        # workstation that port belongs to a different project's instance with no APP namespace,
        # and a wrong default does not error, it measures the wrong machine. Hence the target is
        # printed on every run -- the operator always sees which instance answered.
        self.port = os.environ.get("IRIS_PORT", "52773")
        self.ns = os.environ.get("IRIS_NAMESPACE", "FHIRFOUNDATION")
        user = os.environ.get("IRIS_USER", "_SYSTEM")
        pwd = os.environ.get("IRIS_PASSWORD", "SYS")
        self.auth = "Basic " + base64.b64encode(f"{user}:{pwd}".encode()).decode()
        self.base = f"http://{self.host}:{self.port}/api/atelier/v1/{urllib.parse.quote(self.ns, safe='')}"

    def _post(self, path: str, payload: dict) -> dict:
        req = urllib.request.Request(
            self.base + path,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json", "Authorization": self.auth},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", "replace")
        # A dead endpoint answers with a BLANK BODY, while an absent class answers with a
        # well-formed empty content[]. Collapsing the two is how a mid-run outage gets written up
        # as "the method does not exist", so they stay distinct here.
        if not raw.strip():
            raise RuntimeError("blank body from IRIS (dead endpoint) -- not an empty result")
        return json.loads(raw)

    def query(self, sql: str) -> list[dict]:
        if re.search(r"\border\s+by\b", sql, re.I):
            raise RuntimeError("ORDER BY on a %Dictionary query -- see the instrument hazard above")
        doc = self._post("/action/query", {"query": sql})
        errors = (doc.get("status") or {}).get("errors") or []
        if errors:
            raise RuntimeError(f"SQL error: {errors}")
        return (doc.get("result") or {}).get("content") or []

    def version(self) -> str:
        # The version lives on the SERVER root, /api/atelier/ -- not on the namespace endpoint and
        # not under /v1/. Measured: the namespace payload carries name+db[] and no version at all,
        # and /api/atelier/v1/ answers {} . Reading the wrong one returns an empty string, which
        # then reads as "wrong version" instead of "I did not measure the version" -- the failure
        # shape this whole file exists to refuse. Hence the emptiness check in the caller.
        root = f"http://{self.host}:{self.port}/api/atelier/"
        req = urllib.request.Request(root, headers={"Authorization": self.auth})
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", "replace")
        if not raw.strip():
            raise RuntimeError("blank body from IRIS (dead endpoint)")
        content = (json.loads(raw).get("result") or {}).get("content") or {}
        return content.get("version", "")


# ---------------------------------------------------------------------------
# Parsing the document.
# ---------------------------------------------------------------------------

IDENT = r"[%A-Za-z][A-Za-z0-9]*"
CLASSNAME = r"[%A-Za-z][A-Za-z0-9%]*(?:\.[A-Za-z0-9%]+)+"

RE_CARD = re.compile(r"^##\s+`(" + CLASSNAME + r")`")
RE_BACKTICK_CLASS = re.compile(r"`(" + CLASSNAME + r")`")
RE_SIG = re.compile(r"`(\([^`]*\)(?:\s*As\s+[%\w.]+)?)`")
RE_BARE = re.compile(r"^`(" + IDENT + r")`$")

# `Output x As T = v` / `ByRef x As T` / `x As T` / `x`
# The trailing '...' is ObjectScript's variadic declaration and is part of the argument NAME:
# measured, HS.HC.Util.Trace.Helper.HSTrace has FormalSpec 'pCurrentClass,pMethod,pArgList...'
# with three ASCII periods. A typographic ellipsis is a different string and must not parse.
RE_ARG = re.compile(
    r"^(?:(?P<mode>Output|ByRef)\s+)?(?P<name>" + IDENT + r"(?:\.\.\.)?)"
    r"(?:\s+As\s+(?P<type>[%\w.]+))?"
    r"(?:\s*=\s*(?P<default>.+))?$"
)

# ReturnType comes back from IRIS resolved to its full package, while FormalSpec keeps whatever the
# author wrote. Measured: ReturnType '%Library.Status' for a method whose FormalSpec says '%Boolean'.
# So only the return type is canonicalised, and only for the datatype classes that live in %Library.
LIBRARY_DATATYPES = {
    "%String", "%Status", "%Boolean", "%Integer", "%Numeric", "%Float", "%Double",
    "%Date", "%Time", "%TimeStamp", "%Binary", "%List", "%RawString", "%Char",
    "%Persistent", "%RegisteredObject", "%DynamicObject", "%DynamicArray", "%Collection",
}


def canon_return(t: str) -> str:
    t = (t or "").strip()
    if not t:
        return ""
    if t in LIBRARY_DATATYPES:
        return "%Library." + t[1:]
    return t


def split_args(inner: str) -> list[str]:
    """Split an argument list on top-level commas, respecting quotes and nesting."""
    out, buf, depth, quote = [], [], 0, False
    for ch in inner:
        if quote:
            buf.append(ch)
            if ch == '"':
                quote = False
            continue
        if ch == '"':
            quote = True
            buf.append(ch)
        elif ch in "([{":
            depth += 1
            buf.append(ch)
        elif ch in ")]}":
            depth -= 1
            buf.append(ch)
        elif ch == "," and depth == 0:
            out.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def parse_signature(sig: str) -> tuple[str, str]:
    """'(Output pX As %String = "") As %Status' -> ('*pX:%String=""', '%Library.Status').

    Raises ValueError on anything it cannot account for -- a signature row that does not parse is
    a failure, never a skip.
    """
    sig = sig.strip()
    if not sig.startswith("("):
        raise ValueError(f"does not start with '(': {sig!r}")
    depth, close = 0, -1
    for i, ch in enumerate(sig):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                close = i
                break
    if close < 0:
        raise ValueError(f"unbalanced parentheses: {sig!r}")
    inner, rest = sig[1:close], sig[close + 1:].strip()

    ret = ""
    if rest:
        m = re.match(r"^As\s+([%\w.]+)$", rest)
        if not m:
            raise ValueError(f"trailing text is not 'As <Type>': {rest!r}")
        ret = m.group(1)

    parts = []
    for raw in split_args(inner):
        m = RE_ARG.match(raw)
        if not m:
            raise ValueError(f"unparseable argument {raw!r} in {sig!r}")
        prefix = {"Output": "*", "ByRef": "&", None: ""}[m.group("mode")]
        piece = prefix + m.group("name")
        if m.group("type"):
            piece += ":" + m.group("type")
        if m.group("default") is not None:
            piece += "=" + m.group("default").strip()
        parts.append(piece)
    return ",".join(parts), canon_return(ret)


def classmethod_flag(cells: list[str]) -> bool:
    """Read the document's own words for class-method-ness. Ambiguity is an error."""
    hay = " ".join(cells[1:]).lower()
    says_class = bool(re.search(r"\bclassmethod\b|\bclass method\b|\*\*yes\*\*", hay))
    says_inst = bool(re.search(r"\binstance\b|\*\*no\b|\|\s*no\s*\||^no\b|\bno —", hay))
    if says_class and says_inst:
        raise ValueError(f"row says both class method and instance: {cells!r}")
    if not says_class and not says_inst:
        raise ValueError(f"row states neither class method nor instance: {cells!r}")
    return says_class


def parse_doc(text: str):
    """-> (gated, callbacks, cards, excluded)

    gated: list of dicts {card, target, member, classmethod, formalspec, returntype, line}
    callbacks: list of names from the 3-column all-identifier roster
    excluded: list of (line, reason) for rows that look member-ish but carry no signature
    """
    gated, callbacks, cards, excluded = [], [], [], []
    card = None
    for n, line in enumerate(text.splitlines(), 1):
        m = RE_CARD.match(line)
        if m:
            card = m.group(1)
            cards.append(card)
            continue
        if not line.startswith("| `") or card is None:
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue

        # The On<Streamlet>() roster: exactly three cells, every one a bare identifier. Anchored on
        # the column count on purpose -- a 2-column table of bare identifiers is the property/initial
        # table two sections down ("| `TransmissionMode` | `transaction` |"), which is not a roster.
        bare = [RE_BARE.match(c) for c in cells]
        if len(cells) == 3 and all(bare):
            callbacks.extend(b.group(1) for b in bare)
            continue

        sig = RE_SIG.search(cells[-1])
        if not sig:
            excluded.append((n, f"no parenthesised signature in the last cell: {cells[0]}"))
            continue

        # Which class owns it? A backticked dotted name in a middle cell overrides the card -- that
        # is the whole point of the Interop.Operation card, whose members come from its supers.
        target = card
        for c in cells[1:-1]:
            hit = RE_BACKTICK_CLASS.search(c)
            if hit:
                target = hit.group(1)
                break

        formal, ret = parse_signature(sig.group(1))
        is_cm = classmethod_flag(cells)
        # One cell can name several members sharing a shape: "| `OnInit`, `OnTearDown` | ... |"
        members = re.findall(r"`(" + IDENT + r")`", cells[0])
        if not members:
            raise ValueError(f"line {n}: first cell names no member: {cells[0]!r}")
        for member in members:
            gated.append({
                "card": card, "target": target, "member": member,
                "classmethod": is_cm, "formalspec": formal, "returntype": ret, "line": n,
            })
    return gated, callbacks, cards, excluded


# ---------------------------------------------------------------------------
# Self-test: the normaliser against shapes measured on a live instance.
# ---------------------------------------------------------------------------

FIXTURES = [
    # (human form in the document, measured FormalSpec, measured ReturnType)
    ("(pRequest As EnsLib.HL7.Message, Output pXML As %Stream.GlobalCharacter, pLogAlerts As %Boolean = 1,"
     " pObservationMode As %Boolean = 0, pMultiLineOBXCompatibilityMode As %Boolean = 0,"
     " pKeepDuplicateOBXIdentifiers As %Boolean = 0) As %Status",
     "pRequest:EnsLib.HL7.Message,*pXML:%Stream.GlobalCharacter,pLogAlerts:%Boolean=1,"
     "pObservationMode:%Boolean=0,pMultiLineOBXCompatibilityMode:%Boolean=0,"
     "pKeepDuplicateOBXIdentifiers:%Boolean=0", "%Library.Status"),
    ("(pIOStream As %IO.I.CharacterStream, Output pStatus As %Status = $$$OK,"
     " ByRef pConfigItem As %String = \"\", pIOFormatClassname As %String = \"\") As EnsLib.HL7.Message",
     "pIOStream:%IO.I.CharacterStream,*pStatus:%Status=$$$OK,&pConfigItem:%String=\"\","
     "pIOFormatClassname:%String=\"\"", "EnsLib.HL7.Message"),
    ("(Output pHost As %String, Output pPort As %String)", "*pHost:%String,*pPort:%String", ""),
    ("(pResourceObj, pFHIRFormat, pFormatFHIROutput, pSchema, pFormatter, pIndentChars,"
     " pLineTerminator) As %Stream.Object",
     "pResourceObj,pFHIRFormat,pFormatFHIROutput,pSchema,pFormatter,pIndentChars,pLineTerminator",
     "%Stream.Object"),
    ("(pProduction As %String = \"\")", "pProduction:%String=\"\"", ""),
    ("(pProduction As %String = \"*\")", "pProduction:%String=\"*\"", ""),
    ("(pSeparators As %String, pSequenceNumber As %String, Output pStatus As %Status,"
     " pIOFormatClassname As %String) As %String",
     "pSeparators:%String,pSequenceNumber:%String,*pStatus:%Status,pIOFormatClassname:%String",
     "%Library.String"),
    ("() As %Status", "", "%Library.Status"),
]

REJECTS = [
    "(pCurrentClass, pMethod, pArgList…)",          # the ellipsis row: vague, must not parse
    "as above plus `pLocalHostAndPort As %String`",  # prose, not a signature
    "(pX As %String",                                # unbalanced
    "(pX As %String) returns %Status",               # trailing text that is not 'As <Type>'
]


def self_test() -> bool:
    print("Self-test -- the signature normaliser\n")
    bad = 0
    for human, want_spec, want_ret in FIXTURES:
        try:
            spec, ret = parse_signature(human)
        except ValueError as exc:
            print(f"  FAIL  raised on a valid shape: {exc}")
            bad += 1
            continue
        if spec != want_spec or ret != want_ret:
            print(f"  FAIL  {human[:48]}...")
            print(f"        spec want {want_spec!r}")
            print(f"             got  {spec!r}")
            print(f"        ret  want {want_ret!r} got {ret!r}")
            bad += 1
        else:
            print(f"  ok    {(human[:66] + '...') if len(human) > 66 else human}")
    for junk in REJECTS:
        try:
            parse_signature(junk)
        except ValueError:
            print(f"  ok    rejected  {junk[:60]}")
        else:
            print(f"  FAIL  accepted junk: {junk!r}")
            bad += 1
    # The ambiguity guard is a check in its own right: a row that states neither class-method-ness
    # nor instance-ness must not silently default to one of them.
    for cells, label in (
        ([("`X`"), "no — instance", "`() As %Status`"], "instance row"),
        ([("`X`"), "**yes**", "`() As %Status`"], "class-method row"),
    ):
        try:
            classmethod_flag(cells)
            print(f"  ok    reads the {label}")
        except ValueError as exc:
            print(f"  FAIL  {label}: {exc}")
            bad += 1
    try:
        classmethod_flag(["`X`", "silent", "`() As %Status`"])
        print("  FAIL  accepted a row stating neither class method nor instance")
        bad += 1
    except ValueError:
        print("  ok    rejects a row stating neither")

    print(f"\n{bad} failure(s)")
    return bad == 0


# ---------------------------------------------------------------------------
# The gate.
# ---------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--self-test", action="store_true", help="parser fixtures only, no IRIS needed")
    args = ap.parse_args()

    if args.self_test:
        return 0 if self_test() else 1

    print("Signature cards -- checked against a live IRIS\n")
    text = DOC.read_text(encoding="utf-8")
    try:
        gated, callbacks, cards, excluded = parse_doc(text)
    except ValueError as exc:
        print(f"  FAIL  the document did not parse: {exc}")
        return 1

    # Defence 1: the parser's own population controls. A regression that stops recognising rows
    # reports fewer checks and would otherwise still exit 0.
    pops = [
        ("cards", len(set(cards)), EXPECTED_CARDS),
        ("gated signature rows", len(gated), EXPECTED_GATED),
        ("On<Streamlet>() callbacks", len(callbacks), EXPECTED_CALLBACKS),
    ]
    bad = 0
    for label, got, want in pops:
        if got != want:
            print(f"  FAIL  parsed {got} {label}, expected {want} -- the parser or the document moved.")
            print(f"        Re-read the document and update the EXPECTED_* constant deliberately.")
            bad += 1
        else:
            print(f"  ok    parsed {got} {label}")
    if bad:
        return 1

    for line, reason in excluded:
        print(f"  --    not gated (line {line}): {reason}")
    print()

    iris = Iris()
    print(f"  target {iris.base}")
    try:
        version = iris.version()
    except Exception as exc:
        print(f"  FAIL  cannot reach IRIS: {exc}")
        print("        Set IRIS_HOST / IRIS_PORT / IRIS_NAMESPACE / IRIS_USER / IRIS_PASSWORD.")
        return 1
    if not version.strip():
        print("  FAIL  the version came back empty -- that is a broken instrument, not a version")
        print("        mismatch. Check /api/atelier/ on this instance before reading anything else")
        print("        here as a result.")
        return 1
    print(f"  ok    {version}")
    if EXPECTED_VERSION not in version:
        print(f"  FAIL  this instance is not {EXPECTED_VERSION}, which the document says it was")
        print("        measured on. The cards are not wrong, they are UNVERIFIED here: re-measure")
        print("        and update the provenance line, or point this at the pinned image.")
        return 1

    # Controls before conclusions. A positive one proves the dictionary answers at all; a negative
    # one proves an absence is an absence rather than a broken query.
    try:
        n = iris.query("SELECT COUNT(*) AS N FROM %Dictionary.CompiledMethod "
                       "WHERE parent='Ens.BusinessOperation'")[0]["N"]
    except Exception as exc:
        print(f"  FAIL  the dictionary is not queryable: {exc}")
        return 1
    if int(n) < 300:
        print(f"  FAIL  positive control: Ens.BusinessOperation has {n} methods, expected >= 300")
        return 1
    print(f"  ok    positive control: Ens.BusinessOperation resolves {n} methods")
    absent = iris.query("SELECT Name FROM %Dictionary.CompiledMethod "
                        "WHERE parent='Ens.BusinessOperation' AND Name='NoSuchMemberExistsHere'")
    if absent:
        print(f"  FAIL  negative control returned {len(absent)} rows for a nonexistent member")
        return 1
    print("  ok    negative control: a nonexistent member returns 0 rows, not an error")
    print()

    # One query per class, no ORDER BY, names quoted individually.
    by_class: dict[str, list[dict]] = {}
    for g in gated:
        by_class.setdefault(g["target"], []).append(g)
    measured: dict[tuple[str, str], dict] = {}
    for cls, rows in sorted(by_class.items()):
        names = sorted({r["member"] for r in rows})
        inlist = ",".join("'" + x.replace("'", "''") + "'" for x in names)
        sql = ("SELECT Name, ClassMethod, ReturnType, FormalSpec FROM %Dictionary.CompiledMethod "
               f"WHERE parent='{cls}' AND Name IN ({inlist})")
        try:
            got = iris.query(sql)
        except Exception as exc:
            print(f"  FAIL  querying {cls}: {exc}")
            return 1
        for row in got:
            measured[(cls, row["Name"])] = row
        print(f"  ok    {cls}: asked {len(names)}, resolved {len(got)}")
    print()

    failures = []
    for g in sorted(gated, key=lambda x: (x["card"], x["member"])):
        key = (g["target"], g["member"])
        row = measured.get(key)
        if row is None:
            failures.append((g, "ABSENT", f"{g['target']} has no member named {g['member']}"))
            continue
        if bool(row["ClassMethod"]) != g["classmethod"]:
            failures.append((g, "CLASSMETHOD",
                             f"document says {'ClassMethod' if g['classmethod'] else 'instance'}, "
                             f"instance says {'ClassMethod' if row['ClassMethod'] else 'instance'}"))
        if (row.get("FormalSpec") or "") != g["formalspec"]:
            failures.append((g, "FORMALSPEC",
                             f"document {g['formalspec']!r}\n        instance {row.get('FormalSpec')!r}"))
        if canon_return(row.get("ReturnType") or "") != g["returntype"]:
            failures.append((g, "RETURNTYPE",
                             f"document {g['returntype']!r}, instance {canon_return(row.get('ReturnType') or '')!r}"))

    # The callback roster: own-origin ClassMethods with an empty FormalSpec, as the card states.
    cb_card = "HS.Gateway.HL7.HL7ToSDA3"
    inlist = ",".join("'" + x + "'" for x in sorted(set(callbacks)))
    cb_rows = {r["Name"]: r for r in iris.query(
        "SELECT Name, ClassMethod, FormalSpec, Origin FROM %Dictionary.CompiledMethod "
        f"WHERE parent='{cb_card}' AND Name IN ({inlist})")}
    for name in sorted(set(callbacks)):
        row = cb_rows.get(name)
        if row is None:
            failures.append(({"card": cb_card, "member": name, "line": 0}, "ABSENT",
                             f"{cb_card} has no callback named {name}"))
            continue
        if not row["ClassMethod"]:
            failures.append(({"card": cb_card, "member": name, "line": 0}, "CLASSMETHOD",
                             "card says the callbacks are ClassMethods; this one is an instance method"))
        if (row.get("FormalSpec") or "") != "":
            failures.append(({"card": cb_card, "member": name, "line": 0}, "FORMALSPEC",
                             f"card says every callback has an empty FormalSpec; got "
                             f"{row.get('FormalSpec')!r}"))
        if (row.get("Origin") or "") != cb_card:
            failures.append(({"card": cb_card, "member": name, "line": 0}, "ORIGIN",
                             f"card says own-origin; Origin is {row.get('Origin')!r}"))
    print(f"  ok    checked {len(set(callbacks))} callbacks on {cb_card}")
    print()

    if failures:
        # Classify by MECHANISM before listing symptoms. One wrong namespace produces an ABSENT per
        # gated member, and 30-odd of those read as "every card is wrong" rather than as the single
        # configuration mistake they are. Measured: pointed at USER on this instance, the
        # Ens.BusinessOperation positive control still passes -- it proves the dictionary answers,
        # NOT that HSLIB is mapped -- and every HS.* member then reports absent.
        absent = sum(1 for _, kind, _ in failures if kind == "ABSENT")
        if absent >= max(2, len(gated) // 2):
            print(f"FAIL  {absent} of {len(gated)} gated members are ABSENT in namespace {iris.ns}.")
            print("      That many absences is one cause, not many: this namespace almost certainly")
            print("      lacks the HS.* / ENSLIB mapping these cards describe. Point at a Foundation")
            print("      namespace before reading any of the detail below as a card defect.\n")
        print(f"FAIL  {len(failures)} signature claim(s) no longer match this instance\n")
        for g, kind, detail in failures:
            where = f"{DOC.name}:{g['line']}" if g.get("line") else DOC.name
            print(f"  {kind:<12} {g['card']}.{g['member']}  ({where})")
            print(f"        {detail}")
        print("\nThe document is the oracle: fix the card to match the instance, or establish that")
        print("the instance moved (image tag, namespace mapping) and re-measure deliberately.")
        return 1

    print(f"Signatures: all {len(gated)} member claims and {len(set(callbacks))} callbacks match "
          f"{version.split()[0] if version else 'the instance'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
