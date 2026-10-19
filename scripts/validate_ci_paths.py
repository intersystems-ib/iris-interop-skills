#!/usr/bin/env python3
"""Does each validator's workflow WATCH every file that validator reads?

    python3 scripts/validate_ci_paths.py              # the always-on gate (no execution)
    python3 scripts/validate_ci_paths.py --trace scripts/test_hooks.py
    python3 scripts/validate_ci_paths.py --self-test  # the parser's own unit tests

WHY THIS EXISTS. A `paths:` filter that is missing one of its validator's inputs makes the
gate invisible for exactly the change that needed it: the push lands, no job runs, and the
run page is not red — it is empty. This repo has shipped that shape three times.

  1.15.1   test-hooks.yml ran the issue-fingerprint tests while its filter still listed only
           `hooks/**`, so editing `scripts/issue_fingerprint.py` ran nothing. Caught in
           1.16.0 by a human; the comment is still in that workflow.
  #418     validate-skills.yml was blind to 5 of its inputs, validate-examples.yml to 94 of
           its tier-1 inputs. Caught by a human.
  #421     fixed those two and reported "0 unwatched now" — true of the two files it edited,
           and wrong by 268 for test-hooks.yml, which it never looked at. Caught by a human.

Three for three, each caught by someone noticing. The N+1th omission needs a machine, and
that is all this file is.

TWO LINKS, BECAUSE A SINGLE-LINK DESIGN DRIFTS SILENTLY
    The failure mode of any one mechanism is that the mechanism itself stops working and
    reports a smaller set — "0 unwatched", the clean zero. So the claim is split in half and
    each half is falsifiable on its own.

    LINK 2, `paths:` vs DECLARATION — pure text, no execution, runs on every push as part of
    scripts/test_hooks.py. Each validator's inputs are DECLARED here as repo-relative globs;
    the globs are expanded against `git ls-files` and every concrete tracked file is matched
    against its workflow's own `push:` and `pull_request:` filters. A file that is an input
    and is not matched is named as a (validator, workflow, path) triple.

    LINK 1, DECLARATION vs REALITY — runs the validator under an audit hook
    (scripts/_input_audit.py) and fails when it touches a tracked file the declaration does
    not cover. This is the link that catches a NEW read, which no static deriver can be
    trusted with: when a deriver stops recognising a call site it under-reports, and
    under-reporting is indistinguishable from success. Link 1 rides in each validator's own
    workflow, so a new read fails the job for the change that introduced it.

    Neither link can cover for the other. Link 2 with a stale declaration passes while
    reality has moved; link 1 with a correct declaration passes while the workflow filter is
    empty. Both have to hold.

WHY THE DECLARATION LIVES HERE AND NOT IN EACH VALIDATOR
    #418's design put each INPUTS tuple at the top of the validator it describes, which is
    the better place — it is next to the code it makes a claim about. It is not where they
    are, because this change was scoped to the workflows plus scripts/test_hooks.py and
    scripts/validate_skills.py and scripts/validate_examples.py were owned by another agent
    editing them at the same time. Moving each tuple into its own validator is a mechanical
    follow-up and changes nothing else here: VALIDATORS would read its `inputs` from the
    module instead of carrying it.

WHAT IS NOT GUARDED, so a clean run is not read as more than it is
    * GitHub evaluates `paths:` against the files a push or PR actually CHANGED. This gate
      checks pattern-matching only. It cannot see a filter that is right and a job that is
      skipped for some other reason (a `if:` condition, a concurrency cancel, no runner).
    * The input set is derived from ONE run of each validator on ONE tree. A read that only
      happens on a branch of the code this tree does not reach is invisible to link 1; it is
      the declaration, not the trace, that has to be widened for it.
    * Link 1 OVER-approximates in one known way, which is the safe direction for a filter
      but does manufacture a filter line now and then: a path whose EXISTENCE was merely
      probed counts as an input even when no assertion reads its contents. That is why
      `LICENSE` is an input of scripts/test_hooks.py — the CR-16 sweep stats every glob hit
      before rejecting it on extension. Watching a file nothing reads only runs a job too
      often; missing one is the failure this file exists to prevent.
"""
import io
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_DIR = os.path.join(".github", "workflows")

# A path that cannot be a real input, used to ask "would this filter match ANYTHING inside
# that directory?". GitHub filters only ever see changed FILE paths, so a directory input
# reduces to the files under it.
DIR_PROBE = "__iis_dir_probe__"


class FilterParseError(Exception):
    """The workflow could not be read. Raised, never swallowed into an empty list.

    An unparseable filter that returns `[]` reports every input as unwatched; one that
    returns "watches everything" reports none. Both are answers invented by the parser, and
    the second is the dangerous one.
    """


# --------------------------------------------------------------------------------------
# THE DECLARATION. One entry per validator, mapping it to the workflow that runs it.
#
# `inputs` is the set of repo paths the validator is ALLOWED to touch, as GitHub-style
# globs; link 1 fails on anything outside it, link 2 requires the workflow to watch
# everything inside it. `floor` is the hook-liveness control: the minimum number of tracked
# files a trace must find. Its only job is to make a dead audit hook fail LOUDLY instead of
# reporting a clean zero, so it is set well under today's count, which the gate prints.
# --------------------------------------------------------------------------------------
class Validator(object):
    def __init__(self, script, workflow, inputs, floor, note=""):
        self.script = script
        self.workflow = os.path.join(WORKFLOW_DIR, workflow)
        self.inputs = inputs
        self.floor = floor
        self.note = note

    def __repr__(self):
        return self.script


VALIDATORS = (
    Validator(
        "scripts/validate_skills.py", "validate-skills.yml",
        inputs=(
            "skills/**",                        # :54 the SKILL.md glob, :60 reads each
            ".claude-plugin/plugin.json",       # :194 S6 hook count, S10 version
            ".claude-plugin/marketplace.json",  # :194 S6 hook count, S10 version
            "hooks/hooks.json",                 # :188 S6 hook count
            "README.md",                        # :209 S6 hook table
            "scripts/skills_baseline.json",     # :389 S8 token ratchet
            "scripts/validate_skills.py",       # itself
        ),
        floor=20,                               # 27 tracked inputs on 2026-10-16
    ),
    Validator(
        "scripts/validate_examples.py", "validate-examples.yml",
        inputs=(
            "BestPractices/**",                 # the bank, the external mirror, COVERAGE-MAP
            "skills/**",                        # tier 3 snippets, C9/C19, tier 2 skill assets
            "scripts/validate_examples.py",     # itself
            "scripts/examples_baseline.json",
            "scripts/external_baseline.json",   # tier 2b only — see "too wide" below
            "scripts/snippets_baseline.json",
            "scripts/atelier_fixtures.json",
        ),
        floor=150,                              # 235 tracked inputs in TIER 1 on 2026-10-16
        note="tier 1 only; --compile adds no path outside these globs",
    ),
    Validator(
        "scripts/test_hooks.py", "test-hooks.yml",
        inputs=(
            "hooks/**",                         # the subjects
            "scripts/**",                       # :1314 the CR-16 sweep reads every .py/.json
            "skills/**",                        # :1314 sweep, :1808 router, :1108 TOPICS dirs
            "BestPractices/**",                 # :1314 the sweep, 138 files today
            "agents/**",                        # :1885 the CCR clause in two agents
            # Two mechanisms, and the second is the one that matters. (a) :1425 asserts
            # `walk_files(ROOT) > 100`, and that walk is an os.walk over the WHOLE tree,
            # dot-directories included, precisely because glob skips them (#95) -- so the
            # listings of .github/ and .claude-plugin/ are inputs. (b) link 2 of this gate
            # runs inside test_hooks.py and OPENS every workflow in VALIDATORS. Without (b)
            # watched here, deleting a filter line from validate-skills.yml would run no
            # job at all: a path-filter gate must not itself be path-filtered.
            ".github/**",
            ".claude-plugin/**",
            "CLAUDE.md",                        # :1314 the sweep
            "README.md",                        # :1314 the sweep
            "settings.json",                    # :1314 the sweep
            # The sweep stats every glob hit at :1309 before rejecting it on extension, so
            # LICENSE is an input by existence only -- nothing reads its contents. Kept
            # because over-watching costs a job run and under-watching costs the gate.
            "LICENSE",
        ),
        floor=200,                              # 296 tracked inputs on 2026-10-16
        note="the suite walks the whole tree twice, so its input set IS the repo",
    ),
    Validator(
        "scripts/test_issue_fingerprint.py", "test-hooks.yml",
        inputs=(
            "scripts/issue_fingerprint.py",      # :24 imports it
            "scripts/test_issue_fingerprint.py",  # itself
        ),
        floor=2,
        note="floor 2 is the cold-cache control: a warm __pycache__ hides the import",
    ),
    Validator(
        "scripts/validate_ci_paths.py", "test-hooks.yml",
        inputs=(
            ".github/workflows/**",           # it parses the filters of every mapped workflow
            # The table-completeness check lists scripts/ and stats every entry, so the
            # whole directory is an input: a new validate_*/test_* file appearing there
            # changes the verdict. Found by link 1 on this very file -- the declaration
            # first said only the two .py files below, and the trace named the other 13
            # with the line that stats them.
            "scripts/**",
            "scripts/validate_ci_paths.py",   # itself
            "scripts/_input_audit.py",        # --trace loads it into the child; stat'd here
        ),
        floor=4,                              # itself + the 3 workflows it parses
        note="the gate is in its own table, so the bootstrap trap is visible rather than "
             "implicit: it must be watched by the job that runs it",
    ),
)

# Every scripts/validate_*.py and scripts/test_*.py must appear above, or be excused here
# with a reason. Without this the FIFTH validator is onboarded with no gate at all, which is
# the 1.16.0 failure in a new costume.
NOT_A_VALIDATOR = {
    # (empty today -- every validate_*/test_* script in scripts/ is in VALIDATORS)
}


# --------------------------------------------------------------------------------------
# GitHub `paths:` glob semantics. `**` spans `/`, `*` and `?` do not.
# --------------------------------------------------------------------------------------
def glob_to_regex(pattern):
    """Compile one GitHub filter pattern to an anchored regex over a repo-relative path."""
    if pattern.startswith("!"):
        # Negation inverts the meaning of every later pattern in the list. Rather than
        # half-implement it and silently answer the wrong question, refuse.
        raise FilterParseError("negated filter pattern is not supported here: %r" % pattern)
    out, i, n = [], 0, len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            if pattern[i:i + 3] == "**/":
                out.append("(?:.*/)?")   # `**/x` must also match a top-level `x`
                i += 3
            elif pattern[i:i + 2] == "**":
                out.append(".*")
                i += 2
            else:
                out.append("[^/]*")
                i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == "[":
            j = pattern.find("]", i + 1)
            if j < 0:
                raise FilterParseError("unterminated [ in %r" % pattern)
            body = pattern[i + 1:j]
            out.append("[" + ("^" + body[1:] if body[:1] == "!" else body) + "]")
            i = j + 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.compile("\\A" + "".join(out) + "\\Z")


def matched_by(patterns, path):
    """The first pattern that matches `path`, or None. The pattern, not a boolean, so a
    report can say which line is doing the watching."""
    for p in patterns:
        if glob_to_regex(p).match(path):
            return p
    return None


# --------------------------------------------------------------------------------------
# The workflow filter parser.
#
# This is the piece that gets its own unit tests, because #418's measurement wrote one,
# left YAML inline comments attached to the values, and manufactured five findings with a
# plausible story attached: `.claude-plugin/plugin.json` IS listed in validate-skills.yml,
# but as `- '.claude-plugin/plugin.json'      # S6 hook count, S10 version`, and a parser
# that keeps the comment compares against a string no path will ever equal. A false
# positive that reads like a finding is worse than no gate.
# --------------------------------------------------------------------------------------
ALL_PATHS = "<no paths: key -- watches everything>"


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def yaml_scalar(raw):
    """One YAML scalar from a sequence item's text, inline comment removed.

    Quoted: the value ends at the closing quote and ANYTHING after it is a comment.
    Plain:  a comment starts at ` #`; a bare `#` inside the value does not start one.
    """
    raw = raw.strip()
    if raw[:1] in ("'", '"'):
        q, i, buf = raw[0], 1, []
        while i < len(raw):
            c = raw[i]
            if c == q:
                if q == "'" and raw[i + 1:i + 2] == "'":
                    buf.append("'")       # YAML's '' escape inside a single-quoted scalar
                    i += 2
                    continue
                return "".join(buf)
            if q == '"' and c == "\\" and i + 1 < len(raw):
                buf.append(raw[i + 1])
                i += 2
                continue
            buf.append(c)
            i += 1
        raise FilterParseError("unterminated quote in sequence item: %r" % raw)
    cut = raw.find(" #")
    if cut >= 0:
        raw = raw[:cut]
    return raw.strip()


def _significant(lines, start, limit_indent):
    """Yield (index, indent, stripped) for the block indented deeper than limit_indent,
    skipping blanks and whole-line comments, stopping when the indentation leaves it."""
    i = start
    while i < len(lines):
        s = lines[i]
        if not s.strip() or s.lstrip().startswith("#"):
            i += 1
            continue
        ind = _indent(s)
        if ind <= limit_indent:
            return
        yield i, ind, s.strip()
        i += 1


def workflow_filters(text):
    """-> {"push": [...] | ALL_PATHS | None, "pull_request": ...} for one workflow.

    None means the trigger is not configured at all; ALL_PATHS means it is configured with
    no `paths:` key, so nothing can be unwatched. Those three outcomes are kept apart on
    purpose: collapsing "no filter" into "empty filter" would report every input of
    traffic-snapshot.yml as unwatched, and collapsing it the other way would report a
    genuinely empty filter as fine.
    """
    lines = text.split("\n")
    on_at = on_indent = None
    for n, s in enumerate(lines):
        if _indent(s) == 0 and re.match(r"""^(on|"on"|'on')\s*:""", s):
            on_at, on_indent = n, 0
            break
    if on_at is None:
        raise FilterParseError("no top-level `on:` key")

    result = {"push": None, "pull_request": None}
    for idx, ind, stripped in _significant(lines, on_at + 1, on_indent):
        m = re.match(r"^(push|pull_request)\s*:\s*(.*)$", stripped)
        if not m:
            continue
        trigger, rest = m.group(1), m.group(2).strip()
        if rest and not rest.startswith("#"):
            raise FilterParseError("inline value on `%s:` is not supported: %r"
                                   % (trigger, stripped))
        found = ALL_PATHS
        for _j, pind, pstr in _significant(lines, idx + 1, ind):
            pm = re.match(r"^(paths|paths-ignore)\s*:\s*(.*)$", pstr)
            if not pm:
                continue
            if pm.group(1) == "paths-ignore":
                # An exclusion list cannot be checked for completeness by this gate: it
                # says what is NOT watched, and the complement is the whole repo at the
                # moment the push happens. Refuse rather than answer the wrong question.
                raise FilterParseError(
                    "`paths-ignore:` under `%s:` cannot be verified by this gate" % trigger)
            if pm.group(2).strip() and not pm.group(2).strip().startswith("#"):
                raise FilterParseError("inline `paths:` sequence is not supported: %r" % pstr)
            items = []
            for _k, _iind, istr in _significant(lines, _j + 1, pind):
                if not istr.startswith("- "):
                    raise FilterParseError("not a sequence item under `paths:`: %r" % istr)
                items.append(yaml_scalar(istr[2:]))
            found = items
            break
        result[trigger] = found
    return result


# --------------------------------------------------------------------------------------
def tracked_files():
    """`git ls-files`, as a set. An UNTRACKED file cannot be the subject of a push or PR
    filter, so the whole comparison happens inside this set."""
    p = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise FilterParseError("git ls-files failed: %s" % p.stderr.strip()[:200])
    files = set(x for x in p.stdout.split("\0") if x)
    if not files:
        raise FilterParseError("git ls-files returned nothing -- not a repo?")
    return files


def declared_files(validator, tracked):
    """Every tracked file the declaration says this validator may read."""
    pats = [glob_to_regex(g) for g in validator.inputs]
    return set(f for f in tracked if any(r.match(f) for r in pats))


class Finding(object):
    def __init__(self, kind, validator, workflow, path, why):
        self.kind, self.validator, self.workflow, self.path, self.why = \
            kind, validator, workflow, path, why

    def __str__(self):
        return "{:<10} {} -> {} : {}   ({})".format(
            self.kind, self.validator, self.workflow or "-", self.path, self.why)


# --------------------------------------------------------------------------------------
# LINK 2 -- declaration vs the workflow's own filters. Pure text.
# --------------------------------------------------------------------------------------
def link2(verbose=True):
    """-> (findings, notes). Never returns an empty findings list on a parse failure."""
    findings, notes = [], []
    tracked = tracked_files()

    # Table completeness FIRST: a validator that is not in the table is not merely
    # unchecked, it makes every count below a count over the wrong population.
    #
    # The population here is tracked files UNION what is on disk under scripts/, which is
    # the one place this gate looks past `git ls-files`. A brand-new validator is untracked
    # in the working tree that introduces it, and "untracked, so not my problem" is how the
    # fifth validator gets onboarded with no gate -- the 1.16.0 failure in a new costume.
    pat = re.compile(r"\Ascripts/(?:validate|test)_[A-Za-z0-9_]+\.py\Z")
    in_table = set(v.script for v in VALIDATORS)
    on_disk = set("scripts/" + n for n in sorted(os.listdir(os.path.join(ROOT, "scripts")))
                  if os.path.isfile(os.path.join(ROOT, "scripts", n)))
    for f in sorted(tracked | on_disk):
        if pat.match(f) and f not in in_table and f not in NOT_A_VALIDATOR:
            findings.append(Finding("untabled", f, None, f,
                                    "matches scripts/{validate,test}_*.py (%s) but is in "
                                    "neither VALIDATORS nor NOT_A_VALIDATOR"
                                    % ("tracked" if f in tracked else "untracked, on disk")))

    for v in VALIDATORS:
        # Presence is asked of the DISK, tracking only reported. A validator added by the
        # very change being gated is untracked in its own working tree, and failing on that
        # would mean the gate can never be extended without first committing blind. A
        # script that is nowhere is still a hard failure.
        if not os.path.isfile(os.path.join(ROOT, v.script)):
            findings.append(Finding("missing", v.script, v.workflow, v.script,
                                    "VALIDATORS names a script that is not on disk"))
            continue
        if v.script not in tracked:
            notes.append("%s: on disk but UNTRACKED -- it must be committed with this "
                         "change, or the filter line that watches it guards nothing"
                         % v.script)
        wf_abs = os.path.join(ROOT, v.workflow)
        if not os.path.isfile(wf_abs):
            findings.append(Finding("missing", v.script, v.workflow, v.workflow,
                                    "VALIDATORS maps to a workflow that does not exist"))
            continue
        wf_text = io.open(wf_abs, encoding="utf-8").read()

        # The mapping itself has to be true: a table row pointing at a workflow that never
        # runs the script would make every path below pass for the wrong reason.
        if not re.search(r"^\s*(?:run:|.*\s)%s(?:\s|$)" % re.escape(v.script),
                         wf_text, re.M):
            findings.append(Finding("unrun", v.script, v.workflow, v.script,
                                    "the workflow never names this script -- bad mapping"))
            continue

        filters = workflow_filters(wf_text)
        push, pr = filters["push"], filters["pull_request"]
        if push is None and pr is None:
            notes.append("%s: neither push: nor pull_request: is configured in %s"
                         % (v.script, v.workflow))
            continue
        if push != pr:
            findings.append(Finding("divergent", v.script, v.workflow, "push vs pull_request",
                                    "the two filter lists are not identical, so a PR and a "
                                    "push to the same files run different jobs"))
        want = declared_files(v, tracked)
        for trigger, pats in (("push", push), ("pull_request", pr)):
            if pats is None or pats is ALL_PATHS:
                continue
            unwatched = sorted(f for f in want if matched_by(pats, f) is None)
            for f in unwatched:
                findings.append(Finding("unwatched", v.script, v.workflow, f,
                                        "declared input, matched by no %s: paths: entry"
                                        % trigger))
            if verbose:
                print("  {:<36} {:<30} {:>4} inputs, {:>2} filters, {:>3} unwatched ({})"
                      .format(v.script, os.path.basename(v.workflow), len(want),
                              len(pats), len(unwatched), trigger))
        # A declared glob that matches nothing at all is a line nobody maintains -- the
        # shape that rots after a rename and then quietly vouches for an empty set.
        # A LITERAL path (no wildcard) that exists on disk but is not tracked yet is the
        # new-file case, not rot, so it falls back to the disk; a WILDCARD glob gets no
        # such fallback, because one matching only untracked files is genuinely suspect.
        for g in v.inputs:
            r = glob_to_regex(g)
            if any(r.match(f) for f in tracked):
                continue
            literal = not any(c in g for c in "*?[")
            if literal and os.path.isfile(os.path.join(ROOT, g)):
                notes.append("%s: declared input %s exists but is UNTRACKED" % (v.script, g))
                continue
            findings.append(Finding("deadglob", v.script, v.workflow, g,
                                    "declared input glob matches no tracked file"))
    return findings, notes


# --------------------------------------------------------------------------------------
# LINK 1 -- declaration vs what the validator actually touches, at runtime.
# --------------------------------------------------------------------------------------
_SITECUSTOMIZE = '''\
# Generated by scripts/validate_ci_paths.py. Loaded by every traced process (and by its
# children, which inherit PYTHONPATH). Loads the audit module BY PATH rather than putting
# scripts/ on sys.path: a traced hook must not suddenly be able to import this repo's
# scripts/ modules, or tracing would change what the code under test resolves.
try:
    import importlib.util as _u
    _s = _u.spec_from_file_location("_iis_input_audit", r"{audit}")
    _m = _u.module_from_spec(_s)
    _s.loader.exec_module(_m)
except Exception:
    pass
'''


def trace(script):
    """Run `script` under the audit hook. -> (returncode, files, dirs, where, stdio).

    `files` and `dirs` are repo-relative; `where` maps a path to the frames that touched it
    first. Dedup is per process in the hook, so the same path arrives once per child.
    """
    tmp = tempfile.mkdtemp(prefix="iis-ci-paths-")
    sc_dir = os.path.join(tmp, "sc")
    os.makedirs(sc_dir)
    log = os.path.join(tmp, "trace.tsv")
    audit = os.path.join(ROOT, "scripts", "_input_audit.py")
    if not os.path.isfile(audit):
        raise FilterParseError("scripts/_input_audit.py is missing; cannot trace")
    io.open(os.path.join(sc_dir, "sitecustomize.py"), "w", encoding="utf-8").write(
        _SITECUSTOMIZE.format(audit=audit))

    env = dict(os.environ)
    env["IIS_INPUT_AUDIT_LOG"] = log
    env["PYTHONPATH"] = sc_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    # THE COLD-CACHE CONTROL, and it is load-bearing. With a warm scripts/__pycache__ an
    # imported repo module is read from its .pyc and the source is only stat'd through
    # importlib's own frozen `posix`, which neither the audit hook nor the stat shim can
    # see. Measured: scripts/test_issue_fingerprint.py traces TWO files cold and ONE warm,
    # and the one it loses is scripts/issue_fingerprint.py -- the exact file whose missing
    # filter line was the 1.15.1 bug. Redirecting the cache to a temp dir forces every
    # repo module to be compiled from source, and leaves the repo's own cache alone.
    env["PYTHONPYCACHEPREFIX"] = os.path.join(tmp, "pyc")

    p = subprocess.run([sys.executable, os.path.join(ROOT, script)],
                       cwd=ROOT, env=env, capture_output=True, text=True)
    files, dirs, where = set(), set(), {}
    if os.path.isfile(log):
        for line in io.open(log, encoding="utf-8"):
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            kind, path, frame = parts
            (files if kind == "file" else dirs).add(path)
            where.setdefault(path, frame)
    return p.returncode, files, dirs, where, (p.stdout, p.stderr)


def link1(validator, verbose=True):
    """-> (findings, notes) for one validator, from a real run."""
    findings, notes = [], []
    tracked = tracked_files()
    rc, files, dirs, where, _io2 = trace(validator.script)
    touched = files & tracked
    declared = declared_files(validator, tracked)

    if verbose:
        print("  {}: exit {}, traced {} files + {} dirs, {} tracked, floor {}"
              .format(validator.script, rc, len(files), len(dirs), len(touched),
                      validator.floor))

    # THE CONTROL THAT MATTERS MOST. A hook that silently stopped firing yields an empty set
    # and every "undeclared" test below then passes -- the textbook false green. An absolute
    # floor is the only thing that distinguishes "nothing undeclared" from "nothing seen".
    if len(touched) < validator.floor:
        findings.append(Finding("deadtrace", validator.script, validator.workflow,
                                "%d tracked inputs" % len(touched),
                                "below the floor of %d: the audit hook is probably not "
                                "firing, so every result from this run is worthless"
                                % validator.floor))
        return findings, notes

    for f in sorted(touched - declared):
        findings.append(Finding("undeclared", validator.script, validator.workflow, f,
                                "read at %s but matched by no INPUTS glob"
                                % where.get(f, "?")))
    for d in sorted(dirs):
        probe = d + "/" + DIR_PROBE
        if matched_by(validator.inputs, probe) is None:
            findings.append(Finding("undeclared", validator.script, validator.workflow,
                                    d + "/", "directory listed at %s but no INPUTS glob "
                                    "covers anything inside it" % where.get(d, "?")))

    # Declaration WIDER than reality is reported, not failed. A tier-2-only input is
    # legitimately untouched by a tier-1 run: scripts/external_baseline.json is read only
    # under --compile, and that population difference is exactly why #418's measurement
    # counted 94 where #421 counted 95. Neither number was wrong.
    extra = sorted(declared - touched)
    if extra:
        notes.append("%s: %d declared file(s) not touched by this run (first 5: %s)"
                     % (validator.script, len(extra), ", ".join(extra[:5])))
    return findings, notes


# --------------------------------------------------------------------------------------
# The parser's own unit tests. See the comment above the parser for why it has them.
# --------------------------------------------------------------------------------------
def self_test(verbose=True):
    bad = []

    def eq(label, got, want):
        if got != want:
            bad.append("%s: got %r want %r" % (label, got, want))
        elif verbose:
            print("  ok    %s" % label)

    def raises(label, fn):
        try:
            fn()
        except FilterParseError:
            if verbose:
                print("  ok    %s" % label)
            return
        except Exception as e:
            bad.append("%s: raised %r, wanted FilterParseError" % (label, e))
            return
        bad.append("%s: did not raise" % label)

    # --- yaml_scalar: the exact shape that manufactured five false findings in #418 ---
    eq("scalar strips an inline comment after a quoted value",
       yaml_scalar("'.claude-plugin/plugin.json'      # S6 hook count, S10 version"),
       ".claude-plugin/plugin.json")
    eq("scalar strips an inline comment after a plain value",
       yaml_scalar("README.md   # S6 hook table"), "README.md")
    eq("scalar keeps a quoted value whole", yaml_scalar("'skills/**'"), "skills/**")
    eq("scalar handles double quotes", yaml_scalar('"a/b.md"  # x'), "a/b.md")
    eq("scalar keeps a bare # that starts no comment", yaml_scalar("a#b.md"), "a#b.md")
    eq("scalar unescapes YAML's '' inside single quotes",
       yaml_scalar("'it''s.md'"), "it's.md")
    raises("scalar refuses an unterminated quote", lambda: yaml_scalar("'oops.md"))

    # --- glob_to_regex: GitHub semantics ---
    cases = [
        ("skills/**", "skills/a.md", True), ("skills/**", "skills/a/b/c.md", True),
        ("skills/**", "skillsx/a.md", False), ("skills/**", "a/skills/b.md", False),
        ("skills/*/SKILL.md", "skills/bpl/SKILL.md", True),
        ("skills/*/SKILL.md", "skills/bpl/x/SKILL.md", False),
        ("README.md", "README.md", True), ("README.md", "docs/README.md", False),
        ("**/README.md", "README.md", True), ("**/README.md", "a/b/README.md", True),
        ("**.cls", "a/b.cls", True), ("**.cls", "b.cls", True),
        ("scripts/*.py", "scripts/a.py", True), ("scripts/*.py", "scripts/a/b.py", False),
        (".github/**", ".github/workflows/x.yml", True),
        ("hooks/**", "hooks/a.py", True), ("hooks/**", "hooks.json", False),
        ("x?.md", "xa.md", True), ("x?.md", "xab.md", False),
        ("[ab].md", "a.md", True), ("[ab].md", "c.md", False),
    ]
    for pat, path, want in cases:
        eq("glob %-20r vs %-26r" % (pat, path),
           glob_to_regex(pat).match(path) is not None, want)
    raises("glob refuses a negated pattern", lambda: glob_to_regex("!a.md"))

    # --- workflow_filters: the three outcomes must stay apart ---
    wf = ("name: x\n"
          "on:\n"
          "  push:\n"
          "    paths:\n"
          "      - 'a/**'      # because of A\n"
          "      # a whole-line comment\n"
          "      - 'b.md'\n"
          "  pull_request:\n"
          "    paths:\n"
          "      - 'a/**'\n"
          "      - 'b.md'\n"
          "  workflow_dispatch:\n"
          "jobs:\n"
          "  j:\n"
          "    steps: []\n")
    eq("filters: push list", workflow_filters(wf)["push"], ["a/**", "b.md"])
    eq("filters: pull_request list", workflow_filters(wf)["pull_request"], ["a/**", "b.md"])
    eq("filters: an unconfigured trigger is None",
       workflow_filters("on:\n  push:\n    paths:\n      - 'a'\n")["pull_request"], None)
    eq("filters: a trigger with no paths: watches everything",
       workflow_filters("on:\n  push:\n  pull_request:\n    paths:\n      - 'a'\n")["push"],
       ALL_PATHS)
    eq("filters: `jobs:` at column 0 ends the on: block",
       workflow_filters("on:\n  push:\n    paths:\n      - 'a'\njobs:\n  push:\n    paths:\n"
                        "      - 'NOT A FILTER'\n")["push"], ["a"])
    raises("filters refuse paths-ignore",
           lambda: workflow_filters("on:\n  push:\n    paths-ignore:\n      - 'a'\n"))
    raises("filters refuse a workflow with no on:",
           lambda: workflow_filters("name: x\njobs: {}\n"))

    # --- the real workflows must parse, and parse to something non-empty ---
    # POSITIVE CONTROL for the parser: if it ever starts returning [] for a file that does
    # have filters, every "unwatched" count becomes the whole input set and every
    # "watches everything" becomes a free pass. Assert a known-present pattern.
    for name, wanted in (("validate-skills.yml", "skills/**"),
                         ("test-hooks.yml", "hooks/**"),
                         ("validate-examples.yml", "BestPractices/**")):
        f = workflow_filters(io.open(os.path.join(ROOT, WORKFLOW_DIR, name),
                                     encoding="utf-8").read())
        eq("parses %s and finds %r in push:" % (name, wanted),
           isinstance(f["push"], list) and wanted in f["push"], True)
    return bad


# --------------------------------------------------------------------------------------
def audit():
    """The always-on half, for scripts/test_hooks.py. -> (findings, notes, selftest_errors)"""
    errs = self_test(verbose=False)
    findings, notes = link2(verbose=False)
    return findings, notes, errs


def main(argv):
    if "--self-test" in argv:
        print("\nvalidate_ci_paths  parser unit tests\n")
        bad = self_test()
        for b in bad:
            print("  FAIL  %s" % b)
        print("\n{} failure(s)".format(len(bad)))
        return 1 if bad else 0

    findings, notes = [], []
    if "--trace" in argv:
        name = argv[argv.index("--trace") + 1]
        hit = [v for v in VALIDATORS if v.script == name]
        if not hit:
            print("not in VALIDATORS: %s" % name)
            return 2
        print("\nvalidate_ci_paths --trace  (link 1: declaration vs reality)\n")
        for v in hit:
            f, n = link1(v)
            findings += f
            notes += n
    else:
        print("\nvalidate_ci_paths  (link 2: every declared input is watched)\n")
        bad = self_test(verbose=False)
        for b in bad:
            findings.append(Finding("parserbug", "scripts/validate_ci_paths.py", None,
                                    "self-test", b))
        f, n = link2()
        findings += f
        notes += n

    print("")
    for n in notes:
        print("  note  %s" % n)
    for f in findings:
        print("  FAIL  %s" % f)
    print("\n{} failure(s)".format(len(findings)))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
