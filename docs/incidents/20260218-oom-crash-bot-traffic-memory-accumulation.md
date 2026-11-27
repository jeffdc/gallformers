# P2: OOM Crash & Bot Traffic Analysis - February 18, 2026

## Status: Open — Mitigations deployed, codebase investigation complete, fixes planned

**Status (2026-11-27):** Closed. Landed on `main` on 2026-02-18: LiveView `hibernate_after: 5_000` (in `config/config.exs`, not `endpoint.ex`) and server-side pagination of the admin lists (matter 8ae6, dcf299a8); the AuditCache rework, with scans on demand only, `hibernate_after` and `new_paths ++ acc` in `list_gall_paths_recursive` (matter ee67, 6b7e8fb2); on `taxogall` AuditCache is gone from `lib/` with the old admin (a075e07a). Matter 9ad7 converted Privacy, Filter Guide, Articles, Article and About to controllers (3d5a8f28, #528, 2026-03-09), and `/explore` now redirects. The 1GB VM rejected here landed two days later (`fly.toml`, 7a2032c3). Not landed: the Gall, Host, Source, Place, ID and home pages are still LiveViews (docs/backlog.md, "Convert read-only LiveView pages to controllers where it pays"); live memory telemetry (`telemetry.ex` has no reporter; docs/backlog.md, "Error tracking and alerting").

## Summary

Production experienced an OOM kill at ~10:58 UTC (5:58 AM ET) on Feb 18 — the second OOM
in 3 days. Request log analysis reveals all HTTP responses completing in <407ms right up to
the crash, meaning the OOM is from gradual memory accumulation over the application's
lifetime, not from individual request pressure.

65% of all HTTP traffic is bots. 33% is from SEO analysis crawlers providing no value to
the site. A vulnerability scanner also contributed a 428 req/min burst.

Fly Edge Response Time graphs show a gradual increase in edge latency over several hours
leading up to the crash, confirming the app was progressively degrading at the connection
acceptance level even while individual requests remained fast. This is survivorship bias in
the request logs — only requests that completed get logged; requests timing out at the proxy
are invisible.

A live memory graph captured during the investigation shows the machine at 399/459 MiB
(87% utilization) with a ~70 MiB step-function allocation at ~11:00 ET — indicating the
machine is already approaching another OOM.

## Impact

- **OOM restart**: ~60 second outage at ~10:58 UTC
- **Degraded performance**: gradual edge latency increase from ~03:00-06:00 ET visible on
  Fly Edge Response Time graph
- **Near-miss**: at time of investigation (~11:23 ET), machine at 87% memory with 37 MiB
  headroom and a fresh 70 MiB step-function allocation

## Machine Info

- Machine: `7847515a205e68` (blue-dawn-7651)
- Size: `shared-cpu-1x:512MB`
- Region: iad

## Timeline (all UTC, ET = UTC-5)

| Time (UTC) | Time (ET) | Event |
|------------|-----------|-------|
| ~08:00 | ~03:00 AM | Fly Edge Response Time begins gradual climb |
| ~10:00 | ~05:00 AM | Edge p90 noticeably above baseline |
| 10:58 | 5:58 AM | **OOM kill** — edge response time spike to >1 min |
| ~11:00 | ~06:00 AM | Machine restarts, metrics normalize |
| ~16:00 | ~11:00 AM | Live observation: 70 MiB step-function allocation, 37 MiB remaining |

## Findings

### 1. Request Logs Show a Healthy App (Survivorship Bias)

All 36,601 logged HTTP requests completed with normal performance:

| Metric | Value |
|--------|-------|
| Total requests (00:00-15:59 UTC) | 36,601 |
| Median response time | 10ms |
| p99 response time | ~100ms |
| Max response time | 407ms |
| 200 responses | 95.4% |
| 404 responses | 4.3% |
| No 500 responses | ✓ |

There is no degradation visible in the request logs around the crash time. Every 10-minute
bucket from 03:00-10:58 UTC shows avg response times of 8-20ms with p99 under 200ms.

**This means the OOM is invisible from the app's perspective.** The requests that made it
through were fast. The ones that didn't (proxy timeouts) were never logged.

### 2. Fly Edge Response Time Tells the Real Story

The Fly Edge Response Time graph (measured at the proxy, not the app) shows:

- **Baseline**: blue (p90) at ~10-15s, orange (p50) at ~2-5s
- **08:00-10:58 UTC (03:00-06:00 ET)**: gradual climb in edge latency
- **10:58 UTC**: spike to >1 minute (the OOM — proxy waiting for dead app)
- **Post-restart**: immediate return to baseline

The gradual climb means the Fly proxy was waiting longer and longer to get responses from
the app. The BEAM was likely spending increasing time in garbage collection or unable to
accept connections as memory pressure grew — even though the requests it did handle remained
fast.

### 3. 65% of Traffic Is Bots

| Category | Requests | % of total |
|----------|----------|-----------|
| **SEO analysis bots (blocked)** | **12,236** | **33.4%** |
| Amazonbot | 6,861 | 18.7% |
| PetalBot | 1,348 | 3.7% |
| Other legitimate bots | 3,373 | 9.2% |
| Health checks (Consul, upptime) | 2,136 | 5.8% |
| Vulnerability scanner | 904 | 2.5% |
| Human traffic | ~10,000 | ~27% |

**SEO analysis bot breakdown (now blocked):**

| Bot | Requests | Purpose |
|-----|----------|---------|
| AhrefsBot | 2,766 | Backlink/keyword database |
| SemrushBot | 3,674 | SEO analysis platform |
| SERankingBacklinksBot | 5,701 | Backlink monitoring |
| MJ12bot | 95 | Majestic SEO |
| DotBot | 15 | Moz SEO |

These bots crawl to build databases used by SEO professionals. They do not contribute to
the site's search engine visibility — only Googlebot (108 req) and bingbot (137 req) affect
actual search rankings. Kagi search uses Google/Bing APIs for its primary index; its own
crawler (Kagibot) was not seen in today's logs.

### 4. Single IP Responsible for 29% of All Traffic

IP `15.158.60.113` made **10,752 requests** (29% of total), sustained at 380-1,044
requests/hour across the full day. This IP runs Amazonbot (6,858 req) and SemrushBot (3,674
req) — both with their honest user agent strings.

### 5. Vulnerability Scanner Burst

At 12:02 UTC, IPs in the `52.46.22.*` range (AWS) using a Firefox/47 user agent sent 428
requests in one minute, probing 887 unique paths including `.env`, `phpinfo.php`,
`wp-config`, `remote/logincheck`, and other common vulnerability targets. All returned 404.
This scanner contributed 904 total requests across the day.

### 6. Overnight Grafana Pattern Explained

The first HTTP Response Times chart showed a pattern between ~10PM-5AM ET:
- **10PM-midnight**: p99/p90 drop from their daytime levels
- **Midnight-3AM**: metrics at lowest point
- **3AM-6AM**: gradual climb back up, then crash

Initial theory attributed this to WebSocket connection lifecycle (fewer human users
overnight). However, the Fly Edge Response Time graph shows the 3AM-6AM climb is actually
the app degrading under memory pressure — **the climb is the OOM in progress**, not a user
activity pattern.

The overnight dip (10PM-3AM) may still reflect lower traffic giving the app temporary
relief, before accumulation catches up again.

### 7. Memory State at Time of Investigation

At ~11:00 ET (post-restart, ~5 hours of uptime), memory graph showed:

| Metric | Value |
|--------|-------|
| Total | 459 MiB |
| Used | 399 MiB (87%) |
| Available | 37.6 MiB |
| Free | 21.8 MiB |

A ~70 MiB step-function jump occurred at ~11:00 ET — a single large allocation, not
gradual growth. At this rate, another OOM is likely within hours.

## Root Cause Analysis

**Primary**: Gradual BEAM memory accumulation that does not resolve over the application's
lifetime. The app starts healthy after a restart and progressively consumes memory until OOM.

A codebase investigation on Feb 18 identified multiple concrete sources of memory waste. The
accumulation is not one root cause but a combination of: no LiveView process hibernation, large
data held in process heaps indefinitely, a background S3 scan that spikes memory on demand, and
every page (including read-only ones) implemented as LiveViews with long-lived processes.

### 70 MiB step-function: most likely AuditCache S3 scan

The `Images.AuditCache` GenServer (audit_cache.ex) auto-triggers a full S3 enumeration when
its 1-hour TTL expires. The scan:

1. Pages through all S3 objects via `Storage.list_gall_paths_recursive`, accumulating the
   entire list using `acc ++ new_paths` (quadratic memory — copies the list on every page)
2. Loads all image paths from the DB into a MapSet
3. Loads all species IDs into another MapSet
4. Stores the resulting orphan list permanently in the GenServer heap

During the scan, memory holds all intermediate copies plus both MapSets plus the growing
result list. After scan completion, the orphan list remains in the GenServer heap (no
`hibernate_after` configured). A single scan is consistent with a discrete ~70 MiB step.

The scan triggers automatically on any `AuditCache.get_count()` call when stale, including
the admin image audit page mount. It also triggers on `get_orphans()`. No admin action is
needed — the TTL expiry is sufficient if the page was visited in the previous hour.

### Gradual accumulation: LiveView memory waste

**Zero LiveView memory tuning exists in the codebase.** No `hibernate_after`, no socket
compression, no timeout configuration in any config file or LiveView module.

Specific findings:

1. **No hibernate_after anywhere** — idle LiveView processes never hibernate, keeping their
   full expanded heap indefinitely. Every open browser tab holds a process with all its
   assigns in hot memory.

2. **ExploreLive stores 3 trees × 2 copies** — `mount/3` loads galls_tree, undescribed_tree,
   and hosts_tree, then stores each one again as `*_filtered` assigns. Six copies of full
   taxonomy tree data per open `/explore` tab.

3. **Admin index pages load unbounded result sets** — `Admin.GallLive.Index`,
   `Admin.HostLive.Index`, `Admin.TaxonomyLive.Index` all call `Repo.all()` with no LIMIT,
   storing thousands of records in assigns for client-side pagination.

4. **Every page is a LiveView** — including read-only display pages (species detail, explore,
   home) that don't need server-driven interactivity. Each page visit spawns a LiveView
   process, runs mount twice (dead render + WebSocket), and keeps the process alive. Bots
   don't connect WebSockets, but the dead render still allocates and the BEAM allocator may
   not return memory to the OS promptly.

5. **No connected?(socket) gating on expensive mounts** — `ExploreLive` and admin index pages
   load all data unconditionally on both dead render and live mount. `HomeLive` does this
   correctly (gates behind `connected?`) but it's the exception.

### ETS tables: bounded, not a concern

- **`:glossary_terms`** (markdown.ex) — single entry, 15-min TTL. Negligible.
- **Hammer.Backend.ETS** — rate limiter buckets, 1-hour expiry, swept every 10 minutes.
  Only covers API routes currently, so limited entries.
- **Phoenix.PubSub** — uses `:pg` (process groups), cleaned up on subscriber death. Bounded.

### Previous suspects ruled out or downgraded

- **BEAM allocator fragmentation** — still a contributing factor from bot traffic volume, but
  the concrete findings above explain the majority of memory usage without needing to invoke
  fragmentation as a primary cause.
- **Atoms table** — no `String.to_atom/1` usage found in the codebase. Not a factor.
- **Litestream** — snapshot interval already at 24h. sync-interval 5s has minimal memory
  footprint. Not the step-function source.

## Actions Taken

### Deployed (this session)

- [x] **Block SEO analysis bots in robots.txt** — `Disallow: /` for AhrefsBot, SemrushBot,
  SERankingBacklinksBot, MJ12bot, DotBot. Cuts ~33% of traffic from well-behaved bots.
- [x] **Add `Crawl-delay: 10`** — caps well-behaved bots at 6 req/min (360/hour) instead of
  unlimited.
- [x] **Sync robots.txt** — controller was out of sync with static file. Added missing
  disallow rules for `/id`, `/globalsearch`, `/auth`, `/health`, `/dev`.
- [x] **Add matter `1edb`** — "Investigate BEAM memory accumulation causing OOM" added to top
  of docket.

### Planned (from codebase investigation)

- [ ] **Matter 8ae6: LiveView memory tuning** — Add `hibernate_after: 5_000` to LiveView
  socket config (one-line change in endpoint.ex). Add server-side pagination to admin index
  pages (GallLive.Index, HostLive.Index, TaxonomyLive.Index).
- [ ] **Matter ee67: AuditCache rework** — Remove auto-trigger on TTL expiry; make S3 scan
  on-demand only (explicit admin button click). Add `hibernate_after` to the GenServer. Fix
  quadratic `acc ++ new_paths` list accumulation in `Storage.list_gall_paths_recursive`.
- [ ] **Matter 9ad7: Audit LiveView usage** — Evaluate converting read-only pages (species
  detail, explore, home) from LiveViews to controller + dead template. Species detail pages
  are likely the highest-impact conversion given bot crawl volume.

### Deferred (not effective for this issue)

- **Bot detection middleware** — considered and rejected. Analysis showed individual requests
  are cheap (~10-30ms, fast GC). The problem is cumulative memory growth, not per-request
  cost. Adding middleware would increase code complexity and cognitive load for marginal
  memory savings.
- **Memory bump to 1GB** — rejected by project owner. Memory costs are rising and throwing
  memory at the problem delays rather than solves it. Strategy is two-pronged: reduce
  unnecessary traffic + fix the underlying memory behavior.

## What We Still Don't Know

1. **Exact memory breakdown on the live system** — the codebase investigation identified
   concrete sources, but we haven't confirmed with `:erlang.memory/0` on production. Adding
   `:recon` as a dependency would allow `fly ssh console` inspection. The telemetry poller
   in `telemetry.ex` already runs every 10s with an empty measurement list — wiring up
   `:erlang.memory/0` reporting there would give continuous visibility.
2. **Whether the Fly HTTP Response Time chart includes WebSocket duration** — Fly docs don't
   specify. The baseline p90 at 10-15s in the "HTTP Response Times" chart could be WebSocket
   connection duration or could be something else. We have no proof either way.
3. **How much memory the AuditCache scan actually uses** — the scan already logs start and
   completion. Adding `:erlang.memory(:total)` before/after would confirm whether it's the
   70 MiB source. This is the single most valuable diagnostic to add.
4. **How many LiveView processes are typically alive** — need process count data from
   production to understand the per-process × count contribution.

## Relationship to Feb 15 Incident

This is the same underlying issue as the [Feb 15 OOM](20260215-request-log-anomalies-oom.md).
That investigation identified Litestream hourly snapshots as the primary trigger and BEAM
memory retention as the underlying cause. The snapshot interval was reverted to 24h, which
removed that specific trigger — but the underlying memory accumulation continues without it.

The Feb 15 OOM was triggered by Litestream snapshot + crawler burst. The Feb 18 OOM occurred
without either trigger, meaning the base memory accumulation rate is sufficient to reach OOM
on its own within ~18-24 hours of uptime.

## Infrastructure Reference

- **Machine**: shared-cpu-1x, 512MB RAM, iad region
- **Database**: SQLite ~38MB, WAL mode
- **Litestream**: sync-interval 5s, snapshot-interval 24h
- **Connection pool**: 10 (runtime.exs)
- **Health check**: every 30s, 5s timeout
- **Concurrency limit**: soft 200, hard 250 (fly.toml)
- **Rate limiting**: API routes only, 100 req/min/IP

## Related

- [20260215-request-log-anomalies-oom.md](20260215-request-log-anomalies-oom.md) — Previous
  OOM, 3 days prior. Same underlying issue, different trigger.
- [Matter 1edb](../../.mull/archive/1edb-investigate-beam-memory-accumulation-causing-oom.md) —
  Docket item for root cause investigation of memory accumulation.
- [Matter 8ae6](../../.mull/archive/8ae6-liveview-memory-tuning-hibernate-after-server-side-pagination.md) —
  LiveView memory tuning (hibernate_after + server-side pagination).
- [Matter ee67](../../.mull/archive/ee67-auditcache-performance-rework-lazy-scan-hibernate.md) —
  AuditCache performance rework (lazy scan + hibernate).
- [Matter 9ad7](../../.mull/matters/9ad7-audit-liveview-usage-convert-read-only-pages-to-controllers.md) —
  Audit LiveView usage — convert read-only pages to controllers.
- [Matter 220d](../../.mull/matters/220d-rate-limiting-for-all-routes.md) — Rate limiting
  expansion to page routes.
