#!/usr/bin/env python3
"""PostToolUse drift guard: the namespace moved, the tree did not (iris-interop-skills).

`src_before_iris` (PreToolUse) makes sure a class put into IRIS EXISTS on disk. That is a
presence check, and presence is not agreement. Two ordinary moves slip straight past it:

  1. `iris_doc(mode=put, content=...)` whose inline content DIFFERS from the file already on
     disk -- Claude editing a class straight into IRIS as a design evolves. The file exists,
     so the gate allows the put; the namespace advances and the tree stays behind.
  2. `iris_production_item` (or the Portal) mutating the production. No `iris_doc` call is
     involved at all, so no gate sees it, and `Production.cls` on disk silently goes stale.

Neither shows up in the feedback loop, and that is what makes this recurring rather than
rare: the tests run against the NAMESPACE, so the suite stays green the whole time. #181
reported it twice in one session -- the disk DTL still had 10 assigns while the running one
had 12, and disk `Production.cls` was still the single-router version. A conformance pass
found it much later, by byte-comparing. Nothing before that could have.

WARN, DO NOT BLOCK -- deliberately, and not merely out of caution:
`src_before_iris` denies on a mechanical, non-judgemental fact (the file is absent or it is
not). Divergence is not that fact. A put can legitimately differ from disk in ways nobody
should have to argue with a gate about, and the cost of being wrong is asymmetric: a false
deny stops real work, while a false warning costs one line of context. The repo already has
five PostToolUse guards in exactly this shape; this is the sixth.

Reads the PostToolUse JSON on stdin. Advisory only, never blocks, silent when clean.
"""
import sys, json, os, re, glob

# Stable marker (#162): prepended, never woven into the prose, so a reword cannot
# switch a corpus detector off. One grep for `[IIS-` finds every gate and guard.
MARKER = "[IIS-DRIFT] "

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".idea", ".vscode"}

# Same exemption as src_before_iris: these are produced in the namespace by design and
# exported afterwards, so the disk copy legitimately lags until the export step.
GENERATED = re.compile(r"(?:^|\.)(?:WSC|SOAPENC)\.|\.Record$|\.Record\.cls$", re.I)

# iris_production_item actions that CHANGE the production. `get_settings` only reads.
MUTATING = {"add", "remove", "enable", "disable", "set_settings"}

# Keys only present once iris_doc has actually written and/or compiled. Borrowed from
# conformance_stop_gate (#157): the question is not "did it error" but "is there positive
# evidence it never reached IRIS". A put that src_before_iris DENIED must not be reported
# as drift -- respecting the sibling gate is the correct behaviour, not a finding.
REACHED_IRIS_KEYS = ("compile_console", "compile_errors", "compiled",
                     "open_uri", "storage_stripped")


def _result_text(resp):
    """The `content` of a tool result, as text, across the shapes clients emit."""
    c = resp.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b["text"] for b in c
                          if isinstance(b, dict) and isinstance(b.get("text"), str))
    return ""


def reached_iris(resp):
    """False only with positive evidence the call never landed in the namespace.

    Mirrors conformance_stop_gate.put_reached_iris (#157) deliberately, including its
    ordering. The naive read -- "is_error means nothing was written" -- is wrong in both
    directions here:

      * a put that src_before_iris DENIED comes back is_error with this plugin's own PROSE
        as the content. Nothing was stored, so there is no drift, and warning would punish
        the session for respecting the sibling gate.
      * a put whose COMPILE failed also comes back is_error, but the document IS stored --
        so that one is real drift, and treating is_error as "not written" would switch this
        guard off for exactly the orphaned work it exists to catch.

    The test is therefore not "did it error" but "is there positive evidence it never got
    there". Anything unrecognised or unparseable counts as reached, so this can only ever
    remove a false warning.
    """
    if not isinstance(resp, dict):
        return True                              # no result recorded -> assume it landed
    if not resp.get("is_error"):
        return True
    txt = _result_text(resp).strip()
    if not txt:
        return True
    try:
        body = json.loads(txt)
    except Exception:
        return False                             # prose -> a gate's deny message
    if not isinstance(body, dict):
        return True
    if any(k in body for k in REACHED_IRIS_KEYS):
        return True                              # stored, compile failed
    if "error" in body:
        return False                             # MCP refusal
    return True


def normalise(text):
    """Compare sources, not whitespace.

    Line endings and trailing blanks differ for reasons nobody wants a warning about
    (CRLF from an editor, a missing final newline). Anything beyond that is a real
    difference in the class and worth a line of context.
    """
    lines = [ln.rstrip() for ln in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def project_root():
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def disk_path(root, cls):
    """The file for this class, or None. Atelier nested layout, plus the legacy flat form."""
    parts = cls.split(".")
    tail = "/" + "/".join(parts) + ".cls"
    flat = "/" + cls + ".cls"
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.lower().endswith(".cls"):
                continue
            norm = os.path.join(dirpath, fn).replace("\\", "/")
            if norm.endswith(tail) or norm.endswith(flat):
                return norm
    return None


def emit(msg):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": MARKER + msg}}))
    sys.exit(0)


def check_doc(ti, resp):
    if ti.get("mode") != "put":
        return                                   # get/delete/compile are not drift
    content = ti.get("content")
    if not isinstance(content, str) or not content.strip():
        return                                   # a put with no inline content changes no source
    name = str(ti.get("name") or "").strip()
    if not name or GENERATED.search(name):
        return
    if not reached_iris(resp):
        return                                   # blocked or refused -> the namespace did not move
    cls = re.sub(r"\.cls$", "", name, flags=re.I)
    path = disk_path(project_root(), cls)
    if path is None:
        return                                   # absent, not divergent -- src_before_iris owns it
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            on_disk = fh.read()
    except Exception:
        return
    if normalise(on_disk) == normalise(content):
        return                                   # tree and namespace agree

    rel = os.path.relpath(path, project_root()).replace("\\", "/")
    emit(
        "Source drift: `" + cls + "` now differs between IRIS and disk. The content you just "
        "put is NOT what `" + rel + "` contains, so the namespace has moved ahead of the tree.\n\n"
        "Write the same content to `" + rel + "` now. Nothing downstream will remind you: the "
        "tests run against the namespace, so they stay green while the repo stops reproducing "
        "the running production — and the divergence surfaces much later as a CR-12 finding.\n\n"
        "(If the disk file is the stale one by intent, that is the same fix. If IRIS is the "
        "stale one, `iris_doc(mode=get)` instead.)"
    )


def check_production_item(ti, resp):
    action = str(ti.get("action") or "").strip().lower()
    if action not in MUTATING:
        return
    if not reached_iris(resp):
        return
    item = str(ti.get("item") or "").strip()
    prod = str(ti.get("production") or "").strip()
    who = ("`" + prod + "`") if prod else "the running production"
    emit(
        "Source drift: `iris_production_item(action=" + action + ")` changed " + who +
        (" (item `" + item + "`)" if item else "") + " in the NAMESPACE only. No `.cls` was "
        "written, so nothing has updated the production class on disk and no gate sees this.\n\n"
        "Pull it back: `iris_doc(mode=get)` the production class and Write it to `src/`. "
        "Tests run against the namespace and will stay green either way, which is exactly why "
        "this goes unnoticed until a conformance byte-compare (CR-12) finds the tree no longer "
        "reproduces what is running."
    )


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return                                   # never disturb a session on a hook bug
    tool = str(data.get("tool_name") or "")
    ti = data.get("tool_input", {}) or {}
    resp = data.get("tool_response", data.get("tool_output", {}))
    if not isinstance(ti, dict):
        return
    if tool.endswith("iris_production_item"):
        check_production_item(ti, resp)
    elif tool.endswith("iris_doc"):
        check_doc(ti, resp)


if __name__ == "__main__":
    main()
