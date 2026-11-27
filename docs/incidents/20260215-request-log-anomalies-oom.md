# P2: Request Log Anomalies & OOM Restart - February 15, 2026

## Status: Open - Investigation

**Status (2026-11-27):** Closed. Landed: the invalid-URL data migration, `validate_url/2` on `source.link`, `source.licenselink` and `species_source.externallink`, and the `valid_url?/1` guard in the Gall, Host, Source and image templates (matters be64, 1cab and 8257, all in d9b244fa, 2026-02-15, on `main`); the 1GB VM (`fly.toml` `memory = "1024mb"`, 7a2032c3, 2026-02-20); external monitoring as the downdetector Lambda, which requests the home page every 5 minutes and emails on failure (32f0403c, 2026-02-27; it doesn't measure response time); the memory investigation (matter 1edb, done 2026-02-18; see the Feb 18 and Feb 20 reports); errors and crash reports in the on-disk JSON logs, `/data/logs/app.log` (LoggerJSON in place of the custom request logger, 42ec0821, 2026-03-25); and the move to Postgres, which retired SQLite and Litestream (f25f2518, 2026-03-16). Not landed: rate limiting on page routes (the `RateLimiter` plug is still only on the `/api` scope in `router.ex`, on `main` and `taxogall`; matter 220d, not in docs/backlog.md); log shipping to an external service (not in docs/backlog.md; the nearest entry is "Error tracking and alerting").

## Summary

Production experienced an OOM kill and restart at ~06:39 UTC (1:39 AM ET) on Feb 15.
Analysis of the preceding hours reveals a pattern of escalating performance degradation
triggered by a crawler burst and amplified by hourly Litestream snapshots, ultimately
exhausting the 512MB memory limit.

Separately, several specific pages consistently return fast 500 errors due to data issues.

## Impact

- **OOM restart**: ~60 second outage at 06:39 UTC
- **Degraded performance**: ~4 hours of intermittent slow responses (02:31-06:38 UTC)
- **User-facing 500s**: 378 server errors across the 24-hour period
- **Failed health checks**: 2x 503 on /health (12-22s response times)

## Machine Info

- Machine: `7847515a205e68` (blue-dawn-7651)
- Size: `shared-cpu-1x:512MB`
- Region: iad
- Last updated (restart): `2026-02-15T06:39:28Z`

## Timeline (all UTC, ET = UTC-5)

| Time (UTC) | Event |
|------------|-------|
| 02:31:35 | Crawler burst begins — 842 requests in ~2 minutes from AWS IP ranges |
| 02:31-02:32 | 207 requests exceed 5 seconds; /id tool hit repeatedly during burst |
| 02:32:39 | Burst subsides, response times normalize |
| 03:39-03:42 | First Litestream snapshot spike — 55 slow requests (30-93s) |
| 04:40-04:42 | Second spike — 59 slow requests, mass 500 errors at 04:40:51 |
| 04:41:11 | Health check takes 44 seconds |
| 05:39-05:42 | Third spike — 73 slow requests, responses up to **200 seconds** |
| 06:38:08 | Response times climbing again (96ms for /id, then 3-4s for galls) |
| 06:38:19 | Last requests before gap: 2.5-3.9s response times |
| 06:38:28 | Health check takes 307ms |
| 06:38:29-06:39:38 | **~69 second gap** — OOM kill + restart |
| 06:39:38 | First request after restart — healthy (2ms /health) |
| 06:39:38+ | All responses normal (<35ms) |

## Findings

### 1. Escalating Degradation Pattern (Critical)

The slow request spikes follow the Litestream `snapshot-interval: 1h` cadence (litestream.yml).
Each successive spike was worse than the previous:

| Hour (UTC) | Slow requests (>5s) | Max response time | 500 errors |
|------------|---------------------|-------------------|------------|
| 02 | 207 | 11.5s | 47 (ID tool) |
| 03 | 55 | 93s | 0 |
| 04 | 59 | 93s | ~45 |
| 05 | 73 | 200s | ~20 |
| 06 | (OOM before spike completed) | 3.9s | 0 |

The escalation strongly suggests **memory is not being released** between spikes. Each
Litestream snapshot adds memory pressure on top of the uncollected residue from the previous
spike, until the 512MB limit is breached.

### 2. Crawler Burst as Initial Trigger

At 02:31:35, a crawler swarm hit the site — 842 requests in ~2 minutes, all from AWS IP
ranges (CloudFront/Amazonbot). The varied user agents (Chrome, Firefox, Safari on Windows
and Mac) suggest a distributed crawler fleet, not a single bot.

Top IPs during burst:
- `3.172.31.41` — 194 requests
- `18.68.32.12` — 55 requests
- `3.172.74.199` — 37 requests

This burst likely created many concurrent LiveView processes and database connections that
contributed to the initial memory elevation. The /id tool was hit 47 times during the burst
and generated all 47 of its 500 errors — the ID page is heavy (loads all gall images for
the identification interface).

### 3. Litestream Snapshot Contention

Litestream is configured with `snapshot-interval: 1h`. The hourly performance spikes
at :39-:42 past the hour correlate with snapshot operations. During a snapshot, Litestream
must checkpoint the WAL, which requires an exclusive lock. With concurrent requests queuing
behind the lock, response times spike and connection pool saturation can cascade into 500s.

### 4. Mass 500 Error Cascade at 04:40:51

At 04:40:51 UTC, **22 requests** all returned 500 with similar ~35-38 second durations.
These are connection pool timeouts — all queued requests timing out simultaneously when the
pool couldn't serve them. A second batch followed at 04:41:02 (10 more 500s), then a third
at 04:41:11 with even longer timeouts (74-93s).

### 5. Fast 500s on Specific Pages — Invalid URL Data (Root Cause Found)

These pages consistently return 500 in 3-20ms regardless of server load. The Fly application
logs confirm the error:

```
** (ArgumentError) unsupported scheme given to <.link>. In case you want to link to an
unknown or unsafe scheme, such as javascript, use a tuple: {:javascript, rest}
```

Stack trace points to `gall_live.ex:655` and `source_live.ex:162` — both render `<.link>`
with `href=` values that aren't valid URLs.

**`species_source.externallink` — 4 bad records:**

| ID | species_id | source_id | Problem |
|----|-----------|-----------|---------|
| 522 | 570 | 7 | Leading space: `" https://..."` |
| 1524 | 1400 | 14 | Corrupt: `"blandahttps://..."` (data entry error) |
| 5943 | 581 | 546 | Whitespace only: `" "` |
| 7943 | 5594 | 835 | Missing scheme: `"www.biodiversitylibrary.org/..."` |

**`source.link` — 8 bad records:**

| Source ID | Problem |
|-----------|---------|
| 393 | Missing scheme: `"doi.org/..."` |
| 491 | Not a URL: title text pasted into link field |
| 504 | Missing scheme: `"ir.cut.ac.za/..."` |
| 588 | Not a URL: citation text pasted into link field |
| 622 | Literal `"none"` |
| 787 | Missing scheme: `"www.biodiversitylibrary.org/..."` |
| 805 | Missing scheme: `"www.jstor.org/..."` |
| 835 | Missing scheme: `"www.biodiversitylibrary.org/..."` |

**Fix required**: Two layers:
1. **Data fix** — migration to clean up the 12 bad records (trim whitespace, prepend `https://`
   where fixable, clear garbage values)
2. **Code fix** — validate URL scheme before passing to `<.link>` so future bad data doesn't
   crash the page. Could be a simple guard or a URL normalization helper.

These errors occur throughout the day — crawlers repeatedly hit the broken pages.

### 6. /id Tool Errors Correlated with Load

All 47 `/id` 500 errors occurred during congestion periods, not during normal operation.
The ID tool works fine under normal load (avg 377ms across 1,941 requests). The errors are
a symptom of the congestion, not a cause — likely database timeouts during the heavy periods.

### 7. Overall Traffic Profile

| Metric | Value |
|--------|-------|
| Total requests (24h) | 68,248 |
| Feb 14 | 45,557 |
| Feb 15 (partial) | 22,691 |
| 200 responses | 63,919 (93.7%) |
| 404 responses | 3,882 (5.7%) — mostly bot probing |
| 500 responses | 378 (0.55%) |
| Response time <100ms | 96% |
| Response time >30s | 105 (0.15%) |
| Bot scan 404s | ~3,800 (standard noise) |

## Root Cause Analysis

**Primary**: Litestream snapshot interval was changed from 24h to 1h on Feb 14. This means
snapshots now run every hour instead of once a day. Each snapshot checkpoints the WAL and
uploads the full 38MB database to S3, requiring significant memory and holding a checkpoint
lock during the process. Previously, the single daily snapshot was survivable; hourly
snapshots compound with memory that the BEAM doesn't release between spikes.

**Contributing**:
1. **Memory not released between spikes** — the BEAM VM allocates memory during load bursts
   (LiveView processes, Ecto query results, binary data) but doesn't return it to the OS
   promptly. BEAM's memory allocators hold onto freed memory for reuse. On a 512MB machine,
   this means each successive spike starts from a higher baseline.
2. **Crawler burst as trigger** — at 02:31, a crawler swarm (842 requests in 2 min) from
   Amazon's infrastructure pushed memory up. The crawlers use fake browser user agents from
   distributed AWS IPs, making them hard to distinguish from real traffic.
3. **Rate limiting only on API routes** — the existing `RateLimiter` plug only covers
   `/api` routes (router.ex:202). LiveView/page routes have no rate limiting at all.
4. **512MB memory limit** — tight for Phoenix + Litestream + SQLite on a single machine.
   Prod DB is 38MB; Phoenix baseline is ~150-200MB; leaves ~250MB for request handling and
   Litestream operations.

## Analysis & Discussion

### Litestream Snapshot Memory Behavior

The snapshot-interval change from 24h to 1h is the most significant contributing factor.
During a Litestream snapshot:

1. **WAL checkpoint** — SQLite copies WAL pages back to the main DB file. This requires
   reading and writing the affected pages, holding a CHECKPOINT lock that blocks writers.
2. **Full DB read** — Litestream reads the entire database (38MB) to create the snapshot.
3. **S3 upload** — the snapshot is uploaded to S3, holding the data in memory during transfer.
4. **BEAM memory retention** — the BEAM VM's allocators don't eagerly return memory to the
   OS. Memory used by Litestream's Go runtime and by Phoenix processes serving concurrent
   requests during the lock contention stays allocated.

With a 24h interval, this happened once (usually during low traffic) and the system had all
day to gradually release memory. With 1h, each snapshot adds ~30-50MB of pressure that
doesn't fully resolve before the next one.

**Recommendation**: Revert to 24h snapshots immediately. The WAL replication (`sync-interval:
5s`) already provides RPO of ~5 seconds — snapshots are only needed for faster restore, not
for durability. If faster restore is desired, 4h or 6h is a reasonable compromise.

### Amazon Crawler & robots.txt

The `/id` path is `Disallow`'d in robots.txt, but this crawler doesn't care. Key observations:

- Only **2 of ~50 requests** used the honest `Amazonbot/0.1` user agent
- The other **~48 requests** used fake browser UAs (Chrome 119/120, Firefox 120/121, Edge)
- All from AWS IP ranges: `3.172.x.x`, `18.68.x.x`, `15.158.x.x`
- This is Amazon's "headless browser" crawler that ignores robots.txt and masquerades as
  real browsers. It's a known issue in the webmaster community.

**Options to block**:
1. **IP range blocking** — block AWS IP ranges at the Fly proxy level or in a plug.
   Aggressive but effective. Risk: blocks legitimate AWS-hosted users (rare for this site).
2. **Behavioral detection** — the burst pattern (50+ requests/minute from a single IP, all
   to different pages, no JS execution) is distinguishable from real users. A plug could
   track request rate per IP and return 429 for LiveView routes, not just API.
3. **CloudFront header** — Amazon's crawler sends `Via: CloudFront` headers. Could filter on
   that, but they may change it.
4. **Aggressive robots.txt** — add `User-agent: Amazonbot` with `Disallow: /` but this only
   works for the 4% that self-identify.

**Recommended approach**: Extend the existing `RateLimiter` to cover all routes (not just API),
with a higher limit for page routes (e.g., 30 req/min per IP). This catches all aggressive
crawlers regardless of user agent.

### Response Time Alerting

The site had >1s response times for ~3 hours with no alerting. Current monitoring:
- Fly health check: every 30s, 5s timeout, GET /health — only catches complete outages
- No response time monitoring
- No memory monitoring
- No error rate monitoring

**Options**:
1. **Fly.io Metrics & Alerts** — Fly exposes Prometheus metrics. Can alert on p95 response
   time, error rate, memory usage. Free tier available.
2. **Application-level telemetry** — Phoenix already emits `:telemetry` events. Could add a
   GenServer that tracks rolling p95 and logs warnings when thresholds are breached.
3. **Request log analysis** — the JSON request logs already have everything needed. A
   periodic task (every 5 min) could scan recent entries and alert if p95 > 1s or error
   rate > 1%.
4. **External monitoring** — services like UptimeRobot, Better Stack, or Checkly can monitor
   response times from outside. Low effort, catches real user impact.

**Recommended**: Start with external monitoring (option 4) for immediate coverage, then add
Fly metrics (option 1) for memory/process-level visibility.

### Log Capture

Fly's log explorer is limited to 1000 entries and doesn't support time-range queries well.
The JSON request logs on disk are more useful but lack application error details (stack traces,
exception info).

**Options**:
1. **Ship Fly logs to external service** — Fly supports NATS-based log shipping to services
   like Logtail, Papertrail, Datadog, or self-hosted Vector/Loki. This gives full log
   retention with search.
2. **Enhance request logger** — add exception info to the JSON request log entries. When a
   request returns 500, include the exception module and message. This makes the on-disk
   logs self-contained for most investigations.
3. **Periodic log rotation to S3** — add a cron-like task to upload request log files to S3
   daily. Cheap storage, keeps history.

**Recommended**: Option 2 (enhance request logger) is quick and solves 80% of the problem.
Option 1 (log shipping) for comprehensive coverage if incidents become more frequent.

### 512MB RAM — Is It Enough?

Current memory budget on 512MB:
- BEAM VM baseline: ~100-150MB
- Ecto connection pool (10 connections): ~20-30MB
- LiveView processes: variable, depends on concurrent users
- Litestream (Go sidecar): ~30-50MB
- SQLite page cache: configurable, currently default
- **Remaining headroom: ~200-250MB** under normal load

This is tight but workable for normal traffic. The problem is spikes — a crawler burst
creating 100+ concurrent LiveView processes plus a Litestream snapshot can easily consume
the remaining headroom.

**Options**:
| Size | Cost | Headroom | Verdict |
|------|------|----------|---------|
| 512MB | $3.57/mo | ~200MB | Marginal — survives normal load, OOMs on spikes |
| 1GB | $7.14/mo | ~700MB | Comfortable — survives moderate spikes |
| 2GB | $14.28/mo | ~1.5GB | Overkill unless traffic grows significantly |

**Recommendation**: Bump to 1GB ($3.57/mo increase) as immediate relief while investigating
the memory behavior. This buys time without masking the underlying issue.

### Postgres Migration Consideration

The recurring pattern — SQLite single-writer contention, Litestream memory overhead,
checkpoint locking, connection pool pressure — raises the question of whether SQLite is
the right fit for production.

**What Postgres solves**:
- **No Litestream** — managed Postgres (Fly Postgres, Neon, Supabase) handles replication
  and backups natively. Eliminates the sidecar memory overhead and snapshot contention.
- **Concurrent writers** — MVCC means reads never block writes. The entire class of
  "checkpoint lock causing cascading timeouts" goes away.
- **Better connection pooling** — PgBouncer/Supavisor handle connection multiplexing at
  the database level, not just the application level.
- **Memory isolation** — database memory is in a separate process, not competing with the
  BEAM VM for the same 512MB.
- **Monitoring** — mature tooling for query performance, connection stats, memory usage.

**What Postgres costs**:
- **Migration effort** — schema is straightforward (Ecto handles it), but SQLite-specific
  fragments, PRAGMA calls, and the migration helper (`safe_recreate_table`) need rework.
- **Monthly cost** — Fly Postgres: free for single-node dev, ~$7-15/mo for reliable setup.
  Neon: free tier generous, ~$19/mo for production. Supabase: free tier, ~$25/mo for pro.
- **Operational complexity** — another service to manage, though managed offerings reduce
  this significantly.
- **Latency** — currently SQLite is in-process (~1ms queries). Network Postgres adds 1-2ms
  per query. For this app's query patterns (5-15 queries per page), this means ~10-30ms
  additional latency. Pages would go from 15ms to 35-45ms — still fast.
- **Deployment model change** — no more single-file database on a volume. Backups become
  the provider's responsibility (generally a good thing).

**What doesn't change**: The memory leak / BEAM memory retention behavior exists regardless
of database. Postgres eliminates the Litestream overhead but doesn't fix unbounded process
growth if that's happening.

**Assessment**: The strongest argument for Postgres isn't any single incident — it's the
pattern. This is the second overnight degradation in 10 days, both involving SQLite
contention. The Litestream snapshot change exposed how fragile the current setup is. If the
site continues to grow (more crawlers, more users, more data), SQLite's single-writer model
will keep creating these pressure points.

The counterargument: if the Litestream snapshot interval is reverted to 24h and the memory
behavior is investigated, SQLite may be fine for current traffic levels. The site serves
~45K requests/day with 96% under 100ms — that's well within SQLite's comfort zone for reads.

**This is a strategic decision, not an emergency.** The immediate fixes (revert snapshot
interval, bump to 1GB, add rate limiting) stabilize the current setup. Postgres migration
can be evaluated deliberately.

## Recommended Actions (Revised)

### Immediate (Today)

- [x] **Revert Litestream snapshot interval** — changed `snapshot-interval` from `1h` back
  to `24h` in `litestream.yml`. WAL sync at 5s already provides durability. Needs deploy.
- [ ] **Fix invalid URL data** — migration to clean up 12 bad records in `source.link` and
  `species_source.externallink`. Root cause identified in Finding #5. Tracked: `mull:be64`.
- [ ] **Add URL validation to changesets** — prevent bad URL data from entering the DB via
  changeset validation on source.link, source.licenselink, species_source.externallink.
  Tracked: `mull:1cab` (needs be64).
- [ ] **Gracefully handle invalid URLs in templates** — defense-in-depth so bad data degrades
  to text-without-link rather than crashing the page. Tracked: `mull:8257`.

### Short Term (This Week)

- [ ] **Bump RAM to 1GB** — `fly scale memory 1024`. $3.57/mo increase. Buys headroom while
  investigating memory behavior.
- [ ] **Extend rate limiting to all routes** — plan written at
  [docs/plans/2026-02-15-extend-rate-limiting.md](../plans/2026-02-15-extend-rate-limiting.md).
  Refactor existing `RateLimiter` plug to be configurable (scope + limit), add to `:browser`
  pipeline at 60 req/min/IP, fix IP detection to use `fly-client-ip`, add 429 error page.
- [ ] **Add external monitoring** — set up response time monitoring via UptimeRobot or
  similar. Alert if p95 > 1s for 5 minutes.
- [ ] **Enhance request logger** — add exception module/message to JSON log entries for 500
  responses, eliminating the need to correlate Fly logs.

### Medium Term (Next Sprint)

- [ ] **Memory investigation** — add `:recon` to production deps, capture memory snapshots
  during normal operation and after load spikes. Key questions:
  - Are LiveView processes being cleaned up after disconnection?
  - Is ETS table growth unbounded (Hammer rate limiter state, PubSub)?
  - Is BEAM holding allocated memory that could be returned to OS?
  - Test `System.flag(:fullsweep_after, 0)` or `:erlang.memory()` periodic logging.
- [ ] **Log shipping** — evaluate Fly NATS log shipping to a service (Logtail, Better Stack)
  for full log retention and search.
- [ ] **Postgres evaluation** — if memory investigation reveals SQLite-specific pressure
  points, begin planning migration. Start with a branch that swaps ecto_sqlite3 for
  postgrex and runs the test suite.

## Request Log Field Reference

The request logger writes JSON with these fields:
- `status` — HTTP status code
- `path` — request path
- `ip` — client IP
- `ts` — ISO 8601 timestamp
- `method` — HTTP method
- `duration_ms` — response time in milliseconds
- `ua` — user agent string

## Infrastructure Reference

- **Machine**: shared-cpu-1x, 512MB RAM, iad region
- **Database**: SQLite 38MB (prod), WAL mode
- **Connection pool**: 10 (runtime.exs)
- **Litestream**: sync-interval 5s, snapshot-interval 24h (reverted from 1h on Feb 15)
- **Health check**: every 30s, 5s timeout
- **Concurrency limit**: soft 200, hard 250 (fly.toml)
- **Rate limiting**: API routes only, 100 req/min/IP (RateLimiter plug)

## Related

- [20260205-id-tool-n-plus-one-query.md](20260205-id-tool-n-plus-one-query.md) — Previous
  incident with similar overnight degradation pattern. The N+1 query was fixed but the
  underlying memory/contention vulnerability remains.
- [litestream.yml](../../litestream.yml) — Litestream configuration
- [fly.toml](../../fly.toml) — Fly.io deployment configuration
