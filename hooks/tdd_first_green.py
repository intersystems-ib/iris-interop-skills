#!/usr/bin/env python3
"""PostToolUse detector for test-after-code (iris-interop-skills).

TDD's invariant is not "there is a test" — it is "the test failed before the code made it
pass". A test class whose FIRST EVER run is green was written against code that already
existed, so its assertions describe current behaviour instead of the specification. That is
the mechanism behind shallow tests, and it is invisible to any count of assertions.

Measured over a workshop cohort: 67 of 103 test classes (65%) were green on their first
run, while assertion density was healthy (5.3 Test* methods per class, 2.8 asserts each).
Prescribing "more assertions" would have missed the problem entirely.

Keeps a per-project ledger of which test classes have already run, so "first" means first
in the project, not first in the session. Advisory only; never blocks.
"""
import sys, json, os, re, hashlib

# Stable marker (#162): prepended, never woven into the prose, so a reword cannot
# switch a corpus detector off. One grep for `[IIS-` finds every gate and guard.
MARKER = "[IIS-TDD-GREEN] "

# A DISTINCT marker (#240): the two messages describe opposite failures -- a test that was never
# red, and a test that has stayed red -- so a corpus that cannot tell them apart cannot measure
# either. One grep for `[IIS-` still finds both.
MARKER_RED = "[IIS-TDD-REDLOOP] "

LEDGER = ".claude/.iris-interop-tdd-seen"
REDS = ".claude/.iris-interop-tdd-reds"

# Advisory at the third consecutive red, never blocking. Measured over a workshop cohort: of the 6
# red streaks of >=3 in 120 steps, FIVE went green with no intervention -- so a gate that blocked
# here would abort five runs that were about to succeed. The value is in naming the streak and
# pointing at the failing assertion, not in stopping the loop.
RED_STREAK = 3


def ledger_path():
    proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    return os.path.join(proj, LEDGER)


def seen(key):
    """True if this test class has run before; records it either way."""
    p = ledger_path()
    tag = hashlib.sha1(key.encode("utf-8", "replace")).hexdigest()[:16]
    try:
        if os.path.isfile(p):
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                if tag in f.read().split():
                    return True
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a", encoding="utf-8") as f:
            f.write(tag + "\n")
    except Exception:
        return True  # never nag on a ledger problem
    return False


def reds_path():
    proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    return os.path.join(proj, REDS)


def _reds_read():
    try:
        with open(reds_path(), "r", encoding="utf-8", errors="replace") as f:
            out = {}
            for line in f:
                bits = line.split()
                if len(bits) == 2 and bits[1].isdigit():
                    out[bits[0]] = int(bits[1])
            return out
    except Exception:
        return {}


def _reds_write(d):
    try:
        p = reds_path()
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            for k, v in sorted(d.items()):
                f.write(k + " " + str(v) + "\n")
    except Exception:
        pass  # a ledger problem must never nag and never crash the hook


def bump_red(key):
    """Count this consecutive red for `key` and return the new total."""
    tag = hashlib.sha1(key.encode("utf-8", "replace")).hexdigest()[:16]
    d = _reds_read()
    d[tag] = d.get(tag, 0) + 1
    _reds_write(d)
    return d[tag]


def clear_red(key):
    """End the streak. Returns the count that was cleared, so a caller can tell whether this green
    followed a red -- which is the difference between the correct TDD cycle and a first-run green."""
    tag = hashlib.sha1(key.encode("utf-8", "replace")).hexdigest()[:16]
    d = _reds_read()
    n = d.pop(tag, 0)
    if n:
        _reds_write(d)
    return n


def outcome_is_green(payload):
    if not isinstance(payload, dict):
        return None
    if "outcome" in payload:
        return payload.get("outcome") == "passed" or bool(payload.get("success"))
    if "success" in payload:
        return bool(payload["success"])
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    ti = data.get("tool_input", {}) or {}
    target = ti.get("pattern") or ti.get("class") or ti.get("target") or ""
    if not isinstance(target, str) or not target.strip():
        return

    # NOTE (#125): this reads the tool RESPONSE, so it never sees a call the client rejected
    # locally on schema grounds. MCP 0.11.0 added `required` entries to tools that previously
    # declared no schema, so incomplete calls that used to travel and fail at the server can now
    # be refused client-side, producing no tool_response and no PostToolUse event at all. This
    # hook does not break; its denominator quietly loses those calls. Do not compare rates
    # across that pin boundary without accounting for it.
    raw = data.get("tool_response", data.get("tool_result", ""))
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except Exception:
            raw = {}
    green = outcome_is_green(raw)

    if green is False:
        # A red is what TDD wants -- once. A THIRD consecutive red on the same target means the
        # last two edits taught nothing, and the usual cause is editing without having read the
        # assertion that failed. Unparseable responses (green is None) are deliberately NOT counted:
        # they would manufacture a streak out of a schema change.
        n = bump_red(target.strip())
        if n == RED_STREAK:
            msg = (
                "`" + target.strip() + "` has now failed " + str(n) + " times in a row. Before "
                "editing anything else, READ THE FAILING ASSERTION: `iris_get_log(log_id=...)` and "
                "the run's `failure_message` name the assert and the values it compared. Two edits "
                "that did not change the failure mean the hypothesis is wrong, not that the fix was "
                "too small. If the third red tells you nothing new, stop and report the blocker -- "
                "the class, the assertion, and what you have ruled out -- rather than trying a "
                "fourth variation. One specific check first: a test still red right after "
                "`iris_compile` may be running the OLD code, because a running host job does not "
                "reload on compile; recycle that item with "
                "`iris_production(action=restart, item=\"<Item>\")`. "
                "See iris-interop-skills:tdd, 'Loop budget - stop at the third red'."
            )
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": MARKER_RED + msg}}))
        return

    if green is not True:
        return  # unparseable -- say nothing rather than guess

    # A green ends the streak -- and if there WAS a streak, this green is the correct TDD cycle
    # (red -> implement -> green), not a first-run green. Before the red ledger existed this hook
    # could not tell the two apart: `seen()` is written only on the green path, so a class that went
    # red three times and then green was reported as "passed on its FIRST run" -- the hook nagging at
    # precisely the flow it exists to encourage. Found by testing the counter added for #240.
    had_red = clear_red(target.strip())
    if had_red:
        return

    if seen(target.strip()):
        return  # ran before; a later green is just the normal cycle

    msg = (
        "TDD check: `" + target.strip() + "` passed on its FIRST run. In spec -> test -> RED "
        "-> implement -> green, the first run is red — a test that is green immediately was "
        "written against code that already existed, so it encodes current behaviour rather "
        "than the specification. Before calling this component done, add at least one case "
        "that FAILS against the implementation as it stands right now: a rejected input for "
        "each validation rule in the spec, the boundary values, and the malformed-input "
        "fixtures. If nothing you can write fails, the test is not yet testing the spec. "
        "See iris-interop-skills:tdd, 'How much test is enough'."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": MARKER + msg}}))


if __name__ == "__main__":
    main()
