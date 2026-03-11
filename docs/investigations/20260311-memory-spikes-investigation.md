# P3: Recurring Transient Memory Spikes - March 11, 2026

## Status: Open — probable causes identified, not fully confirmed

## Summary

Production shows recurring brief memory spikes (seconds-long) from a ~512 MiB baseline up
to 830-960 MiB throughout the day. The spikes resolve on their own — no OOM kills, no
request errors, no restarts. Six spikes observed in a ~12 hour window.

At least 3 of 6 spikes correlate strongly with bot crawl bursts hitting `/place/*` pages
at 100+ requests/minute. The remaining 3 spikes occur during low/normal traffic and likely
have a different trigger (Litestream WAL operations being the leading candidate).

The database has grown to **147 MB** (4x since February), driven by the `page_views` table
which is 102 MB with indexes (567K rows, 35 days of unrolled data). This amplifies any I/O
operation's impact on OS page cache.

## Impact

- **Duration**: Each spike lasts ~15-30 seconds
- **Scope**: No user-visible impact — all requests served normally (200, <60ms)
- **Risk**: Peak of 960 MiB against 1024 MiB limit = 94% utilization. A larger burst
  could trigger OOM.

## Machine Info

- Machine: `7847515a205e68` (blue-dawn-7651)
- Size: `shared-cpu-2x:1024MB`
- Region: iad
- Release: v143 (deployed March 10 01:47 UTC)

## Timeline (all EDT = UTC-4)

| Time (EDT) | Time (UTC) | Peak MiB | Trigger |
|------------|------------|----------|---------|
| ~21:50 Mar 10 | ~01:50 | ~830 | `/place` crawl burst (108 /place reqs in 5 min) |
| ~00:45 Mar 11 | ~04:45 | ~720 | `/place` crawl burst (152 /place reqs in 5 min) |
| ~03:45 | ~07:45 | ~660 | Unknown — low traffic (30 req/min), no /place burst |
| ~08:20 | ~12:20 | ~896 | `/place` crawl burst (300 /place reqs in 3 min) |
| ~11:15 | ~15:15 | ~960 | Unknown — dip to 470 then spike. Low traffic (20-44 req/min) |
| ~11:50 | ~15:50 | ~908 | Unknown — normal traffic, no /place burst |

## Findings

### 1. Bot crawling /place pages at high rate (confirmed for 3/6 spikes)

During the 12:20 UTC spike, 300 `/place/*` pages were hit in 3 minutes — vs. 9 normally.
Multiple UAs from CloudFront IPs suggest a scraper rotating user agents:

- `Chrome/121.0.0.0 Edg/121.0.0.0` (132 requests from one IP)
- `Edg/121.0.0.0 AtContent/95.5.5392.49` — known scraping service suffix
- `Edg/121.0.0.0 Herring/95.1.1930.31` — same pattern
- `Bytespider` (TikTok's crawler)

The 01:50 and 04:45 UTC spikes show the same pattern at lower intensity (100-150 /place
requests per 5 min).

**Why /place pages?** Each request queries SQLite (places, place_hierarchy with recursive
CTEs, indexes). 100+ diverse place queries in quick succession would read many different
B-tree pages from the 147 MB database, filling the OS page cache.

### 2. Three spikes with no crawl correlation (undetermined)

The 07:45, 15:15, and 15:50 UTC spikes have normal/low HTTP traffic (20-35 req/min) with
no unusual request patterns. Leading candidate: **Litestream WAL operations**.

Litestream syncs WAL segments to S3 every 5 seconds. Periodically, it checkpoints the WAL
(reads WAL pages, writes to main DB file) and takes full snapshots (reads entire DB,
compresses, uploads). These operations cause significant disk I/O that would show in cgroup
memory as page cache growth.

Last Litestream snapshot: March 10 21:47 UTC (57 MB compressed). Next expected ~March 11
21:47 UTC (24h interval). The non-crawl spikes don't line up with the snapshot schedule,
but Litestream may trigger early checkpoints based on WAL offset accumulation.

### 3. page_views table is 70% of the database

| Table | Size (with indexes) | Rows |
|-------|-------------------:|-----:|
| page_views + indexes | 102 MB | 567K |
| gall_range + indexes | 8 MB | 139K |
| Everything else | 37 MB | — |
| **Total** | **147 MB** | — |

page_views spans Feb 4 - Mar 11 (35 days). The rollup's 90-day prune hasn't kicked in yet,
and the rollup still runs at 00:05 UTC (the fix to 07:00 UTC is on the current branch but
not deployed). The page_views table is growing by ~16K rows/day (~3 MB/day).

### 4. Existing rollup still blocking at 00:05 UTC

Confirmed by slow requests at exactly 00:05:21 UTC today — 9 requests with ~10,000ms
durations matching SQLite busy_timeout. Two requests returned 500 yesterday (March 10).
The schedule fix exists in the working branch but isn't deployed.

### 5. Why these spikes are different from prior OOMs

| Factor | Feb OOMs | Today's spikes |
|--------|----------|----------------|
| Duration | Gradual or step-function, persistent | Seconds-long, fully recovers |
| Cause | BEAM driver_alloc carrier retention | OS page cache (cgroup accounting) |
| Trigger | Page cache ceiling (625 MB) | Bot crawl bursts + Litestream I/O |
| Risk | Certain OOM | Near-miss (960 of 1024 MiB) |

## What We Ruled Out

- **Deploy**: No deploys today, v143 since March 10
- **Machine events**: No restarts, no OOM kills
- **Admin activity**: User browsing admin gall pages, but fast requests only
- **Analytics rollup**: Runs at 00:05 UTC, spikes occur throughout the day
- **LiveView accumulation**: Fixed in Feb with hibernate_after + pagination
- **Page cache setting**: cache_size = -2000 (2 MB/connection, 20 MB total) — correct

## Root Cause Assessment

**Probable (not confirmed):** Two overlapping causes:

1. Bot crawl bursts (especially `/place/*`) cause rapid disk I/O that fills the OS page
   cache, which is counted in the cgroup memory metric. When the kernel reclaims the cache,
   the metric drops.

2. Litestream WAL operations (checkpoints, possibly snapshot prep) cause similar transient
   I/O spikes during low-traffic periods.

Both are amplified by the 147 MB database size (4x since February), primarily due to
the unrolled `page_views` table.

**What would confirm this:** Memory telemetry that separates BEAM RSS from OS page cache.
The BEAM's `:erlang.memory()` would show stable usage during these spikes if the cause is
page cache. This data isn't currently collected.

## Recommendations

### Immediate risk reduction

1. **Deploy rollup fixes** (matter c52c) — move schedule to 07:00 UTC, split transactions.
   The nightly 00:05 UTC block is a separate confirmed problem.

2. **Prune page_views manually** — The table is 102 MB / 567K rows with 35 days of data.
   Running `Gallformers.Analytics.Rollup.prune_old_page_views(30)` would delete ~5 days of
   already-rolled-up data, reducing the table by ~15%.

3. **Rate limit /place pages for bot traffic** — The scraper hitting 300+ /place pages in
   3 minutes is the most common spike trigger. Even basic rate limiting (e.g., 60 req/min
   per IP path prefix) would prevent the bursts.

### Observability improvements

4. **Add memory breakdown to telemetry** — Expose `:erlang.memory()` (BEAM-only) alongside
   the cgroup metric so we can distinguish BEAM growth from page cache.

5. **Log Litestream operations** — Check if Litestream verbose logging can surface
   checkpoint/snapshot events with timestamps to correlate with spikes.

### Longer term

6. **Consider `memory.memsw.max_usage_in_bytes` vs `memory.usage_in_bytes`** — If Fly.io
   or Grafana can report RSS-only (without page cache), the spikes would likely disappear
   from the dashboard.

## What We Still Don't Know

1. Whether the spikes are truly page cache (would need BEAM-level memory telemetry to
   confirm BEAM RSS stays flat during spikes)
2. What specifically triggers the non-crawl spikes (Litestream checkpoint timing, or
   something else entirely)
3. Whether these spikes have ever caused OOM (the 960 MiB peak is very close to the 1024
   MiB limit)

## Related

- [20260310 - Analytics Rollup Blocking](20260310-brief-outage-response-spike.md)
- [20260309 - 90-Minute Unresponsive Outage](20260309-unresponsive-crash-cpu-investigation.md)
- [20260220 - OOM driver_alloc Fragmentation](20260220-oom-driver-alloc-fragmentation.md)
- Matter c52c — Analytics rollup fixes
- Matter 220d — Rate limiting for all routes
- Matter cd9d — Observability and metrics infrastructure
