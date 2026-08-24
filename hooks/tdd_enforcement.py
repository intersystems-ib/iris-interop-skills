#!/usr/bin/env python3
"""PostToolUse TDD guard for Write|Edit and iris_doc (iris-interop-skills).

If an interop implementation class (BS/BP/BO/DT/DTS/RUL, DTL, Rule) is written WITHOUT a
test for it, remind the model to write the test first (spec -> test -> red -> implement ->
green; tests extend %UnitTest.TestProduction). Advisory only; never blocks.

Three things this has to get right, learned across two evaluation rounds (a cohort where it
fired zero times, then a corpus where every fire was a false positive):

  1. The component detector must accept BOTH shapes of name — the class is `Pkg.BO.Name`
     but the FILE is `src/Pkg/BO/Name.cls` (Atelier nested layout) — and the type must be a
     DELIMITED SEGMENT, never a bare substring. Matching `dtl`/`rule` anywhere in the path
     fired on every class under a directory like `hl7-dtl-mapping/` or `DTL-BUILD-01/`
     while missing real `.DT.` classes entirely.
  2. It must cover the tools actually used. Classes reach IRIS either as a file
     (Write/Edit) or straight through `iris_doc(mode=put)`; watching only the first misses
     everything written directly to the namespace.
  3. "A test exists" must recognise the plugin's OWN documented convention. The tdd skill
     prescribes `MyApp.Tests.DT.Censo2Menus` -> `Tests/DT/Censo2Menus.cls`: the test lives
     in a `Tests` package and its basename carries no "Test" substring. A basename-only
     check nags the test file itself and re-fires forever on already-tested classes.
"""
import sys, json, os, re, glob

# Type segment delimited by a dot OR a path separator on BOTH sides: matches `Pkg.BO.Name`
# and `src/Pkg/BO/Name.cls`, never a substring of a directory name. `DTL`/`Rule` are kept
# as segment-anchored aliases for projects that don't use the Tipo abbreviations.
COMPONENT = re.compile(r"[./\\](?:BS|BP|BO|DT|DTS|RUL|DTL|Rule)[./\\]", re.I)

# The write IS a test: basename contains "test", or the class/file sits in a Test/Tests
# package or directory (the convention `tdd` documents).
TESTS_SEG = re.compile(r"[./\\]Tests?[./\\]", re.I)


def component_name(ti):
    """The class or file this call is writing, or '' if it isn't a class write."""
    # iris_doc(mode=put, name="Pkg.BO.Name.cls")
    if ti.get("mode") == "put" and isinstance(ti.get("name"), str):
        return ti["name"]
    path = ti.get("file_path") or ti.get("path") or ""
    return path if str(path).lower().endswith(".cls") else ""


def has_tests(root):
    """Any test under root: *Test*.cls anywhere, or any .cls inside a Test/Tests dir."""
    if not root:
        return False
    if glob.glob(os.path.join(root, "**", "*Test*.cls"), recursive=True):
        return True
    for d in ("Tests", "Test"):
        if glob.glob(os.path.join(root, "**", d, "**", "*.cls"), recursive=True):
            return True
    return False


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    ti = data.get("tool_input", {}) or {}
    target = component_name(ti)
    if not target:
        return
    norm = str(target).replace("\\", "/")
    if not COMPONENT.search(norm):
        return
    base = os.path.basename(norm)
    if "test" in base.lower() or TESTS_SEG.search(norm):  # the test itself — fine
        return

    # A test anywhere in the project counts. Deliberately loose: the goal is to nudge when
    # there is NO test at all, not to police naming. The parent dir is included because the
    # documented layout puts Tests/ beside the Tipo dirs (src/Pkg/DT/ vs src/Pkg/Tests/).
    roots = []
    d = os.path.dirname(norm)
    if d and os.path.isdir(d):
        roots.append(d)
        parent = os.path.dirname(d)
        if parent and os.path.isdir(parent):
            roots.append(parent)
    proj = os.environ.get("CLAUDE_PROJECT_DIR")
    if proj and proj not in roots:
        roots.append(proj)
    for r in roots:
        if has_tests(r):
            return

    msg = (
        "TDD: you just wrote the interop component " + base + " and no test class exists "
        "for it (neither *Test*.cls nor a Tests/ package). Per iris-interop-skills:tdd the "
        "order is spec -> test -> RED -> implement -> green: write the test first and SEE "
        "IT FAIL, so it tests the spec rather than the code you already wrote. Test classes "
        "extend %UnitTest.TestProduction. A component is not done until iris_test returns "
        "green on a test that was red before."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse", "additionalContext": msg}}))


if __name__ == "__main__":
    main()
