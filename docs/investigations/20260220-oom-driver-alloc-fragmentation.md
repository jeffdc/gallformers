# P2: OOM Crash — driver_alloc Fragmentation - February 20, 2026

## Status: Fixed — deploying cache_size reduction + RAM bump

## Summary

Production experienced an OOM kill at ~14:22 UTC (9:22 AM ET) on Feb 20. This is the third
OOM incident (after Feb 15 and Feb 18). Unlike previous incidents attributed to gradual
LiveView memory accumulation, this crash was caused by **ecto_sqlite3's page cache default
consuming more memory than the machine has RAM**.

ecto_sqlite3 sets `PRAGMA cache_size = -64000` by default — 62.5 MB per connection. With 10
connections in the pool, the theoretical page cache ceiling is **625 MB**, exceeding the
machine's 512 MB RAM. All SQLite memory is allocated through the BEAM's `driver_alloc` via
exqlite's NIF, and the BEAM does not return freed carrier memory to the OS. The combination
of an oversized page cache ceiling and BEAM carrier retention made OOM inevitable.

## Correction Notice

The initial draft of this investigation (written by a previous AI agent) contained a
significant error in the page cache analysis. It claimed SQLite's default page cache was
"2000 pages × 4KB × 10 connections = 80 MB," confusing SQLite's raw default (`-2000`, i.e.
2 MB/connection) with what ecto_sqlite3 actually configures. The real value set by
ecto_sqlite3 is `-64000` (62.5 MB/connection), found in
`deps/ecto_sqlite3/lib/ecto/adapters/sqlite3/connection.ex:24`. The agent did not trace the
actual code path from ecto_sqlite3 through exqlite — it assumed SQLite's own default was in
effect when ecto_sqlite3 overrides it to a value nearly 8x larger. The corrected analysis
follows.

## Impact

- **OOM restart**: ~90 second outage at ~14:22 UTC
- **No data loss**: Litestream WAL sync (5s interval) ensures durability
- **Memory climbing post-restart**: 99.3 MB driver_alloc carrier already reserved within
  ~1.5 hours of restart

## Machine Info

- Machine: `7847515a205e68` (blue-dawn-7651)
- Size: `shared-cpu-1x:512MB` (being bumped to 1GB)
- Region: iad
- Last updated: `2026-02-20T14:23:39Z` (OOM restart)

## Timeline (all UTC, ET = UTC-5)

| Time (UTC) | Time (ET) | Event |
|------------|-----------|-------|
| Feb 18 ~10:00 | ~05:00 AM | Previous OOM restart |
| Feb 18 ~17:17 | ~12:17 PM | Deploy with hibernate_after + admin pagination fixes |
| Feb 18 10:00 → Feb 20 14:22 | — | **52 hours of stable uptime** (vs 18-24h pre-fix) |
| Feb 20 04:30-09:15 ET | 09:30-14:15 | Memory flat at ~350 MiB for 5+ hours |
| Feb 20 14:22:15 | 09:22:15 AM | Step-function memory spike (~100 MiB in 15 seconds) |
| Feb 20 14:22:21 | 09:22:21 AM | Last request before gap: `GET /genus/501` (8ms) |
| Feb 20 14:23:39 | 09:23:39 AM | Machine restarted by Fly (OOM kill) |
| Feb 20 14:23:51 | 09:23:51 AM | First request after restart: `GET /health` |
| Feb 20 ~15:50 | ~10:50 AM | LiveDashboard inspection: driver_alloc at 99.3 MB carrier |

## Findings

### 1. Step-Function Spike, Not Gradual Accumulation

The Fly memory graph shows memory was **flat at ~350 MiB for 5+ hours** (04:30-09:15 ET),
then jumped ~100 MiB in a 15-second window (09:22:15-09:22:30 ET), triggering the OOM kill.

This is fundamentally different from the Feb 18 pattern (gradual climb over 18-24 hours).
Something allocated a large chunk of memory in one shot.

### 2. No HTTP Request Trigger

Request logs show only 3 requests in the spike window:
- `14:22:18` — `GET /gall/1858` (26ms, Amazonbot)
- `14:22:19` — `GET /health` (0ms, Consul)
- `14:22:21` — `GET /genus/501` (8ms, Amazonbot)

All fast, all normal. No admin activity, no image processing, no PDF generation, no heavy
pages. The trigger was **not from HTTP traffic**.

### 3. driver_alloc Is the Smoking Gun

LiveDashboard memory allocator inspection ~1.5 hours after restart:

| Allocator | Block size (in use) | Carrier size (reserved) | Waste |
|-----------|--------------------:|------------------------:|------:|
| `driver_alloc` | **3.5 MB** | **99.3 MB** | **95.8 MB** |
| `ll_alloc` | 34.6 MB | 55.0 MB | 20.4 MB |
| `eheap_alloc` | 14.0 MB | 22.9 MB | 8.9 MB |
| `literal_alloc` | 14.0 MB | 15.0 MB | 1.0 MB |
| All others | ~4 MB | ~13 MB | ~9 MB |
| **Total** | **70.2 MB** | **205.6 MB** | **135.4 MB** |

`driver_alloc` accounts for **71% of all wasted memory**. The BEAM allocates memory for
NIF drivers in "carriers" — large OS-level allocations that are subdivided into blocks.
When blocks are freed, the carrier remains reserved. The BEAM does not aggressively return
carrier memory to the OS.

`driver_alloc` is used by:
- **exqlite** (SQLite NIF) — the primary suspect given the 38 MB database
- **Vix/libvips** (image processing NIF) — loaded but not actively processing

### 4. The OOM Mechanism

Based on the evidence:

1. Normal operating state: ~350 MiB (BEAM carriers + Litestream + OS overhead)
2. Something triggered a large NIF allocation through `driver_alloc`
3. The BEAM requested a new carrier from the OS (~100 MiB)
4. Total memory exceeded the 512 MB limit → OOM kill
5. After restart, `driver_alloc` quickly re-acquires a large carrier (99.3 MB within 1.5h)

The carrier size (99.3 MB) is already at the OOM-triggering level post-restart. The next
large NIF operation could cause another OOM.

### 5. Previous Mitigations Are Working

The Feb 18 deploy included:
- `hibernate_after: 5_000` on all LiveView processes ✓ (in config.exs)
- Server-side pagination on admin index pages ✓
- AuditCache rework (on-demand only, hibernate) ✓
- AuditCache S3 scan disabled in prod ✓

These changes extended stable uptime from 18-24 hours to **52 hours**. The gradual LiveView
accumulation is fixed. This OOM has a different, more acute trigger.

### 6. Traffic Was Normal

| Metric | Feb 19 (no crash) | Feb 20 (crash) |
|--------|------------------:|---------------:|
| Requests (to 14:22 UTC) | ~23,500 est. | 23,624 |
| Request rate (proj. 24h) | 39,534 | ~39,455 |
| Max p95 response time | 51ms | 61ms |
| Unique IPs | 388 | 242 |

No traffic anomaly. The crash was not load-driven.

### 7. ETS Tables Are Clean

74 ETS tables, all normal sizes. Largest: `:code_server` at 2.3 MB. `Gallformers.Repo`
at 229 KB. No runaway growth.

### 8. Process Count Is Normal

577-579 processes. Top processes by memory:
- `:code_server`: 4.5 MB (normal)
- LiveView socket (LiveDashboard): 2.5 MB (expected)
- Various LiveView sockets: 150-600 KB each
- No runaway processes

### 9. exqlite Routes ALL SQLite Memory Through driver_alloc

Source inspection of `deps/exqlite/c_src/sqlite3_nif.c` confirmed that exqlite installs a
custom SQLite memory allocator at NIF load time (line 1142):

```c
sqlite3_config(SQLITE_CONFIG_MALLOC, &methods);
```

Every `exqlite_malloc` call goes through `enif_alloc` (line 69), which routes to the BEAM's
`driver_alloc`. This means SQLite's **page cache, WAL buffers, statement caches, and all
internal memory** flow through `driver_alloc` carriers.

This is hardcoded — there is no configuration option to disable it.

### 10. ecto_sqlite3's Page Cache Default Is the Root Cause

The actual page cache configuration, traced through the code:

1. **Gallformers config** — No `cache_size` option set in `runtime.exs`, `dev.exs`, or
   `test.exs`
2. **ecto_sqlite3** — `deps/ecto_sqlite3/lib/ecto/adapters/sqlite3/connection.ex:24` injects
   `cache_size: -64_000` via `Keyword.put_new` before passing options to exqlite
3. **exqlite** — `deps/exqlite/lib/exqlite/connection.ex:482` calls
   `Pragma.cache_size(options)` → returns `-64000` → executes `PRAGMA cache_size = -64000`
4. **SQLite** — `-64000` means 64,000 KiB = **62.5 MB per connection**

With 10 connections in production:

| Per connection | Total (10 connections) | Machine RAM |
|---------------:|-----------------------:|------------:|
| 62.5 MB        | **625 MB**             | 512 MB      |

**The page cache ceiling alone exceeds machine RAM.** Even if not all connections fill
their caches simultaneously, the BEAM's carrier retention means memory ratchets upward
over time. Once enough pages are cached across connections, the carriers grow to ~100 MB
and any additional spike (WAL checkpoint, concurrent queries) pushes past the limit.

For context, SQLite's own default is `-2000` (2 MB/connection). ecto_sqlite3 overrides
this to `-64000` as a performance optimization — reasonable for a server with gigabytes
of RAM, but catastrophic on a 512 MB machine.

### 11. The Carrier Fragmentation Problem

The BEAM allocates `driver_alloc` carriers in progressively larger chunks. Once allocated,
carriers are **not returned to the OS** even when the blocks within them are freed. This is
by design — the BEAM reuses carriers for future allocations. But on a memory-constrained
machine (512 MB), this means:

1. SQLite page caches fill up across connections → `driver_alloc` carriers grow
2. Blocks are freed when queries complete or connections idle
3. Carriers remain reserved (99.3 MB carrier with only 3.5 MB in blocks)
4. A spike operation (WAL checkpoint, large query) needs new memory
5. BEAM requests additional carrier from OS → pushes past 512 MB limit → OOM

Research from [Erlang Forums](https://erlangforums.com/t/vm-settings-to-combat-large-single-block-carriers-and-fragmentation/1958)
and [OTP Issue #9521](https://github.com/erlang/otp/issues/9521) confirms that `driver_alloc`
carrier fragmentation is a known BEAM behavior. Tuning `+Mdrlmbcs` (largest multiblock
carrier size) alone can worsen fragmentation — the `sbct` (singleblock carrier threshold)
must be adjusted in tandem.

## Root Cause

**Primary**: ecto_sqlite3 sets `PRAGMA cache_size = -64000` by default (62.5 MB per
connection). With 10 connections, the page cache ceiling is 625 MB — exceeding the 512 MB
machine limit. All SQLite memory flows through the BEAM's `driver_alloc` allocator (via
exqlite's NIF), and the BEAM does not return freed carrier memory to the OS. Over time,
page cache allocations inflate `driver_alloc` carriers to ~100 MB, and any spike pushes
total memory past the OOM threshold.

**Trigger for the step-function**: Most likely a WAL checkpoint or burst of queries across
multiple connections causing simultaneous page cache growth. When the existing `driver_alloc`
carrier(s) couldn't accommodate the spike, the BEAM requested a new carrier from the OS,
pushing total memory past 512 MB.

**Not the cause**: HTTP traffic, bot crawlers, LiveView accumulation, ETS growth, AuditCache,
image processing, PDF generation, Litestream 24h snapshot (timing doesn't align).

## Actions

### Complete

- [x] **Bump RAM to 1GB** — changed `fly.toml` from 512mb to 1024mb. Provides safety
  margin while deploying the cache fix. Takes effect on next deploy.
- [x] **Reduce SQLite page cache to SQLite default** — Added `cache_size: -2000` to Repo
  config in `runtime.exs`, `dev.exs`, and `test.exs`. This overrides ecto_sqlite3's default
  of `-64000`, reducing per-connection page cache from 62.5 MB to 2 MB. Total page cache
  ceiling drops from 625 MB to 20 MB across 10 connections. For a 38 MB database serving
  <1 req/sec, 2 MB/connection is sufficient.

### Deferred

- **BEAM allocator tuning** — `+Mdrlmbcs`/`+Mdrsbct`/`+MBacul` flags. Less urgent now
  that the page cache ceiling is reduced from 625 MB to 20 MB. May revisit if
  `driver_alloc` carrier waste remains high after deploy.
- **Memory telemetry** — Wire up `driver_alloc` carrier vs block size to the telemetry
  poller for continuous visibility. Still valuable for future diagnosis.
- **Reduce connection pool size** — Currently 10, could be 5 for this traffic level. Less
  urgent now that per-connection cache is small. Hold for observation.
- Rate limiting on all routes (matter 220d) — not the trigger for this OOM
- Convert read-only pages to controllers (matter 9ad7) — not the trigger for this OOM

## What We Still Don't Know

1. **Whether the cache_size fix fully resolves carrier fragmentation** — the page cache is
   the dominant source of `driver_alloc` usage, but WAL buffers and statement caches also
   contribute. The 1 GB RAM bump provides margin while we observe.
2. **Whether the carrier size stabilizes at a reasonable level** — with 1 GB we can observe
   the long-term carrier behavior without OOM interference.
3. **Whether Litestream WAL checkpoints cause transient spikes above the carrier baseline** —
   even with small page caches, a checkpoint touching many pages might cause a temporary
   allocation burst.

## Relationship to Previous Incidents

| Incident | Uptime before OOM | Pattern | Primary cause |
|----------|------------------:|---------|---------------|
| Feb 15 | ~6-12 hours | Escalating spikes at Litestream 1h interval | Litestream 1h snapshots + BEAM retention |
| Feb 18 | ~18-24 hours | Gradual climb | LiveView accumulation (no hibernate, unbounded admin pages) |
| **Feb 20** | **~52 hours** | **Flat then step-function** | **ecto_sqlite3 page cache default (625 MB ceiling on 512 MB machine)** |

Each incident had a different primary trigger. The Feb 18 fixes (hibernate_after, pagination)
successfully addressed the gradual accumulation. This new pattern — an oversized page cache
default from the database adapter — is a distinct configuration issue that was previously
masked by the faster gradual OOM.

## Infrastructure Reference

- **Machine**: shared-cpu-1x, 512MB RAM → 1024MB (pending deploy), iad region
- **Database**: SQLite ~38MB, WAL mode
- **Litestream**: sync-interval 5s, snapshot-interval 24h
- **Connection pool**: 10 (runtime.exs)
- **Page cache**: `-2000` per connection (2 MB), overriding ecto_sqlite3 default of `-64000`
- **Health check**: every 30s, 5s timeout
- **Concurrency limit**: soft 200, hard 250 (fly.toml)

## Related

- [20260218-oom-crash-bot-traffic-memory-accumulation.md](20260218-oom-crash-bot-traffic-memory-accumulation.md) —
  Previous OOM, different root cause (LiveView accumulation)
- [20260215-request-log-anomalies-oom.md](20260215-request-log-anomalies-oom.md) —
  First OOM (Litestream snapshot interval)
- Matter 8ae6 — LiveView memory tuning (deployed, working)
- Matter ee67 — AuditCache rework (deployed, working)
- Matter 9ad7 — Audit LiveView usage (deferred)
- Matter 220d — Rate limiting expansion (deferred)
