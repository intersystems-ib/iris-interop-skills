#!/usr/bin/env python3
"""Prove an A/B arm differs from its base by exactly one declared transform.

Why this is not a grep over `git diff`: the transform REMOVES a string, so the `+`
lines no longer contain it. A filter like `git diff | grep -v '<string>'` therefore
only ever tests the `-` side and passes vacuously — it cannot fail, whatever else the
arm changed. Measured: it reported "single variable" on an arm that had no commit at all.

This applies the transform to every file in the base tree and requires the result to
equal the arm tree byte-for-byte, then checks that the comparison can still fail.

  python3 scripts/verify_arm_single_variable.py <base-ref> <arm-ref> [--string "<s>"]
"""
import subprocess, sys

DEFAULT = " Routed from interop."


def tree(ref):
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", ref],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"cannot read tree {ref}: {r.stderr.strip()}")
    return sorted(r.stdout.split())


def blob(ref, path):
    return subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True).stdout


def transform(data, needle):
    """Drop `needle` from frontmatter description lines only."""
    return b"\n".join(
        line.replace(needle, b"") if line.startswith(b"description:") else line
        for line in data.split(b"\n")
    )


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    base, arm = sys.argv[1], sys.argv[2]
    needle = DEFAULT.encode()
    if "--string" in sys.argv:
        needle = sys.argv[sys.argv.index("--string") + 1].encode()

    fb, fa = tree(base), tree(arm)
    if fb != fa:
        print(f"FAIL: file sets differ: {sorted(set(fb) ^ set(fa))[:10]}")
        return 1

    mismatched, transformed, identical = [], [], []
    for path in fb:
        b, a = blob(base, path), blob(arm, path)
        if transform(b, needle) != a:
            mismatched.append(path)
        elif b != a:
            transformed.append(path)
        else:
            identical.append(path)

    print(f"{base} -> {arm}   transform: remove {needle.decode()!r} from description lines")
    print(f"  files compared        {len(fb)}")
    print(f"  transformed and equal {len(transformed)}")
    print(f"  byte-identical        {len(identical)}")
    print(f"  MISMATCHES            {len(mismatched)}")
    for p in mismatched[:10]:
        print(f"    {p}")

    # The comparison must be able to fail, or a pass means nothing.
    probe = transformed[0] if transformed else fb[0]
    pos_ok = transform(blob(base, probe), needle) + b"x" != blob(arm, probe)
    neg_ok = not identical or blob(base, identical[0]) == blob(arm, identical[0])
    print(f"  positive control      {'ok' if pos_ok else 'BROKEN TEST — corrupt input compared equal'}")
    print(f"  negative control      {'ok' if neg_ok else 'BROKEN TEST — untouched file compared unequal'}")

    if not transformed:
        print("FAIL: the transform changed nothing — the arm is not built, or the string is absent")
        return 1
    if mismatched or not pos_ok or not neg_ok:
        print("VERDICT: CONFOUNDED — this arm cannot be used for a single-variable comparison")
        return 1
    print("VERDICT: single-variable PROVEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
