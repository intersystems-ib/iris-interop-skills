#!/usr/bin/env python3
"""Stop gate: "before declaring done" needs a point at which done is declared.

The plugin specifies a final compliance pass, defines twelve criteria for it, and tells the
model to run it before declaring the work finished. Measured over 206 runs that produced
authored `.cls`, the `conformance-reviewer` agent was spawned **0 times** — while
`interop-builder`, whose instruction lives in the SessionStart hook, was spawned 79 times.
The two instructions differ only in where they live (issue #96).

The registered events were SessionStart, PreToolUse x2 and PostToolUse x4. There was no
`Stop` hook, so "before declaring done" had no enforcement point at all: the model decided
it was finished, stopped, and nothing ran. An advisory PostToolUse nudge is empirically
worth 0 invocations in 206 runs.

This hook is that missing point. It fires once, at the moment the model would stop.

TWO CHECKS, DELIBERATELY DIFFERENT IN KIND
------------------------------------------
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

2. **Conformance pass not run, behavioural.** If the session authored interop classes and
   never invoked the reviewer, say so once. This one is a nudge with teeth rather than a
   proof of error, so it blocks a single time and then gets out of the way.

Both respect `stop_hook_active`, and both are additionally bounded by a session cutoff and a
persisted latch (#122). That combination — not `stop_hook_active` alone — is what makes the
model interrupted at most once per body of work. `stop_hook_active` is true only while the
model is already being re-invoked by THIS hook; it resets on every new user turn, so on its
own it prevents an infinite loop within one turn and nothing more. Relying on it for "once
per session" is how this gate came to fire on seventeen consecutive turns, over classes
written the previous day, in turns that authored nothing.

A gate that cannot be satisfied is a gate that gets disabled.

NOT MEASURED. That 0/206 is measured; whether this moves it is not, and cannot be from the
skills session — it needs an eval pass (issue #102). Check (1) does not depend on model
behaviour and so cannot regress to zero; check (2) might.
"""
import sys, json, os, re, hashlib, calendar, time

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
    """Every class name actually DEFINED by a file under the project.

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
    found = set()
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
            found.update(CLASS_DECL.findall(text))
            found.update(XML_DECL.findall(text))
            # a file named for its class counts even if the body cannot be parsed
            base = fn[:-4] if low.endswith(".cls") else None
            if base and "." in base:
                found.add(base)
    return found


def find_orphans(root, classes):
    """Classes this session put into IRIS that no file under the project defines."""
    on_disk = classes_on_disk(root)
    return [c for c in sorted(classes) if c not in on_disk]


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


def latch_seen(transcript, signature):
    """True if this exact body of unreviewed work has already been raised once."""
    p = _latch_path(transcript)
    if not p:
        return False
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh).get("signature") == signature
    except Exception:
        return False


def latch_record(transcript, signature):
    p = _latch_path(transcript)
    if not p:
        return
    try:
        with open(p, "w", encoding="utf-8") as fh:
            json.dump({"signature": signature, "at": int(time.time())}, fh)
    except OSError:
        pass  # a latch we cannot write costs a repeat, never a crash


def put_signature(put):
    return hashlib.sha1("\n".join(sorted(put)).encode("utf-8")).hexdigest()


def scan_transcript(path, cutoff=0.0):
    """Return (classes put into IRIS this session, whether a conformance pass ran).

    Matches the JSON keys of genuine tool invocations, never prose: the router's own text
    contains the literal string `Skill(iris-interop-skills:conformance-review)`, so it
    appears in 98.4% of transcripts as loaded context. Counting that as evidence of a
    review is the trap that made this look fine for 206 runs.
    """
    put, reviewed = set(), False
    files = transcript_set(path)
    opened = 0

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
                    if not isinstance(block, dict) or block.get("type") != "tool_use":
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
                        put.add(strip_cls(name))

                    elif mode == "delete":
                        # Staging scratch classes and deleting them afterwards is a legitimate
                        # workflow — it is how the example bank is compile-checked. Without
                        # this, cleaning up correctly looks identical to abandoning work in the
                        # namespace, and the gate fires on the careful case.
                        for n in ([inp.get("name")] + list(inp.get("names") or [])):
                            if isinstance(n, str) and n.strip():
                                put.discard(strip_cls(n.strip()))

    if not opened:
        _trace("transcript_unreadable", transcript=path, candidates=len(files))
        return put, True  # cannot read anything -> never block on a hook's blind spot
    _trace("scanned", transcripts=opened, subagents=len(files) - 1, puts=len(put), reviewed=reviewed)
    return put, reviewed


def _count_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return sum(1 for _ in fh)
    except OSError:
        return -1


def strip_cls(name):
    return re.sub(r"\.cls$", "", name, flags=re.I)


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}))
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
    put, reviewed = scan_transcript(transcript, cutoff)
    if not put:
        _trace("no_puts", transcript=transcript,
               exists=os.path.exists(transcript),
               lines=_count_lines(transcript), reviewed=reviewed, cutoff=cutoff)
        return  # this session authored no interop classes; nothing to gate

    # #122: one body of unreviewed work earns one interruption, across BOTH branches.
    # Clearing the orphan condition used to hand the turn straight to the no-review
    # branch, which reads to the user as a gate that will not stop.
    signature = put_signature(put)
    if latch_seen(transcript, signature):
        _trace("latched", puts=len(put), signature=signature[:12])
        return

    root = project_root(data)
    orphans = find_orphans(root, put)

    if orphans:
        _trace("blocking_orphans", put=len(put), orphans=len(orphans))
        listed = "\n".join(
            "  - {}   ->  write it to src/{}.cls".format(c, c.replace(".", "/"))
            for c in orphans[:15]
        )
        more = "\n  ... and {} more".format(len(orphans) - 15) if len(orphans) > 15 else ""
        latch_record(transcript, signature)
        block(
            "CR-12 — {} of the {} class(es) this session wrote into IRIS exist ONLY in the "
            "namespace:\n\n{}{}\n\n"
            "The namespace is not version-controlled, not reviewable, and does not survive the "
            "instance, so this work is already lost — it just has not been noticed yet. Write "
            "each class to disk with the same content that is in IRIS, then stop.\n\n"
            "(Measured: 16 runs finished with no .cls on disk at all and 12 of them scored as "
            "passes, one at 96.45 — ground truth is read from the namespace, so saving nothing "
            "still grades green.)".format(len(orphans), len(put), listed, more)
        )

    if not reviewed:
        _trace("blocking_no_review", put=len(put))
        latch_record(transcript, signature)
        block(
            "The conformance pass has not run. This session authored {} interop class(es) and "
            "every one is on disk, but nothing has checked them against the twelve criteria.\n\n"
            "Run it now:\n"
            "  Agent(subagent_type=\"iris-interop-skills:conformance-reviewer\")\n"
            "    — the full pass; re-verifies tests through the real iris_test rather than "
            "trusting a self-graded [SqlProc], which is CR-7.\n"
            "  or Skill(iris-interop-skills:conformance-review) to review inline.\n\n"
            "If the criteria genuinely do not apply here, say so and stop again — this fires "
            "once per session, not in a loop.".format(len(put))
        )


if __name__ == "__main__":
    main()
