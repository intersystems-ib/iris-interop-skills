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
    if "IIS-STOP-CR12" in p.stdout:
        return "BLOCK/orphan"
    if "IIS-STOP-CR15" in p.stdout:
        return "BLOCK/cr15"
    return "BLOCK/no-review"


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
        ("source-of-truth",           r"Source-of-truth:",                            "src_before_iris.py"),
        ("source-drift",              r"Source drift:",                               "src_drift_guard.py")]:
    _src = io.open(os.path.join(ROOT, "hooks", _fn), encoding="utf-8").read()
    check(_label, True, bool(_re.search(_pat, _src)))
# Negative control: their shipped pattern for the TDD rule said "an interop component" and
# never matched any release from 1.6.0 to 1.8.8. Pinning the wrong string is the failure this
# section exists to prevent, so assert the wrong one does NOT match.
check("negative control — \"an\" must not match", False,
      bool(_re.search(r"TDD: you just wrote an interop component",
                      io.open(os.path.join(ROOT, "hooks", "tdd_enforcement.py"),
                              encoding="utf-8").read())))

# --------------------------------------------------------------------------------------
# #180  CR-6 keys off the production WIRING, not one class's keywords.
#
# The violation is created by an edit to a DIFFERENT component than the one that ends up
# wrong: a generic router is correct until an HL7 service is pointed at it, and nothing
# re-checks the router at that moment. A green end-to-end test cannot see it either, since
# the generic engine transports EnsLib.HL7.Message perfectly well.
#
# The two NEGATIVE cases carry the weight here. A naive "file mentions EnsLib.HL7 and also
# mentions EnsLib.MsgRouter.RoutingEngine" grep fires on both of them, and both are correct
# productions — an HL7 flow and a generic router coexisting without being wired together is
# the normal shape of a two-input production. A check that flagged those would be turned off
# within a week, which is the failure mode worth testing for.
import conformance_prescan as _cp  # noqa: E402

_ITEMS = {
    "hl7_bs":     '<Item Name="BS.AdtIn" ClassName="EnsLib.HL7.Service.FileService">'
                  '<Setting Target="Host" Name="TargetConfigNames">{tgt}</Setting></Item>',
    "recmap_bs":  '<Item Name="BS.Censo" ClassName="EnsLib.RecordMap.Service.FileService">'
                  '<Setting Target="Host" Name="TargetConfigNames">Router.Main</Setting></Item>',
    "generic":    '<Item Name="Router.Main" ClassName="EnsLib.MsgRouter.RoutingEngine"/>',
    "hl7_router": '<Item Name="Router.Main" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine"/>',
    "hl7_bo":     '<Item Name="BO.AdtOut" ClassName="EnsLib.HL7.Operation.FileOperation"/>',
}


def prod(*chunks):
    return ("Class Demo.Production Extends Ens.Production\n{\nXData ProductionDefinition\n{\n"
            '<Production Name="Demo.Production">' + "".join(chunks) + "</Production>\n}\n}")


# ── #331 / #332 ─────────────────────────────────────────────────────────────────────────────
#
# CR-15 and the comment leak. The two NEGATIVE-turned-POSITIVE cases carry the weight: before
# code_only(), a `none_of` escape was satisfied by a COMMENT, so a hand BP documented as "unlike a
# BPL, this class ..." switched off the very criterion written for it. That phrasing is not a freak
# case, it is what someone writing a deliberate hand BP actually types.
_BP_HEAD = "Class Demo.BP.FanOut Extends Ens.BusinessProcess\n{\n"
_SEND = '    Set tSC = ..SendRequestAsync("BO.Target", tReq)\n'
_ONRESP = "Method OnResponse(request, ByRef response, callrequest, callresponse, pCompletionKey) As %Status\n{\n    Quit $$$OK\n}\n"

def _cr(src, cid):
    # all_hits, not checks_for: CR-15 moved from CHECKS to STRUCTURAL when it was escalated
    # (#331), and reading only checks_for would have turned these six cases into no-ops that
    # still printed "ok". all_hits is what main() itself calls.
    return any(h.startswith(cid + " ") for h in _cp.all_hits(src))


print("\n#332  CR-15 fires on a hand BP with SendRequestAsync and no OnResponse")
print("  {:<52}{:<10}{:<10}{}".format("case", "want", "got", ""))

for _label, _src, _want in [
    # POSITIVE: the measured shape. Ens.BusinessProcess.OnResponse is
    # `Quit $$$EnsError($$$NotImplemented)`, so every reply is #5003.
    ("hand BP, SendRequestAsync, no OnResponse",
     _BP_HEAD + "Method OnRequest(request, ByRef response) As %Status\n{\n" + _SEND + "    Quit $$$OK\n}\n}", True),
    # NEGATIVE: overrides OnResponse. The whole point of the criterion is satisfied.
    ("hand BP that DOES override OnResponse",
     _BP_HEAD + "Method OnRequest(request, ByRef response) As %Status\n{\n" + _SEND + "    Quit $$$OK\n}\n" + _ONRESP + "}", False),
    # NEGATIVE: a BPL generates its own OnResponse -- measured, its body opens
    # `If %compiledclass.Name="Ens.BusinessProcessBPL" Quit $$$OK`.
    ("a BPL subclass",
     "Class Demo.BP.Flow Extends Ens.BusinessProcessBPL\n{\n" + _SEND + "}", False),
    # NEGATIVE: no async call at all -- a synchronous BP has no replies to handle.
    ("hand BP using SendRequestSync only",
     _BP_HEAD + '    Set tSC = ..SendRequestSync("BO.Target", tReq, .tRsp)\n}', False),
    # THE LEAK, as a POSITIVE. A comment naming BPL must NOT exempt the class.
    ("hand BP whose COMMENT mentions Ens.BusinessProcessBPL",
     "/// Unlike Ens.BusinessProcessBPL, this class is written by hand on purpose.\n"
     + _BP_HEAD + "Method OnRequest(request, ByRef response) As %Status\n{\n" + _SEND + "    Quit $$$OK\n}\n}", True),
    # THE LEAK AGAIN, on the other escape: a comment mentioning OnResponse is not an override.
    ("hand BP whose COMMENT mentions OnResponse",
     _BP_HEAD + "/// A real one would need Method OnResponse here.\n"
     + "Method OnRequest(request, ByRef response) As %Status\n{\n" + _SEND + "    Quit $$$OK\n}\n}", True),
]:
    check(_label, _want, _cr(_src, "CR-15"))

# --------------------------------------------------------------------------------------
print("\n#331  pResponseRequired is read PER CALL SITE, because CR-15 now blocks")
print("  {:<52}{:<10}{:<10}{}".format("case", "want", "got", ""))

# CR-15 was two regexes while it was advisory. Escalating it to the Stop gate made one
# question load-bearing: `SendRequestAsync`'s signature is `pResponseRequired:%Boolean=1`, so
# passing 0 is a legal fire-and-forget call that never invokes OnResponse. Measured on IRIS
# for Health 2026.1, three hand BPs in one production, one message each:
#
#   pResponseRequired   OnResponse   Event Log                             reached the BO
#   default (1)         absent       ERROR #5003 / <Ens>ErrBPTerminated    yes
#   explicit 0          absent       clean                                 yes
#   default (1)         present      clean                                 yes
#
# Row 2 is a class a regex would have BLOCKED. And the file-level escape a regex would need
# ("a 0 appears in a SendRequestAsync call") is satisfied by one such call in a class that also
# makes a default one -- the "0 AND a default call" row below, which is a real defect that a
# file-level escape would have waved through. Per call site, neither error is necessary.
#
# COVERAGE: these are text judgements about one file. Two rows are pinned to a live
# measurement (marked MEASURED); the rest are constructed shapes, and none of them is evidence
# about how often the criterion fires in real work.

def _hbp(body, extra=""):
    return "Class Demo.BP.X Extends Ens.BusinessProcess%s\n{\n%s\n}\n" % (extra, body)

_MT = "Method OnRequest(r As Ens.Request, Output p As Ens.Response) As %Status\n{\n@BODY@\n}"

def _M(body):
    return _MT.replace("@BODY@", body)

for _label, _src, _want in [
    ("MEASURED: default third arg -> #5003",
     _hbp(_M(' Quit ..SendRequestAsync("BO.Sink", r)')), "provable"),
    ("MEASURED: explicit 0 -> clean, must not block",
     _hbp(_M(' Quit ..SendRequestAsync("BO.Sink", r, 0)')), "clear"),
    ("explicit 1",
     _hbp(_M(' Quit ..SendRequestAsync("BO.Sink", r, 1)')), "provable"),
    # `f(a, b, , k)` elides the third argument, which means the default, which is 1.
    ("elided third arg is still the default",
     _hbp(_M(' Quit ..SendRequestAsync("BO.Sink", r, , "key")')), "provable"),
    # The row a file-level `none_of` regex gets WRONG: one exempt call does not exempt the file.
    ("0 AND a default call in one class",
     _hbp(_M(' Do ..SendRequestAsync("A", r, 0)\n Quit ..SendRequestAsync("B", r)')), "provable"),
    # Undecidable from this file -> advisory, never a block.
    ("variable third arg is not decidable",
     _hbp(_M(' Quit ..SendRequestAsync("A", r, tNeedReply)')), "possible"),
    ("macro third arg is not decidable",
     _hbp(_M(' Quit ..SendRequestAsync("A", r, ..#WANTREPLY)')), "possible"),
    ("OnResponse present",
     _hbp((_M(' Quit ..SendRequestAsync("A", r)')) + "\n" + _ONRESP), "clear"),
    # An Abstract class is never a production item, so it cannot fail at run time. The blind
    # spot this leaves (a concrete subclass extends the BASE, so it never matches HAND_BP) is
    # written down in cr15_verdict's docstring rather than papered over.
    ("Abstract base is never instantiated",
     _hbp(_M(' Quit ..SendRequestAsync("A", r)'), extra=" [ Abstract ]"), "clear"),
    ("no SendRequestAsync at all", _hbp(_M(" Quit $$$OK")), "clear"),
    ("a BPL generates its own OnResponse",
     "Class Demo.BP.F Extends Ens.BusinessProcessBPL\n{\nXData BPL {}\n}", "clear"),
    # The parser, in the two ways ObjectScript breaks a naive comma split.
    ("a comma inside a quoted argument",
     _hbp(_M(' Quit ..SendRequestAsync("A,B", r, 0)')), "clear"),
    # `[` is the CONTAINS operator, not a bracket: counting it would unbalance the call.
    ("the contains operator inside an argument",
     _hbp(_M(' Quit ..SendRequestAsync($Select(r.Body [ "x":"A",1:"B"), r, 0)')), "clear"),
    ("a nested call whose own arg is 0",
     _hbp(_M(' Quit ..SendRequestAsync("A", ..Build(r, 0))')), "provable"),
]:
    check(_label, _want, _cp.cr15_verdict(_src))

# An unbalanced call must read as "unknown", never as "no arguments" -- which would make it
# provable, i.e. would turn a parse failure into a block.
check("an unbalanced call is unknown, not provable", "possible",
      _cp.cr15_verdict(_hbp(' Quit ..SendRequestAsync("A", r')))
check("_call_args signals None when unbalanced", True, _cp._call_args('f(a, b', 1) is None)
# positive control for the line above: the same parser on a BALANCED call returns the args,
# so "is None" is reading a real distinction rather than a function that always fails.
check("_call_args splits a balanced call", "a|b",
      "|".join(a.strip() for a in (_cp._call_args('f(a, b)', 1) or [])))

# --------------------------------------------------------------------------------------
print("\n#331  the Stop gate BLOCKS on a provable CR-15, and only on a provable one")
print("  {:<52}{:<10}{:<10}{}".format("case", "want", "got", ""))

# The escalation itself. An advisory PostToolUse warning was measured being read,
# acknowledged and stepped over (#331: two flagged classes shipped, 16 ErrBPTerminated in the
# resulting production), so the criterion needs a check at the moment work is declared done.
#
# COVERAGE: this proves the branch fires, latches, and prefers the file on disk. It does not
# prove a model obeys it -- that needs the eval pass in #102, same as CR-12.

_w15 = tempfile.mkdtemp()
os.makedirs(os.path.join(_w15, "src", "Demo", "BP"), exist_ok=True)

def _write15(name, src):
    fp = os.path.join(_w15, "src", "Demo", "BP", name + ".cls")
    with open(fp, "w") as fh:
        fh.write(src)
    return fp

_BAD = "Class Demo.BP.Bad Extends Ens.BusinessProcess\n{\n" + (_M(' Quit ..SendRequestAsync("BO.S", r)')) + "\n}\n"
_GOOD = "Class Demo.BP.Good Extends Ens.BusinessProcess\n{\n" + (_M(' Quit ..SendRequestAsync("BO.S", r)')) + "\n" + _ONRESP + "}\n"
_FIRE = "Class Demo.BP.Fire Extends Ens.BusinessProcess\n{\n" + (_M(' Quit ..SendRequestAsync("BO.S", r, 0)')) + "\n}\n"

_write15("Bad", _BAD)
_write15("Good", _GOOD)
_write15("Fire", _FIRE)

def _put15(cls, body):
    return {"mode": "put", "name": cls + ".cls", "content": body}

_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Bad", _BAD))])
clear(_t)
check("provable CR-15 blocks", "BLOCK/cr15", stop(_t, _w15))
check("same offender next turn is latched", "ALLOW", stop(_t, _w15))

_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Good", _GOOD))])
clear(_t)
check("OnResponse present -> not the CR-15 branch", "BLOCK/no-review", stop(_t, _w15))

# The whole reason for the call-site analysis: this class is CORRECT and must not be blocked.
_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Fire", _FIRE))])
clear(_t)
check("pResponseRequired=0 must not block", "BLOCK/no-review", stop(_t, _w15))

# A reviewed session is not exempt: CR-15 is a proof, not a nudge, so it outranks the review.
_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Bad", _BAD)),
                 rec(-200, "Agent", {"subagent_type": "iris-interop-skills:conformance-reviewer"})])
clear(_t)
check("a review does not excuse a provable CR-15", "BLOCK/cr15", stop(_t, _w15))

# SOURCE SELECTION, both directions. The file on disk wins over the content that was put --
# otherwise fixing the file and not re-putting it leaves a demand that cannot be satisfied.
_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Good", _BAD.replace("Demo.BP.Bad", "Demo.BP.Good")))])
clear(_t)
check("disk (fixed) beats put content (broken)", "BLOCK/no-review", stop(_t, _w15))

_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Bad", _GOOD.replace("Demo.BP.Good", "Demo.BP.Bad")))])
clear(_t)
check("disk (broken) beats put content (fixed)", "BLOCK/cr15", stop(_t, _w15))

# CR-12 is a precondition, not a peer: a class with no file cannot be read, so the orphan
# branch must come first rather than this one guessing from the namespace copy.
_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Nowhere", _BAD.replace("Demo.BP.Bad", "Demo.BP.Nowhere")))])
clear(_t)
check("an orphan is CR-12 first, not CR-15", "BLOCK/orphan", stop(_t, _w15))

# ---- the reason text ----
# Same reasoning as #169: no grep can express "does not hand the agent a one-character
# bypass", so the pin is on the exact strings. pResponseRequired=0 IS a documented exemption
# (conformance-review/SKILL.md), and it must NOT appear here: naming it in a denial turns a
# semantic decision -- request/reply vs fire-and-forget -- into the cheapest way out.
_t = transcript([rec(-300, "iris_doc", _put15("Demo.BP.Bad", _BAD))])
clear(_t)
_r15 = stop_reason(_t, _w15)
check("positive control — the CR-15 branch fired", True, _r15.startswith("[IIS-STOP-CR15] CR-15"))
check("names the offending class", True, "Demo.BP.Bad" in _r15)
check("names the runtime failure, not the criterion", True, "ERROR #5003: Not implemented" in _r15)
check("names the OnResponse override as the fix", True, "Method OnResponse(request As Ens.Request" in _r15)
check("names the RoutingEngine alternative", True, "EnsLib.MsgRouter.RoutingEngine" in _r15)
check("says why a green flow proves nothing", True, "the data arrives" in _r15)
check("does NOT hand over pResponseRequired=0", False, "pResponseRequired=0" in _r15)

print("\n#331  a comment can no longer TRIGGER a criterion either")
print("  {:<52}{:<10}{:<10}{}".format("case", "want", "got", ""))

for _label, _src, _want in [
    # NEGATIVE: CR-5 needs Ens.Rule.Definition AND MSH:9. With MSH:9 only in prose it must not
    # fire -- measured on the bank, this was a live false positive on routing-rule-fanout.cls.
    ("CR-5 with MSH:9 only in a comment",
     "/// Routing on MSH:9 is the case this file does NOT use.\n"
     "Class Demo.RUL.Fan Extends Ens.Rule.Definition\n{\n}", False),
    # POSITIVE control: the same criterion still fires when MSH:9 is in the rule itself.
    ("CR-5 with MSH:9 in the rule body",
     "Class Demo.RUL.Fan Extends Ens.Rule.Definition\n{\n"
     '<when condition=\'HL7.{MSH:9.1}="ADT"\'/>\n}', True),
]:
    check(_label, _want, _cr(_src, "CR-5"))

# code_only is line-based on purpose: a trailing // must not truncate the line before it.
check("a trailing // does not cut the code before it", True,
      "SendRequestAsync(" in _cp.code_only('    Do ..SendRequestAsync("x")  // reply handled below\n'))

print("\n#180  CR-6 fires on the wiring, and stays quiet when nothing is wired")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

for _label, _src, _want in [
    # POSITIVE: the exact #180 sequence — a router built for a RecordMap flow, later given
    # an HL7 input. Both items are individually fine; the pairing is the violation.
    ("hl7 BS -> generic router", prod(_ITEMS["recmap_bs"], _ITEMS["hl7_bs"].format(tgt="Router.Main"),
                                      _ITEMS["generic"]), True),
    # POSITIVE: the router is not the first target listed.
    ("generic router 2nd in list", prod(_ITEMS["hl7_bs"].format(tgt="BO.AdtOut,Router.Main"),
                                        _ITEMS["hl7_bo"], _ITEMS["generic"]), True),
    # NEGATIVE: same wiring, correct engine. Proves the check reads ClassName, not "is there HL7".
    ("hl7 BS -> HL7 router", prod(_ITEMS["hl7_bs"].format(tgt="Router.Main"),
                                  _ITEMS["hl7_router"]), False),
    # NEGATIVE: both present, NOT wired together. The naive grep's false positive.
    ("hl7 flow + generic router, unwired", prod(_ITEMS["hl7_bs"].format(tgt="BO.AdtOut"),
                                                _ITEMS["hl7_bo"], _ITEMS["recmap_bs"],
                                                _ITEMS["generic"]), False),
    # NEGATIVE: no generic router anywhere.
    ("no generic router", prod(_ITEMS["hl7_bs"].format(tgt="Router.Main"), _ITEMS["hl7_router"]), False),
    # NEGATIVE: an ordinary class is not a production.
    ("plain class", "Class Demo.MSG.X Extends (%Persistent, Ens.Request)\n{\n}", False),
]:
    check(_label, _want, _cp.cr6_generic_router_hosting_hl7(_src))

# A parser bug must never break a Write. main() swallows exceptions from a structural check;
# assert the contract the swallow depends on -- the function returns a bool, never raises.
check("malformed XML does not raise", True,
      isinstance(_cp.cr6_generic_router_hosting_hl7('<Item Name="a" ClassName='), bool))
# #181  The drift guard: presence is not agreement.
#
# src_before_iris asks "does a file exist for this class". A put whose inline content
# DIFFERS from that file passes it, and the namespace quietly moves ahead of the tree.
# Tests run against the namespace, so the loop stays green and nothing signals the drift
# until a much later conformance byte-compare.
#
# The controls that matter are the silent ones. This guard speaks on every iris_doc(put)
# and every mutating iris_production_item, which is a high-traffic path -- a guard that
# also fired on matching content, on a get, or on a put that the SIBLING GATE had just
# denied would be noise, and noise gets hooks disabled. The blocked-put case is the
# sharpest: warning there would punish the session for respecting src_before_iris, which
# is the same inversion #157 fixed in the stop gate.
DRIFT = os.path.join(ROOT, "hooks", "src_drift_guard.py")

_CLS = "Demo.MSG.PatientReq"
_SRC_V1 = "Class Demo.MSG.PatientReq Extends (%Persistent, Ens.Request)\n{\nProperty Id As %String;\n}"
_SRC_V2 = _SRC_V1.replace("Property Id As %String;",
                          "Property Id As %String;\nProperty Nombre As %String;")
_OK_RESULT = {"open_uri": "isfs://x/Demo/MSG/PatientReq.cls", "storage_stripped": False}
_DENY_TEXT = ("[IIS-SRC-DISK] Source-of-truth: `Demo.MSG.PatientReq` would exist only in the "
              "IRIS namespace.")


def drift_out(payload, cwd):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=cwd)
    p = subprocess.run([sys.executable, DRIFT], input=json.dumps(payload),
                       capture_output=True, text=True, env=env)
    if p.returncode != 0 or p.stderr.strip():
        return "CRASH: " + (p.stderr.strip().splitlines()[-1][:120] if p.stderr.strip() else "rc")
    return "WARN" if p.stdout.strip() else "SILENT"


def doc_post(mode, content, result, name=_CLS + ".cls"):
    ti = {"mode": mode, "name": name}
    if content is not None:
        ti["content"] = content
    return {"tool_name": "mcp__iris__iris_doc", "tool_input": ti, "tool_response": result}


print("\n#181  drift guard warns on divergence, and ONLY on divergence")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

_tmp = tempfile.mkdtemp(prefix="iis181-")
_f = os.path.join(_tmp, "src", "Demo", "MSG", "PatientReq.cls")
os.makedirs(os.path.dirname(_f))
io.open(_f, "w", encoding="utf-8").write(_SRC_V1)

for _label, _payload, _want in [
    # POSITIVE: the #181 case -- authored inline, disk still holds the older version.
    ("put differs from disk",        doc_post("put", _SRC_V2, _OK_RESULT),            "WARN"),
    # NEGATIVE: Write-then-put was followed. The whole point is that this stays quiet.
    ("put matches disk",             doc_post("put", _SRC_V1, _OK_RESULT),            "SILENT"),
    # NEGATIVE: whitespace is not drift -- CRLF and a missing final newline are editor noise.
    ("put differs only by CRLF/EOF", doc_post("put", _SRC_V1.replace("\n", "\r\n") + "\n\n",
                                              _OK_RESULT),                            "SILENT"),
    # NEGATIVE: the sibling gate denied this put. Nothing reached IRIS, so nothing drifted --
    # warning here would punish correct behaviour (#157's inversion).
    ("put blocked by src_before_iris", doc_post("put", _SRC_V2,
                                                {"is_error": True, "content": _DENY_TEXT}), "SILENT"),
    # NEGATIVE: a failed compile still STORES the document, so that one is real drift (#157 case C).
    ("put stored but compile failed", doc_post("put", _SRC_V2,
                                               {"is_error": True,
                                                "content": json.dumps({"compile_errors": ["#5373"]})}),
                                                                                       "WARN"),
    # NEGATIVE: get is the FIX direction, not the problem.
    ("mode=get",                     doc_post("get", None, _OK_RESULT),               "SILENT"),
    # NEGATIVE: no file on disk at all is src_before_iris's job, not this one.
    ("class not on disk",            doc_post("put", _SRC_V2, _OK_RESULT,
                                              name="Demo.MSG.Absent.cls"),            "SILENT"),
    # NEGATIVE: generated artefacts are exported after generation, so disk legitimately lags.
    ("generated .Record",            doc_post("put", _SRC_V2, _OK_RESULT,
                                              name="Demo.RecordMap.X.Record.cls"),    "SILENT"),
]:
    check(_label, _want, drift_out(_payload, _tmp))

# iris_production_item never writes a .cls, so NO gate sees it -- the second half of #181.
for _label, _action, _want in [
    ("production_item add",          "add",          "WARN"),
    ("production_item set_settings", "set_settings", "WARN"),
    ("production_item get_settings", "get_settings", "SILENT"),
]:
    check(_label, _want, drift_out(
        {"tool_name": "mcp__iris__iris_production_item",
         "tool_input": {"action": _action, "item": "BS.In", "production": "Demo.Production"},
         "tool_response": {"ok": True}}, _tmp))

# The marker must reach the emitted text, not merely exist in the source (the lesson the
# #162 section below records): a guard whose marker never ships is undetectable downstream.
_emitted_drift = subprocess.run(
    [sys.executable, DRIFT], input=json.dumps(doc_post("put", _SRC_V2, _OK_RESULT)),
    capture_output=True, text=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=_tmp))
check("marker reaches the output", True,
      json.loads(_emitted_drift.stdout)["hookSpecificOutput"]["additionalContext"]
      .startswith("[IIS-DRIFT] "))

# --------------------------------------------------------------------------------------
# #221  IIS-CG-NAME must not fire on InterSystems' own packages, and must not fire on a READ.
#
# 4 of 4 observed denials were false positives: iris_doc(mode=get) of
# EnsLib.HL7.Service.FileService, whose middle segments are ['HL7', 'Service']. Those names
# are not ours to rename, the plugin's own skills send the model to them BY NAME, and reading
# a superclass is the documented introspection path.
#
# The mode filter is the subtle half. It is written as "skip only when mode is PRESENT and is
# not put" rather than "mode == put", because iris_compile sits in the same matcher and carries
# NO mode key: `mode == "put"` would silently switch this rule off on the one other path a
# badly named class can land on. The last two cases are that control.
print("\n#221  interop_conformance_gate — NAME is scoped to classes the model authors")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

def _named(name, **extra):
    return {"tool_name": "mcp__iris__iris_doc", "tool_input": dict({"name": name}, **extra)}

for _label, _want, _payload in [
        ("EnsLib read (was 4/4 false positive)", "ALLOW",
         _named("EnsLib.HL7.Service.FileService.cls", mode="get")),
        ("EnsLib put — still not ours to rename", "ALLOW",
         _named("EnsLib.RecordMap.Service.FileService.cls", mode="put")),
        ("Ens.* and %Library.* exempt too", "ALLOW",
         _named("%Library.SQLConnection.cls", mode="get")),
        ("authored .Service. put — POSITIVE CONTROL", "DENY",
         _named("Pkg.Service.Census.cls", mode="put")),
        ("authored .Service. read is not authoring", "ALLOW",
         _named("Pkg.Service.Census.cls", mode="get")),
        ("iris_compile has NO mode — must still deny", "DENY",
         {"tool_name": "mcp__iris__iris_compile",
          "tool_input": {"name": "Pkg.Service.Census.cls"}}),
]:
    check(_label, _want, run_hook(GATE, _payload))


# --------------------------------------------------------------------------------------
# #219  IIS-CG-UNDERSCORE. `_` is the concatenation operator; the compiler blames the braces.
#
# The exemptions are what keep this from being a noisy deny: a delimited member name is legal
# (GOBJ 2.6.3), and an XData body carries underscores as DATA — an HL7 schema's ADT_A01, a
# <Setting Name="Foo_Bar">. The last two cases are the false positives this rule would cause
# without mask_xdata and the quote check.
print("\n#219  interop_conformance_gate — underscore in an identifier")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

_UND_CLS = "Class Pkg.DT.ADT_A01ToMenuReq Extends Ens.DataTransformDTL\n{\n}"
_UND_MEM = ("Class Pkg.Tests.BS.In Extends %UnitTest.TestProduction\n{\n"
            'Parameter IN_DIR = "/data/IN/";\n}')
_UND_OK = ("Class Pkg.Tests.BS.In Extends %UnitTest.TestProduction\n{\n"
           'Parameter InDir = "/data/IN/";\n}')
_UND_DELIM = ("Class Pkg.MSG.Row Extends (%Persistent, Ens.Request)\n{\n"
              'Property "My_Property" As %String;\n}')
# NOTE ON SCOPE: an XML XData body cannot trip this rule anyway — every line starts with '<'
# and UNDERSCORE_MEMBER is anchored to a line STARTING with a member keyword. So the XML case
# below is a control, not a demonstration that masking is required. The keyword-initial case
# after it is the one mask_xdata actually earns its place on; drop the masking and it denies.
_UND_XDATA = ("""Class Pkg.HL7.Custom Extends %RegisteredObject\n{\n"""
              """XData Schema\n{\n"""
              """<Category name='Cust' base='2.5'>\n"""
              """  <MessageStructure name='ADT_A01' definition='2.5:MSH~[~ZDI~]'/>\n"""
              """  <MessageType name='ADT_A01' structure='ADT_A01'/>\n"""
              """</Category>\n}\n}""")
_UND_XDATA_KW = ("Class Pkg.UTL.Notes Extends %RegisteredObject\n{\n"
                 "XData Doc\n{\n"
                 "Method GetFoo_Bar() was renamed in 2026.1\n"
                 "Parameter OLD_NAME is no longer read\n"
                 "}\n}")

for _label, _want, _payload in [
        ("class name carries _  (the #5559 case)", "DENY", doc("Pkg.DT.X.cls", _UND_CLS)),
        ("Parameter IN_DIR", "DENY", doc("Pkg.Tests.BS.In.cls", _UND_MEM)),
        ("the fixing rewrite", "ALLOW", doc("Pkg.Tests.BS.In.cls", _UND_OK)),
        ("delimited member name is LEGAL", "ALLOW", doc("Pkg.MSG.Row.cls", _UND_DELIM)),
        ("ADT_A01 inside XData is DATA", "ALLOW", doc("Pkg.HL7.Custom.cls", _UND_XDATA)),
        ("keyword-initial line in XData is DATA", "ALLOW",
         doc("Pkg.UTL.Notes.cls", _UND_XDATA_KW)),
        ("a READ is never gated on content", "ALLOW",
         doc("Pkg.DT.X.cls", _UND_CLS, mode="get")),
]:
    check(_label, _want, run_hook(GATE, _payload))

# The Write leg (#219) — and the constraint that keeps it from denying edits to this plugin's
# OWN documentation. Every build skill here carries `Class … Extends EnsLib.…Adapter` and
# ADT_A01 inside fenced examples; without the .cls path check a Write of a SKILL.md is a deny.
print("\n#219  the Write|Edit leg is scoped to .cls paths")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))
for _label, _want, _payload in [
        ("Write of a .cls with _  — must deny", "DENY",
         {"tool_name": "Write",
          "tool_input": {"file_path": "/w/src/Pkg/DT/X.cls", "content": _UND_CLS}}),
        ("Write of a SKILL.md quoting it — ALLOW", "ALLOW",
         {"tool_name": "Write",
          "tool_input": {"file_path": "/w/skills/x/SKILL.md",
                         "content": "Example:\n```\n" + _UND_CLS + "\n```\n"}}),
        ("Edit new_string on a .cls", "DENY",
         {"tool_name": "Edit",
          "tool_input": {"file_path": "/w/src/Pkg/DT/X.cls", "new_string": _UND_CLS}}),
        ("Write of a plain .md is untouched", "ALLOW",
         {"tool_name": "Write",
          "tool_input": {"file_path": "/w/README.md", "content": _UND_CLS}}),
]:
    check(_label, _want, run_hook(GATE, _payload))


# --------------------------------------------------------------------------------------
# #212  IIS-CG-INTROSPECT is an ADVISORY. A deny here would block CleanProduction(), the
# documented remedy for a stuck production — so the lifecycle control is the load-bearing case.
print("\n#212  hand-rolled introspection gets an advisory, never a deny")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

def _exec_out(code):
    """ADVISE / DENY / ALLOW — an advisory and a deny are both stdout, so read the payload."""
    p = subprocess.run([sys.executable, GATE],
                       input=json.dumps({"tool_name": "mcp__iris__iris_execute",
                                         "tool_input": {"code": code, "namespace": "NS"}}),
                       capture_output=True, text=True)
    if p.returncode != 0 or p.stderr.strip():
        return "CRASH"
    if not p.stdout.strip():
        return "ALLOW"
    out = json.loads(p.stdout)["hookSpecificOutput"]
    return "DENY" if out.get("permissionDecision") == "deny" else "ADVISE"

for _label, _want, _code in [
        ("GetProductionStatus", "ADVISE",
         "Set tSC=##class(Ens.Director).GetProductionStatus(.n,.s)"),
        ("GetHostInstance", "ADVISE", '##class(Ens.Director).GetHostInstance("BO.Send")'),
        ("EnsPortal.* is not an API", "ADVISE",
         '##class(EnsPortal.Utils).GetProductionStatus(.st)'),
        ("CleanProduction alone", "ALLOW",
         "Do ##class(Ens.Director).CleanProduction()"),
        ("StopProduction alone", "ALLOW",
         "Do ##class(Ens.Director).StopProduction(30,1)"),
        # The load-bearing one. Both in a single snippet is how the recovery ladder's remedy is
        # actually typed: check the status, then clean. Without LIFECYCLE_OK this advises on the
        # documented fix for a stuck production.
        ("status + CleanProduction together", "ALLOW",
         "Set s=##class(Ens.Director).GetProductionStatus(.n,.st)\n"
         "Do ##class(Ens.Director).CleanProduction()"),
        ("a real violation still DENIES first", "DENY",
         'Do $SYSTEM.OBJ.Load("/tmp/x.xml","ck")'),
]:
    check(_label, _want, _exec_out(_code))


# --------------------------------------------------------------------------------------
# #210  The stop gate's latch is keyed on the unresolved CONDITION, not on the body of work.
# Keyed on the body of work, writing one more class changed the key and the gate re-blocked
# for the same problem — one interruption per workbook step. And a get answering NOT_FOUND
# cancels the put, which is the evidence the CR-12 message itself asks the model to produce.
print("\n#210  stop-gate latch is per-condition, and NOT_FOUND cancels a put")
print("  {:<38}{:<16}{:<16}{}".format("case", "want", "got", ""))

check("latch stores per key, not one slot", True,
      (lambda t: (g.latch_record(t, "CR12_claimed", ["A"]),
                  g.latch_record(t, "REVIEW", g.REVIEW_SENTINEL),
                  g.latch_seen(t, "CR12_claimed", ["A"]) and
                  g.latch_seen(t, "REVIEW", g.REVIEW_SENTINEL))[-1])(
          os.path.join(tempfile.mkdtemp(), "t.jsonl")))

check("a different value is NOT latched", False,
      (lambda t: (g.latch_record(t, "CR12_claimed", ["A"]),
                  g.latch_seen(t, "CR12_claimed", ["A", "B"]))[-1])(
          os.path.join(tempfile.mkdtemp(), "t.jsonl")))

def _blk(payload, is_error=True):
    return {"is_error": is_error,
            "content": [{"type": "text", "text": json.dumps(payload)}]}

for _label, _want, _block in [
        ("NOT_FOUND is proof of absence", True,
         _blk({"success": False, "error_code": "NOT_FOUND", "error": "no such doc"})),
        ("NAMESPACE_NOT_FOUND is NOT", False,
         _blk({"success": False, "error_code": "NAMESPACE_NOT_FOUND"})),
        ("ATELIER_NOT_FOUND is NOT", False,
         _blk({"success": False, "error_code": "ATELIER_NOT_FOUND"})),
        ("a successful get is not absence", False,
         _blk({"success": True, "content": "Class X {}"}, is_error=False)),
        ("prose, not JSON, is not absence", False,
         {"is_error": True, "content": [{"type": "text", "text": "boom"}]}),
]:
    check(_label, _want, g.get_says_absent(_block))


# --------------------------------------------------------------------------- #240
# tdd_first_green.py gained an advisory red-streak counter. Two behaviours matter and neither is
# visible from reading the file: the advisory must fire ONCE at the third consecutive red (not every
# red after it), and a green that FOLLOWED reds must no longer be reported as a first-run green --
# that was a false positive on the exact flow the hook exists to encourage, found by testing the
# counter rather than by reading the code.
import tempfile as _tf, shutil as _sh

_FG = os.path.join(ROOT, "hooks", "tdd_first_green.py")


def _fg(project_dir, green, target="My.Tests.X"):
    """Run the hook and return its marker, or 'silent'."""
    if green is None:
        resp = "not json at all"
    else:
        resp = {"outcome": "passed" if green else "failed", "success": bool(green)}
    payload = {"tool_name": "iris_test", "tool_input": {"pattern": target}, "tool_response": resp}
    pr = subprocess.run([sys.executable, _FG], input=json.dumps(payload), capture_output=True,
                        text=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=project_dir))
    if pr.returncode != 0 or pr.stderr.strip():
        return "CRASH"
    if not pr.stdout.strip():
        return "silent"
    try:
        ctx = json.loads(pr.stdout)["hookSpecificOutput"]["additionalContext"]
    except Exception:
        return "UNPARSEABLE"
    return ctx.split("]")[0] + "]"


print("\n#240 tdd_first_green red-streak counter")
_d = _tf.mkdtemp()
try:
    check("red 1 is silent", "silent", _fg(_d, False))
    check("red 2 is silent", "silent", _fg(_d, False))
    check("red 3 advises", "[IIS-TDD-REDLOOP]", _fg(_d, False))
    check("red 4 does not repeat", "silent", _fg(_d, False))
    check("green after reds is silent", "silent", _fg(_d, True))
    check("streak resets after green", "silent", _fg(_d, False))
    _fg(_d, False)
    check("third red advises again", "[IIS-TDD-REDLOOP]", _fg(_d, False))
finally:
    _sh.rmtree(_d, ignore_errors=True)

_d = _tf.mkdtemp()
try:
    # The detector this hook was written for must still fire: a green with NO prior red.
    check("genuine first-run green fires", "[IIS-TDD-GREEN]", _fg(_d, True, "My.Tests.Fresh"))
finally:
    _sh.rmtree(_d, ignore_errors=True)

_d = _tf.mkdtemp()
try:
    # An unparseable response must not manufacture a streak -- a schema change would otherwise
    # look like three failing runs.
    _fg(_d, None); _fg(_d, None)
    check("unparseable never advises", "silent", _fg(_d, None))
finally:
    _sh.rmtree(_d, ignore_errors=True)


# --------------------------------------------------------------------------- #243
# interop_route.py had NO tests. Three things are asserted, because the router's failures are all
# silent: a prompt that routes to nothing looks the same as a prompt with no interop content.
_ROUTE = os.path.join(ROOT, "hooks", "interop_route.py")


def _route(prompt):
    """The skills this prompt routes to, in order, or 'NOTHING'."""
    pr = subprocess.run([sys.executable, _ROUTE], input=json.dumps({"prompt": prompt}),
                        capture_output=True, text=True)
    if pr.returncode != 0 or pr.stderr.strip():
        return "CRASH"
    if not pr.stdout.strip():
        return "NOTHING"
    try:
        ctx = json.loads(pr.stdout)["hookSpecificOutput"]["additionalContext"]
    except Exception:
        return "UNPARSEABLE"
    return ",".join(_re.findall(r"iris-interop-skills:([a-z-]+)", ctx))


print("\n#243 interop_route coverage")

# (a) every topic name must be a real skill, or it can never route no matter what matches.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("_ir", _ROUTE)
_ir = _ilu.module_from_spec(_spec); _spec.loader.exec_module(_ir)
_missing = [n for n, _ in _ir.TOPICS
            if not os.path.isdir(os.path.join(ROOT, "skills", n))]
check("every topic is a real skill", "[]", str(_missing))

# (b) the routes this issue was filed about. Each was measured before the fix:
#     "Comprueba ..." routed to tdd (via the unanchored `prueba` inside `comprueba`) and a SOAP
#     prompt routed to nothing at all, because there was no soap-bo entry.
for _label, _prompt, _want in [
        ("verification prompt routes", "Comprueba que ha funcionado el envio", "message-search-debug"),
        ("SOAP prompt reaches soap-bo", "genera el cliente SOAP desde el WSDL", "soap-bo"),
        ("EN verification routes", "did it arrive? check the visual trace and the event log", "message-search-debug"),
        ("a real test prompt still routes to tdd", "escribe un test con %UnitTest", "tdd"),
        ("PKCE routes to security", "configura OAuth con PKCE", "security"),
]:
    check(_label, True, _want in _route(_prompt).split(","))

# (b2) and the OTHER half of that fix, which (b) does not detect on its own: `prueba` was
#      unanchored, so "Comprueba" matched it and a verification prompt was routed to tdd. Asserting
#      only that message-search-debug appears passes even with the old pattern, because both matched.
#      This asserts the absence, which is the only thing the anchor changed.
check("comprueba does not route to tdd", False,
      "tdd" in _route("Comprueba que ha funcionado el envio").split(","))

# (c) ranking, not declaration order, decides which topics survive MAX. message-search-debug is
#     declared 10th; a prompt that matches it three times must outrank a single incidental match on
#     an earlier topic. Without this, widening a late pattern is inert -- which is why fixes 2 and 5
#     of #243 had to land together.
_ranked = _route("visual trace, event log and message viewer for the production").split(",")
check("rank beats declaration order", True,
      bool(_ranked) and _ranked[0] == "message-search-debug")

# (d) a prompt with no interop content must stay silent rather than guess.
check("no interop content is silent", "NOTHING", _route("what is the weather like today"))


# --------------------------------------------------------------------------------------
print("\n#336  the iris_execute rules read CODE, not comments")
print("  {:<52}{:<10}{:<10}{}".format("case", "want", "got", ""))

# Reported with a positive control, and reproduced exactly: the same trivial `write` was ALLOWED
# on its own and DENIED with `// This comment mentions $SYSTEM.OBJ.Compile` above it. The gate's
# own docstring says it "denies only high-confidence violations (no false positives on ordinary
# code)", and this was a false positive on ordinary code.
#
# The incentive is what makes it worth fixing rather than working around: renaming the API in the
# comment makes the call pass, so the workaround is to write a LESS accurate comment — a gate for
# code quality pushing toward code that explains itself worse. It cost a real round trip.
#
# THE ALLOW DIRECTION IS THE LOAD-BEARING HALF, as the issue points out: every deny row below
# already passed before the fix. A single-direction suite would have shipped this bug.
#
# COVERAGE: this exercises the four iris_execute rules through the hook. It says nothing about
# the name/adapter/namespace rules above them, which never read the `code` string.

def _exec_verdict(code):
    """DENY / ADVISE / ALLOW for an iris_execute call — the three outcomes are distinct.

    run_hook() collapses to DENY on any stdout, and rule (3d) writes stdout to ADVISE. Scoring an
    advisory as a deny would make the (3d) rows below meaningless.
    """
    p = subprocess.run(
        [sys.executable, GATE],
        input=json.dumps({"tool_name": "mcp__iris-interop-dev__iris_execute",
                          "tool_input": {"code": code, "namespace": "FHIRTEST"}}),
        capture_output=True, text=True)
    if p.returncode != 0 or p.stderr.strip():
        return "CRASH: " + (p.stderr.strip().splitlines()[-1][:80] if p.stderr.strip() else "rc")
    if not p.stdout.strip():
        return "ALLOW"
    h = json.loads(p.stdout)
    h = h.get("hookSpecificOutput") or h
    return "DENY" if "permissionDecisionReason" in h else "ADVISE"

_W = 'write "X",!'

for _label, _code, _want in [
    # The issue's own pair, verbatim in substance.
    ("issue control: no forbidden name anywhere", 'write "CONTROL_OK ",$ZVERSION,!', "ALLOW"),
    ("issue case: the name only in a // comment",
     '// This comment mentions $SYSTEM.OBJ.Compile and nothing else does.\n' + _W, "ALLOW"),
    # Every ObjectScript comment form, since the reported one is only the first.
    ("a trailing // comment on a code line", _W + '  // avoid $SYSTEM.OBJ.Compile here', "ALLOW"),
    ("a ; comment (the classic form)", '; we do not use $SYSTEM.OBJ.Load\n' + _W, "ALLOW"),
    ("a #; preprocessor comment", '#; $SYSTEM.OBJ.Import is banned\n' + _W, "ALLOW"),
    ("a /* */ block spanning lines",
     '/* $SYSTEM.OBJ.Compile\n   is what we avoid */\n' + _W, "ALLOW"),
    # ...and the sibling rules the issue did not name, which had the same defect.
    ("(3b) a comment naming ^oddDEF", '// never Set ^oddDEF directly\n' + _W, "ALLOW"),
    ("(3b) a comment naming TextServices.SetText",
     '// not %Compiler.UDL.TextServices.SetTextFromStream\n' + _W, "ALLOW"),

    # ---- the deny direction must be untouched ----
    ("$SYSTEM.OBJ.Compile, for real", 'Do $SYSTEM.OBJ.Compile("Demo.BO.X","ck")', "DENY"),
    ("##class(%SYSTEM.OBJ).Load, for real",
     'Do ##class(%SYSTEM.OBJ).Load("/tmp/x.cls","ck")', "DENY"),
    ("TextServices.SetTextFromStream, for real",
     'Do ##class(%Compiler.UDL.TextServices).SetTextFromStream("USER","A.B",s)', "DENY"),
    ("Set ^oddDEF, for real", 'Set ^oddDEF("A.B",1)=1', "DENY"),
    ("a real call on the line AFTER a comment",
     '// a harmless note\nDo $SYSTEM.OBJ.Compile("Demo.X","ck")', "DENY"),

    # THE HAZARD THE NAIVE FIX CREATES. Cutting each line at the first `//` truncates
    # "http://example.org" and would hide the real call after it — turning this false positive
    # into a false NEGATIVE in a deny gate, which is the worse trade. Same for `;` in a string.
    ("a real call after a URL inside a string",
     'Set u="http://example.org/a" Do $SYSTEM.OBJ.Compile("Demo.X","ck")', "DENY"),
    ("a real call after a ; inside a string",
     'Set d=$Piece(x,";",1) Do $SYSTEM.OBJ.Load("/tmp/y.cls")', "DENY"),
    ("a real call after an escaped quote in a string",
     'Set q="a""b" Do $SYSTEM.OBJ.Compile("Demo.X","ck")', "DENY"),
]:
    check(_label, _want, _exec_verdict(_code))

# (3d) runs the other way: a comment could buy an EXEMPTION from the advisory. Narrower than it
# looks, and measured rather than assumed — LIFECYCLE_OK needs the DOTTED form, so a bare mention
# never exempted anything. The first draft of this claim said it did; a removal test said no.
import interop_conformance_gate as _cg  # noqa: E402

_dotted = ('// do NOT use ##class(Ens.Director).CleanProduction() here\n'
           'Set x=##class(Ens.Director).GetProductionStatus(.p,.s)')
_bare = ('// unlike CleanProduction, this only reads\n'
         'Set x=##class(Ens.Director).GetProductionStatus(.p,.s)')
check("a comment with the dotted form no longer exempts", False,
      bool(_cg.LIFECYCLE_OK.search(_cg.strip_comments(_dotted))))
check("...and it DID exempt before stripping (control)", True,
      bool(_cg.LIFECYCLE_OK.search(_dotted)))
check("a bare mention never exempted either way", False,
      bool(_cg.LIFECYCLE_OK.search(_bare)))
# The exemption must survive for a REAL lifecycle call, or (3d) becomes noise on the documented
# remedy it exists to permit.
check("a real CleanProduction call is still exempt", True,
      bool(_cg.LIFECYCLE_OK.search(_cg.strip_comments('Do ##class(Ens.Director).CleanProduction()'))))
check("(3d) still advises on a real hand-rolled probe", "ADVISE",
      _exec_verdict('Set x=##class(Ens.Director).GetProductionStatus(.p,.s)'))

# The stripper masks with SPACES and keeps newlines: CLASS_WRITE_BYPASS anchors on `(?:^|[\s:])`
# and none of these patterns use re.M, so deleting text could join tokens across a removed
# comment and change what the anchors see.
check("masking preserves length", True,
      len(_cg.strip_comments(_W + "  // x")) == len(_W + "  // x"))
check("masking preserves newlines", 3,
      _cg.strip_comments("// a\n/* b\n c */\n").count("\n"))
check("a string containing // is untouched", True,
      "http://example.org" in _cg.strip_comments('Set u="http://example.org"'))


print("\n{} failure(s)".format(len(failures)))
for f in failures:
    print("  FAILED:", f)
sys.exit(1 if failures else 0)
