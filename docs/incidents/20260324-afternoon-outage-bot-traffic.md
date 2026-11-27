# P2: Repeated Crashes and Degradation Under Bot Traffic - March 24, 2026

## Status: Open — root cause undetermined, all infrastructure metrics clean

**Status (2026-11-27):** Closed. Landed: persistent structured error logging, with all Logger output (errors, Postgrex events, crash reports) written as JSON to `/data/logs/app.log` on the volume and kept across restarts (LoggerJSON, 42ec0821, 2026-03-25; `config/runtime.exs`). Not landed: BEAM-level and Postgrex/DBConnection telemetry (`telemetry.ex` defines VM and Ecto metrics but no reporter consumes them; docs/backlog.md, "Error tracking and alerting"); rate limiting for bots (the `RateLimiter` plug is still only on `/api`; matter 220d, not in docs/backlog.md); blocking Barkrowler in robots.txt (not in `priv/static/robots.txt` or `robots_controller.ex` on `main` or `taxogall`; not in docs/backlog.md). The root cause was never determined.

## Summary

Production experienced ~2 hours of degradation and two complete outages between 4:25 PM
and 6:14 PM ET (20:25 - 22:14 UTC). The pattern was gradual latency escalation followed
by process death, not the instant cutover seen in the March 9 host maintenance incident.

**All observable infrastructure metrics were healthy during the incident:**
- CPU: credits at max, utilization minimal (both app and DB)
- Memory: stable at ~512/962 MiB on app, ~599/962 MiB on DB (no growth, no spike)
- No OOM (oom_killed=false)
- No host maintenance (fly incidents hosts list clean)
- No deploys (last was 6 days prior)

**Root cause is below our current observability layer.** All OS-level metrics (CPU, memory)
were healthy on both app and DB servers throughout the incident. We do not have
application-level telemetry (BEAM internals, connection pool state, error logs) from the
incident window — server logs were lost during the restarts.

Without application-level data, we cannot determine whether the cause was app-internal
(BEAM process issue, connection pool behavior), network-related (Fly 6PN between app and
DB), or something else entirely.

## Impact

- **Total degradation window**: ~110 minutes (20:25 - 22:14 UTC)
- **Complete outage 1**: 14.4 minutes (21:11:27 - 21:25:52 UTC)
- **Complete outage 2**: 21.5 minutes (21:53:10 - 22:14:39 UTC)
- **500 errors served**: 49 (across /gall, /place, /host, /source, /family, /genus, /id pages)
- **503 health check failures**: 9
- **User-facing**: Real browser users received 500 errors and multi-second page loads

## Machine Info

- Machine: `7847515a205e68` (blue-dawn-7651)
- Size: `shared-cpu-1x:1024MB`
- Region: iad
- Release: v155 (deployed 2026-03-18 23:58 UTC — 6 days before incident)
- HealthWatchdog: active

## Timeline (all ET = UTC-4 EDT)

| Time (ET) | Time (UTC) | Event |
|-----------|------------|-------|
| **Pre-incident** | | |
| 1:00 AM+ | 05:00+ | Barkrowler begins sustained crawl of /place/* pages at 10 req/min |
| 1:00 AM - 4:24 PM | 05:00 - 20:24 | ~15 hours sustained bot load; app healthy, normal latency |
| **Phase 1: Degradation onset** | | |
| 4:25 PM | 20:25 | First 500 error (/place/ES-SG, 5183ms). Health checks go 503 |
| 4:25-4:27 | 20:25-20:27 | 11 errors, latency spikes to 1800-3600ms avg. Brief recovery at 20:28 |
| 4:28-4:39 | 20:28-20:39 | Partial recovery — latency 20-50ms but unstable. One slow minute (20:32, 880ms avg) |
| 4:40 | 20:40 | **Amazonbot burst begins** (~22 req/min). Second error spike: 6 errors, 4317ms avg |
| 4:40-5:11 | 20:40-21:11 | Oscillating degradation. Recurring 500 error clusters every 4-8 min. Latency peaks at 25,354ms (/host/4767 at 21:05) |
| **Phase 2: First outage** | | |
| 5:11 | 21:11 | Last request logged. Process killed (event log truncated — no exit event visible) |
| 5:11-5:25 | 21:11-21:25 | **14.4-minute complete outage** — zero requests served |
| 5:25 | 21:25 | Machine restarts (`starting/restart` at 21:25:29, `started` at 21:25:32) |
| **Phase 3: Partial recovery** | | |
| 5:25-5:53 | 21:25-21:53 | Recovers at lower traffic (Barkrowler did not return after outage). Intermittent errors at 21:38, 21:42, 21:46. Slow responses at 21:30 (887ms), 21:52 (649ms) |
| **Phase 4: Second outage** | | |
| 5:53 | 21:53 | Last request logged (/gall/1834, 200 OK). Process dying again |
| 5:53-6:13 | 21:53-22:13 | **21.5-minute complete outage** — zero requests served |
| 6:13 | 22:13:52 | Process killed: `exit_code=-1, oom_killed=false, requested_stop=false` |
| 6:14 | 22:14:10 | Machine restarts, first request at 22:14:39 (529ms avg — cold start) |
| **Recovery** | | |
| 6:14+ | 22:14+ | Stable recovery. No Barkrowler, no Amazonbot. Latency returns to 15-30ms |

## Bot Traffic Analysis

### Sustained crawlers during incident

| Bot | Rate | Duration | Total (24h) | Pages crawled |
|-----|------|----------|-------------|---------------|
| Barkrowler (babbar.tech) | 10 req/min, rock-steady | 05:00 - 21:11 UTC (16+ hours) | 8,672 | /place/* exclusively |
| ClaudeBot | ~6-8 req/min | All day | 8,223 | Mixed |
| Amazonbot | ~2 req/min baseline, **30 req/min burst at 20:40-20:50** | All day with bursts | 4,367 | Mixed |
| FakeAndroid7Bot | ~1-2 req/min | All day | 1,574 | Mixed |

### Traffic at degradation onset

Pre-incident (19:00-20:00): 1,875 req/hr — normal latency, all healthy
Incident window (20:00-21:00): 1,905 req/hr — similar volume, massive latency increase

The total request rate was NOT significantly higher during the incident — the issue is not
an acute traffic spike.

### Amazonbot burst correlation

The Amazonbot burst at 20:40-20:50 (109-157 requests per 5 min vs near-zero before) correlates with the deepest degradation, but the initial degradation at 20:25 preceded the burst. The burst worsened an already-degraded system.

## What We Ruled Out

### Host maintenance
`fly incidents hosts list` shows no active host issues. Unlike the March 9 incident, no
host-level events match this timeline.

### Deploy / code change
Last deploy was v155 on 2026-03-18 (6 days prior). No code changes between stable
operation and incident.

### OOM / memory
Fly reports `oom_killed=false` on the exit event. Memory would need to be confirmed on
Grafana, but the exit flag is definitive.

### Traffic spike (raw volume)
Hourly request volume was normal (~1,900/hr during the incident vs ~2,000/hr average).
Hour 14 served 5,898 requests with no issues. The problem is not request volume alone.

### Fly platform outage
status.flyio.net and `fly incidents hosts list` both clean.

### Single expensive route
All page types showed equal degradation during the incident:
- Baseline → Incident avg latency: /place/* 13ms → 190ms (15x), /gall/* 39ms → 349ms (9x), /host/* 18ms → 284ms (16x)
- This rules out a specific query or code path — the entire BEAM was starved.

## Root Cause Analysis

### Ruled out: CPU credit exhaustion

Grafana CPU Quota chart confirms credits at max (8.33 mins / ~80%) throughout the incident
window on both app and DB servers. CPU utilization well below baseline.

### Ruled out: Memory pressure

Grafana memory charts show stable usage on both machines:
- App: ~512 MiB used / 962 MiB total (53%) — flat, no growth, no spike before either crash
- DB: ~599 MiB used / 962 MiB total (62%) — completely flat throughout
- After restart, app memory lower at ~391 MiB — no re-accumulation visible before second crash

This rules out the memory accumulation patterns from Feb 18 (LiveView), Feb 20
(driver_alloc), and Mar 11 (OS page cache) investigations.

### Ruled out: Host maintenance

`fly incidents hosts list` shows no host-level events. Unlike the March 9 incident, no
host maintenance explains the timing.

### Ruled out: Code/deploy change

Last deploy was v155 on 2026-03-18 (6 days prior). No code changes between stable
operation and incident onset.

### Undetermined: Root cause is below observability layer

All OS-level metrics (CPU, memory, disk) were healthy on both machines while the app was
clearly dying (500 errors, multi-second latencies, health check failures). This means the
cause is something we currently cannot observe.

**What we know (facts):**
- The `/health` endpoint returned 503 nine times during the incident. The health endpoint
  code returns 503 when `Repo.query("SELECT 1")` fails.
- Various pages returned 500 a total of 49 times. We do not have error messages or stack
  traces — only status codes, paths, and durations from the request log.
- 500 errors cluster at identical sub-second timestamps (e.g., 6 errors all at
  20:40:14.318). This suggests requests were blocked on a shared resource and released/failed
  simultaneously — but we cannot confirm what that resource was.
- The second crash occurred 28 minutes after restart #1 despite lower traffic.

**What we do not know:**
- Whether the 500 errors were caused by DB connection failures, application exceptions,
  process timeouts, or something else. The request log has no error details.
- Whether the health check 503s mean the DB was unreachable, the connection pool was
  exhausted, or the BEAM was too overloaded to execute the query.
- Whether this was an app-only issue, a network issue between app and DB, or a Fly
  infrastructure issue not covered by `fly incidents hosts list`.

**Possible mechanisms (unranked — insufficient data to rank):**

1. **App-internal issue** — something in the BEAM (process accumulation not visible in OS
   memory, scheduler contention, port exhaustion, GenServer bottleneck) caused cascading
   slowdown. The health check failed because the app couldn't service it, not because the
   DB was unreachable.

2. **Fly 6PN network issue** — transient network disruption between app and DB machines
   caused Postgrex connections to hang. Pool filled, requests cascaded, health check failed
   on pool checkout. Both machines individually healthy because the problem was between them.

3. **Postgrex/DBConnection pool behavior** — some edge case in pool management under
   sustained load (e.g., connection recycling, idle timeout interaction) caused pool
   starvation without an external trigger.

4. **Fly infrastructure issue not captured by available diagnostics** — `fly incidents
   hosts list` covers host maintenance but may not cover all infrastructure events (network,
   proxy, routing).

**We cannot distinguish between these without application-level telemetry from the incident
window.** Server logs were lost during the restarts — the exact period we need is the one
we cannot see.

## Actions Taken

- Downloaded and analyzed request logs
- Documented timeline with evidence

## What We Still Don't Know

1. **What the 500 errors actually were** — no error messages, stack traces, or application
   logs from the incident. We only know the status code and duration. The errors could be
   DB-related, application exceptions, process timeouts, or anything else.
2. **Why the health check failed** — `Repo.query("SELECT 1")` returned an error, but we
   don't know if it was a DB connectivity issue, pool exhaustion, or the app being unable
   to execute the query for some other reason.
3. **Whether the HealthWatchdog triggered the kills** — exit_code=-1 is consistent with
   both watchdog (`System.stop(1)`) and Fly killing the process. Application logs from the
   incident window were lost during the restarts.
4. **What killed the process the first time** (21:11) — machine event log is truncated,
   no exit event visible for the first crash.
5. **Whether this was app-only or involved the network/DB** — all we know is that both
   machines' OS metrics were healthy. We have no visibility into the BEAM's internal state,
   the connection pool, or the network between machines.

## Recommended Actions

### Observability (highest priority — we're blind to the cause)

| Action | Why |
|--------|-----|
| **Persistent structured error logging** — write errors/exceptions to a file like request logs | Server logs are lost on restart. This is the single biggest gap — we had no error messages from the incident. Would immediately tell us what the 500s were. |
| **BEAM-level telemetry** — `:erlang.memory/0`, process count, port count, scheduler utilization | OS metrics were clean; the cause may be internal to the BEAM. This would catch process leaks, scheduler contention, or memory patterns invisible to cgroup metrics. |
| **Postgrex/DBConnection telemetry** — checkout wait time, queue depth, idle/busy counts | Would distinguish "DB path broken" from "app too busy to query DB." One of many possible causes, but a common one worth instrumenting. |

### Mitigation (reduces blast radius regardless of root cause)

| Action | Why |
|--------|-----|
| Rate limiting for bots (matter 220d) | Barkrowler at 10 req/min for 16 hours is unnecessary load. May not be the root cause but reduces stress on all resources |
| Block Barkrowler in robots.txt | Provides zero value to the site (SEO analysis crawler), crawling every /place page systematically |

## Related

- [20260309 - 90-Minute Unresponsive Outage](20260309-unresponsive-crash-cpu-investigation.md) — Fly host maintenance (different pattern)
- [20260310 - Response Time Spike](20260310-brief-outage-response-spike.md) — Analytics rollup SQLite contention (resolved)
- [20260218 - OOM Crash Bot Traffic](20260218-oom-crash-bot-traffic-memory-accumulation.md) — Prior bot-driven incident
- Mull matter 220d — Rate limiting for all routes (planned)
