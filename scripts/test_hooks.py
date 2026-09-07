#!/usr/bin/env python3
"""Regression tests for the two blocking hooks.

Both defects fixed in #122 and #124 shipped for many releases and were found by reading
code and by a corpus sweep — neither was caught by a test, because there were none. Every
case below is one that was WRONG before its fix, plus the controls proving the fix did not
simply make the hook quieter.

A silent gate and a working gate are indistinguishable from the outside, so the positive
controls matter more than the negative ones. Run from the repo root:

    python3 scripts/test_hooks.py
"""
import io, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join(ROOT, "hooks", "interop_conformance_gate.py")
STOP = os.path.join(ROOT, "hooks", "conformance_stop_gate.py")
sys.path.insert(0, os.path.join(ROOT, "hooks"))
import conformance_stop_gate as g  # noqa: E402

NOW = time.time()
failures = []


def run_hook(script, payload):
    """DENY/ALLOW, with a crash reported as a crash.

    Merging stderr into stdout here would score a Python traceback as a deny, which makes
    a broken hook look like a working one. Keep the streams apart.
    """
    p = subprocess.run([sys.executable, script], input=json.dumps(payload),
                       capture_output=True, text=True)
    if p.returncode != 0 or p.stderr.strip():
        return "CRASH: " + (p.stderr.strip().splitlines()[-1][:120] if p.stderr.strip() else "rc")
    return "DENY" if p.stdout.strip() else "ALLOW"


def check(name, want, got):
    ok = want == got
    if not ok:
        failures.append(name)
    print("  {:<38}{:<16}{:<16}{}".format(name, want, got, "ok" if ok else "** MISMATCH"))


# --------------------------------------------------------------------------- #124
def doc(name, content, **extra):
    return {"tool_name": "mcp__iris__iris_doc",
            "tool_input": dict({"name": name, "content": content}, **extra)}


print("\n#124  interop_conformance_gate — adapter rule")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

CASES = [
    ("non-conformant BS", "DENY",
     doc("Demo.BS.FileIn.cls", "Class Demo.BS.FileIn Extends EnsLib.File.InboundAdapter\n{\n}")),
    ("the fixing rewrite", "ALLOW",
     doc("Demo.BS.FileIn.cls", 'Class Demo.BS.FileIn Extends Ens.BusinessService\n{\n'
                               'Parameter ADAPTER = "EnsLib.File.InboundAdapter";\n}')),
    ("author's own adapter", "ALLOW",
     doc("Demo.Adapter.MyIn.cls", "Class Demo.Adapter.MyIn Extends EnsLib.File.InboundAdapter\n{\n}")),
    # was DENY: looks_bs_bo scanned every segment, so a .BO. PACKAGE tripped it
    ("real adapter under a .BO. package", "ALLOW",
     doc("HS.Local.BO.Adapter.MyOutboundAdapter.cls",
         "Class HS.Local.BO.Adapter.MyOutboundAdapter Extends EnsLib.HTTP.OutboundAdapter\n{\n}")),
    # was DENY: the regex was unanchored and matched inside a /// comment
    ("conformant class, comment names it", "ALLOW",
     doc("Demo.BO.Http.cls",
         "/// Business Operation. Extends Ens.BusinessOperation; do NOT Extends "
         "EnsLib.HTTP.OutboundAdapter.\nClass Demo.BO.Http Extends Ens.BusinessOperation\n{\n"
         'Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";\n}')),
    # was DENY: content was matched against the union of every name in the call
    ("multi-doc put, names unioned", "ALLOW",
     {"tool_name": "iris_doc",
      "tool_input": {"names": ["Demo.Adapter.MyIn.cls", "Demo.BS.Other.cls"],
                     "content": "Class Demo.Adapter.MyIn Extends EnsLib.File.InboundAdapter\n{\n}"}}),
    # was ALLOW: the bypass. `[A-Za-z0-9_.%]*` cannot cross the `(`
    ("parenthesized single superclass", "DENY",
     doc("Demo.BS.FileIn.cls", "Class Demo.BS.FileIn Extends (EnsLib.File.InboundAdapter)\n{\n}")),
    # was ALLOW: and this is the form skills/dicom/SKILL.md:172 teaches for a BS class
    ("parenthesized multi superclass", "DENY",
     doc("Demo.BS.FileIn.cls",
         "Class Demo.BS.FileIn Extends (Ens.BusinessService, EnsLib.File.InboundAdapter)\n{\n}")),
    ("the plugin's own DICOM example", "ALLOW",
     doc("DICOM.BS.RESTService.cls",
         "Class DICOM.BS.RESTService Extends (Ens.BusinessService, %CSP.REST)\n{\n}")),
    ("BO named .Operation. (rule 1)", "DENY",
     doc("Demo.Operation.Send.cls", "Class Demo.Operation.Send Extends Ens.BusinessOperation\n{\n}")),
    ("lowercase class/extends", "DENY",
     doc("Demo.BS.FileIn.cls", "class Demo.BS.FileIn extends EnsLib.File.InboundAdapter\n{\n}")),
]
for name, want, payload in CASES:
    check(name, want, run_hook(GATE, payload))


# --------------------------------------------------------------------------- #122
def iso(off):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(NOW + off))


def rec(off, tool, inp):
    return json.dumps({"timestamp": iso(off),
                       "message": {"content": [{"type": "tool_use", "name": tool, "input": inp}]}})


def rec_id(off, tool, inp, tuid):
    return json.dumps({"timestamp": iso(off),
                       "message": {"content": [{"type": "tool_use", "name": tool,
                                                "input": inp, "id": tuid}]}})


def res(off, tuid, content, is_error=False):
    b = {"type": "tool_result", "tool_use_id": tuid, "content": content}
    if is_error:
        b["is_error"] = True
    return json.dumps({"timestamp": iso(off), "message": {"content": [b]}})


def transcript(lines):
    fd, p = tempfile.mkstemp(suffix=".jsonl")
    with os.fdopen(fd, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    return p


def stop(tpath, cwd, **extra):
    p = subprocess.run([sys.executable, STOP],
                       input=json.dumps(dict({"transcript_path": tpath, "cwd": cwd}, **extra)),
                       capture_output=True, text=True)
    if p.returncode != 0 or p.stderr.strip():
        return "CRASH: " + (p.stderr.strip().splitlines()[-1][:120] if p.stderr.strip() else "rc")
    if not p.stdout.strip():
        return "ALLOW"
    return "BLOCK/orphan" if "CR-12" in p.stdout else "BLOCK/no-review"


def clear(t):
    lp = g._latch_path(t)
    if lp and os.path.exists(lp):
        os.remove(lp)


print("\n#122  conformance_stop_gate — recency bound and once-per-session latch")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

work = tempfile.mkdtemp()
os.makedirs(os.path.join(work, "src", "Demo", "BS"), exist_ok=True)
with open(os.path.join(work, "src", "Demo", "BS", "Live.cls"), "w") as fh:
    fh.write("Class Demo.BS.Live {}")

PUT_LIVE = {"mode": "put", "name": "Demo.BS.Live.cls", "content": "Class Demo.BS.Live {}"}
PUT_GHOST = {"mode": "put", "name": "Demo.BO.Ghost.cls", "content": "Class Demo.BO.Ghost {}"}

t = transcript([rec(-300, "iris_doc", PUT_LIVE)])
clear(t)
check("live put, on disk, unreviewed", "BLOCK/no-review", stop(t, work))
check("same work, next turn (latched)", "ALLOW", stop(t, work))

t = transcript([rec(-300, "iris_doc", PUT_GHOST)])
clear(t)
check("live put, not on disk (CR-12)", "BLOCK/orphan", stop(t, work))

t = transcript([rec(-300, "iris_doc", PUT_LIVE),
                rec(-200, "Agent", {"subagent_type": "iris-interop-skills:conformance-reviewer"})])
clear(t)
check("live put, reviewed", "ALLOW", stop(t, work))

# the seventeen-firing bug: yesterday's classes gating today's turns
t = transcript([rec(-26 * 3600, "iris_doc", PUT_GHOST), rec(-300, "Bash", {"command": "echo"})])
clear(t)
check("put 26h ago, long gap since", "ALLOW", stop(t, work))

# ...but a long CONTINUOUS session is not a previous session and must still gate
lines = [rec(-6 * 3600, "iris_doc", PUT_GHOST)]
lines += [rec(-6 * 3600 + i * 1800, "Bash", {"command": "echo"}) for i in range(1, 12)]
t = transcript(lines)
clear(t)
check("6h continuous session, no gap", "BLOCK/orphan", stop(t, work))

# a latch must not swallow work that arrived after it fired
t = transcript([rec(-300, "iris_doc", PUT_GHOST)])
clear(t)
stop(t, work)
with open(t, "a") as fh:
    fh.write(rec(-100, "iris_doc", {"mode": "put", "name": "Demo.BO.Second.cls",
                                    "content": "Class Demo.BO.Second {}"}) + "\n")
check("new class after a firing", "BLOCK/orphan", stop(t, work))

t = transcript([rec(-300, "iris_doc", PUT_GHOST)])
clear(t)
check("stop_hook_active short-circuits", "ALLOW", stop(t, work, stop_hook_active=True))

check("unreadable transcript", "ALLOW", stop(transcript(["{not json"]), work))

# --------------------------------------------------------------------------- #157
# A put that src_before_iris BLOCKED is not a class written into IRIS. The two
# "must still fire" rows are the load-bearing half: excluding every is_error
# would turn this false positive into a FALSE NEGATIVE and switch CR-12 off for
# exactly the orphaned work it exists to catch. Bodies are the real shapes taken
# from 37 transcript specimens, not invented ones.
print("\n#157  conformance_stop_gate — a put counts only if it reached IRIS")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

BLOCKED = ("Source-of-truth: `Demo.BO.Ghost` would exist only in the IRIS namespace. "
           "No file for it was found under this project, and the namespace is not "
           "version-controlled, not reviewable, and does not survive the instance.")
STORAGE = json.dumps({"error": "The class content includes an explicit Storage definition. "
                               "Writing it via iris_doc would strip the Storage block."})
# The real C shape, key-for-key from all 9 specimens in the corpus: it carries an
# "error" key ALONGSIDE the compile markers. An invented fixture without "error"
# passes for the wrong reason -- it falls through the final return instead of
# exercising REACHED_IRIS_KEYS, and a mutant that deletes that check survives.
COMPILE_FAIL = json.dumps({"compile_console": ["Compiling class Demo.BO.Ghost",
                                               "Skipping class Demo.BO.Ghost"],
                           "compile_errors": ["ERROR #5373: Class 'X' does not exist"],
                           "compiled": False, "open_uri": "isfs://APP/Demo.BO.Ghost.cls",
                           "storage_stripped": False,
                           "error": "Compilation failed", "name": "Demo.BO.Ghost.cls"})
OK_PUT = [{"type": "text", "text": json.dumps(
    {"name": "Demo.BO.Ghost.cls", "open_uri": "isfs://APP/Demo.BO.Ghost.cls",
     "storage_stripped": False, "success": True})}]

for label, body, err, want in [
        ("A  src_before_iris blocked the put", BLOCKED,      True,  "ALLOW"),
        ("B  MCP refused it (storage guard)",  STORAGE,      True,  "ALLOW"),
        ("C  stored, compile failed",          COMPILE_FAIL, True,  "BLOCK/orphan"),
        ("D  put succeeded",                   OK_PUT,       False, "BLOCK/orphan")]:
    t = transcript([rec_id(-300, "iris_doc", PUT_GHOST, "tu_1"),
                    res(-299, "tu_1", body, err)])
    clear(t)
    check(label, want, stop(t, work))

# --------------------------------------------------------------------------------------
print("\n#169  conformance_stop_gate — the CR-12 remedy must be RECOVERABLE")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

# The demand used to name the requirement ("write it to disk with the same content that
# is in IRIS") and never the route, so the only way to comply for a class that does not
# exist was to invent one. These assert the route is named, because the route is what
# makes the instruction unfabricatable -- iris_doc(mode=get) cannot return source for a
# class that was never there.
#
# COVERAGE, stated here because a clean run reads like more than it is: this checks the
# SPELLING of the remedy, not that an agent follows it. It cannot see whether the file
# an agent writes actually came from the namespace. What it does guarantee is that the
# instruction can never silently drift back to the unfabricatable-free form (#169).


def stop_reason(tpath, cwd, **extra):
    p = subprocess.run([sys.executable, STOP],
                       input=json.dumps(dict({"transcript_path": tpath, "cwd": cwd}, **extra)),
                       capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        return ""
    return json.loads(p.stdout)["reason"]


t = transcript([rec(-300, "iris_doc", PUT_GHOST)])
clear(t)
reason = stop_reason(t, work)

# Two DISTINCT strings, because the route appears twice and one `in reason` test is
# satisfied by either. A first draft asserted only "iris_doc(mode=get" and a mutant that
# deleted the entire numbered-step block SURVIVED -- the per-class lines carried it.
check("numbered step names the route", True, "1. iris_doc(mode=get" in reason)
check("per-class line carries the route", True,
      'iris_doc(mode=get, name="Demo.BO.Ghost.cls")' in reason)
check("names the absent-class outcome", True, "not in the namespace" in reason)
# A pin on the exact pre-#169 wording, not a general property: no grep can express "does
# not tell the agent to write a file without saying where the content comes from".
check("no longer says only `write it to`", False, "write it to src/" in reason)
# Positive control: the reason is non-empty and really is the CR-12 branch, so the four
# assertions above are reading text that exists rather than passing on an empty string.
check("positive control — CR-12 branch fired", True,
      reason.startswith("[IIS-STOP-CR12] CR-12"))

# --------------------------------------------------------------------------------------
print("\n#162  every gate and guard message carries a stable marker")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

# A corpus can only count gate activity by grepping the message text, so every reword has
# silently degraded a measurement. The concrete cost, measured by the testsuite session:
# their parser was blind from plugin 1.6.0 through 1.8.8 -- EIGHT releases -- because their
# pattern said "an interop component" and the hook says "the interop component". One word,
# and the failure reads as "the gate did not fire", which is silence, which nothing notices.
#
# So markers are PREPENDED and the prose is left byte-identical. That is the whole design:
# a prefix cannot break an unanchored downstream search, so the marker can land in one
# release and detectors can migrate to it in their own time, with no window where the old
# pattern has stopped matching and the new one has not started.
#
# COVERAGE: this checks that a marker is EMITTED and is unique. It cannot check that the
# marker means what it says, and it is not evidence about how often any rule fires.
import ast as _ast, glob as _glob, re as _re

_markers, _unmarked = {}, []
for _path in sorted(_glob.glob(os.path.join(ROOT, "hooks", "*.py"))):
    _fn = os.path.basename(_path)
    _src = io.open(_path, encoding="utf-8").read()
    _tree = _ast.parse(_src)
    # The prefix is read out of the module's own deny()/block() body rather than hardcoded
    # here, so uniqueness is checked on the marker that is actually EMITTED. Two hooks may
    # legitimately share a rule name ("NAME") under different prefixes; they may not share
    # a full marker, because a corpus cannot tell those apart.
    _prefix = ""
    for _node in _tree.body:
        if isinstance(_node, _ast.FunctionDef) and _node.name in ("deny", "block"):
            for _sub in _ast.walk(_node):
                if isinstance(_sub, _ast.Constant) and isinstance(_sub.value, str) \
                        and _sub.value.startswith("[IIS-"):
                    _prefix = _sub.value
    # (a) deny()/block() call sites must pass a rule literal as their first argument.
    for _node in _ast.walk(_tree):
        if not isinstance(_node, _ast.Call) or not isinstance(_node.func, _ast.Name):
            continue
        if _node.func.id not in ("deny", "block") or not _node.args:
            continue
        _first = _node.args[0]
        if isinstance(_first, _ast.Constant) and isinstance(_first.value, str) \
                and _re.fullmatch(r"[A-Z0-9]+(-[A-Z0-9]+)*", _first.value):
            _markers.setdefault(_prefix + _first.value + "]", []).append(
                "%s:%d" % (_fn, _node.lineno))
        else:
            _unmarked.append("%s:%d  %s()" % (_fn, _node.lineno, _node.func.id))
    # (b) a PostToolUse guard carries its marker as a module constant instead.
    for _node in _tree.body:
        if isinstance(_node, _ast.Assign) and any(
                isinstance(t, _ast.Name) and t.id == "MARKER" for t in _node.targets):
            _lit = getattr(_node.value, "value", None)
            _markers.setdefault(str(_lit), []).append("%s:%d" % (_fn, _node.lineno))
    if "additionalContext" in _src and "MARKER" not in _src:
        _unmarked.append("%s  emits additionalContext with no MARKER" % _fn)

_dupes = ["%s at %s" % (k, ", ".join(v)) for k, v in sorted(_markers.items()) if len(v) > 1]
check("every deny/block/guard site is marked", 0, len(_unmarked))
check("no marker is used twice", 0, len(_dupes))
for _bad in _unmarked + _dupes:
    print("          - {}".format(_bad))
# A clean list is not evidence until it is non-empty: nine sites exist, and an AST walk that
# silently matched nothing would also report zero unmarked. This is the control.
check("positive control — sites were actually found", True, len(_markers) >= 15)

print("\n  marker inventory (enumerated, not filtered — see #131):")
for _m, _where in sorted(_markers.items()):
    print("    {:<28} {}".format(_m, ", ".join(_where)))

# --------------------------------------------------------------------------------------
# Source-level checks prove the literal is PRESENT; they do not prove it reaches the
# output. These two run the gate for real and read the emitted reason, which is the only
# thing a corpus ever sees.
def gate_reason(payload):
    p = subprocess.run([sys.executable, GATE], input=json.dumps(payload),
                       capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        return ""
    return json.loads(p.stdout)["hookSpecificOutput"]["permissionDecisionReason"]


_emitted = gate_reason(
    doc("Demo.BS.FileIn.cls", "Class Demo.BS.FileIn Extends EnsLib.File.InboundAdapter\n{\n}"))
check("marker reaches the emitted reason", True, _emitted.startswith("[IIS-CG-ADAPTER] "))
check("and the keyed prose survives it", True,
      bool(_re.search(r"must Extend Ens\.BusinessService", _emitted)))

print("\n#162  the prose downstream detectors key on is UNCHANGED")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

# Pinned from iris-interop-skills-test `src/iist/grading/taxonomy.py` GATE_PATTERN_STRINGS.
# That repo greps these literals out of hook output. They are recorded HERE so that a future
# reword sees the cost before making it, rather than discovering it as eight releases of
# silence. This is a COUPLING, not a style rule: if one of these must change, tell that
# session first and let the marker-keyed detector land ahead of the change.
for _label, _pat, _fn in [
        ("naming-convention",         r"Naming convention:",                          "interop_conformance_gate.py"),
        ("adapter-extended-directly", r"must Extend Ens\.BusinessService",            "interop_conformance_gate.py"),
        ("load-via-iris_execute",     r"Loading/compiling classes through iris_execute", "interop_conformance_gate.py"),
        ("tdd-without-test",          r"TDD: you just wrote the interop component",   "tdd_enforcement.py"),
        ("source-of-truth",           r"Source-of-truth:",                            "src_before_iris.py")]:
    _src = io.open(os.path.join(ROOT, "hooks", _fn), encoding="utf-8").read()
    check(_label, True, bool(_re.search(_pat, _src)))
# Negative control: their shipped pattern for the TDD rule said "an interop component" and
# never matched any release from 1.6.0 to 1.8.8. Pinning the wrong string is the failure this
# section exists to prevent, so assert the wrong one does NOT match.
check("negative control — \"an\" must not match", False,
      bool(_re.search(r"TDD: you just wrote an interop component",
                      io.open(os.path.join(ROOT, "hooks", "tdd_enforcement.py"),
                              encoding="utf-8").read())))

print("\n{} failure(s)".format(len(failures)))
for f in failures:
    print("  FAILED:", f)
sys.exit(1 if failures else 0)
