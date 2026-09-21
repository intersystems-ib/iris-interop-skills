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
checks_run = 0


def check(cid, what, bad, detail=lambda x: x):
    global checks_run
    checks_run += 1
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

# S9 -- the DOCUMENTED cap, and it was being breached (#365).
#
# Anthropic's Agent Skills docs state it twice: `description` maximum **1,024 characters**. Measured
# at the time this was added, conformance-review was 1,090 -- 66 over -- and the 66 characters past
# the cap were the TAIL OF THE SPANISH TRIGGER LIST:
#
#     "n implementado, es correcto, cumple, revisión, control de calidad."
#
# So the overflow was eating `revisión` and `control de calidad` on a plugin whose users write
# Spanish, and #127 measured that trigger words are the half that is FREE and valuable while prose is
# the tax. Whatever a client does past 1,024 -- truncate or reject -- being over a documented maximum
# with triggers in the excess is a defect.
#
# CHARACTERS, not words. #365 framed it as "157 words against a ~100 budget"; there is no published
# word budget. The 100 figure in the docs is "~100 tokens per Skill" -- a statement of METADATA COST,
# not a limit -- and words are neither. The cap that exists is 1,024 characters, so that is what this
# checks.
#
# THIS DOES NOT LICENCE SHORTENING DESCRIPTIONS GENERALLY. CLAUDE.md is explicit: #127 measured
# ADDING 60 words (-13.3 precision) and whether removal is symmetric is untested, so an edit made for
# matching performance still needs a before/after. Trimming to get under a documented hard cap is a
# correctness fix and a different thing.
DESC_CHAR_CAP = 1024
over_cap = []
for path in skills:
    name = os.path.basename(os.path.dirname(path))
    fm = frontmatter(open(path, encoding="utf-8").read())
    if not fm:
        continue
    m = re.search(r"^description:\s*(.*?)(?=\n[a-z-]+:|\Z)", fm, re.S | re.M)
    if not m:
        continue
    desc = m.group(1).strip()
    if len(desc) > DESC_CHAR_CAP:
        over = len(desc) - DESC_CHAR_CAP
        over_cap.append("{}: description is {} chars, documented cap {} ({} over). What falls past "
                        "the cap here: {!r} -- cut PROSE, never trigger words (#127: prose is a tax, "
                        "triggers are free)".format(name, len(desc), DESC_CHAR_CAP, over,
                                                    desc[DESC_CHAR_CAP:][:60]))
check("S9", "every description is within the documented {}-character cap".format(DESC_CHAR_CAP),
      over_cap)
if not skills:
    failures.append("S9")
    print("  FAIL  S9  no skill was measured -- a clean pass here is vacuous")

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

# COVERAGE OF S5, stated here because a clean run reads like more than it is. This gate guards a
# SPELLING in skill text; it does not guard the rule "a [SqlProc] call resolves". It cannot see a
# wrong schema prefix, a name assembled at runtime, or a method that never got the [SqlProc]
# keyword (-149). Verifying it in both directions — done, and it named bpl:205 when the defect was
# reintroduced — proves one known-bad input reaches its failure path; it does not prove the check
# recognises every violation of the constraint it is named after. S5 green == no skill DOCUMENTS
# the -359 form. It is NOT evidence that any call in the corpus resolves.

# S6 -- the shipped hook count is DERIVED here rather than trusted (#167).
#
# Both descriptions said "Ships 8 hooks" and enumerated 1 + 2 + 5, silently omitting the
# conformance-stop-gate -- the only BLOCKING Stop hook in the package, and the single most
# surprising thing installing this plugin does. It was hand-maintained, so it went stale the
# release the Stop gate was added and nothing noticed for nine versions.
#
# The check is the arithmetic, not the wording: whatever number the description states must
# equal the number of hook COMMANDS in hooks.json. Reword freely; the count cannot drift.
import json as _json

with open(os.path.join(ROOT, "hooks", "hooks.json")) as fh:
    _hooks = _json.load(fh).get("hooks", {})
_actual = sum(len(e.get("hooks", [])) for entries in _hooks.values() for e in entries)

_stated = []
for _f in (".claude-plugin/plugin.json", ".claude-plugin/marketplace.json"):
    with open(os.path.join(ROOT, _f)) as fh:
        _d = _json.load(fh)
    _descs = ([_d["description"]] if "description" in _d else []) + \
             [_p.get("description", "") for _p in _d.get("plugins", [])]
    for _x in _descs:
        _m = re.search(r"Ships (\d+) hooks", _x)
        if _m:
            _stated.append((_f, int(_m.group(1))))

bad_hookcount = ["{} says {} hooks; hooks.json has {} ({})".format(
                     _f, _n, _actual,
                     ", ".join("{} {}".format(len([h for e in _v for h in e.get("hooks", [])]), _k)
                               for _k, _v in sorted(_hooks.items())))
                 for _f, _n in _stated if _n != _actual]
if not _stated:
    bad_hookcount.append("no shipped description states a hook count — the claim this check "
                         "guards has vanished, which is a silent pass, not a clean one")

check("S6", "shipped descriptions state the real hook count (#167)", bad_hookcount)

# S7 -- the 500-line discipline was won BY HAND and nothing held it (#355, finishing #337).
#
# v1.91.0-v1.93.0 brought 20 of 20 SKILL.md under the published limit one file at a time. Not one
# check measured size, so the next edit could have put them straight back and CI would have said
# nothing. A budget nobody asserts rots -- the same reason C9 exists in validate_examples.
#
# THE RULE IS LINES, and that is a decision, not an oversight. Anthropic's authoring guidance states
# "Keep SKILL.md body under 500 lines for optimal performance" three separate times, including in its
# own checklist. That is the rule this gate enforces.
#
# THE OTHER BUDGET IS REPORTED AND NOT ENFORCED, deliberately. The Skills overview also gives Level 2
# a cost of "Under 5k tokens", which is a different unit and a much harder bar: measured at the
# conventional chars/4 estimate, 14 of 20 skills exceed it, tdd worst at ~9.2k. #355 put that figure
# at ONE skill by counting WORDS (tdd 5,471 w) -- but words are not tokens, and for this content they
# run about 0.6x, so a word count understates the token cost by roughly 40% and misses thirteen
# skills. Enforcing 5k tokens would mean halving most of the plugin, which is a programme and not a
# gate change, so this prints the number instead of failing on it. It cannot rot while it is printed.
#
# The line count is of the BODY, not the file: frontmatter is Level 1 metadata, always loaded, and
# already governed by its own 1,024-character cap on `description`.
LINE_BUDGET = 500
TOKEN_ADVISORY = 5000

oversize, sizes = [], []
for path in skills:
    name = os.path.basename(os.path.dirname(path))
    text = open(path, encoding="utf-8").read()
    fm = re.match(r"\A---\s*\n.*?\n---\s*(?:\n|$)", text, re.S)
    body = text[fm.end():] if fm else text
    lines = body.count("\n") + 1
    est_tokens = len(body) // 4          # conventional rough estimate; not a tokeniser
    sizes.append((name, lines, len(body.split()), est_tokens))
    if lines > LINE_BUDGET:
        oversize.append("{}: {} lines of body, budget {} -- split the mutually-exclusive part into "
                        "references/<topic>.md and link it one level deep".format(
                            name, lines, LINE_BUDGET))

check("S7", "every SKILL.md body is within the published {}-line budget".format(LINE_BUDGET),
      oversize)

# Positive control for S7: if this list is empty the check above is measuring nothing.
if not sizes:
    failures.append("S7")
    print("  FAIL  S7  no SKILL.md was measured at all -- a clean pass here is vacuous")

# S8 -- the PER-SKILL token ratchet. "Lines only" is the published rule and S7 enforces it, but it is
# not the whole truth and the repo decided to stop pretending otherwise: measured, 14 of 20 skills
# exceed the overview's "Under 5k tokens" Level-2 figure while every one of them passes the 500-line
# rule. Enforcing 5k today would mean halving fourteen skills at once, so instead nothing may get
# WORSE.
#
# PER SKILL, not a total, and that is the whole mechanism. A total would let one skill grow while
# another shrinks, which is how the always-loaded cost creeps up unnoticed.
#
# THE REMEDY IS EVICTION PLUS A DIRECTIVE POINTER, and this text has now been wrong twice in two
# different ways. Both corrections are kept because the second one only makes sense against the first.
#
#   v1 said: move the new material to references/ "where it costs nothing until read".
#   v2 said: never relocate anything needed, because bundled files are measured at 1 pickup in 44
#            across Haiku 4.5 AND Sonnet 4.6 (p = 1.00 between them) -- so relocating a needed
#            capability costs the whole capability.
#
# v2's NUMBER is right and its CONCLUSION is wrong, which is the more dangerous shape. It is not the
# tier that fails, it is the VERB the file is pointed at with. Same card, same file, same `assets/`
# directory, Sonnet 4.6, 6 reps per gate (#388/#379):
#
#   passive mention  ("plantilla en `assets/x.md`", "See [references/x.md](...)")  0/6
#   directive + trigger ("Before writing a DTL, read assets/dtl-xdata.md")         5/6 - 6/6
#                                                                 Fisher p = 0.0152
#   relative vs absolute path                                     5/6 vs 6/6, p = 1.00 (not the cause)
#
# And the 1-in-44 is explained by construction rather than by any property of the tier: across the 20
# SKILL.md bodies there are 113 citations of bundled files and ~5 carry an imperative verb anywhere
# near them, none in the directive-with-trigger form. A measurement of "are bundled files read?" taken
# over those 113 citations had to come back ~0.
#
# So eviction is safe, and it is the only remedy that fits the budget WITHOUT losing the capability --
# but it has two parts and the second is not optional. Move the depth out AND rewrite the pointer as
# an imperative with a trigger condition. Full table and provenance: BestPractices/AB-PREREGISTRATION.md,
# which is the single record of these figures precisely so they are not restated here and left to rot.
#
# The queue this gate was aimed at (#339, #345, #347) is exactly the queue that ADDS required content,
# so v2's wording pointed every future fix INTO the body -- inflating the very thing this gate exists
# to protect, at the moment the contributor is deciding where material goes. That is why the wording
# matters more than its age.
#
# THE FIX IS MODEL-SPECIFIC, and this is now measured rather than assumed. Haiku 4.5 was run on the
# same VM, same day, same card, same assets/ file, 6 reps per gate (#388):
#
#                                      Haiku        Sonnet      Fisher
#   prompt (control +)                 6/6  100%    6/6  100%
#   nothing (control -)                0/6    0%    0/6    0%
#   directive, all three gates         1/18   6%   17/18  94%    p = 0.00000007
#
#   Haiku: directive 1/18 vs control -    p = 1.0000   <-- indistinguishable from no file at all
#   Haiku: prompt 6/6  vs directive 1/18  p = 0.000052 <-- and the instrument DOES work on Haiku
#
# So the directive pointer recovers the bundled tier on Sonnet and does NOT recover it on Haiku: for a
# small model, moving something needed into a file is still deleting it, whatever verb points at it.
# The previous version of this text guessed exactly that and had no number for it; it borrowed the 27%
# BODY-tier figure to argue about references/ and assets/, which is a different tier. That borrowing is
# gone -- 1/18 is from the tier this paragraph is about.
#
# LIMITS: one task, one skill, one file, n=6 per gate. Not tested whether repeating the pointer every
# turn, or firing it from a hook, reaches Haiku.
#
# chars/4 is a conventional estimate, not a tokeniser. That is fine for a ratchet -- it only has to be
# the SAME estimate on both sides of a comparison, and it is computed once here and recorded from the
# same code path.
SKILLS_BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "skills_baseline.json")

_recorded = {}
if os.path.exists(SKILLS_BASELINE):
    try:
        _recorded = _json.load(open(SKILLS_BASELINE)).get("skill_body_tokens") or {}
    except Exception:
        _recorded = {}

grew_tok = []
if not _recorded:
    # An inert ratchet reports "ok", which is the silent pass this repo keeps being bitten by.
    grew_tok.append("no scripts/skills_baseline.json, so this ratchet is measuring nothing -- "
                    "record it with: python3 scripts/validate_skills.py --record-sizes")
else:
    for name, lines, words, tk in sizes:
        was = _recorded.get(name)
        if was is None:
            grew_tok.append("{}: not in the baseline ({} tokens) -- a NEW skill must be recorded "
                            "deliberately".format(name, tk))
        elif tk > was:
            grew_tok.append("{}: ~{} body tokens, baseline ~{} (+{}) -- FUND IT by evicting "
                            "genuinely optional depth to skills/{}/references/, or re-record "
                            "deliberately. EVICTION HAS TWO PARTS AND THE SECOND IS NOT OPTIONAL: "
                            "move the depth out, AND rewrite the pointer as an imperative with a "
                            "trigger condition -- 'Before writing a DTL, read assets/dtl-xdata.md', "
                            "not 'See [references/x.md](references/x.md)'. Measured on Sonnet 4.6, "
                            "same file and same tier: the passive mention is read 0 times in 6 "
                            "(indistinguishable from the card not existing), the directive form "
                            "5-6 in 6, Fisher p = 0.0152; relative vs absolute path makes no "
                            "difference (p = 1.00). Evicting behind a passive pointer still costs "
                            "the whole capability -- evicting behind a directive one costs nothing "
                            "ON SONNET (94% across the three directive gates, n=18, vs 0% passive). "
                            "It does NOT recover on Haiku 4.5: 1 of 18, statistically indistinguishable "
                            "from the file not existing (p = 1.00 against the negative control) even "
                            "though the same content pasted into the prompt lands 6/6. For a small "
                            "model, moving something needed into a file is still deleting it, whatever "
                            "verb points at it -- so anything that TRULY cannot fail belongs in a hook "
                            "or a gate denial, not in prose and not behind a pointer. "
                            "Table: BestPractices/AB-PREREGISTRATION.md"
                            .format(name, tk, was, tk - was, name))
check("S8", "no SKILL.md body grew its always-loaded token cost (per-skill ratchet)", grew_tok)

if _recorded:
    _shrank = [(n, tk, _recorded[n]) for n, l, w, tk in sizes
               if n in _recorded and tk < _recorded[n]]
    for n, tk, was in sorted(_shrank, key=lambda x: x[1] - x[2]):
        print("          note: {} down to ~{} tokens from ~{} -- progress; re-record with "
              "--record-sizes".format(n, tk, was))

if "--record-sizes" in sys.argv:
    with open(SKILLS_BASELINE, "w") as _fh:
        _json.dump({
            "_comment": "Estimated always-loaded body tokens (chars/4) per SKILL.md. S8 ratchets "
                        "this per skill: growth fails, a drop only prints. The ENFORCED line budget "
                        "is S7's 500; this exists because 14 of 20 skills exceed the overview's 5k "
                        "token figure and the debt must not grow while it is worked down.",
            "skill_body_tokens": {n: tk for n, l, w, tk in sorted(sizes)},
        }, _fh, indent=2)
        _fh.write("\n")
    print("\n  skill sizes recorded: {} skills -> {}".format(len(sizes), os.path.basename(SKILLS_BASELINE)))

over_tok = sorted((s for s in sizes if s[3] > TOKEN_ADVISORY), key=lambda s: -s[3])
if over_tok:
    print("\n  NOTE: {} of {} skills exceed the overview's \"Under 5k tokens\" Level-2 figure "
          "(chars/4 estimate,\n  advisory only -- the ENFORCED rule is {} lines, see the S7 note in "
          "this file):".format(len(over_tok), len(sizes), LINE_BUDGET))
    for name, lines, words, tk in over_tok[:5]:
        print("    {:<24} {:>4} lines  {:>5} words  ~{:>5} tokens".format(name, lines, words, tk))
    if len(over_tok) > 5:
        print("    ... and {} more".format(len(over_tok) - 5))

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

# The count is derived, not typed. It used to be a literal 5 -- the same hand-maintained-number
# defect S6 exists to catch, sitting in the summary line of the gate that now catches it.
print("\nSkills: {}\n".format(
    "all {} checks pass".format(checks_run) if not failures
    else "{} FAILED".format(", ".join(failures))))
sys.exit(1 if failures else 0)
