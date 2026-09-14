#!/usr/bin/env python3
"""PostToolUse conformance pre-scan for Write|Edit of IRIS .cls (iris-interop-skills).

Cheap, deterministic pre-screen: when an interop class is written, scan that ONE file's
text for the mechanically-detectable anti-patterns (the ⚙ criteria CR-1/2/4/5/6/7/10/11 in
the conformance-review skill). If any match, nudge the model to run the conformance-reviewer
agent for the real (cross-file, semantic) review. Advisory only — never blocks, only emits
additionalContext, and stays silent when nothing matches. The agent, not this hook, is the
source of the verdict; this only decides whether a review is worth running.
"""
import sys, json, os, re

# Stable marker (#162): prepended, never woven into the prose, so a reword cannot
# switch a corpus detector off. One grep for `[IIS-` finds every gate and guard.
MARKER = "[IIS-PRESCAN] "


def read_source(ti):
    """Best-effort: the .cls content from disk (post-write) or from the tool input."""
    path = ti.get("file_path") or ti.get("path") or ""
    if path and os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                return path, f.read()
        except Exception:
            pass
    # Fallback to inline content (Write) — Edit gives no full content, so disk is primary.
    for k in ("content", "new_string", "new_str"):
        v = ti.get(k)
        if isinstance(v, str) and v:
            return path, v
    return path, ""


# (regex-or-list, regex-none-of-list, label). A criterion fires when ALL "all_of" match
# and NONE of "none_of" match. Conservative to avoid false positives; the agent confirms.
CHECKS = [
    ("CR-1", "pass-through BP instead of a MessageRouter rule",
     [r"Extends\s*[\s(][^{]*Ens\.BusinessProcess\b", r"\.Transform\(", r"SendRequestAsync\("],
     [r"Ens\.BusinessProcessBPL"]),
    ("CR-2", "hand-rolled file parser instead of a RecordMap",
     [r"Extends\s*[\s(][^{]*Ens\.BusinessService\b", r"EnsLib\.File\.InboundAdapter", r"(\$Piece\(|\.ReadLine\()"],
     []),
    ("CR-4", "DTL written as <code> with no <assign>",
     [r"Ens\.DataTransformDTL", r"<code>"],
     [r"<assign\b"]),
    ("CR-5", "HL7 rule matching MSH:9.x without docCategory/docName",
     [r"Ens\.Rule\.Definition", r"MSH:9"],
     [r"docCategory|docName"]),
    ("CR-7", "tests 'passing' via a self-authored [SqlProc] runner, not %UnitTest",
     [r"\[\s*SqlProc\s*\]", r'"PASS'],
     []),
    ("CR-10", "hardcoded absolute path in a class",
     [r'"[A-Za-z]:\\|"/tmp/|"/usr/'],
     []),
    # CR-11 fires on the PAYLOAD class, not on the message that carries it. The message is
    # undecidable from one file: `Property Address As MyApp.DAT.Address` is the same text
    # whether Address is %SerialObject (correct) or %Persistent (leaks) — the type lives in
    # another file, so checking there would flag the correct, common case on every write.
    # The payload itself IS decidable, and being declared %Persistent is the moment the
    # decision goes wrong. Cross-file confirmation (is it referenced by a message at all?
    # does that message cascade?) is the reviewer agent's job, not this hook's.
    ("CR-11", "persistent message payload with no delete cascade — purge will orphan its rows",
     [r"Class\s+[\w.]*\.(?:DAT|MSG)\.[\w.]+\s+Extends\s*[\s(][^{]*%Persistent"],
     [r"Ens\.(?:Request|Response|Business|DataTransform)", r"\bTrigger\s+\w+", r"%OnDelete"]),
]


# --------------------------------------------------------------------------------- CR-6
# CR-6 is the one ⚙ criterion that is NOT a property of a class's own text: a generic
# router is correct until an HL7 flow is pointed at it. The violation is created by a
# LATER, separate edit — adding an HL7 service whose TargetConfigNames names the existing
# router — and nothing re-evaluates the router at that moment (#180). A green end-to-end
# test cannot see it either: the generic engine transports EnsLib.HL7.Message fine, it
# just loses schema validation in the rule editor and the {MSH:9.1} paths.
#
# So this one reads the production WIRING rather than a single class's keywords. The
# Production XData names items and links them by TargetConfigNames, which is enough to
# decide it from one file.
#
# WHAT THIS CHECK CANNOT SEE (#151 — the gate guards a spelling, not the rule):
#   - A CUSTOM SUBCLASS of an HL7 service. `MyApp.BS.HL7In Extends EnsLib.HL7.Service.FileService`
#     appears in the Item as `MyApp.BS.HL7In`, and the superclass lives in another file. Same
#     for a custom router subclass. Those are invisible here and stay the reviewer agent's job.
#   - A router fed by iris_production_item or the Portal rather than by editing Production.cls —
#     this hook only runs on Write|Edit of a .cls.
#   - Whether the rule attached to the router actually uses HL7 constructs; presence of an HL7
#     message on the wire is the trigger, which is the point (the rule is where you LOSE the
#     HL7 assist, so the flag must not wait for the rule to prove it).
# A clean run therefore means "no HL7 item in this file names a generic router by ClassName",
# not "CR-6 holds".

# Self-closing alternative FIRST and non-greedy body second: with `<Item ...>.*?</Item>`
# leading, a self-closing `<Item .../>` matches the opening branch (`[^>]*>` happily
# consumes through the `/`) and then runs forward to the NEXT item's `</Item>`, merging
# two items into one. That merge attributed a later RecordMap service's
# TargetConfigNames to an earlier HL7 operation and fired CR-6 on a correct production.
ITEM_RE = re.compile(r"<Item\b[^>]*/>|<Item\b[^>]*>.*?</Item>", re.S | re.I)
ATTR_RE = re.compile(r'(\w+)\s*=\s*"([^"]*)"')
TARGETS_RE = re.compile(
    r'<Setting[^>]*\bName\s*=\s*"TargetConfigNames"[^>]*>(.*?)</Setting>', re.S | re.I)

GENERIC_ROUTER = "enslib.msgrouter.routingengine"


def cr6_generic_router_hosting_hl7(src):
    """True when an EnsLib.HL7.* item targets a GENERIC routing-engine item by name."""
    items = []
    for chunk in ITEM_RE.findall(src):
        attrs = dict((k.lower(), v) for k, v in ATTR_RE.findall(chunk.split(">", 1)[0]))
        name, cls = attrs.get("name", ""), attrs.get("classname", "")
        if not name or not cls:
            continue
        targets = []
        for raw in TARGETS_RE.findall(chunk):
            targets += [t.strip() for t in raw.split(",") if t.strip()]
        items.append((name, cls, targets))

    generic = set(n for n, c, _ in items if c.strip().lower() == GENERIC_ROUTER)
    if not generic:
        return False
    for name, cls, targets in items:
        c = cls.strip().lower()
        # An HL7 host, but not the HL7 router itself (that one is the correct answer).
        if not c.startswith("enslib.hl7."):
            continue
        if c == "enslib.hl7.msgrouter.routingengine":
            continue
        if any(t in generic for t in targets):
            return True
    return False


STRUCTURAL = [
    ("CR-6", "HL7 flow wired into a GENERIC EnsLib.MsgRouter.RoutingEngine",
     cr6_generic_router_hosting_hl7),
]


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    ti = data.get("tool_input", {}) or {}
    path = ti.get("file_path") or ti.get("path") or ""
    if not str(path).lower().endswith(".cls"):
        return
    fpath, src = read_source(ti)
    if not src:
        return

    hits = []
    for cid, label, all_of, none_of in CHECKS:
        if all(re.search(p, src) for p in all_of) and not any(re.search(p, src) for p in none_of):
            hits.append("%s (%s)" % (cid, label))
    for cid, label, fn in STRUCTURAL:
        try:
            fired = fn(src)
        except Exception:
            fired = False          # never break a write on a parser bug
        if fired:
            hits.append("%s (%s)" % (cid, label))
    if not hits:
        return

    base = os.path.basename(fpath) or "the class"
    msg = (
        "Conformance pre-scan flagged possible best-practice issues in " + base + ": "
        + "; ".join(hits) + ". Per iris-interop-skills:conformance-review, run the "
        "conformance-reviewer agent (or Skill(iris-interop-skills:conformance-review)) once "
        "the component is built + TDD-green to confirm and get the canonical fix — and verify "
        "tests via the real iris_test tool, not a [SqlProc] self-report. Advisory."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": MARKER + msg}}))


if __name__ == "__main__":
    main()
