---
status: done
effort: 1 day
created: 2026-02-18
updated: 2026-02-24
epic: platform
docs: [docs/plans/completed/2026-02-24-analytics-compaction-design.md, docs/plans/completed/2026-02-24-analytics-compaction.md]
---

# Compact analytics data (largest table, unbounded growth)

The analytics table is the largest table in the database and grows without bound. Investigate compaction strategies — rolling up old rows into summary aggregates, pruning raw data after N days, archiving to S3, or switching to a time-bucketed schema. Not urgent but will become a problem at scale.

## Rollup Plan (2026-02-18)

### Current state
- ~192k rows over 14 days (~13,700/day, ~1 MB/day)
- page_views is 29% of the entire DB after just 2 weeks
- 3 indexes add additional overhead
- UI gets slow on 30/90 day views — all queries scan raw rows

### Design: multiple summary tables + retention window

**Summary tables** (rolled up daily):
- `daily_stats` — date, page_views, unique_visitors (1 row/day)
- `daily_page_stats` — date, path, page_views, unique_visitors (~100-200 rows/day)
- `daily_referrer_stats` — date, referrer_host, page_views (~20-30 rows/day)
- `daily_device_stats` — date, device_type, count (3 rows/day)
- `daily_browser_stats` — date, browser, count (~8-10 rows/day)

~250 summary rows/day vs ~13,700 raw rows/day (55x reduction).

**Query strategy — always-rollup**:
- Nightly GenServer job rolls up each completed day into summary tables
- All multi-day queries (7d, 30d, 90d) hit summary tables — consistently fast at any range
- "Today" view still queries raw page_views (always small, one day of data)

**Retention**:
- Raw page_views: keep 90 days rolling, delete older
- Summary tables: keep indefinitely (tiny footprint)

**UI impact**: None. All current views (daily chart, top pages, top referrers, devices, browsers) work identically against summary tables. Unique visitors for top pages in multi-day ranges remain sum-of-daily-uniques (matches existing behavior and disclaimer).

**Rollup job**: Simple GenServer with Process.send_after, runs once daily after midnight UTC. No Oban needed (requires Postgres). If Postgres migration happens later, could move to Oban.
