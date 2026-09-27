#!/usr/bin/env python3
"""Which directories count as "on disk" — shared by the three hooks that ask (#401).

WHY THIS EXISTS. `src_before_iris.on_disk`, `src_drift_guard.disk_path` and
`conformance_stop_gate.classes_on_disk` each walked the WHOLE project and accepted a match
anywhere in it. Found while rehearsing a live demo (5 timed runs, 2026-09-27): that project
keeps a reset seed beside `src/` — `seed/diet/Diet/BO/Login.cls` — to restore a namespace
between runs, and all three hooks were satisfied by the seed copy:

  - a class built live and put with iris_doc(mode=put) passed the disk-first gate with
    nothing written to `src/` at all;
  - [IIS-DRIFT] told the model to write the class to `seed/diet/...` rather than `src/`;
  - the Stop gate's CR-12 counted the seed copy as on disk.

The project's CLAUDE.md ended up telling the model to disregard the drift messages. A gate
whose own project documents it as a false positive is off, whatever its exit code says.

ONE AXIS ONLY: the SCOPE of the walk. How a match is DECIDED is left to each caller and is
deliberately not unified here — `conformance_stop_gate` decides presence by the class name
declared INSIDE the file, because this plugin's own bank names files by topic
(`dtl-order-to-vendor.cls` defines `Example.DT.OrderToVendor`) and a path-only check called
25 of 25 real classes missing. Narrowing the scope preserves that; unifying the match would
have broken it.

NON-REGRESSION, and it is the reason this is safe to ship: `source_roots()` falls back to the
project root when no `src/` exists, so a project laid out any other way behaves exactly as
before. This plugin's own repo has no `src/` — its bank lives under `BestPractices/examples/`
— so every existing example keeps resolving. test_hooks.py asserts that.

TWO OPTIONAL PROJECT FILES, both plain text, one entry per line, `#` comments, blank lines
ignored. Neither is required and neither exists by default:

    .claude/iis-source-roots   directories to treat as source roots, overriding the `src/`
                              search. For a project whose sources are in `app/cls/`.
    .claude/iis-ignore        fnmatch globs, relative to the project root, of directories
                              to skip. `seed` and `seed/*` both exclude `seed/` entirely.

.gitignore is deliberately NOT consulted. A seed or fixture directory is usually COMMITTED,
so it is not in .gitignore, so honouring .gitignore would not have fixed the case that
prompted this. An explicit list is also predictable — no negations, no nested files, no
precedence rules to get subtly wrong.
"""
import fnmatch
import glob
import os

# Directories never worth walking. Kept here so the three hooks cannot drift apart on it.
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".idea", ".vscode"}

SOURCE_ROOTS_FILE = os.path.join(".claude", "iis-source-roots")
IGNORE_FILE = os.path.join(".claude", "iis-ignore")


def _config_lines(root, relpath):
    """Non-empty, non-comment lines of a project config file, or [] if absent/unreadable.

    Unreadable is treated as absent on purpose: a hook must never fail because a project
    shipped a malformed dotfile. The cost of ignoring it is the previous behaviour.
    """
    try:
        with open(os.path.join(root, relpath), encoding="utf-8", errors="replace") as fh:
            out = []
            for line in fh:
                line = line.split("#", 1)[0].strip()
                if line:
                    out.append(line)
            return out
    except OSError:
        return []


def ignore_globs(root):
    """fnmatch patterns, project-relative, naming directories to skip."""
    return _config_lines(root, IGNORE_FILE)


def source_roots(root):
    """Directories to search when asking "does this class have a file?".

    Precedence, first hit wins:
      1. `.claude/iis-source-roots`, for a project whose sources are not under `src/`.
      2. every directory named `src` down to depth 3 — the layout the `interop` skill
         mandates (`src/<Pkg>/<Tipo>/<Name>.cls`) and the one the bootstrap tells the model
         to write. Depth 3 covers a monorepo (`services/orders/src`).
      3. the project root, unchanged from before this file existed.

    Returned paths are absolute and de-duplicated, outermost first.
    """
    declared = []
    for entry in _config_lines(root, SOURCE_ROOTS_FILE):
        cand = os.path.normpath(os.path.join(root, entry))
        if os.path.isdir(cand):
            declared.append(cand)
    if declared:
        return _dedup(declared)

    found = []
    for depth in range(4):
        pattern = os.path.join(root, *(["*"] * depth), "src")
        for d in sorted(glob.glob(pattern)):
            if os.path.isdir(d) and os.path.basename(d) not in SKIP_DIRS:
                found.append(os.path.normpath(d))
    if found:
        return _dedup(found)

    return [os.path.normpath(root)]


def _dedup(paths):
    seen, out = set(), []
    for p in paths:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def scoped(root):
    """True when source_roots() actually narrowed anything.

    False means the walk covers the whole project, i.e. the pre-#401 behaviour, so a caller
    must not claim a file is "outside the source root" — there is no source root to be
    outside of.
    """
    roots = source_roots(root)
    return not (len(roots) == 1 and roots[0] == os.path.normpath(root))


def walk_files(root, exts=(".cls",), whole_project=False):
    """Yield every file under the scoped source roots whose name ends in one of `exts`.

    `whole_project=True` ignores the source roots and walks everything, which is how a
    caller produces the "the file exists, but not where it belongs" diagnostic. The ignore
    list still applies — an ignored directory is out of scope for every question.

    os.walk rather than glob("**"): glob silently skips dot-directories, so a class staged
    under one reads as missing and the gate denies a file that is right there (#95).
    """
    root = os.path.normpath(root)
    globs = ignore_globs(root)
    bases = [root] if whole_project else source_roots(root)
    exts = tuple(e.lower() for e in exts)

    for base in bases:
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames
                           if d not in SKIP_DIRS
                           and not _ignored(root, os.path.join(dirpath, d), globs)]
            for fn in filenames:
                if fn.lower().endswith(exts):
                    yield os.path.join(dirpath, fn)


def _ignored(root, path, globs):
    """True when `path` matches an entry in .claude/iis-ignore.

    A bare `seed` excludes the directory AND everything under it, which is what someone
    writing one line in an ignore file means. Requiring `seed/**` as well would be a trap.
    """
    if not globs:
        return False
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    for pat in globs:
        pat = pat.rstrip("/")
        if fnmatch.fnmatch(rel, pat) or rel.startswith(pat + "/"):
            return True
        # `seed/*` should also exclude `seed` itself, or the glob only bites one level down.
        if pat.endswith("/*") and (rel == pat[:-2] or rel.startswith(pat[:-2] + "/")):
            return True
    return False


def conventional_path(root, cls):
    """Where a missing class SHOULD be written: <first source root>/<Pkg>/<Tipo>/<Name>.cls.

    This is the other half of #401. The old remedy text was built from wherever a file
    happened to be found, so once the seed copy matched, the guard told the model to write
    into `seed/`. Deriving it from the source root instead means the advice points at the
    tree the rule is about, whether or not a stray copy exists.
    """
    root = os.path.normpath(root)
    roots = source_roots(root)
    base = roots[0] if roots else root
    rel = os.path.relpath(base, root).replace(os.sep, "/")
    # No source root found means greenfield, NOT "put it at the project root". The rule the
    # gate enforces is "write src/<Pkg>/<Tipo>/<Name>.cls FIRST", and it holds before the
    # directory exists -- that is the whole point of gating the first put (#107). Returning
    # a bare `Demo/BO/Login.cls` here would have the gate teach the wrong layout.
    prefix = "src/" if rel in (".", "") else rel + "/"
    return prefix + cls.replace(".", "/") + ".cls"
