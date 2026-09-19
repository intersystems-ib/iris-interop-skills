#!/usr/bin/env python3
"""PostToolUse conformance pre-scan for Write|Edit of IRIS .cls (iris-interop-skills).

Cheap, deterministic pre-screen: when an interop class is written, scan that ONE file's
text for the mechanically-detectable anti-patterns (the ⚙ criteria CR-1/2/4/5/6/7/10/11 in
the conformance-review skill). If any match, nudge the model to run the conformance-reviewer
agent for the real (cross-file, semantic) review. Advisory only — never blocks, only emits
additionalContext, and stays silent when nothing matches. The agent, not this hook, is the
source of the verdict; this only decides whether a review is worth running.
"""
import sys, json, os, re, hashlib, time

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


def code_only(src):
    """`src` with whole-line comments removed, for matching CHECKS against.

    WHY THIS EXISTS. The `none_of` escapes are plain text matches, so before this they were
    satisfied by a COMMENT. Measured on the bank: `bp-class-based-async.cls` extends
    `Ens.BusinessProcess`, not BPL, and mentions `Ens.BusinessProcessBPL` exactly once -- in a
    `///` line explaining the difference. That comment alone exempted it from CR-1.

    And the exemption is not a freak case, it is the LIKELY one: a developer writing a deliberate
    hand BP naturally documents it as "unlike a BPL, this class ...", and thereby switches off the
    criterion that was written for them. Strip the prose, match the code.

    Deliberately line-based and not a tokeniser. A `//` that follows code on the same line is left
    alone: cutting at the first `//` would corrupt a string containing a URL, and turning a
    false negative into a false positive is the worse trade for an advisory.
    """
    kept = []
    for line in src.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("///") or stripped.startswith("//") or stripped.startswith("#;"):
            continue
        kept.append(line)
    return "\n".join(kept)


def checks_for(src):
    """The `CID (label)` strings the text criteria fire for, matched against code only."""
    body = code_only(src)
    out = []
    for cid, label, all_of, none_of in CHECKS:
        if all(re.search(p, body) for p in all_of) and not any(re.search(p, body) for p in none_of):
            out.append("%s (%s)" % (cid, label))
    return out


# (regex-or-list, regex-none-of-list, label). A criterion fires when ALL "all_of" match
# and NONE of "none_of" match. Conservative to avoid false positives; the agent confirms.
CHECKS = [
    ("CR-1", "pass-through BP instead of a MessageRouter rule",
     [r"Extends\s*[\s(][^{]*Ens\.BusinessProcess\b", r"\.Transform\(", r"SendRequestAsync\("],
     [r"Ens\.BusinessProcessBPL"]),
    # CR-15 COMPLEMENTS CR-1 rather than duplicating it. CR-1 says "do not write a BP to route";
    # it has legitimate exceptions, and when someone writes a hand BP WITH reason there is still
    # nothing telling them OnResponse is mandatory. Confirmed at the source: Ens.BusinessProcess's
    # own OnResponse body is `// Subclass responsibility  Quit $$$EnsError($$$NotImplemented)`, and
    # $$$NotImplemented renders as `ERROR #5003: Not implemented`. So a hand BP that calls
    # SendRequestAsync with the DEFAULT pResponseRequired=1 and does not override OnResponse fails
    # on EVERY reply. Not a style opinion: a guaranteed runtime failure.
    #
    # Ens.BusinessProcessBPL is exempt because it GENERATES its own OnResponse -- measured, its body
    # begins `If %compiledclass.Name="Ens.BusinessProcessBPL" Quit $$$OK` followed by generated code.
    ("CR-15", "hand BP calls SendRequestAsync but overrides no OnResponse — #5003 at every reply",
     [r"Extends\s*[\s(][^{]*Ens\.BusinessProcess\b", r"SendRequestAsync\("],
     [r"Method\s+OnResponse\b", r"Ens\.BusinessProcessBPL"]),
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
    # CR-11 fires on the PAYLOAD class, not on the message that carries it. The message is
    # undecidable from one file: `Property Address As MyApp.DAT.Address` is the same text
    # whether Address is %SerialObject (correct) or %Persistent (leaks) — the type lives in
    # another file, so checking there would flag the correct, common case on every write.
    # The payload itself IS decidable, and being declared %Persistent is the moment the
    # decision goes wrong. Cross-file confirmation (is it referenced by a message at all?
    # does that message cascade?) is the reviewer agent's job, not this hook's.
    ("CR-14", "OnInit override on a prebuilt EnsLib service that never calls ##super() — "
              "the base class never initialises the parser and the service silently drops input",
     [r"Extends\s*[\s(][^{]*EnsLib\.[\w.]+\.(?:Service|Operation)\.[\w.]+",
      r"Method\s+OnInit\s*\("],
     [r"##super\s*\("]),
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


# --------------------------------------------------------------------------------- CR-10
# An absolute path is a defect only where there is somewhere else to put it. A production item
# has Settings (JDBCClasspath, FilePath, Filename are adapter settings, ESQL §3.1) — a
# provisioning helper and a %UnitTest fixture do not, and the fixture MUST name a real file on
# the server. Firing on those produced 24 of 33 false positives (73%) and ZERO corrections in one
# cohort day, including on the exercise's own reference solution (#213).
#
# This cannot be written as a `none_of` list: none_of disqualifies on ANY single match over the
# whole file text, and the condition here is a CONJUNCTION — a path literal AND a runtime
# superclass. Allow-listing by superclass also fails CLOSED: an unrecognised superclass is not
# flagged, the right default for an advisory that produced no corrections at all in its old form.
ABS_PATH = re.compile(r'"[A-Za-z]:\\|"/tmp/|"/usr/')

# Superclasses that ARE production items, i.e. that have a Setting to move the path into.
RUNTIME_SUPER = re.compile(
    r"(?im)^\s*Class\s+[\w.%]+\s+Extends\s*[\s(][^{\n]*\b(?:"
    r"Ens\.BusinessService|Ens\.BusinessOperation|Ens\.BusinessProcess(?:BPL)?|"
    r"Ens\.DataTransformDTL|EnsLib\.[\w.]*\.(?:Service|Operation|Process)[\w.]*"
    r")\b")

# A fixture resolves a real path by design — never flag it.
UNITTEST_SUPER = re.compile(r"(?im)^\s*Class\s+[\w.%]+\s+Extends\s*[\s(][^{\n]*%UnitTest\.")


def cr10_hardcoded_path_in_runtime_component(src):
    """True only when a path literal sits in a class that HAS a production Setting."""
    if not ABS_PATH.search(src):
        return False
    if UNITTEST_SUPER.search(src):
        return False
    return bool(RUNTIME_SUPER.search(src))


STRUCTURAL = [
    ("CR-6", "HL7 flow wired into a GENERIC EnsLib.MsgRouter.RoutingEngine",
     cr6_generic_router_hosting_hl7),
    ("CR-10", "hardcoded absolute path in a runtime component (a Setting exists for it)",
     cr10_hardcoded_path_in_runtime_component),
]


# --- dedup latch ---------------------------------------------------------------- #217
# PostToolUse fires on EVERY Write|Edit of the same .cls, and the hits are a pure function of the
# file's text — so an unchanged violation reprinted an identical ~95-token additionalContext on
# every save: 23 of 34 firings in one measured day were repeats over 11 unique (file, criteria)
# pairs, one student getting the same CR-10 five times in five minutes with nothing in the file
# changing. A marker that appears eleven times while nothing changes reads as background noise,
# and it drags the one true positive down with it.
#
# Same shape as conformance_stop_gate.py's latch, but the stored value is a LIST: that gate
# latches ONE body of work per transcript, while a session raises several distinct
# (file, criteria) pairs that must not evict each other.
#
# The key carries the SORTED CRITERION IDS, not just the path: a criterion that is new for this
# file is new information and must still speak.
def _seen_path(session_key):
    d = os.path.join(os.path.expanduser("~"), ".claude", "iris-interop-skills", "prescan")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        return None
    key = hashlib.sha1(session_key.encode("utf-8")).hexdigest()[:16]
    return os.path.join(d, key + ".json")


def already_raised(session_key, signature):
    """True when this exact (file, criteria) pair was already raised in this session."""
    p = _seen_path(session_key)
    if not p:
        return False
    try:
        with open(p, encoding="utf-8") as fh:
            return signature in (json.load(fh).get("raised") or [])
    except Exception:
        return False


def record_raised(session_key, signature):
    p = _seen_path(session_key)
    if not p:
        return
    try:
        raised = []
        if os.path.exists(p):
            with open(p, encoding="utf-8") as fh:
                raised = json.load(fh).get("raised") or []
        if signature not in raised:
            raised.append(signature)
        with open(p, "w", encoding="utf-8") as fh:
            json.dump({"raised": raised[-200:], "at": int(time.time())}, fh)
    except Exception:
        pass  # a latch we cannot write costs a repeat, never a crash


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

    hits = list(checks_for(src))
    for cid, label, fn in STRUCTURAL:
        try:
            fired = fn(src)
        except Exception:
            fired = False          # never break a write on a parser bug
        if fired:
            hits.append("%s (%s)" % (cid, label))
    if not hits:
        return

    # One warning per (session, file, criteria set) — see the latch note above.
    session_key = data.get("transcript_path") or data.get("session_id") or ""
    signature = hashlib.sha1(
        ("%s|%s" % (os.path.abspath(fpath), ",".join(sorted(hits)))).encode("utf-8")
    ).hexdigest()
    if session_key and already_raised(session_key, signature):
        return               # silent: identical advice for the identical file

    base = os.path.basename(fpath) or "the class"
    msg = (
        "Conformance pre-scan flagged " + base + ": " + "; ".join(hits) + ". "
        "Run Skill(iris-interop-skills:conformance-review) on this class now — or hand it to "
        "Agent(subagent_type=\"iris-interop-skills:conformance-reviewer\") for the full pass — "
        "to confirm and get the canonical fix. "
        "Advisory; this is the only warning you will get for these criteria on this file."
    )
    # NAME THE FAILURE, NOT THE CRITERION. A warning that states a style rule competes with the
    # rest of the session's context; one that states what breaks at run time does not. Both notes
    # below are measured, and #331 is the case for them: an advisory that named only the criterion
    # was read, acknowledged and stepped over.
    if any(h.startswith("CR-15") for h in hits):
        msg += (" CR-15 specifically: Ens.BusinessProcess.OnResponse is `Quit "
                "$$$EnsError($$$NotImplemented)`, so with the default pResponseRequired=1 EVERY reply "
                "terminates the process with `<Ens>ErrBPTerminated ... ERROR #5003: Not implemented`. "
                "The circuit can still deliver, so end-to-end tests pass and the only evidence is in "
                "the Event Log. Either override OnResponse, or use EnsLib.MsgRouter.RoutingEngine, "
                "which has nothing to implement.")
    if any(h.startswith("CR-1 ") for h in hits):
        msg += (" CR-1 specifically: a hand BP is not just less idiomatic — it obliges you to "
                "implement OnResponse, and without it SendRequestAsync terminates the process with "
                "#5003 on every reply (see CR-15).")
    if any(h.startswith("CR-7") for h in hits):
        msg += (" CR-7 specifically: test results count only from the real iris_test tool, "
                "never from a [SqlProc] that returns \"PASS\".")

    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": MARKER + msg}}))
    if session_key:
        record_raised(session_key, signature)


if __name__ == "__main__":
    main()
