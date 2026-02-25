# Analytics Compaction Design

**Matter**: 9423 — Compact analytics data (largest table, unbounded growth)
**Date**: 2026-02-24

## Problem

The `page_views` table grows at ~13,700 rows/day (~1 MB/day) and is already 29% of the database after 2 weeks. The 30-day analytics view takes multiple seconds to render at ~20 days of data because all queries scan raw rows.

## Design

### Summary Tables

Five new tables, created via Ecto migration:

| Table | Columns | ~Rows/day |
|-------|---------|-----------|
| `daily_stats` | date, page_views, unique_visitors | 1 |
| `daily_page_stats` | date, path, page_views, unique_visitors | 100-200 |
| `daily_referrer_stats` | date, referrer_host, page_views | 20-30 |
| `daily_device_stats` | date, device_type, count | 3 |
| `daily_browser_stats` | date, browser, count | 8-10 |

All tables have a unique index on their natural key (date + dimension) and an index on date for range queries. ~250 summary rows/day vs ~13,700 raw rows (55x reduction).

### Rollup Job

`Gallformers.Analytics.Rollup` GenServer, supervised in `application.ex`:

- On startup: backfill any un-rolled-up past days
- Schedules nightly via `Process.send_after` for shortly after midnight UTC
- Aggregates each completed day from `page_views` into summary tables
- Idempotent: uses `INSERT OR REPLACE` so re-running is safe
- Also prunes raw `page_views` older than 90 days

### Query Changes

- **"Today"**: unchanged, queries raw `page_views` (one day, always small)
- **"7d", "30d", "90d"**: rewritten to query summary tables
- Each multi-day query combines summary data for past days + raw data for today
- Functions affected: `daily_stats/2`, `top_pages/2`, `top_referrers/2`, `device_breakdown/2`, `browser_breakdown/2`

### Retention

- Raw `page_views`: 90-day rolling window, older rows deleted nightly
- Summary tables: kept indefinitely (tiny footprint)

### Unchanged

- LiveView UI (no template changes)
- Tracking pipeline (`track_page_view/1`)
- `PageView` schema
