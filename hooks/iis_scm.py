#!/usr/bin/env python3
"""Which source-control model this project uses — `files` (default) or `ccr` (#410).

WHY. The plugin assumes FILE-BASED source control: code lives in `src/`, is pushed to IRIS, and
is committed to git. Four hooks enforce that and the bootstrap states it as rule 7, "THE FILESYSTEM
IS THE SOURCE OF TRUTH". Under CCR — InterSystems' own change control — the model is reversed: you
edit in the BASE namespace through the server-side hooks, they export each item to the CCR workspace
and queue it, and a "commit" is a Bundle and Upload in the CCR UI. **The namespace is the truth**,
and a stale local `src/` can overwrite the server version.

So a CCR session with this plugin enabled is blocked on its first edit, and nothing could switch the
conflicting gates off: the hooks read only IRIS_INTEROP_HOOK_DEBUG and
IRIS_INTEROP_STOP_GATE_GAP_HOURS, and Claude Code cannot disable one plugin's hooks selectively.

TWO SOURCES, env first, because they fail in opposite situations:

    IRIS_INTEROP_SCM=ccr        in the project's .claude/settings.json `env`. Reaches hooks because
                                hook processes inherit the session environment -- but project `env`
                                applies only once the folder is TRUSTED.
    .claude/iis-scm             a file containing `ccr`. Works in an untrusted folder, or when the
                                session was started without the variable. Same convention as
                                .claude/iis-source-roots / .claude/iis-ignore (#401).

NO AUTO-DETECTION. A hook cannot reach IRIS, so it cannot read the namespace's source-control class
to find out. Guessing would be worse than asking: guessing `ccr` disables real gates on a git
project, and guessing `files` is what blocks the CCR session today.

AN UNRECOGNISED VALUE MEANS `files`, deliberately. This decides whether BLOCKING gates run, so a
typo must not silently switch enforcement off -- it must leave it exactly as it is today. The typo
is recorded in the debug trace instead, where it can be found.

The same variable name as the MCP side (intersystems-ib/iris-interop-dev#417), so one setting
configures both halves.
"""
import json
import os
import sys

FILES = "files"
CCR = "ccr"

SCM_FILE = os.path.join(".claude", "iis-scm")

# Stable marker for every message this mode adds (#162).
MARKER = "[IIS-SCM-CCR] "


def _trace(where, **kw):
    path = os.environ.get("IRIS_INTEROP_HOOK_DEBUG")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"hook": "iis_scm", "exit": where, **kw}) + "\n")
    except Exception:
        pass


def scm_mode(root=None):
    """`"ccr"` or `"files"`. Never raises, never returns anything else."""
    raw = os.environ.get("IRIS_INTEROP_SCM")
    src = "env"
    if not (raw or "").strip():
        raw, src = _from_file(root), "file"
    val = (raw or "").strip().lower()
    if val == CCR:
        return CCR
    if val in ("", FILES):
        return FILES
    # A value that is neither: keep today's behaviour and say so where it can be found.
    _trace("unrecognised_mode", value=val[:40], source=src, using=FILES)
    return FILES


def unrecognised(root=None):
    """The raw value when it resolves to `files` by FALLBACK rather than by intent, else "".

    A SWALLOWED TYPO IS A NEGATIVE FACT, which is the shape this repo keeps removing: the debug
    trace above is invisible unless IRIS_INTEROP_HOOK_DEBUG is set, so an operator who typed
    `IRIS_INTEROP_SCM=CRR` would sit in `files` mode with every CCR gate silently inactive and no
    way to find out. The bootstrap surfaces this once per session.

    Matching the MCP side, which returns the same thing as `scm_mode_warning` on `check_config`
    (iris-interop-dev#417) -- their idea, and they were right that the trace alone is not enough.
    """
    raw = os.environ.get("IRIS_INTEROP_SCM")
    src = "IRIS_INTEROP_SCM"
    if not (raw or "").strip():
        raw, src = _from_file(root), SCM_FILE
    val = (raw or "").strip()
    if not val or val.lower() in (FILES, CCR):
        return ""
    return "%s=%r is not a source-control mode; using %r. Valid: %r or %r." % (
        src, val[:40], FILES, FILES, CCR)


def _from_file(root):
    if not root:
        return ""
    try:
        with open(os.path.join(root, SCM_FILE), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.split("#", 1)[0].strip()
                if line:
                    return line
    except OSError:
        pass
    return ""


def is_ccr(root=None):
    return scm_mode(root) == CCR


# --- evidence, because a hook cannot ask IRIS who holds the check-out --------------------
#
# Every CCR-mode check reads the SESSION TRANSCRIPT. Verified against 24 of 24 real PreToolUse
# payloads captured from a live project: `transcript_path` is present on PreToolUse, PostToolUse,
# Stop, SubagentStop, SessionStart and UserPromptSubmit alike, so a PreToolUse gate can read it.
#
# THE CHECKOUT BRANCH IS NOT REACHABLE TODAY AND THAT IS DELIBERATE. `iris_source_control` exists
# in the MCP (crates/.../src/tools/scm.rs) but is NOT in `INTEROP_TOOLS`, which
# is the profile this plugin targets -- exposing it is iris-interop-dev#417. So no transcript can
# contain a checkout call yet. It is accepted here anyway so that the day #417 lands nothing needs
# changing, and every message this mode writes prescribes `iris_doc(mode=get)`, which works now.
CHECKOUT_TOOL = "iris_source_control"
CHECKOUT_ACTIONS = ("checkout", "check_out", "execute")


def seen_document(transcript_path, cls):
    """True when THIS session already read or checked out `cls`.

    Accepts, in the order they became available:
      * iris_doc(mode=get) naming it            <- the only one reachable today
      * iris_doc(mode=head) naming it           <- and this is how you clear the gate for a NEW one
      * iris_source_control(action=checkout)    <- pending #417
      * a put that carried an elicitation id    <- the MCP's check-out dialog was answered

    WHY `head` COUNTS, and it closes a gap in #410 as filed. That design says to deny a put of an
    EXISTING document and allow a first put of a NEW one -- but a hook cannot reach IRIS, so it
    cannot tell the two apart, and "no prior read" is exactly the ambiguous case. `iris_doc`'s
    `mode=head` checks existence. So the instruction becomes: read it first, with `get` if it is
    there and `head` if you believe it is not, and either way the call itself is the evidence.
    That makes the gate VERIFIABLE rather than assertable -- the same reason #169's CR-12 remedy
    names `iris_doc(mode=get)` instead of asking the model to promise something.

    Unreadable transcript -> True. A hook must never deny because it could not look; that would
    block a CCR session for a reason it cannot act on, which is the failure this whole mode exists
    to remove.
    """
    if not transcript_path:
        return True
    want = (cls or "").strip().lower()
    if not want:
        return True
    try:
        opened = False
        for path in _transcript_files(transcript_path):
            try:
                fh = open(path, encoding="utf-8", errors="replace")
            except OSError:
                continue
            opened = True
            with fh:
                for line in fh:
                    if want not in line.lower():
                        continue          # cheap reject before the JSON parse
                    if _line_shows_read(line, want):
                        return True
        if not opened:
            return True
        return False
    except Exception:
        return True


def _transcript_files(transcript_path):
    """The main transcript plus any subagent transcripts beside it.

    Same shape conformance_stop_gate uses: a subagent's work lands in
    `<transcript-without-.jsonl>/subagents/`, and a delegated edit is still this session's edit.
    """
    out = [transcript_path]
    base = transcript_path[:-6] if transcript_path.endswith(".jsonl") else transcript_path
    sub = os.path.join(base, "subagents")
    for dirpath, dirnames, filenames in os.walk(sub):
        for fn in filenames:
            if fn.endswith(".jsonl"):
                out.append(os.path.join(dirpath, fn))
    return out


def _line_shows_read(line, want):
    try:
        rec = json.loads(line)
    except Exception:
        return False
    content = (rec.get("message") or {}).get("content")
    if not isinstance(content, list):
        return False
    for b in content:
        if not isinstance(b, dict) or b.get("type") != "tool_use":
            continue
        tool = str(b.get("name") or "")
        inp = b.get("input") or {}
        if not isinstance(inp, dict):
            continue
        names = [inp.get("name")] + list(inp.get("names") or [])
        named = any(isinstance(n, str) and want == _strip(n) for n in names)
        if not named:
            continue
        if "iris_doc" in tool and str(inp.get("mode") or "get").lower() in ("get", "head"):
            return True
        if CHECKOUT_TOOL in tool and str(inp.get("action") or "").lower() in CHECKOUT_ACTIONS:
            return True
        if "iris_doc" in tool and inp.get("elicitation_id"):
            return True
    return False


def _strip(name):
    n = name.strip().lower()
    for ext in (".cls", ".xml", ".mac", ".inc", ".int"):
        if n.endswith(ext):
            return n[: -len(ext)]
    return n


if __name__ == "__main__":       # `python3 hooks/iis_scm.py` prints the resolved mode
    print(scm_mode(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()))
