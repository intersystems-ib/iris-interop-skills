#!/bin/sh
# PostToolUse conformance pre-scan for Write|Edit (iris-interop-skills) — when an interop
# .cls is written, cheaply screen that file for the mechanically-detectable anti-patterns
# (CR-1/2/4/5/7/10) and, if any match, nudge to run the conformance-reviewer agent. Thin
# wrapper: exec the .py so the hook JSON on stdin reaches Python. Resolves the interpreter
# as python3 -> python -> py (Windows has no real `python3`, only a Store stub that must be rejected); no-op if none is on PATH. Never blocks.
PY=
for _cand in python3 python py; do
    _path=$(command -v "$_cand" 2>/dev/null) || continue
    # Being on PATH is not the same as working. Windows ships a 0-byte Microsoft Store
    # stub named python3.exe in %LOCALAPPDATA%\Microsoft\WindowsApps: `command -v` finds
    # it, exec'ing it prints "Python was not found" and exits non-zero. Taking the first
    # name that resolves made every hook fail on a machine that had a perfectly good
    # python.exe one PATH entry away. Run the candidate before trusting it.
    "$_path" -c '' >/dev/null 2>&1 || continue
    PY=$_path
    break
done
[ -n "$PY" ] || exit 0
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$PY" "$DIR/conformance_prescan.py"
