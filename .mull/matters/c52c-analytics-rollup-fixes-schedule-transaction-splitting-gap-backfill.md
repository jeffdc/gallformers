---
status: refined
created: 2026-03-10
updated: 2026-03-10
epic: platform
relates: [be9d]
---

# Analytics rollup fixes — schedule, transaction splitting, gap backfill

## Context

Investigation: `docs/investigations/20260310-brief-outage-response-spike.md`

The `Analytics.Rollup` GenServer caused nightly ~30-45s outages at 00:05 UTC (8:05 PM ET)
by holding a SQLite write lock during prime-time traffic. Confirmed recurring on March 10
and March 11 via request logs. Also likely contributed to the March 9 90-minute outage
(separate investigation).

## Already Done

- Moved schedule from 00:05 UTC to 07:00 UTC (3 AM ET) — eliminates user-visible impact

## Remaining Work

### 1. Break the single large transaction
`rollup_day/1` wraps all 5 summary table operations in one `Repo.transaction`. Each
DELETE/INSERT cycle should be its own mini-transaction to minimize lock duration.

### 2. Yield between days
`rollup_pending_days/0` processes all pending days in a tight `Enum.reduce`. Add a
`Process.sleep` or similar yield between days so the BEAM scheduler and SQLite can
breathe between batches.

### 3. Backfill March 1 gap
`daily_stats` is missing 2026-03-01 (11,029 raw page_views exist). Current
`next_pending_date/0` uses `MAX(date) + 1` so it will never revisit the gap.
Options:
- Add a `backfill_gaps/0` that scans for missing dates
- Or fix `next_pending_date/0` to find the first gap instead of just the max
- One-off: call `Rollup.rollup_day(~D[2026-03-01])` on prod

### 4. Prune separately
`prune_old_page_views/0` runs immediately after rollup — another heavy DELETE.
Move it to its own scheduled time or at least add a delay after rollup completes.

## Key numbers
- `page_views`: 521K rows
- Daily volume: 10-25K rows
- `busy_timeout`: 10,000ms (config/runtime.exs line 84)
- `pool_size`: 10 (production)
- WAL autocheckpoint: 1000 pages (default)

