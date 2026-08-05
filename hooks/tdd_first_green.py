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

LEDGER = ".claude/.iris-interop-tdd-seen"


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

    raw = data.get("tool_response", data.get("tool_result", ""))
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except Exception:
            raw = {}
    green = outcome_is_green(raw)
    if green is not True:
        return  # red, or unparseable — nothing to say; red is what we want

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
        "hookEventName": "PostToolUse", "additionalContext": msg}}))


if __name__ == "__main__":
    main()
