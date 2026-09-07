#!/usr/bin/env python3
"""PostToolUse non-Docker hint (iris-interop-skills, C4).

When an interop tool returns DOCKER_REQUIRED, the instance is native/remote — the fixed tools
(iris_production, iris_test, lookup/credential) work over the HTTP/Atelier path. Surface a one-time
note so the model retries over HTTP instead of giving up or re-trying with a container. Advisory only.
"""
import sys, json

# Stable marker (#162): prepended, never woven into the prose, so a reword cannot
# switch a corpus detector off. One grep for `[IIS-` finds every gate and guard.
MARKER = "[IIS-DOCKER] "


def payload(r):
    if isinstance(r, str):
        try:
            return json.loads(r)
        except Exception:
            return {}
    if isinstance(r, list):
        for b in r:
            if isinstance(b, dict) and isinstance(b.get("text"), str):
                try:
                    return json.loads(b["text"])
                except Exception:
                    pass
        return {}
    return r if isinstance(r, dict) else {}


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    resp = data.get("tool_response", data.get("tool_output", {}))
    p = payload(resp)
    if str(p.get("error_code", "")).upper() == "DOCKER_REQUIRED":
        msg = (
            "This IRIS is native/remote (no Docker container). The interop tools run over the "
            "HTTP/Atelier path — iris_production, iris_test, and the lookup/credential tools no longer "
            "need a container. Retry WITHOUT IRIS_CONTAINER; set it only if IRIS actually runs in Docker."
        )
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": MARKER + msg}}))


if __name__ == "__main__":
    main()
