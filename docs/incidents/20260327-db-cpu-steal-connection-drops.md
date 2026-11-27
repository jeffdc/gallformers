# P3: DB Connection Pool Failures from CPU Steal - March 27, 2026

## Status: Closed — resolved by migrating DB to ewr region

## Summary

Production experienced two waves of degradation at 10:54 AM and 11:00 AM ET caused by
the Fly Postgres DB machine's shared CPU being stolen by co-tenant workloads. CPU steal
on the DB host is chronically elevated (4-8%, frequently exceeding the 6.25% baseline)
with spikes to 25.5%. During steal spikes, Postgres or the Fly proxy cannot service TCP
keepalives, causing the app's entire Postgrex connection pool to disconnect simultaneously.

**Root cause: CPU steal on the shared-cpu DB host.** The DB machine (`shared-cpu-1x:1024MB`)
is on an overcommitted host. This is an infrastructure problem, not an application problem.

7-day Grafana history showed zero steal before today, so this was a new noisy neighbor on
the iad host — not a chronic condition. This rules out the March 24 incident being the same
root cause (no steal visible then).

## Impact

- **Degradation window**: ~9 minutes across two waves (10:54-10:57, 11:00-11:03 ET)
- **500 errors served**: 7 (across /gall, /host, /place, /source pages)
- **503 health check failures**: 2
- **No full outage** — static assets and pages not requiring DB continued to serve

## Machine Info

**App machine:**
- Machine: `7847515a205e68` (blue-dawn-7651)
- Size: `shared-cpu-1x:1024MB`
- Region: iad
- Release: v156 (deployed 2026-03-25 16:00 UTC — 2 days before incident)

**DB machine:**
- Machine: `e7844005a57d48` (little-pond-6820)
- Size: `shared-cpu-1x:1024MB`
- Region: iad
- Image: `flyio/postgres-flex:17.2`
- VM check status during incident: **critical** — "cpu: system spent 1.13s of the last 10 seconds waiting on cpu"

## Timeline (all ET = UTC-4 EDT)

| Time (ET) | Time (UTC) | Event |
|-----------|------------|-------|
| **Wave 1** | | |
| 10:54:25 AM | 14:54:25 | First Postgrex disconnects — db_conn_1, db_conn_8, db_conn_3 via "tcp recv (idle): timeout" |
| 10:54:31 AM | 14:54:31 | db_conn_10 disconnects |
| 10:54:45 AM | 14:54:45 | Remaining pool connections (2,4,5,6,7,9) disconnect simultaneously |
| 10:54:52 AM | 14:54:52 | First 500: GET /gall/3793 (5191ms — queued waiting for connection) |
| 10:54:56 AM | 14:54:56 | 500s: /host/4717 (2365ms), /gall/5849 (1978ms). Health check 503 (3790ms) |
| ~10:57 AM | ~14:57 | Pool reconnects, 200s resume |
| **Wave 2** | | |
| 11:00:27 AM | 15:00:27 | Postgrex disconnects begin again — db_conn_4 first |
| 11:00:45 AM | 15:00:45 | db_conn_10 disconnects |
| 11:00:57 AM | 15:00:57 | Mass disconnect — all remaining pool connections (1-9) drop within 3 seconds |
| 11:01:12 AM | 15:01:12 | First 500: GET /gall/1385 (5926ms) — "connection not available, request dropped from queue after 5925ms" |
| 11:01:14 AM | 15:01:14 | Multiple connections fail to reconnect: "handshaking for longer than 15000ms" |
| 11:01:26 AM | 15:01:26 | 500s: /place/GP (4856ms), /host/3290 (4017ms), /source/405 (1619ms). Health check 503 |
| 11:01:26 AM | 15:01:26 | Task process crash — DBConnection.ConnectionError |
| 11:01:27 - 11:03:01 AM | 15:01:27 - 15:03:01 | Connections cycle between handshake timeout and disconnect repeatedly |
| 11:03:01 AM | 15:03:01 | First successful 200: GET /gall/1652 (67ms) — pool recovering |
| **Post-incident** | | |
| 11:26 AM | 15:26 | Down alarm fires (delayed ~26 minutes from first wave) |
| **Mitigation** | | |
| ~1:55 PM | ~17:55 | Attempted stop/start of iad DB machine to move to new host |
| ~1:56 PM | ~17:56 | `fly machine start` fails: "insufficient resources available to fulfill request" — iad shared-cpu fully saturated |
| ~1:58 PM | ~17:58 | `fly machine clone` also fails: "insufficient CPUs available to fulfill request" — no shared-cpu capacity in iad at all |
| ~2:01 PM | 18:01 | `fly volumes fork` to iad succeeds (vol_r1lkn27mm9336704) — data copied but no machine to attach it to |
| ~2:05 PM | 18:05 | `fly volumes fork` to ewr succeeds (vol_r637ewjw2xyy7qjr) |
| ~2:06 PM | 18:06 | `fly machine clone` to ewr with forked volume succeeds — new DB machine `85379da4457e68` (black-river-3516) starts in ewr |
| ~2:06 PM | 18:06 | Old iad machine spontaneously restarts (capacity freed up during fork/clone) — two primaries briefly running |
| ~2:09 PM | 18:09 | Disabled autostart on old iad machine, stopped it. App fails over to ewr DB |
| ~2:10 PM | 18:10 | Site confirmed healthy on ewr DB — incident resolved |
| ~2:15 PM | 18:15 | Fly posts status: **"Low capacity in IAD"** — region-wide saturation confirmed. Machine starts failing, deploys may fail even for non-IAD apps. Not just a bad host — the entire region is overcommitted. |
| ~2:02 PM | 18:02 | App server in iad goes down briefly, restarts with 10-15% steal and CPU credits burned to zero on boot |
| ~2:20 PM | 18:20 | Forked app volume to ewr (`vol_42lpw56y5wlp5z1r`) |
| ~2:22 PM | 18:22 | Cloned app machine to ewr — new machine `4d893e0dc36218` (damp-dust-4976) |
| ~2:25 PM | 18:25 | Stopped iad app machine via UI. All infrastructure now in ewr |
| ~2:30 PM | 18:30 | Site confirmed stable on ewr. Updated `fly.toml` primary_region to ewr |

## Precursor

- 2026-03-26 00:30 UTC: Single 500 on `/source/14` with exactly 15000ms timeout — DB connectivity hiccup

## What We Ruled Out

| Cause | Evidence |
|-------|----------|
| **Code change** | Last deploy was March 25, 2 days prior |
| **Memory (app)** | Grafana stable, no OOM |
| **Memory (DB)** | "system spent 0s of the last 60s waiting on memory" |
| **Disk (DB)** | 30% free, well below 90% readonly threshold |
| **I/O (DB)** | "system spent 0s of the last 60s waiting on io" |
| **Traffic spike** | Normal request volume; 404 bursts at 15:04 and 15:25 UTC are unrelated (vuln scanner + logo-probing bot) |
| **Host maintenance** | `fly incidents hosts list` clean for both apps |
| **Platform-wide incident** | No status page reports |
| **App-level error** | Zero non-Postgrex errors today |
| **Connection pool saturation** | DB shows 21 used of 300 max connections |

## Root Cause Analysis

**Confirmed: CPU steal on the DB host.**

Evidence from Grafana (DB machine, `gallformers-db`, instance `e7844005a57d48`):

- CPU steal is **chronically elevated at 4-8%**, frequently exceeding the 6.25% baseline
- At 1:22 PM ET (post-incident), steal measured at **25.5%** — a quarter of the DB's CPU time taken by co-tenants
- CPU utilization from Postgres itself is only 2-5% — the DB workload is minimal
- CPU balance stays at 8.33 minutes — credits are available but cannot be used because the issue is steal, not burst
- The `vm` health check was **critical** during the incident: "system spent 1.13s of the last 10 seconds waiting on cpu"

**Mechanism:** When CPU steal spikes, Postgres or the Fly proxy cannot respond to TCP keepalives within the kernel timeout. The app's Postgrex pool sees all connections drop simultaneously ("tcp recv (idle): closed/timeout"). Reconnection attempts then fail with "handshaking for longer than 15000ms" because the DB-side handshake process is also CPU-starved.

**Not the same as March 24:** 7-day Grafana history showed zero steal before today, so the
March 24 incident had a different (still undetermined) root cause.

## Actions Taken

1. Attempted stop/start of iad DB machine — failed, iad shared-cpu fully saturated
2. Attempted clone in iad — also failed, no shared-cpu capacity in region
3. Forked volume to ewr region (`vol_r637ewjw2xyy7qjr`)
4. Cloned DB machine to ewr with forked volume — new machine `85379da4457e68` (black-river-3516)
5. Disabled autostart on old iad machine, stopped it
6. App reconnected to ewr DB, site healthy

**All infrastructure migrated from iad to ewr** during the incident. Both app and DB now
in ewr (Secaucus, NJ). `fly.toml` updated to `primary_region = "ewr"`.

## Cleanup Remaining

- [x] Orphaned iad forked volume `vol_r1lkn27mm9336704` — delete once ewr is stable (done; Jeff, 2026-11-27)
- [x] Old iad machine `e7844005a57d48` — stopped with autostart disabled, remove after confidence period (done; Jeff, 2026-11-27)
- [x] Original iad volume `vol_vz56250m1w58mozv` — attached to old machine, remove with it (done; Jeff, 2026-11-27)
- [x] Verify WCVP database is accessible on ewr instance (done; Jeff, 2026-11-27)

## Lessons Learned

1. **Fly shared-cpu is not comparable to a dedicated droplet.** 3+ years on DigitalOcean ($24/mo)
   with near-zero incidents vs ~14 investigations in 2 months on Fly shared-cpu. The shared-cpu
   tier is a fundamentally different reliability contract.

2. **iad shared-cpu can become fully saturated.** When we needed to move the DB, the entire
   region had no shared-cpu capacity. A stop/start strategy for escaping a bad host can leave
   you with no running machine.

3. **`fly volumes fork` + `fly machine clone --attach-volume` is the safe migration path.**
   Fork the volume first (preserves data), then clone the machine to a region with capacity.
   Never stop a machine hoping to restart it elsewhere — the volume pins you and capacity
   isn't guaranteed.

4. **Evaluate whether Fly is the right platform for this workload.** Performance-cpu ($60.50/mo)
   would resolve the shared-cpu class of incidents but costs 2.5x what DigitalOcean did.
   The Postgres migration (SQLite → Postgres) was the important architectural win and is portable.

## Related

- `20260324-afternoon-outage-bot-traffic.md` — same symptoms, different root cause (no steal visible in 7-day history)
- `20260309-unresponsive-crash-cpu-investigation.md` — different root cause (host maintenance), same shared-cpu infrastructure
