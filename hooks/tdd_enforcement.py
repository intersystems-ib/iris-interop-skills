#!/usr/bin/env python3
"""PostToolUse TDD guard for Write|Edit and iris_doc (iris-interop-skills).

If an interop implementation class (BS/BP/BO/DT/DTS/RUL, DTL, Rule) is written WITHOUT a
test for it, remind the model to write the test first (spec -> test -> red -> implement ->
green; tests extend %UnitTest.TestProduction). Advisory only; never blocks.

Two things this has to get right, both learned from a workshop cohort where it fired zero
times across 18 students and 567 component classes:

  1. The component detector must accept BOTH shapes of name. The class is `Pkg.BO.Name`
     but the FILE is `src/Pkg/BO/Name.cls` — the `interop` skill mandates the Atelier
     nested layout, so the path carries directory separators, not dots. A detector written
     as `\\.bo\\.` matches only the flat-dotted form that same skill tells you not to use.
  2. It must cover the tools actually used. Classes reach IRIS either as a file
     (Write/Edit) or straight through `iris_doc(mode=put)`; watching only the first misses
     everything written directly to the namespace.
"""
import sys, json, os, re, glob

# Type segment delimited by a dot OR a path separator: matches `Pkg.BO.Name` and
# `src/Pkg/BO/Name.cls` alike. DTS/DT/RUL/BS included — the old pattern had neither
# `dt` nor `rul`, so transforms and rules were invisible even in flat-dotted form.
COMPONENT = re.compile(r"[./\\](?:BS|BP|BO|DT|DTS|RUL)[./\\]|DTL|Rule", re.I)


def component_name(ti):
    """The class or file this call is writing, or '' if it isn't a class write."""
    # iris_doc(mode=put, name="Pkg.BO.Name.cls")
    if ti.get("mode") == "put" and isinstance(ti.get("name"), str):
        return ti["name"]
    path = ti.get("file_path") or ti.get("path") or ""
    return path if str(path).lower().endswith(".cls") else ""


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    ti = data.get("tool_input", {}) or {}
    target = component_name(ti)
    if not target or not COMPONENT.search(target):
        return
    base = os.path.basename(str(target).replace("\\", "/"))
    if "test" in base.lower():  # the test itself — fine
        return

    # A test anywhere in the project counts. Deliberately loose: the goal is to nudge when
    # there is NO test at all, not to police naming.
    roots = []
    d = os.path.dirname(str(target).replace("\\", "/"))
    if d and os.path.isdir(d):
        roots.append(d)
    proj = os.environ.get("CLAUDE_PROJECT_DIR")
    if proj:
        roots.append(proj)
    for r in roots:
        if r and glob.glob(os.path.join(r, "**", "*Test*.cls"), recursive=True):
            return

    msg = (
        "TDD: you just wrote the interop component " + base + " and no *Test*.cls exists "
        "for it. Per iris-interop-skills:tdd the order is spec -> test -> RED -> implement "
        "-> green: write the test first and SEE IT FAIL, so it tests the spec rather than "
        "the code you already wrote. Test classes extend %UnitTest.TestProduction. "
        "A component is not done until iris_test returns green on a test that was red before."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse", "additionalContext": msg}}))


if __name__ == "__main__":
    main()
