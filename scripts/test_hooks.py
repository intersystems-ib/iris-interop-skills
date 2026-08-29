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
import json, os, subprocess, sys, tempfile, time

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

print("\n{} failure(s)".format(len(failures)))
for f in failures:
    print("  FAILED:", f)
sys.exit(1 if failures else 0)
