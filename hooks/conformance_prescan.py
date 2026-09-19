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
    # CR-15 lives in STRUCTURAL, not here — see the block below. It COMPLEMENTS CR-1 rather
    # than duplicating it: CR-1 says "do not write a BP to route" and has legitimate exceptions,
    # and when someone writes a hand BP WITH reason there is still nothing telling them that
    # OnResponse is then mandatory.
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


# -------------------------------------------------------------------------------- CR-15
# CR-15 began in CHECKS as two regexes and moved here the moment it was escalated to the
# Stop gate (#331), because a criterion that BLOCKS cannot be wrong about pResponseRequired.
#
# Measured on IRIS for Health 2026.1 (three hand BPs in one production, one message each):
#
#   pResponseRequired   OnResponse   Event Log                             reached the BO
#   default (1)         absent       ERROR #5003 / <Ens>ErrBPTerminated    yes
#   explicit 0          absent       clean                                 yes
#   default (1)         present      clean                                 yes
#
# Row 2 is why this is no longer a regex. `SendRequestAsync`'s signature is
# `pResponseRequired:%Boolean=1`, so passing 0 is a legal fire-and-forget call: no reply is
# ever delivered, OnResponse is never invoked, and the class is correct without it. The
# file-level escape a regex would need -- "the text 0 appears in a SendRequestAsync call" --
# is satisfied by ONE such call in a class that also makes a default one, so it buys a false
# negative on a real defect to avoid a false positive. Per call site, neither is necessary.
#
# Every row above DELIVERED to the operation. That is the other half of the finding: the
# circuit works, so an end-to-end test passes and the only evidence is in the Event Log.

def _call_args(src, open_idx):
    """Top-level, comma-split arguments of the call whose `(` is at `open_idx`.

    Returns None when the parentheses never balance; callers treat that as "unknown" rather
    than as "no arguments", so an unparseable call can never be read as a proven default.

    Only parentheses nest here. `[` and `]` are deliberately NOT treated as brackets: in
    ObjectScript they are the `contains` and `follows` OPERATORS, so counting them would
    unbalance every call whose argument tests `tMsg [ "x"`.
    """
    depth, i, n = 0, open_idx, len(src)
    cur, args, instr = [], [], False
    while i < n:
        ch = src[i]
        if instr:
            if ch == '"':
                if i + 1 < n and src[i + 1] == '"':
                    cur.append('""')       # "" is an escaped quote, not the end of the string
                    i += 2
                    continue
                instr = False
            cur.append(ch)
            i += 1
            continue
        if ch == '"':
            instr = True
            cur.append(ch)
            i += 1
            continue
        if ch == "(":
            depth += 1
            if depth > 1:
                cur.append(ch)
            i += 1
            continue
        if ch == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(cur))
                return args
            cur.append(ch)
            i += 1
            continue
        if ch == "," and depth == 1:
            args.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    return None


def sendrequestasync_sites(src):
    """One verdict per `SendRequestAsync(` call in `src`: does that call require a response?

    "required" is the only PROVABLE state -- the third argument is absent, elided, or the
    literal 1, so pResponseRequired is 1 and a reply is guaranteed. "optional" is the literal
    0. Everything else (a variable, a macro, an expression, an unbalanced call) is "unknown",
    because whether it evaluates to 0 at run time is not decidable from this file.
    """
    out = []
    for m in re.finditer(r"SendRequestAsync\s*\(", src):
        args = _call_args(src, m.end() - 1)
        if args is None:
            out.append("unknown")
            continue
        third = args[2].strip() if len(args) >= 3 else ""
        if third == "" or third == "1":
            out.append("required")         # absent, elided, or explicit -- pResponseRequired is 1
        elif third == "0":
            out.append("optional")
        else:
            out.append("unknown")
    return out


HAND_BP = re.compile(r"Extends\s*[\s(][^{]*Ens\.BusinessProcess\b")
BPL_BP = re.compile(r"Ens\.BusinessProcessBPL")
HAS_ONRESPONSE = re.compile(r"Method\s+OnResponse\b")
# `Class X Extends Y [ Abstract ]` -- the keyword list, not a method's.
ABSTRACT_CLASS = re.compile(r"(?im)^\s*Class\s+[\w.%]+[^{]*\[[^\]\n]*\bAbstract\b")


def cr15_verdict(src):
    """"provable" | "possible" | "clear" for one class's source.

    provable  at least one SendRequestAsync call in this class leaves pResponseRequired at 1
              and nothing overrides OnResponse. This is the state measured above as failing on
              every reply, and the only one the Stop gate blocks on.
    possible  a hand BP with no OnResponse whose every SendRequestAsync call passes a
              pResponseRequired this file cannot evaluate. Worth an advisory; never a block.
    clear     not a hand BP, a BPL, overrides OnResponse, Abstract, or every call site
              provably passes 0.

    Ens.BusinessProcessBPL is exempt because it GENERATES its own OnResponse -- measured, the
    generated body begins `If %compiledclass.Name="Ens.BusinessProcessBPL" Quit $$$OK`.

    KNOWN BLIND SPOT, written down because a criterion that reads as complete is the one that
    stops people checking. `Abstract` is exempt because an abstract class is never a
    production item and so cannot fail at run time -- but a CONCRETE subclass of it extends
    the base, not `Ens.BusinessProcess`, so this function never sees the subclass and cannot
    tell whether it supplied OnResponse. Cross-file is the reviewer agent's job, not a
    single-file hook's.
    """
    body = code_only(src)
    if not HAND_BP.search(body) or BPL_BP.search(body):
        return "clear"
    if HAS_ONRESPONSE.search(body) or ABSTRACT_CLASS.search(body):
        return "clear"
    sites = sendrequestasync_sites(body)
    if "required" in sites:
        return "provable"
    if "unknown" in sites:
        return "possible"
    return "clear"


def cr15_missing_onresponse(src):
    """The ADVISORY threshold: nudge on doubt, because a false positive costs one warning.

    The Stop gate calls cr15_verdict directly and blocks only on "provable", because there a
    false positive costs the credibility of the gate.
    """
    return cr15_verdict(src) != "clear"


# -------------------------------------------------------------------------------- CR-16
# A secret VALUE written into a versioned file. The mechanism rule -- credentials live in
# Ens.Config.Credentials and are referenced by name -- is already in business-operations, and both
# measured bench variants got that right. They leaked anyway, and this is the rule that was missing:
# the value never goes in the tree. Not a literal, not a comment, not a `.md`, not a recreation recipe.
#
# DELIBERATELY SEES COMMENTS, unlike the CHECKS list. `all_hits` hands STRUCTURAL predicates the RAW
# source while CHECKS go through code_only(), and for once that asymmetry is what is wanted: one of
# the two measured leaks was a `///` comment showing how to call the setup method, and the other was
# a `.md` on-call document. Strip the comments here and the criterion misses the exact shapes it
# exists for.
#
# FOUR NARROW SHAPES, NOT ONE BROAD ONE, and the difference was measured over 267 repo files:
#
#   literal user:pass inside Base64Encode(            0 false positives
#   literal passed to Setup/Set/CreateCredential(     0 false positives
#   non-empty <Setting Name="Password">               0 false positives
#   ANYTHING named password assigned a literal        7 of 7 FALSE POSITIVES
#
# That last row is why the obvious detector is not used: all seven were `Password = pPassword` or
# `pwd = os.environ.get(...)`, which is the CORRECT pattern. A criterion that fires on the right
# answer teaches people to ignore it.
#
# The empty-value form `<Setting Name="Password"></Setting>` is the placeholder idiom and must not
# fire, hence the `(?!</)` -- without it `\S` matches the `<` of the closing tag.
SECRET_IN_TREE = re.compile(
    r'Base64Encode\(\s*"[^"\s:]+:[^"\s]+"'
    r'|(?:SetupCredential|SetCredential|CreateCredential)\(\s*[\'"][^\'"]{3,}[\'"]'
    r'|<Setting[^>]*Name="(?:Password|CredentialsPassword)"[^>]*>\s*(?!</)\S',
    re.I)


def cr16_secret_in_versioned_file(src):
    """True when a secret VALUE appears in the file, including in a comment."""
    return bool(SECRET_IN_TREE.search(src))


STRUCTURAL = [
    ("CR-6", "HL7 flow wired into a GENERIC EnsLib.MsgRouter.RoutingEngine",
     cr6_generic_router_hosting_hl7),
    ("CR-10", "hardcoded absolute path in a runtime component (a Setting exists for it)",
     cr10_hardcoded_path_in_runtime_component),
    ("CR-15", "hand BP calls SendRequestAsync but overrides no OnResponse — #5003 at every reply",
     cr15_missing_onresponse),
    ("CR-16", "a secret VALUE is written into a versioned file — rotate it, do not just delete the line",
     cr16_secret_in_versioned_file),
]


def all_hits(src):
    """Every criterion that fires for one class's source -- text and structural alike.

    main() and the testsuite must agree about what "fires" means. Before this each assembled
    the list itself and only main()'s copy knew about STRUCTURAL, so a criterion moved from
    CHECKS to STRUCTURAL silently left the tests testing nothing.
    """
    hits = list(checks_for(src))
    for cid, label, fn in STRUCTURAL:
        try:
            fired = fn(src)
        except Exception:
            fired = False          # never break a write on a parser bug
        if fired:
            hits.append("%s (%s)" % (cid, label))
    return hits


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
    low = str(path).lower()

    # CR-16 is the ONLY criterion that runs on a non-.cls file, and the scoping is deliberate.
    # One of the two measured leaks was in a `.md` on-call document, so a .cls-only filter cannot
    # see it. Widening the filter for EVERY criterion would be the wrong fix: CR-1's and CR-5's
    # patterns would start matching prose that merely discusses a BP or an MSH:9 route, and an
    # advisory that fires on documentation is one people turn off.
    md_only = low.endswith(".md")
    if not (low.endswith(".cls") or md_only):
        return
    fpath, src = read_source(ti)
    if not src:
        return

    if md_only:
        hits = (["CR-16 (a secret VALUE is written into a versioned file — rotate it, do not just "
                 "delete the line)"] if cr16_secret_in_versioned_file(src) else [])
    else:
        hits = all_hits(src)
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
                "which has nothing to implement. This one is NOT only advisory: if it is still "
                "true when you stop, the Stop gate blocks (#331).")
    if any(h.startswith("CR-1 ") for h in hits):
        msg += (" CR-1 specifically: a hand BP is not just less idiomatic — it obliges you to "
                "implement OnResponse, and without it SendRequestAsync terminates the process with "
                "#5003 on every reply (see CR-15).")
    if any(h.startswith("CR-16") for h in hits):
        msg += (" CR-16 specifically: DELETING THE LINE IS NOT THE FIX. Git keeps every version, so "
                "once a secret is committed the only remedy is to ROTATE it — change the value in "
                "the Portal or wherever it lives, then remove the literal. Pass it as a parameter "
                "at run time and reference the credential by NAME from the item "
                "(`<Setting Name=\"Credentials\">MyCred</Setting>`). A recreation recipe names the "
                "credential ID and where it lives, never its value. Measured: 2 of 2 bench runs had "
                "the mechanism right and leaked the value anyway, each in a file that elsewhere said "
                "not to.")
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
