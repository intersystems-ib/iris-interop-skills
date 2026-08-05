#!/usr/bin/env python3
"""PostToolUse conformance pre-scan for Write|Edit of IRIS .cls (iris-interop-skills).

Cheap, deterministic pre-screen: when an interop class is written, scan that ONE file's
text for the mechanically-detectable anti-patterns (the ⚙ criteria CR-1/2/4/5/7/10/11 in
the conformance-review skill). If any match, nudge the model to run the conformance-reviewer
agent for the real (cross-file, semantic) review. Advisory only — never blocks, only emits
additionalContext, and stays silent when nothing matches. The agent, not this hook, is the
source of the verdict; this only decides whether a review is worth running.
"""
import sys, json, os, re


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
     [r"Extends\s+Ens\.BusinessProcess\b", r"\.Transform\(", r"SendRequestAsync\("],
     [r"Ens\.BusinessProcessBPL"]),
    ("CR-2", "hand-rolled file parser instead of a RecordMap",
     [r"Extends\s+Ens\.BusinessService\b", r"EnsLib\.File\.InboundAdapter", r"(\$Piece\(|\.ReadLine\()"],
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
        "hookEventName": "PostToolUse", "additionalContext": msg}}))


if __name__ == "__main__":
    main()
