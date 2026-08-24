# traffic-data

Permanent per-day history of this repo's GitHub traffic (clones ≈ plugin
installs, plus page views). GitHub's traffic API only retains a rolling
14-day window; the `traffic-snapshot` workflow on `main` runs daily and
merges each window into these files so the cumulative numbers survive.

- `clones.json` / `views.json` — `days` maps `YYYY-MM-DD` → `{count, uniques}`.
  `total_count` is the all-time sum. `daily_uniques_sum` is an **upper bound**
  on unique users (GitHub dedupes uniques per day only; the same user on two
  days counts twice).
- History starts 2026-08-10 (earliest day still in the API window when
  tracking began on 2026-08-24). Anything before that is unrecoverable.

Maintained by `.github/workflows/traffic-snapshot.yml` +
`scripts/traffic_snapshot.py` on `main`. Do not edit by hand — the merge
takes `max()` per day, so manual edits below the API's values are overwritten.
