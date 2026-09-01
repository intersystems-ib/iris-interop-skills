#!/usr/bin/env python3
"""Structural gate over skill frontmatter.

Written for #131. Two sessions independently split trigger lists on the literal `Triggers:`,
missed the four skills that label theirs `Triggers EN:` / `Triggers ES:`, and both concluded
those four carried ZERO trigger words. That wrong number became the premise for a filed issue,
a committed report section, and a proposal to "fix" `report-issue` — which measurement later
showed to be the best-behaved skill in the plugin.

Neither query errored. Filtering on one label can only confirm the rows it already matches; it
can never reveal the rows it silently drops. **A query that cannot return zero is not a check.**
So the enforcement here is enumeration, not matching: S4 prints the whole label space every run,
which is the thirty seconds that would have prevented all of it.

    python3 scripts/validate_skills.py
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Any label variant currently in the tree, and any near-miss someone adds later.
TRIGGER_LABEL = re.compile(r"\bTriggers?\b[^:\n]{0,10}:", re.I)

failures = []


def check(cid, what, bad, detail=lambda x: x):
    if bad:
        failures.append(cid)
        print("  FAIL  {}  {}".format(cid, what))
        for b in bad[:10]:
            print("          - {}".format(detail(b)))
        if len(bad) > 10:
            print("          ... and {} more".format(len(bad) - 10))
    else:
        print("  ok    {}  {}".format(cid, what))


def frontmatter(text):
    """The YAML block between the first two `---` fences, or None."""
    m = re.match(r"\A---\s*\n(.*?)\n---\s*(?:\n|$)", text, re.S)
    return m.group(1) if m else None


def field(fm, name):
    """A frontmatter scalar, folded across continuation lines."""
    m = re.search(r"(?ms)^%s:\s*(.*?)(?=^\S+:|\Z)" % re.escape(name), fm)
    return " ".join(m.group(1).split()) if m else None


skills = sorted(glob.glob(os.path.join(ROOT, "skills", "*", "SKILL.md")))
print("\n{} skills under skills/\n".format(len(skills)))

parsed, no_fm, no_name, name_mismatch, no_desc = {}, [], [], [], []
for path in skills:
    slug = os.path.basename(os.path.dirname(path))
    fm = frontmatter(open(path, encoding="utf-8").read())
    if fm is None:
        no_fm.append(slug)
        continue
    nm, desc = field(fm, "name"), field(fm, "description")
    if not nm:
        no_name.append(slug)
    elif nm != slug:
        name_mismatch.append("{}: name: {!r}".format(slug, nm))
    if not desc:
        no_desc.append(slug)
    else:
        parsed[slug] = desc

check("S1", "every skill has a frontmatter block", no_fm)
check("S2", "frontmatter `name:` matches the directory", name_mismatch)
check("S3", "every skill has a non-empty `description:`", no_desc + no_name)

# --- S4: the #131 check. Enumerate, never filter.
labels, inbody = {}, {}
no_trigger, empty_trigger = [], []
for slug, desc in parsed.items():
    found = list(TRIGGER_LABEL.finditer(desc))
    if not found:
        no_trigger.append(slug)
        continue
    # Only the FIRST match introduces the list. Later ones are prose — `dicom` carries a
    # "NOT a trigger: ..." note, and counting that as a label form reported a fifth variant
    # that does not exist. Enumerating the wrong thing is still enumerating the wrong thing.
    labels.setdefault(found[0].group(0), []).append(slug)
    for m in found[1:]:
        inbody.setdefault(m.group(0), []).append(slug)
    body = desc[found[0].end():]
    if not body.strip(" .,"):
        empty_trigger.append(slug)

check("S4", "every description carries a non-empty trigger list", no_trigger + empty_trigger)

# --- S5: the #141 check. A [SqlProc] projects as <schema>.<Class>_<Method>, where <schema> is the
# package with dots turned into underscores. `SELECT Pkg_Bootstrap_Method(...)` carries no schema
# qualifier at all, so IRIS resolves it against SQLUSER and always answers SQLCODE -359. Four skills
# shipped that form and an eval agent copied one verbatim, so this is a literal-token gate, not a
# style rule. Two or more underscore-joined identifiers before the paren, with no dot, is the defect.
SQLPROC_CALL = re.compile(r"SELECT\s+(%?\w+(?:_\w+){2,})\s*\(")

# A line that cites SQLCODE -359 is TEACHING the bad form, not committing it — the router carries
# both wrong shapes on purpose. Narrow and deliberate: a line that ships the defect and also names
# its error code would slip through, which is why the exemption is the error code and not a
# hand-wavier marker like "example" or a fenced-block test.
TEACHING_THE_FAILURE = re.compile(r"-359\b")

bad_sqlproc = []
for path in skills:
    slug = os.path.basename(os.path.dirname(path))
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if TEACHING_THE_FAILURE.search(line):
            continue
        for m in SQLPROC_CALL.finditer(line):
            bad_sqlproc.append("{}:{}: {} — needs a schema qualifier, e.g. {}".format(
                slug, n, m.group(1),
                m.group(1).replace("_", ".", 1)))

check("S5", "no schema-less `SELECT Pkg_Class_Method(...)` SqlProc call (#141)", bad_sqlproc)

print("\n  label space in use (S4 enumerates rather than filters — see #131):")
for lab, who in sorted(labels.items(), key=lambda kv: -len(kv[1])):
    print("    {:>3}x  {:<16} {}".format(
        len(who), lab, "" if len(who) > 4 else ", ".join(sorted(who))))
if inbody:
    print("\n  later matches, prose not labels (e.g. a \"NOT a trigger: ...\" note):")
    for lab, who in sorted(inbody.items()):
        print("    {:>3}x  {:<16} {}".format(len(who), lab, ", ".join(sorted(who))))
if len(labels) > 1:
    print("\n  NOTE: more than one label form is in use. That is not a failure — normalising\n"
          "  the label changes text the router matches on, and this repo has measured that\n"
          "  description edits need a before/after (#126, #127). Any ANALYSIS of trigger\n"
          "  content must accept every form above; use the S4 regex, never a literal.")

print("\nSkills: {}\n".format(
    "all {} checks pass".format(5) if not failures else "{} FAILED".format(", ".join(failures))))
sys.exit(1 if failures else 0)
