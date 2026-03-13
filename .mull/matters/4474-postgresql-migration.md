---
status: planned
effort: 5-7 days
created: 2026-02-13
updated: 2026-03-13
epic: postgres
docs: [docs/plans/2026-02-12-sqlite-to-postgres-research.md]
relates: [1501, 9ca2, cd9d, eff3]
blocks: [f6bb]
docket: true
---

# PostgreSQL migration

## Context

Research complete — see `docs/plans/2026-02-12-sqlite-to-postgres-research.md` for full analysis (hosting, costs, FTS comparison, infrastructure inventory, risk assessment).

Decision to proceed driven by recurring SQLite production incidents (6+ in 5 weeks — write lock outages, OOM crashes, memory spikes). The single-writer constraint is a fundamental limitation that workarounds can't fix.

## Key Decisions

- **Big bang on an integration branch.** Dedicated focus, no dual-adapter complexity. Pull main as needed to stay in sync.
- **Fly self-managed Postgres.** Same datacenter, same vendor, sub-ms private network. Neon rejected — network hops, new vendor, new failure point.
- **Three Postgres instances.** Local (dev/test), preview (soak), production.
- **WCVP repo stays SQLite.** `ecto_sqlite3` remains as a dependency. Only the main Repo moves to Postgres.
- **Public downloadable DB format: TBD.** Currently .sqlite; may need to change as Postgres-specific types (arrays, JSONB, tsvector, PostGIS) make SQLite conversion untenable. Investigation in Phase 3c.
- **Soak on preview site.** Deploy the Postgres branch to the existing preview infrastructure against preview Postgres. Admin work + background tasks exercise the system. No traffic splitting, no routing.
- **Backups: pg_dump to S3 on a cron.** Reuses existing S3/IAM infra. RPO = cron interval (minutes, not seconds — acceptable). Restore-tested before cutover.
- **Cutover: in-place `fly deploy`.** No A→B routing, no cert swap. Site goes read-only (not dark), soak under real traffic, enable writes when confident. Read-only mode enables zero-data-loss rollback.
- **Schema from Ecto.** Baseline Postgres migration generated from Ecto schemas, not translated from SQLite. Replaces structure.sql as bootstrap. Old migration files deleted on the branch.
- **All code changes on the branch.** Litestream removal, doc updates, dead code deletion — all in Phase 2. Litestream infra cleanup (IAM/S3) in Phase 4 after soak.

## Phases

All child matters under this epic:

- **f6bb Phase 0** — Data audit + conversion tool + site ops features (refined)
- **f654 Phase 1** — Dev + CI workflow (refined)
- **b036 Phase 2** — Code port + docs + Litestream removal (refined)
- **1c9b Phase 3a** — Postgres infrastructure research + provisioning (raw)
- **f176 Phase 3b** — Preview site soak (raw)
- **1858 Phase 3c** — Dev + ops workflow + production provisioning (raw)
- **cead Phase 4** — Cutover (raw)

## Timeline

Goal: concrete plan and date by 2026-03-12 midday. Main work in 3-5 days. Cutover at end. Final soak and cleanup may extend beyond that.

## Risk Register

**Data conversion fidelity** — SQLite loose typing may hide data that Postgres rejects. Mitigated by Phase 0 data audit before writing any conversion code.

**Operational unknowns** — First time running Postgres on Fly. "App up, DB down" is a new failure mode. Mitigated by soak period on preview site (Phase 3b).

**Performance** — 140MB DB, network hop on every query. Mitigated by soak period with real admin operations.

**Backup confidence** — pg_dump cron is simpler than Litestream but untested. Mitigated by restore-testing during soak (Phase 3b).

**Coordination complexity** — Many steps during cutover. Mitigated by rehearsing on preview, read-only mode enabling zero-data-loss rollback (Phase 4).

**Read-only mode escape hatch** — If read-only flag is DB-stored and rollback is needed, admin UI can't turn it off. Need out-of-band mechanism. Decision deferred to Phase 0 implementation.

## Current Inventory (2026-03-11)

DB size ~140MB. 39 fragment/lower/LIKE calls in 8 app files. 2 GROUP_CONCAT calls. 3 fragment("date(?)") calls in analytics.ex. 2 migrations using safe_recreate_table. 55 async:false test files out of 99 total. 30 files referencing Litestream. 16 files with fragment() calls. 19 total migrations (all `use Gallformers.Migration`). App machine: shared-cpu 2 cores, 1GB RAM. Test seeds INSERT INTO species_fts (must be rewritten for Postgres). CI needs both Postgres and SQLite (WCVP tests).
