#!/usr/bin/env python3
"""Snapshot GitHub traffic (clones/views) into a permanent per-day history.

GitHub's traffic API only retains a rolling 14-day window and there is no
all-time counter. This script — run daily by
.github/workflows/traffic-snapshot.yml — fetches the current window and
merges it into per-day history files (clones.json / views.json, kept on the
`traffic-data` branch), so the cumulative numbers survive forever.

Merge rule: upsert by date, keeping max(count) per day — the API revises the
current (partial) day upward, so max() is idempotent across overlapping runs.

Requires TRAFFIC_TOKEN: a PAT able to read repo traffic (classic: `repo`
scope; fine-grained: Administration read-only on this repo). The default
Actions GITHUB_TOKEN cannot read the traffic endpoints.

Usage: traffic_snapshot.py <data-dir>
"""
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

REPO = os.environ.get("GITHUB_REPOSITORY", "intersystems-ib/iris-interop-skills")
TOKEN = os.environ.get("TRAFFIC_TOKEN")


def fetch(kind):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/traffic/{kind}",
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def merge(path, rows):
    try:
        with open(path) as f:
            hist = json.load(f)
    except FileNotFoundError:
        hist = {"days": {}}
    days = hist["days"]
    for row in rows:
        day = row["timestamp"][:10]
        prev = days.get(day, {"count": 0, "uniques": 0})
        days[day] = {
            "count": max(prev["count"], row["count"]),
            "uniques": max(prev["uniques"], row["uniques"]),
        }
    hist["days"] = dict(sorted(days.items()))
    hist["total_count"] = sum(d["count"] for d in days.values())
    # Uniques dedupe only within one day; summing them is an upper bound.
    hist["daily_uniques_sum"] = sum(d["uniques"] for d in days.values())
    hist["updated_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with open(path, "w") as f:
        json.dump(hist, f, indent=2)
        f.write("\n")
    return hist


def main():
    if not TOKEN:
        sys.exit(
            "TRAFFIC_TOKEN is not set. Create a PAT that can read repo traffic "
            "(classic: repo scope / fine-grained: Administration read) and add "
            "it as an Actions secret named TRAFFIC_TOKEN."
        )
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "traffic-data"
    for kind in ("clones", "views"):
        data = fetch(kind)
        hist = merge(os.path.join(data_dir, f"{kind}.json"), data.get(kind) or [])
        print(
            f"{kind}: all-time {hist['total_count']} "
            f"(≤{hist['daily_uniques_sum']} uniques, {len(hist['days'])} days tracked)"
        )


if __name__ == "__main__":
    main()
