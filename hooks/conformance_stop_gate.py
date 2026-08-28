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

Both respect `stop_hook_active`, so the model is interrupted at most once per session and
can always proceed after answering. A gate that cannot be satisfied is a gate that gets
disabled.

NOT MEASURED. That 0/206 is measured; whether this moves it is not, and cannot be from the
skills session — it needs an eval pass (issue #102). Check (1) does not depend on model
behaviour and so cannot regress to zero; check (2) might.
"""
import sys, json, os, re

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


def scan_transcript(path):
    """Return (classes put into IRIS this session, whether a conformance pass ran).

    Matches the JSON keys of genuine tool invocations, never prose: the router's own text
    contains the literal string `Skill(iris-interop-skills:conformance-review)`, so it
    appears in 98.4% of transcripts as loaded context. Counting that as evidence of a
    review is the trap that made this look fine for 206 runs.
    """
    put, reviewed = set(), False
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        _trace("transcript_unreadable", transcript=path)
        return put, True  # cannot read -> never block on a hook's blind spot

    with fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except Exception:
                continue
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

    put, reviewed = scan_transcript(transcript)
    if not put:
        _trace("no_puts", transcript=transcript,
               exists=os.path.exists(transcript),
               lines=_count_lines(transcript), reviewed=reviewed)
        return  # this session authored no interop classes; nothing to gate

    root = project_root(data)
    orphans = find_orphans(root, put)

    if orphans:
        _trace("blocking_orphans", put=len(put), orphans=len(orphans))
        listed = "\n".join(
            "  - {}   ->  write it to src/{}.cls".format(c, c.replace(".", "/"))
            for c in orphans[:15]
        )
        more = "\n  ... and {} more".format(len(orphans) - 15) if len(orphans) > 15 else ""
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
