#!/bin/sh
# PostToolUse TDD guard for Write|Edit (iris-interop-skills) — reminds to write the
# test first when an interop component class is written without a sibling *Test*.cls.
# Thin wrapper: exec the .py so the hook JSON on stdin reaches Python. Resolves the
# interpreter as python3 -> python -> py (Windows has no real `python3`, only a Store stub that must be rejected); no-op if none is
# on PATH. Never blocks.
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
exec "$PY" "$DIR/tdd_enforcement.py"
