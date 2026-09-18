#!/usr/bin/env python3
"""Stable issue fingerprints for the `report-issue` skill.

The skill's whole purpose is to stop the tracker filling with duplicates of the same defect
reported by different people. That rests on one sentence of prose -- "normalize away the
volatile bits (class names, ids, timestamps, namespaces) so the same defect from a different
student maps to the same fingerprint" -- and prose cannot be run. Two people normalising by
hand produce two different titles, the dedup search misses, and the skill has failed at
exactly the job it exists for.

WHY THIS LIVES IN scripts/ AND NOT IN THE EXAMPLE BANK. Tier 2 stages `.cls` files and
`examples_baseline.json` holds class names, so a `.py` helper can never satisfy the bank's
definition of covered. Indexing it there would add a row that reads as coverage while being
checked by nothing (COVERAGE-MAP.md item N16). Here it gets a real test instead.

No pytest: the repo's harnesses are stdlib-only on purpose, so CI needs no dependencies
(same reason as the Atelier client in validate_examples.py). Tests live in
scripts/test_issue_fingerprint.py and run as `python3 scripts/test_issue_fingerprint.py`.

THE ASYMMETRY THAT DRIVES EVERY CHOICE BELOW. Under-normalising costs a duplicate issue:
annoying, visible, easily merged. Over-normalising costs a *lost* report -- two genuinely
different defects collapse to one fingerprint, the second is filed as a "+1" comment on an
unrelated issue, and nobody ever looks at it again. So every rule here is the narrow form,
and the test file asserts both directions: same defect -> same fingerprint, and different
defects -> DIFFERENT fingerprints.

    python3 scripts/issue_fingerprint.py --area mcp --key iris_test \
        --summary 'NO_TESTS_FOUND in namespace APP for Demo.Tests.Foo at 2026-09-18T07:12:00Z'
    [mcp:iris_test] NO_TESTS_FOUND in namespace <ns> for <class> at <ts>

KNOWN LIMIT, asserted in the test file so it stays known: a namespace named WITHOUT the word
"namespace" nearby is not masked -- `in APP for ...` keeps `APP`. Catching that would mean
treating any bare uppercase word as a namespace, which would also eat NO_TESTS_FOUND, PRODUCTION
and every error code -- the over-normalising direction, where reports are lost rather than
duplicated. Write "namespace APP" in the summary and it normalises; the skill's own workflow
already phrases it that way.
"""

from __future__ import annotations

import argparse
import re
import sys

# Class-name prefixes that are PLATFORM, not project. These are the opposite of volatile:
# "EnsLib.HL7.Service.FileService hand-parses rows" is the same defect whoever hits it, and
# collapsing it to <class> would merge unrelated findings about different platform classes.
PLATFORM_ROOTS = (
    "Ens", "EnsLib", "EnsPortal", "HS", "HSMOD", "SYS", "Config", "Security",
    "SchemaMap", "CSPX", "INFORMATION", "%",
)

# Order matters: a timestamp contains digit runs, so it must be consumed before <id>.
_RULES: list[tuple[re.Pattern[str], str]] = [
    # ISO-8601, with or without seconds/fraction/zone.
    (re.compile(r"\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z?)?\b"), "<ts>"),
    # HL7 v2 / IRIS $ZDATETIME style: YYYYMMDD[HHMMSS].
    #
    # DATE-LIKE, not merely 8 digits. A bare \d{8} also matches a message header id, and the
    # test caught it doing so: id 90887766 normalised to <ts> while id 148372 normalised to
    # <id>, so the same defect from two reporters produced two fingerprints -- the exact
    # failure this module exists to prevent. Requiring a plausible century and month/day keeps
    # 20260918 a timestamp and lets 90887766 fall through to <id>.
    (re.compile(r"\b(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])(?:\d{6})?\b"), "<ts>"),
    # namespace=APP / namespace "APP" / namespace APP. The NAME is volatile; the word
    # "namespace" is not, and is deliberately kept -- an earlier version swallowed a preceding
    # "in" as well, which merged one more phrasing at the cost of a title reading
    # "failed <ns> for". Under-normalising costs a duplicate; over-normalising loses a report.
    (re.compile(r"(?i)\bnamespace[=:\s]+[\"']?([A-Za-z][A-Za-z0-9_]*)[\"']?"), "namespace <ns>"),
    # Absolute paths (POSIX and Windows).
    (re.compile(r"(?:[A-Za-z]:)?(?:/[\w.\-]+){2,}/?|(?:[A-Za-z]:)?(?:\\[\w.\-]+){2,}\\?"), "<path>"),
    # Long digit runs: message header ids, session ids, job numbers.
    (re.compile(r"\b\d{4,}\b"), "<id>"),
]

# A dotted identifier: Demo.BS.Foo, MyApp.MSG.Bar.Baz. Applied last, and only when the root
# is not in PLATFORM_ROOTS.
# The lookbehind replaces a leading \b, which could never match at a `%`: `%UnitTest.X` was
# matched from `UnitTest` and rewritten to `%<class>`, masking a platform class.
_DOTTED = re.compile(r"(?<![\w.%])(%?[A-Za-z][\w]*)((?:\.[A-Za-z][\w]*)+)\b")


def _mask_project_classes(text: str) -> str:
    """Replace project class names with <class>; leave platform names alone."""
    def repl(m: re.Match[str]) -> str:
        root = m.group(1)
        if root in PLATFORM_ROOTS or root.startswith("%"):
            return m.group(0)
        # A dotted token that is a filename (foo.py, bar.cls) is not a class reference.
        if m.group(2).lower() in (".py", ".cls", ".md", ".xml", ".sh", ".json", ".yml"):
            return m.group(0)
        return "<class>"
    return _DOTTED.sub(repl, text)


def normalize(text: str) -> str:
    """Strip the volatile bits from a one-line summary.

    Idempotent: normalize(normalize(x)) == normalize(x). The test file asserts this, because a
    fingerprint that changes when re-normalised cannot be searched for -- the second person to
    hit the defect would generate a different title from the one already in the tracker.
    """
    out = text
    for pattern, placeholder in _RULES:
        out = pattern.sub(placeholder, out)
    out = _mask_project_classes(out)
    # Collapse whitespace last: the substitutions above can leave runs behind.
    return " ".join(out.split())


def search_term(area: str, key: str) -> str:
    """The `gh issue list --search` term for this fingerprint.

    This is the actual dedup mechanism -- the title is only useful because this finds it. Kept
    next to the title builder so the two can never drift apart.
    """
    return f"in:title {area}:{key}"


def fingerprint(area: str, key: str, summary: str) -> str:
    """`[<area>:<key>] <normalised summary>` -- the issue title the skill prescribes."""
    area = area.strip().lower()
    key = key.strip()
    return f"[{area}:{key}] {normalize(summary)}"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--area", required=True, help="mcp | conformance | skill | workshop")
    ap.add_argument("--key", required=True, help="tool name, or CR-N for a conformance finding")
    ap.add_argument("--summary", required=True, help="one-line symptom")
    ap.add_argument("--search", action="store_true",
                    help="also print the gh --search term for the dedup step")
    args = ap.parse_args(argv)
    print(fingerprint(args.area, args.key, args.summary))
    if args.search:
        print(search_term(args.area, args.key))
    return 0


if __name__ == "__main__":
    sys.exit(main())
