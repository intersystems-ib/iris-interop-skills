#!/usr/bin/env python3
"""Stop gate: "before declaring done" needs a point at which done is declared.

The plugin specifies a final compliance pass, defines sixteen criteria for it, and tells the
model to run it before declaring the work finished. Measured over 206 runs that produced
authored `.cls`, the `conformance-reviewer` agent was spawned **0 times** — while
`interop-builder`, whose instruction lives in the SessionStart hook, was spawned 79 times.
The two instructions differ only in where they live (issue #96).

The registered events were SessionStart, PreToolUse x2 and PostToolUse x4. There was no
`Stop` hook, so "before declaring done" had no enforcement point at all: the model decided
it was finished, stopped, and nothing ran. An advisory PostToolUse nudge is empirically
worth 0 invocations in 206 runs.

This hook is that missing point. It fires once, at the moment the model would stop.

THREE CHECKS, DELIBERATELY DIFFERENT IN KIND
--------------------------------------------
1. **Orphaned classes (CR-12), mechanical.** Every class this session wrote into IRIS with
   `iris_doc(mode=put)` must also exist on disk. This needs no model judgement and no IRIS
   connection — the transcript records what was put, and the filesystem is right here.

   This closes a real gap in the PreToolUse gate rather than duplicating it.
   `src_before_iris.py` returns early when the project has no `src/` tree at all ("a scratch
   namespace with no source tree is none of this hook's business"). That is defensible per
   call and fails open exactly when the loss is total: a run that never writes a file has no
   source tree, so every put is permitted, and it ends with the namespace holding the only
   copy. 16 runs in the corpus finished with no `.cls` on disk; 12 of them scored as passes,
   one at 96.45. A Stop hook sees the whole session, so it can tell "scratch namespace, no
   authoring" from "authored a production and saved none of it".

2. **CR-15, mechanical and PROVEN.** A hand `Ens.BusinessProcess` that calls
   `SendRequestAsync` leaving `pResponseRequired` at its default of 1, and overrides no
   `OnResponse`, terminates with `ERROR #5003: Not implemented` on every reply. Measured on
   this image, three BPs in one production, one message each:

       pResponseRequired   OnResponse   Event Log                             reached the BO
       default (1)         absent       ERROR #5003 / <Ens>ErrBPTerminated    yes
       explicit 0          absent       clean                                 yes
       default (1)         present      clean                                 yes

   It is here rather than left advisory because #331 measured the advisory being read,
   acknowledged and stepped over: two classes flagged CR-1 by the PostToolUse pre-scan both
   shipped, and the resulting production logged 16 `ErrBPTerminated`. An advisory competes
   with sixty steps of context; a check at the end does not.

   CR-15 and not CR-1 is escalated, deliberately. CR-1 ("do not write a BP to route") has
   legitimate exceptions, so blocking on it would eventually block correct work at the end of
   a long session, which is worse than an ignored warning. CR-15 has no exception once
   `pResponseRequired` is 1: the base method is unimplemented and the reply is guaranteed.

   The predicate is IMPORTED from the pre-scan, never restated -- see the import note below.
   Note row 3 of the table: every case DELIVERED to the operation. That is why this needs a
   gate at all. The flow works, so the end-to-end test passes and the only evidence is in the
   Event Log, which nobody reads once the data has arrived.

3. **Conformance pass not run, behavioural.** If the session authored interop classes and
   never invoked the reviewer, say so once. This one is a nudge with teeth rather than a
   proof of error, so it blocks a single time and then gets out of the way.

All three respect `stop_hook_active`, and all are additionally bounded by a session cutoff
and a persisted latch (#122). That combination — not `stop_hook_active` alone — is what makes the
model interrupted at most once per body of work. `stop_hook_active` is true only while the
model is already being re-invoked by THIS hook; it resets on every new user turn, so on its
own it prevents an infinite loop within one turn and nothing more. Relying on it for "once
per session" is how this gate came to fire on seventeen consecutive turns, over classes
written the previous day, in turns that authored nothing.

A gate that cannot be satisfied is a gate that gets disabled.

NOT MEASURED. That 0/206 is measured; whether this moves it is not, and cannot be from the
skills session — it needs an eval pass (issue #102). Checks (1) and (2) do not depend on model
behaviour and so cannot regress to zero; check (3) might.
"""
import sys, json, os, re, hashlib, calendar, time

# CR-15's predicate is IMPORTED, never restated here. The pre-scan and this gate must agree
# about what fires: a copy would be a second definition to keep in step, and the same
# criterion meaning two things in the advisory layer and the enforcing layer is precisely the
# defect behind #331 ("the detector is correct; the warning obliges nothing"). A restatement
# would also have to carry the pResponseRequired call-site analysis, which is the part that
# took a measurement to get right.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from conformance_prescan import cr15_verdict as _cr15_verdict
except Exception:
    _cr15_verdict = None      # a broken sibling must degrade this branch, never crash the gate

# Every exit path in this hook is silent by design — an allowing hook writes no
# attachment and produces no transcript event. That makes a hook that never fires
# indistinguishable from a hook that fires and allows, which is exactly the position
# the 1.8.1 eval left us in: reason text absent from 11/11 eligible runs, no way to
# tell whether the gate ran at all. Set IRIS_INTEROP_HOOK_DEBUG to a writable path
# and every invocation appends one JSON line saying where it exited.
def _trace(where, **kw):
    path = os.environ.get("IRIS_INTEROP_HOOK_DEBUG")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"hook": "conformance_stop_gate", "exit": where, **kw}) + "\n")
    except Exception:
        pass  # diagnostics must never break the hook

# Generated in IRIS by design, exported afterwards — never hand-authored, so never orphans.
GENERATED = re.compile(r"(?:^|\.)(?:WSC|SOAPENC)\.|\.Record$|\.Record\.cls$", re.I)

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".idea", ".vscode"}

REVIEWER_AGENT = "conformance-reviewer"
REVIEW_SKILL = "conformance-review"


def project_root(data):
    return data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


# A .cls file declares its class; a .cls.xml export names it in an attribute.
CLASS_DECL = re.compile(r"^[ \t]*Class[ \t]+([A-Za-z0-9_.%]+)", re.M)
XML_DECL = re.compile(r"<Class\s+name=[\"\']([A-Za-z0-9_.%]+)[\"\']", re.I)


def classes_on_disk(root):
    """Every class name actually DEFINED by a file under the project, mapped to its path.

    The path half exists for CR-15 below, which has to READ the class it judges. Membership
    tests behave identically on a dict, so find_orphans is unchanged by it.

    Matching on filename is the obvious implementation and it is wrong. This plugin's own
    example bank names files by topic — `dtl-order-to-vendor.cls` defines
    `Example.DT.OrderToVendor` — and a path-only check calls every one of them missing.
    Tested against a real session transcript before this was fixed: 25 classes put into
    IRIS, all 25 on disk, all 25 reported as orphans. A gate that is wrong 25 times out of
    25 on a normal workflow does not get obeyed, it gets removed.

    So presence is decided by content. The conventional path is still used, but only to
    tell the model WHERE to write a class that genuinely is missing.

    os.walk rather than glob('**'): glob silently skips dot-directories, so a class staged
    under one reads as missing (#95 cost a cycle to that).
    """
    found = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            low = fn.lower()
            if not (low.endswith(".cls") or low.endswith(".cls.xml") or low.endswith(".xml")):
                continue
            path = os.path.join(dirpath, fn)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            for name in CLASS_DECL.findall(text) + XML_DECL.findall(text):
                found.setdefault(name, path)
            # a file named for its class counts even if the body cannot be parsed
            base = fn[:-4] if low.endswith(".cls") else None
            if base and "." in base:
                found.setdefault(base, path)
    return found


def find_orphans(root, classes):
    """Classes this session put into IRIS that no file under the project defines."""
    on_disk = classes_on_disk(root)
    return [c for c in sorted(classes) if c not in on_disk]


def cr15_offenders(root, put, srcs):
    """(class, path) for every class among `put` that PROVABLY fails CR-15.

    SOURCE SELECTION, and it decides whether this branch is honest: the file on disk wins over
    the content that was put. The plugin's own rule is that the filesystem is the source of
    truth, CR-12 above has already established that each of these classes has a file, and the
    file is what the model will edit to fix this. Judging the put content instead would keep
    demanding a fix that has already been made on disk but not yet re-put -- a gate that
    cannot be satisfied by doing the right thing, which is how gates get disabled.

    Only "provable" blocks. cr15_verdict's "possible" -- a hand BP whose pResponseRequired is a
    variable this file cannot evaluate -- stays with the advisory pre-scan, because here a false
    positive costs the credibility of the whole gate rather than one warning.
    """
    if _cr15_verdict is None:
        return []                       # no predicate -> this branch does not exist
    on_disk = classes_on_disk(root)
    out = []
    for cname in sorted(put):
        path = on_disk.get(cname)
        src = ""
        if path:
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    src = fh.read()
            except OSError:
                src = ""
        if not src:
            src = srcs.get(cname) or ""
        if not src:
            continue
        try:
            if _cr15_verdict(src) == "provable":
                out.append((cname, path or "(in the namespace only)"))
        except Exception:
            continue                    # never block on a parser bug
    return out


def transcript_set(path):
    """The main transcript plus every subagent transcript belonging to this session.

    THIS IS THE WHOLE BUG THE 1.8.1 EVAL FOUND. A Stop hook is handed the MAIN session's
    transcript, and a subagent's tool calls are not in it — every entry in a main transcript
    carries isSidechain=False, and a session that spawned five agents shows none of their
    work. Measured on a real session: 33 classes were put into IRIS by subagents and the
    gate saw zero of them.

    That made the gate blind on exactly the path this plugin RECOMMENDS. The SessionStart
    hook says "or hand the whole component to the interop-builder agent", and interop-builder
    was the most-spawned agent in the corpus (79 spawns). So the gate fired only in the
    minority of runs where the main session happened to author something itself — 2 of 11
    sonnet runs, 0 of 11 haiku.

    Subagent transcripts live at a deterministic path: strip ".jsonl" from the main
    transcript and look under "<that>/subagents/". os.walk rather than glob("**") because
    glob skips dot-directories.
    """
    files = [path]
    base = path[:-6] if path.lower().endswith(".jsonl") else path
    sub = os.path.join(base, "subagents")
    if os.path.isdir(sub):
        for dirpath, dirnames, filenames in os.walk(sub):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in sorted(filenames):
                if fn.lower().endswith(".jsonl"):
                    files.append(os.path.join(dirpath, fn))
    return files



# --- #122: recency bound + a real once-per-session latch --------------------------------
#
# Two defects, independent, and fixing either alone leaves the other. Both were measured
# against a live transcript in which this gate fired on SEVENTEEN consecutive user turns.
#
# 1. NO RECENCY BOUND. scan_transcript accumulated `put` over the entire transcript with no
#    horizon, so classes written on 2026-08-28 gated every turn on 2026-08-29 — through two
#    releases, in turns that authored nothing. A transcript is not a working session: it
#    survives /exit and resume, and spans days.
#
#    The proxy for a session boundary is a long gap between records. That adapts, where a
#    fixed max-age does not: a genuine multi-hour build keeps all of its puts, while work
#    resumed the next morning correctly starts clean.
#
# 2. `stop_hook_active` CANNOT EXPRESS "ONCE PER SESSION". It is true only while the model is
#    already being re-invoked by this hook, and it resets on every new user turn. It prevents
#    an infinite loop within one turn and nothing more. The docstring's "interrupted at most
#    once per session" and the message's "this fires once per session, not in a loop" were
#    both promising something the mechanism could not deliver — and the documented escape
#    hatch ("say so and stop again") had nowhere to record that it had been said.
#
#    So the latch is written to disk, keyed on the transcript, holding a signature of the
#    body of work it fired about. Same unreviewed work -> already said, stay silent. New
#    classes -> new signature -> it speaks again, which is correct.
#
# The signature deliberately ignores WHICH branch fired. Clearing the orphan condition used
# to hand the turn straight to the no-review branch, which read to the user as a gate that
# would not stop. One body of work gets one interruption.

SESSION_GAP_HOURS = float(os.environ.get("IRIS_INTEROP_STOP_GATE_GAP_HOURS", "4") or 4)


def _epoch(rec):
    """Epoch seconds from a transcript record's ISO-8601 timestamp, or None."""
    ts = rec.get("timestamp")
    if not isinstance(ts, str) or not ts:
        return None
    t = ts.strip().replace("Z", "+0000").replace("z", "+0000")
    t = re.sub(r"\.(\d{1,6})\d*", r".\1", t)          # trim over-long fractional seconds
    t = re.sub(r"([+-]\d{2}):(\d{2})$", r"\1\2", t)     # +00:00 -> +0000
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z",
                "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S"):
        try:
            d = time.strptime(t, fmt)
        except ValueError:
            continue
        try:
            return calendar.timegm(d) - (d.tm_gmtoff or 0) if getattr(d, "tm_gmtoff", None) else calendar.timegm(d)
        except Exception:
            return calendar.timegm(d)
    return None


def session_cutoff(path):
    """Epoch second at which the CURRENT working session starts.

    The last inter-record gap longer than SESSION_GAP_HOURS is treated as a session
    boundary; anything before it belongs to a previous sitting. Returns 0.0 when there is
    no such gap (one continuous session) or when timestamps cannot be read, so an
    unparseable transcript degrades to the old behaviour rather than to silence.
    """
    stamps = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    e = _epoch(json.loads(line))
                except Exception:
                    continue
                if e:
                    stamps.append(e)
    except OSError:
        return 0.0
    stamps.sort()
    gap, cutoff = SESSION_GAP_HOURS * 3600.0, 0.0
    for a, b in zip(stamps, stamps[1:]):
        if b - a > gap:
            cutoff = b
    return cutoff


def _latch_path(transcript):
    d = os.path.join(os.path.expanduser("~"), ".claude", "iris-interop-skills", "stop-gate")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        return None
    key = hashlib.sha1(os.path.abspath(transcript).encode("utf-8")).hexdigest()[:16]
    return os.path.join(d, key + ".json")


REVIEW_SENTINEL = "review-pending"


def _latch_state(transcript):
    p = _latch_path(transcript)
    if not p:
        return {}
    try:
        with open(p, encoding="utf-8") as fh:
            s = json.load(fh)
            return s if isinstance(s, dict) else {}
    except Exception:
        return {}


def latch_seen(transcript, key, value):
    """True if this exact UNRESOLVED CONDITION has already been raised under `key`.

    #122 keyed this on put_signature(put) -- the sha1 of the WHOLE body of work the session
    had written into IRIS. Write one more class and the signature changes, the latch misses,
    and the gate blocks again for the SAME unresolved problem. In an exercise designed to
    build one component per step that is one interruption per step: measured, 32 firings
    across 10 of 14 students, eight of them to one person for one unchanged condition. The
    mechanism was right and the KEY was wrong (#210).
    """
    return _latch_state(transcript).get(key) == value


def latch_record(transcript, key, value):
    p = _latch_path(transcript)
    if not p:
        return
    state = _latch_state(transcript)
    state[key] = value
    state["at"] = int(time.time())
    try:
        with open(p, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
    except OSError:
        pass  # a latch we cannot write costs a repeat, never a crash


# --- #157: a put that never reached IRIS is not a write -----------------------
#
# The gate used to match on the CALL and never on its outcome, so an
# iris_doc(mode=put) that src_before_iris.py BLOCKED was counted as a class
# written into IRIS -- and CR-12's remedy then told the session to create a
# source file for a class that deliberately does not exist. The correct
# behaviour (respecting the sibling gate) was punished, and the prescribed fix
# manufactured the very evidence the gate asks for.
#
# Four result shapes appear in real transcripts (37 specimens, 2026-09-03):
#
#   A  PreToolUse block   is_error, content is this plugin's own prose
#                         ("Source-of-truth: ... would exist only in ...")   NOT written
#   B  MCP refusal        is_error, {"error": "...explicit Storage definition..."}  NOT written
#   C  compile failed     is_error, {"compile_console": [...], "compile_errors": [...]}
#                         -> the document IS stored, only the compile was skipped.  WRITTEN
#   D  success            no is_error, {"open_uri": ..., "storage_stripped": ...}   WRITTEN
#
# C is why "is_error means not written" would be wrong: it would switch CR-12 off
# for orphaned work that really is sitting in the namespace -- turning a false
# positive into a false negative, which is the failure this criterion exists for.
#
# So the test is not "did it error" but "is there positive evidence it never got
# to IRIS". Anything unrecognised, unparseable, or missing a result still counts,
# so this can only ever REMOVE a false positive.

# Keys only present once iris_doc has actually written and/or compiled.
# Matched as JSON KEYS, never as substrings of prose -- a substring gate here
# would guard a spelling rather than the outcome.
REACHED_IRIS_KEYS = ("compile_console", "compile_errors", "compiled",
                     "open_uri", "storage_stripped")


def _result_text(block):
    c = block.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b["text"] for b in c
                          if isinstance(b, dict) and isinstance(b.get("text"), str))
    return ""


def put_reached_iris(block):
    """False only with positive evidence the put never reached the namespace."""
    if not isinstance(block, dict):
        return True                       # no result recorded -> unchanged behaviour
    if not block.get("is_error"):
        return True                       # D
    txt = _result_text(block).strip()
    if not txt:
        return True
    try:
        payload = json.loads(txt)
    except Exception:
        return False                      # A -- prose, so nothing was stored
    if not isinstance(payload, dict):
        return True
    if any(k in payload for k in REACHED_IRIS_KEYS):
        return True                       # C
    if "error" in payload:
        return False                      # B
    return True


def get_says_absent(block):
    """True only for the exact NOT_FOUND envelope iris_doc returns for a missing document.

    The MCP's failure envelope is {"success": false, "error_code": ..., "error": ...}.
    NAMESPACE_NOT_FOUND and ATELIER_NOT_FOUND mean the call could not LOOK -- they are not
    evidence the class is absent and must never discard a put. Match error_code EXACTLY, never
    by suffix: a suffix match would drop real puts on a mistyped namespace and turn a false
    positive into the false negative CR-12 exists to prevent.

    Without this, removing the file with `rm` instead of iris_doc(mode=delete) left the put on
    the books and the gate demanded, five times over to one student, that a class be recovered
    from a namespace that does not have it (#210).
    """
    if not isinstance(block, dict) or not block.get("is_error"):
        return False
    try:
        payload = json.loads(_result_text(block).strip())
    except Exception:
        return False
    return isinstance(payload, dict) and payload.get("error_code") == "NOT_FOUND"


def scan_transcript(path, cutoff=0.0):
    """Return (classes put into IRIS, whether a pass ran, {class: source last put}).

    The third value is what CR-15 falls back to when a class has no file on disk -- it is the
    exact text that reached the namespace, so a judgement made on it is a judgement about what
    actually compiled.

    Matches the JSON keys of genuine tool invocations, never prose: the router's own text
    contains the literal string `Skill(iris-interop-skills:conformance-review)`, so it
    appears in 98.4% of transcripts as loaded context. Counting that as evidence of a
    review is the trap that made this look fine for 206 runs.
    """
    put, reviewed, srcs = set(), False, {}
    files = transcript_set(path)
    opened = 0
    results, events = {}, []          # #157: correlate each put with its outcome

    for fpath in files:
        try:
            fh = open(fpath, encoding="utf-8", errors="replace")
        except OSError:
            continue
        opened += 1
        with fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if cutoff:
                    e = _epoch(rec)
                    if e and e < cutoff:
                        continue  # #122: a previous working session, not this one
                msg = rec.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_result":
                        rid = block.get("tool_use_id")
                        if rid:
                            results[rid] = block
                        continue
                    if block.get("type") != "tool_use":
                        continue
                    tool = str(block.get("name") or "")
                    inp = block.get("input") or {}
                    if not isinstance(inp, dict):
                        continue

                    if REVIEWER_AGENT in str(inp.get("subagent_type") or ""):
                        reviewed = True
                    if REVIEW_SKILL in str(inp.get("skill") or ""):
                        reviewed = True

                    if "iris_doc" not in tool:
                        continue
                    mode = inp.get("mode")

                    if mode == "put":
                        name = str(inp.get("name") or "").strip()
                        content_str = inp.get("content")
                        if not name or not isinstance(content_str, str) or not content_str.strip():
                            continue
                        if GENERATED.search(name):
                            continue
                        events.append(("put", block.get("id"), strip_cls(name), content_str))

                    elif mode == "get":
                        # A get answering NOT_FOUND is positive proof the class is not in the
                        # namespace -- and it is exactly the evidence the CR-12 message asks the
                        # model to produce. Today producing it changes nothing.
                        n = inp.get("name")
                        if isinstance(n, str) and n.strip():
                            events.append(("get", block.get("id"), strip_cls(n.strip()), None))

                    elif mode == "delete":
                        # Staging scratch classes and deleting them afterwards is a legitimate
                        # workflow — it is how the example bank is compile-checked. Without
                        # this, cleaning up correctly looks identical to abandoning work in the
                        # namespace, and the gate fires on the careful case.
                        for n in ([inp.get("name")] + list(inp.get("names") or [])):
                            if isinstance(n, str) and n.strip():
                                events.append(("del", None, strip_cls(n.strip()), None))

    # replay in encounter order so a later delete still cancels an earlier put
    skipped = 0
    for kind, tid, cname, body in events:
        if kind == "del":
            put.discard(cname)
            srcs.pop(cname, None)
        elif kind == "get":
            if get_says_absent(results.get(tid)):
                put.discard(cname)
                srcs.pop(cname, None)
        elif put_reached_iris(results.get(tid)):
            put.add(cname)
            srcs[cname] = body        # last put wins: a re-put is the fix for an earlier one
        else:
            skipped += 1

    if not opened:
        _trace("transcript_unreadable", transcript=path, candidates=len(files))
        return put, True, srcs  # cannot read anything -> never block on a hook's blind spot
    _trace("scanned", transcripts=opened, subagents=len(files) - 1, puts=len(put),
           blocked_puts=skipped, reviewed=reviewed)
    return put, reviewed, srcs


def _count_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return sum(1 for _ in fh)
    except OSError:
        return -1


def strip_cls(name):
    return re.sub(r"\.cls$", "", name, flags=re.I)


def block(rule, reason):
    """Block with a stable leading marker (#162).

    The corpus counts Stop-gate activity from `hook_blocking_error` records (62 across
    49 runs), which says a block happened but not WHICH branch. The marker says which.
    """
    print(json.dumps({"decision": "block",
                      "reason": "[IIS-STOP-" + rule + "] " + reason}))
    sys.exit(0)


def main():
    _trace("invoked")
    try:
        data = json.load(sys.stdin)
    except Exception:
        _trace("bad_stdin")
        return  # never block on a hook bug

    if data.get("stop_hook_active"):
        _trace("stop_hook_active")
        return  # already interrupted once this session; say it once, not in a loop

    transcript = data.get("transcript_path")
    if not transcript:
        _trace("no_transcript_path", keys=sorted(data.keys()))
        return

    cutoff = session_cutoff(transcript)
    put, reviewed, srcs = scan_transcript(transcript, cutoff)
    if not put:
        _trace("no_puts", transcript=transcript,
               exists=os.path.exists(transcript),
               lines=_count_lines(transcript), reviewed=reviewed, cutoff=cutoff)
        return  # this session authored no interop classes; nothing to gate

    # #210: the latch is keyed on the UNRESOLVED CONDITION, per branch -- the orphan SET for
    # CR-12, a fixed sentinel for REVIEW -- not on the body of work. Keying it on the body of
    # work (#122) meant writing one more class changed the key and the gate re-blocked for the
    # same problem, so the more faithfully a student followed a one-component-per-step workbook,
    # the more often the hook stopped them.
    root = project_root(data)
    orphans = find_orphans(root, put)

    # --- #169: the remedy has to be RECOVERABLE, not just mandatory ----------
    #
    # It used to say "write each class to disk with the same content that is in IRIS"
    # -- naming the requirement and never the route. On a TRUE positive that invites a
    # reconstruction from memory, which is not what compiled. On a FALSE positive the
    # only way to comply is to invent source for a class that exists nowhere, which is
    # strictly worse than the orphan CR-12 guards against. Both observed instances were
    # an agent deliberately building a broken class to prove a check can fail, so the
    # misfire selectively punished the discipline we are trying to instil.
    #
    # `iris_doc(mode=get)` answers both halves with one call: it returns the real source
    # when the class is there, and it cannot return source when it is not. So the remedy
    # is unfabricatable by construction -- an agent following it literally cannot produce
    # a file for a class that never existed.
    #
    # This deliberately does NOT say "check first, and skip the gate if absent". Naming
    # the escape route in a denial hands the agent its own bypass (upstream 1.2.7, fork
    # #169/#170). The absence branch is phrased as an OUTCOME of doing the work, and it
    # asks for the tool result rather than an assertion. Note also which way it moves the
    # cheapest escape: today an agent that wants past this gate writes a plausible file,
    # which is undetectable and pollutes the tree; now it has to run a tool and report
    # what came back, which the transcript records. Adversarially this is a strict
    # improvement, not a new hole.
    #
    # The criterion itself already had this right -- conformance-review/SKILL.md CR-12
    # says "iris_doc(mode=get) the namespace-only classes and write them to src/". The
    # fix never propagated to the enforcement message. Same defect, one layer down.
    if orphans:
        claimed = set(_latch_state(transcript).get("CR12_claimed") or [])
        fresh = [c for c in orphans if c not in claimed]
        if not fresh:
            _trace("latched_cr12", orphans=len(orphans))
            return  # every one of these was already asked for; stay silent
        _trace("blocking_orphans", put=len(put), orphans=len(fresh))
        listed = "\n".join(
            "  - {}   ->  iris_doc(mode=get, name=\"{}.cls\")  ->  src/{}.cls".format(
                c, c, c.replace(".", "/"))
            for c in fresh[:15]
        )
        more = "\n  ... and {} more".format(len(fresh) - 15) if len(fresh) > 15 else ""
        latch_record(transcript, "CR12_claimed", sorted(claimed | set(orphans)))
        block(
            "CR12",
            "CR-12 \u2014 {} of the {} class(es) this session wrote into IRIS exist ONLY in the "
            "namespace:\n\n{}{}\n\n"
            "The namespace is not version-controlled, not reviewable, and does not survive the "
            "instance, so this work is already lost \u2014 it just has not been noticed yet.\n\n"
            "RECOVER each one from IRIS \u2014 do not retype it from memory. What is in the "
            "namespace is what actually compiled, and a reconstruction is not it:\n"
            "  1. iris_doc(mode=get, name=\"<Class>.cls\", namespace=\"<NS>\")\n"
            "  2. Write the returned source to src/<Pkg>/<Tipo>/<Name>.cls\n"
            "then stop.\n\n"
            "If mode=get answers that the class is not in the namespace, then it never reached "
            "IRIS, there is nothing to save, and this demand was spurious. Report that tool "
            "result and stop \u2014 do NOT create the file.\n\n"
            "These classes will not be asked for again. If you write NEW classes into IRIS "
            "without a file on disk, those will be.\n\n"
            "(Measured: 16 runs finished with no .cls on disk at all and 12 of them scored as "
            "passes, one at 96.45 \u2014 ground truth is read from the namespace, so saving "
            "nothing still grades green.)".format(len(fresh), len(put), listed, more)
        )

    # --- #331: CR-15, the one criterion worth blocking on -----------------------
    #
    # Ordered after CR-12 and before the review nudge, which is not arbitrary. CR-12 and this
    # are proofs; the review nudge is a nudge. And CR-15 cannot even be evaluated until the
    # class has a file or a recorded put, which CR-12 is what establishes.
    #
    # Latched per unresolved condition and per branch (#210): the key is the SET OF OFFENDING
    # CLASSES, not the body of work, so writing one more unrelated class does not re-raise a
    # problem that has already been named once.
    #
    # The remedy names the two fixes that keep the call's semantics -- override OnResponse, or
    # use a RoutingEngine which has nothing to implement. It deliberately does NOT mention that
    # pResponseRequired=0 also satisfies the criterion. That is a real and documented exemption
    # (it is in conformance-review/SKILL.md, where a person reads it), but naming it inside the
    # denial would hand an agent a one-character way out that silently changes the flow from
    # request/reply to fire-and-forget. Naming the remediation in the denial text is how an
    # agent gets its own bypass (upstream 1.2.7, fork #169/#170).
    offenders = cr15_offenders(root, put, srcs)
    if offenders:
        claimed = set(_latch_state(transcript).get("CR15_claimed") or [])
        fresh = [(c, pth) for c, pth in offenders if c not in claimed]
        if not fresh:
            _trace("latched_cr15", offenders=len(offenders))
            return                      # already named once; stay silent
        _trace("blocking_cr15", put=len(put), offenders=len(fresh))
        listed = "\n".join("  - {}   ({})".format(c, pth) for c, pth in fresh[:15])
        more = "\n  ... and {} more".format(len(fresh) - 15) if len(fresh) > 15 else ""
        latch_record(transcript, "CR15_claimed",
                     sorted(claimed | set(c for c, _ in offenders)))
        block(
            "CR15",
            "CR-15 \u2014 {} hand-written Ens.BusinessProcess class(es) call SendRequestAsync and "
            "override no OnResponse:\n\n{}{}\n\n"
            "Ens.BusinessProcess.OnResponse is `Quit $$$EnsError($$$NotImplemented)`. With "
            "pResponseRequired at its default of 1 the reply IS delivered, the callback IS "
            "invoked, and it is unimplemented \u2014 so every reply terminates the process with "
            "`<Ens>ErrBPTerminated ... ERROR #5003: Not implemented`.\n\n"
            "This is not caught by testing the flow. Measured on this platform: the outbound "
            "operation has already run by the time the reply comes back, so the data arrives, the "
            "production reads green, and the only evidence is in the Event Log.\n\n"
            "Fix each class, then stop:\n"
            "  - override `Method OnResponse(request As Ens.Request, ByRef response As "
            "Ens.Response, callrequest As Ens.Request, callresponse As Ens.Response, "
            "pCompletionKey As %String) As %Status`, or\n"
            "  - replace the hand BP with `EnsLib.MsgRouter.RoutingEngine` plus a business "
            "rule, which has nothing to implement (that is CR-1).\n\n"
            "These classes will not be asked for again.".format(len(fresh), listed, more)
        )

    if not reviewed:
        if latch_seen(transcript, "REVIEW", REVIEW_SENTINEL):
            _trace("latched_review", puts=len(put))
            return  # said once, and the escape hatch was used
        _trace("blocking_no_review", put=len(put))
        latch_record(transcript, "REVIEW", REVIEW_SENTINEL)
        block(
            "REVIEW",
            "The conformance pass has not run. This session authored {} interop class(es) and "
            "every one is on disk, but nothing has checked them against the sixteen criteria.\n\n"
            "Run it now:\n"
            "  Agent(subagent_type=\"iris-interop-skills:conformance-reviewer\")\n"
            "    — the full pass; re-verifies tests through the real iris_test rather than "
            "trusting a self-graded [SqlProc], which is CR-7.\n"
            "  or Skill(iris-interop-skills:conformance-review) to review inline.\n\n"
            "If the criteria genuinely do not apply here, say so and stop again — this will not "
            "fire again for the same classes. It fires again only if you write NEW classes into "
            "IRIS without reviewing them.".format(len(put))
        )


if __name__ == "__main__":
    main()
