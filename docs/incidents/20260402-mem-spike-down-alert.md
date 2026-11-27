# P3: Down Alert + Memory/CPU Anomalies - 2026-04-02

## Status: Open — probable root cause identified

**Status (2026-11-27):** Closed. Landed: the `AliasHandlers` `FunctionClauseError` (the alias type select sent params that matched neither `handle_update_new_alias/2` clause) was fixed by splitting the event in c3878f2d (2026-05-15, on `main`), and on `taxogall` the old admin's `GallLive.Form` and `AliasHandlers` are gone (a075e07a); `Crawl-delay: 10` for all crawlers was already in robots.txt (17b2cdc9, 2026-02-18). Not landed: rate limiting (the `RateLimiter` plug is still only on `/api`; matter 220d, not in docs/backlog.md); profiling `/id` under concurrent load (not in docs/backlog.md); a crawl delay or block aimed at the aggressive crawlers, such as meta-externalagent (not in docs/backlog.md). A fix for the `GallLive.Form.handle_event/3` `FunctionClauseError` is not confirmed: this report doesn't name the event, and c3878f2d, which changed that form's alias handlers, may be it.

## Summary
Down alert at 5:41pm ET. Root cause is two bot/crawler traffic bursts that caused memory pressure on shared-cpu VMs with 1GB RAM. The app never returned 5xx errors and continued serving requests throughout — the down alert was likely triggered by a brief health check timeout during memory pressure.

## Impact
- **Duration**: ~2 minutes (5:41-5:43pm ET based on request continuity)
- **Scope**: Possible brief health check failure; no visible user-facing errors in logs

## Machine Info
- **App**: `gallformers` — machine `4d893e0dc36218` (damp-dust-4976), ewr, shared-cpu 1x 1024MB
- **DB**: `gallformers-db` — machine `85379da4457e68` (black-river-3516), ewr, shared-cpu 1x 1024MB
- No machine crashes or OOM kills on either server
- DB health check failure at 6:10pm ET (recovered in 47s)

## Timeline (all ET — UTC-4)

| Time | Event | Source |
|------|-------|--------|
| 1:47pm | Deploy v158 (1 file, 15 insertions — `gall_host_live.ex`) | `fly releases`, machine events |
| 1:48pm | App CPU spike | Grafana (user-reported) |
| 2:08pm | DB memory spike | Grafana (user-reported, no app logs from this period) |
| 4:21-4:30pm | **Distributed scraper burst**: 2,772 requests in 10 min from 2,232 unique IPs, rotating Chrome UAs + Amazonbot. Peak 614 req/min at 4:27pm (normal baseline ~15 req/min) | app.log analysis |
| 5:08pm | DB memory spike | Grafana (user-reported) |
| 5:37pm | **Facebook Meta crawler burst**: 93 requests in 1 min (74 from meta-externalagent). 14 hits on `/id` (heavy page) | app.log analysis |
| 5:39pm | App memory spike | Grafana (user-reported) |
| 5:41pm | **Down alert** | External monitoring |
| 6:09pm | DB CPU spike | Grafana (user-reported) |
| 6:10pm | DB health check failure: memory 1.27s/10s waiting, IO 3.23s/10s waiting. Role check also failed (cluster membership inconsistent). Both recovered by 6:10:57pm | fly logs gallformers-db |

## What We Ruled Out
- **Fly platform incidents**: No incidents on status.flyio.net or host-level dashboards
- **App crashes/OOM**: No crash or restart events on app machine after 1:47pm deploy
- **DB crashes**: No restart events on DB machine since March 27
- **Code change**: Deploy v158 was 1 file, 15 insertions in admin gall-host page — no perf impact
- **5xx errors**: Zero 500/502/503/504 responses in the entire day's logs
- **Request gaps**: No gaps > 60 seconds in request logs — app served continuously

## Root Cause Analysis

**Assessment: Probable (not confirmed)**

Two bot traffic bursts on shared-cpu VMs with 1GB RAM:

1. **4:21-4:30pm**: Distributed scraper — 2,772 requests from a botnet (2,232 IPs, rotating user agents). App handled it fine (p99 = 35ms, max 221ms, zero errors) but the volume of DB queries likely caused DB memory pressure.

2. **5:37pm**: Facebook Meta crawler — 74 hits in 1 minute, including 14 requests for `/id` (the identification guide — likely memory-intensive as it loads the full gall dataset). This burst directly preceded the app memory spike at 5:39pm and the down alert at 5:41pm.

The DB health check failure at 6:10pm (memory + IO pressure) is consistent with sustained load effects on the shared-cpu tier.

**What we can't confirm:**
- Whether the down alert was triggered by a health check timeout vs. external monitor false positive
- Whether `/id` is actually memory-intensive enough that 14 concurrent requests would cause visible memory pressure
- Root cause of the 2:08pm DB memory spike (no app logs from before the 1:47pm deploy)

## Separate Bugs Found During Investigation

These are unrelated to the down alert but were found in the logs:

1. **`FunctionClauseError` in `GallLive.Form.handle_event/3`** — multiple crashes (01:41, 02:59, 03:03, 04:29 UTC). Missing clause for some event.
2. **`FunctionClauseError` in `AliasHandlers.handle_update_new_ali`** — multiple crashes (03:16, 03:18, 03:55 UTC). Missing clause for alias update.
3. **Postgrex disconnect** at 02:19 UTC — DB connection timeout after 15s (client stuck in `:prim_inet.recv0/3`). Single occurrence.
4. **LiveView cross-session redirect warnings** — repeated `navigate event failed because you are redirecting across live_sessions` for gall pages.

## Actions Taken
- Investigation documented

## What We Still Don't Know
- What monitoring service generated the down alert and what it checks
- Whether the 2:08pm DB memory spike had a similar crawler cause
- Memory profile of the `/id` page under concurrent load
- Whether rate limiting would have prevented the memory pressure

## Recommended Next Steps
- **Rate limiting** (matter 220d is already planned): Would mitigate both the distributed scraper and crawler bursts
- Profile `/id` page memory usage under concurrent load
- Consider `robots.txt` crawl-delay directive for aggressive crawlers
- Fix the `FunctionClauseError` bugs in GallLive.Form and AliasHandlers
