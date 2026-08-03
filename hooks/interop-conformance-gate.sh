#!/bin/sh
# PreToolUse conformance GATE for iris_doc|iris_compile (iris-interop-skills) — BLOCKS a write/compile
# that violates a hard naming/superclass convention (non-standard .Tipo. segment, or a BS/BO that
# extends the adapter directly), forcing a fix before the class lands. Thin wrapper: exec the .py so
# the hook JSON on stdin reaches Python. Resolves python3 -> python -> py (Windows has no real `python3`, only a Store stub that must be rejected);
# if no interpreter is on PATH, exit 0 (allow) — never block legitimate work on a missing interpreter.
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
exec "$PY" "$DIR/interop_conformance_gate.py"
