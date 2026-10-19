#!/usr/bin/env python3
"""Record, at RUNTIME, every repo file a validator actually reads.

WHY THIS IS NOT A GREP. The CI path filters have now been wrong three times in this repo's
history, and every time a human noticed:

  * 1.15.1 added the issue-fingerprint step to test-hooks.yml while the filter still listed
    only `hooks/**` — fixed in 1.16.0, see the comment still standing in that workflow.
  * #418 found validate-skills.yml blind to 5 of its inputs and validate-examples.yml blind
    to 94 of its tier-1 inputs.
  * #421 fixed those two workflows and reported "0 unwatched now" with no population. The
    same measurement over test-hooks.yml was 268 unwatched, before AND after, because
    test-hooks.yml was never one of the two files it looked at.

A static deriver (grep for `open(`, expand the globs you find) fails in the one direction
that matters: when it stops recognising a call site it returns a SMALLER set and reports "0
unwatched". That is the clean zero this repo keeps getting bitten by.

So the derivation runs the validator and watches the interpreter. `sys.addaudithook` sees
`open`, `os.listdir` and `os.scandir` whoever makes the call — including from a subprocess,
because the child inherits PYTHONPATH and loads this module through a generated
`sitecustomize`. That is how all 154 processes `scripts/test_hooks.py` spawns get counted.

THE ONE BLIND SPOT, AND WHY IT IS COVERED BY A SECOND MECHANISM
    `os.stat` raises NO audit event. Measured on CPython 3.13.11: an audit hook that counts
    every event fired by `os.path.isdir()`, `os.path.isfile()`, `os.stat()` and `os.lstat()`
    sees exactly zero, while the same hook sees `os.listdir`, `os.scandir` and `open` fire
    once each. So an audit hook alone CANNOT see a stat-only input — and this repo has two
    that matter, both in test_hooks.py: the `os.path.isdir(ROOT/skills/<n>)` sweep over the
    16 router topics, and the `os.path.isfile(ROOT/skills/ccr-workflow/SKILL.md)` existence
    check. Renaming either subject fails the suite while opening nothing.

    An `open`-only trace therefore understates, which is the failure direction this whole
    module exists to avoid. The second mechanism is a pass-through shim over `os.stat` and
    `os.lstat`, installed only while tracing. `os.path.isdir`, `isfile` and `exists` all
    reach `os.stat` through the `os` module global, so the shim sees them; it forwards every
    argument and both the return value and the exception unchanged.

CONTRACT
    Importing this module is a NO-OP unless $IIS_INPUT_AUDIT_LOG is set. A validator's
    behaviour must not depend on whether it is being traced, so there is nothing written to
    stdout or stderr ever — a traced hook still has to emit parseable JSON — and every hook
    body is wrapped so a bug in here cannot fail a validator.

    With the variable set, one tab-separated line is appended per newly seen repo path:

        <kind>\t<repo-relative path>\t<attributing frame>

    `kind` is `file` or `dir`. The attributing frame is the innermost stack frame whose code
    lives in the repo, so a report can name `scripts/test_hooks.py:1314` rather than
    "something read this". It is `?` for a path the interpreter touched before any repo
    frame existed — a child process reading its own main script, which is a real input.

    Dedup is per process, so the reader must dedup across lines: 154 children each log their
    own main script.

WHAT IS DELIBERATELY DROPPED, and why each would otherwise be a false input
    write-mode opens        an output is not an input
    non-existent paths      the hook fires BEFORE the call, so a probe for a missing
                            `.claude/iis-scm` would otherwise be recorded as an input
    .git/ and __pycache__   not source
    the repo root itself    every relative-path resolution touches it
    sys.path directories    the import machinery stats and scans its own search dirs, so
                            `scripts/` would otherwise be a directory input of every
                            validator and demand a `scripts/**` filter nothing reads
"""
import os
import sys

_LOG = os.environ.get("IIS_INPUT_AUDIT_LOG")

# Two spellings of the root, so the fast reject needs no realpath: the raw path from
# __file__, and its realpath. On macOS a scratch dir lives under /private/tmp while $TMPDIR
# says /tmp, and a single spelling silently drops half the events.
_ROOT_RAW = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ROOT = os.path.realpath(_ROOT_RAW)
_PREFIXES = tuple(sorted({_ROOT_RAW + os.sep, _ROOT + os.sep}))

# `os.stat` is NOT in this list because CPython does not raise an audit event for it; the
# shim at the bottom of this file covers stat instead. See the module docstring.
_EVENTS = ("open", "os.listdir", "os.scandir")

# True while the hook body runs. os.path.realpath and os.path.isdir call os.stat, which the
# shim records, which would re-enter the hook until the stack blew.
_busy = False
_decided = {}
_fh = None
_SELF = os.path.basename(__file__)


def _attribute(depth):
    """The innermost TWO repo frames, `callee<-caller`, or '?'.

    Anchored to the repo, so stdlib frames (io, glob, genericpath, importlib) are skipped,
    and to code other than this module, so the trace never blames the tracer.

    Two frames and not one, because the innermost repo frame is often a shared helper and
    naming it alone hides the assertion. `hooks/iis_scope.py:145` is where the walk happens;
    `scripts/test_hooks.py:1425` is the check that cares, and that is the one a reader needs.
    """
    try:
        f = sys._getframe(depth)
    except ValueError:
        return "?"
    found = []
    while f is not None and len(found) < 2:
        name = f.f_code.co_filename
        if os.path.basename(name) not in (_SELF, "sitecustomize.py") \
                and name.startswith(_PREFIXES):
            found.append("%s:%d" % (os.path.relpath(name, _ROOT), f.f_lineno))
        f = f.f_back
    return "<-".join(found) if found else "?"


def _record(kind, real):
    global _fh
    if _fh is None:
        # Opened lazily and line-buffered. A validator that spawns 150 children must not
        # lose a killed child's lines, and an atexit flush would lose exactly those.
        _fh = open(_LOG, "a", buffering=1, encoding="utf-8")
    _fh.write("%s\t%s\t%s\n" % (kind, os.path.relpath(real, _ROOT), _attribute(3)))


def _note(path, write_mode=False):
    """Classify and maybe record one candidate path. Returns nothing; never raises."""
    global _busy
    if _busy:
        return
    # An int is an already-open fd and bytes paths are used by no validator here. Rejecting
    # by type first keeps the hot path to one isinstance for the thousands of import-time
    # events whose path is a stdlib directory.
    if not isinstance(path, str) or not path:
        return
    if write_mode:
        return
    _busy = True
    try:
        real = path if os.path.isabs(path) else os.path.join(os.getcwd(), path)
        if not real.startswith(_PREFIXES):
            return
        real = os.path.realpath(real)
        if not real.startswith(_PREFIXES):
            return
        if real in _decided:
            return
        probe = real + os.sep
        if os.sep + ".git" + os.sep in probe or os.sep + "__pycache__" + os.sep in probe:
            _decided[real] = None
            return
        if os.path.isdir(real):
            # A sys.path entry is searched by the import machinery, not by the validator.
            if any(os.path.realpath(p) == real for p in sys.path if p):
                _decided[real] = None
                return
            _decided[real] = "dir"
            _record("dir", real)
        elif os.path.isfile(real):
            _decided[real] = "file"
            _record("file", real)
        # Anything else does not exist. NOT marked decided: the event fires before the call,
        # and a file this run creates is a genuine input the next time it is touched.
    except Exception:
        pass
    finally:
        _busy = False


def _hook(event, args):
    if event not in _EVENTS:
        return
    if event == "open":
        mode = args[1]
        _note(args[0], write_mode=isinstance(mode, str) and any(c in mode for c in "wax+"))
    else:
        _note(args[0])


def _install_stat_shim():
    """Pass-through wrappers that record what `os.stat`/`os.lstat` are asked about.

    Pure forwarding: every positional and keyword argument goes through untouched, the
    return value is returned, and an exception propagates. The recording happens BEFORE the
    call for the same reason the audit hook fires before the call — a FileNotFoundError is
    still a question asked about a path — and `_note` then drops the path because it does
    not exist, which is what keeps a probe for a missing file out of the input set.
    """
    real_stat, real_lstat = os.stat, os.lstat

    def stat(path, *a, **kw):
        _note(path)
        return real_stat(path, *a, **kw)

    def lstat(path, *a, **kw):
        _note(path)
        return real_lstat(path, *a, **kw)

    os.stat, os.lstat = stat, lstat


if _LOG:
    sys.addaudithook(_hook)
    _install_stat_shim()
