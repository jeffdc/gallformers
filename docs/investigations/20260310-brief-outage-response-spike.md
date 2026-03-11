# P3: 30-Second Outage / Response Time Spike - March 10, 2026

## Status: Closed — root cause confirmed, fix applied

## Summary

Production experienced a ~45-second degradation at 8:05 PM ET (00:05 UTC March 11) where
incoming requests were blocked, with response times spiking to 10-20 seconds. Caused by the
`Gallformers.Analytics.Rollup` GenServer running a heavy write transaction against SQLite at
exactly 00:05 UTC every night — during prime-time US traffic hours.

Investigation revealed this is a **recurring nightly event**, not a one-off. The same pattern
appears at exactly 00:05:21 UTC on both March 10 and March 11. The rollup was also 3 days
behind (last rolled-up date: March 7), meaning each night it processed more backlog, making
the freeze progressively longer.

## Impact

- **Duration**: ~45 seconds (8:05:01 PM - 8:05:46 PM ET)
- **Scope**: All incoming requests blocked — 9 requests completed with 10,000-19,940ms
  latency. Two requests returned 500 on the previous night's occurrence.
- **Recurrence**: Happening every night at 00:05 UTC since rollup was deployed.

## Machine Info

- Machine: `7847515a205e68` (blue-dawn-7651)
- Size: `shared-cpu-2x:1024MB`
- Region: iad
- Release: v143
- No machine restart events (health watchdog not triggered — freeze < 2.5 min threshold)

## Timeline (all ET = UTC-4 EDT)

| Time | Event |
|------|-------|
| 8:05:01 PM | Last normal-latency requests (`/host/1886` 6ms, `/host/3955` 2ms) |
| 8:05:01 PM | Analytics rollup GenServer fires `:run_rollup`, opens write transaction |
| 8:05:01 - 8:05:11 PM | 10-second gap — no requests logged (blocked by SQLite busy_timeout) |
| 8:05:11 PM | 3 requests squeak through (4-14ms) — brief lock release between operations |
| 8:05:11 - 8:05:21 PM | Second 10-second block — more requests queue up |
| 8:05:21 PM | Transaction commits — 20 queued requests drain simultaneously |
| 8:05:21 PM | `/host/1976` completes with **19,940ms** duration (arrived at ~8:05:01) |
| 8:05:21 PM | 8 other requests complete with ~10,000ms durations (arrived at ~8:05:11) |
| 8:05:21 - 8:05:46 PM | `prune_old_page_views()` runs — another write operation blocks |
| 8:05:46 PM | Full recovery — all requests return to normal 0-24ms latency |

## Root Cause Analysis

### Root cause confirmed: `Analytics.Rollup` write transaction at 00:05 UTC

The `Gallformers.Analytics.Rollup` GenServer schedules itself to run at 00:05 UTC daily
(line 164: `~T[00:05:00]`). It performs:

1. `rollup_day/1` — wraps 5 aggregate queries + DELETE/INSERT cycles in a single
   `Repo.transaction`, holding a SQLite write lock for the entire duration
2. `prune_old_page_views/1` — `Repo.delete_all()` on rows older than 90 days

The write transaction blocks incoming read requests because SQLite's `busy_timeout` is
configured at 10,000ms (line 84 of `config/runtime.exs`). Requests that arrive during the
lock wait up to 10 seconds, matching the observed ~10,000ms durations exactly.

**Evidence:**
- 00:05:21 UTC timestamp matches on both March 10 and March 11
- Request durations of ~10,000ms = `busy_timeout: 10_000` exactly
- 500 errors on March 10 = `SQLITE_BUSY` timeout exceeded
- `/host/1976` duration of 19,940ms ≈ 2× busy_timeout (hit twice: rollup + prune)
- Zero non-GET requests in the hour before — no admin/write activity
- No machine events, no deploys, no platform incidents

**Compounding factors:**
- Rollup was 3 days behind (last rolled-up: March 7), processing multiple days per run
- `page_views` table has 521K rows — aggregation queries are heavy
- Single transaction wraps all 5 summary table operations, maximizing lock duration

### Likely connection to March 9 outage

Yesterday's 90-minute unresponsive incident (00260309 investigation) was at 2:52 PM ET —
NOT at 00:05 UTC, so it was not directly caused by the rollup. However, the rollup's
nightly failures (it was already behind) may have contributed to database stress that
made the system more fragile.

## Actions Taken

- Moved rollup schedule from 00:05 UTC (8:05 PM ET) to 07:00 UTC (3:00 AM ET)

## Remaining Work

- Break the single large `Repo.transaction` into per-table mini-transactions
- Process one day at a time with yields between days to avoid long lock holds
- Consider running rollup catch-up in smaller batches

## Related

- [20260309 - 90-Minute Unresponsive Outage](20260309-unresponsive-crash-cpu-investigation.md)
