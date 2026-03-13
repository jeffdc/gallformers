---
status: raw
created: 2026-03-11
updated: 2026-03-13
epic: postgres
blocks: [f176]
needs: [b036]
parent: 4474
---

# Phase 3a: Postgres infrastructure research + provisioning

## Status: Partially complete — data loading approach needs redesign

## Completed

### Infrastructure provisioned
- **App name**: `gallformers-db`
- **Machine**: `e7844005a57d48` (little-pond-6820), iad region
- **Image**: `flyio/postgres-flex:17.2` (v0.1.0)
- **Size**: shared-cpu-1x, 1024MB RAM
- **Volume**: `vol_vz56250m1w58mozv` (2GB)
- **Auto-stop/auto-start**: enabled (suitable for preview, NOT for production)
- **Attached to**: `gallformers-preview` (DATABASE_URL secret set)
- **NOT attached to**: production `gallformers` app

### Code
- `Gallformers.Convert` module extracted from Mix task — clean, tested, works locally via release eval
- `mix convert_sqlite` is now a thin wrapper around `Gallformers.Convert.convert/1`
- Test seed sequence collisions fixed (setval calls in test_seeds.sql)
- Async persistent_term leak fixed (enforce_read_only_test.exs)
- Migrations run successfully on Fly Postgres from release eval

### Fly Postgres connectivity requirements (verified)
- `.flycast` hostnames for internal DNS (NOT `.internal`)
- `ERL_AFLAGS="-proto_dist inet6_tcp"` in `rel/env.sh.eex`
- `socket_options: [:inet6]` on Repo config in runtime.exs
- These were reverted since data loading approach is being redesigned, but MUST be re-added when preview connects to Postgres for serving traffic

## Not completed

### Data loading into Fly Postgres
The SQLite→Postgres conversion via release eval on Fly is non-viable:
- Exqlite DBConnection pool times out during cold boot (~45s to establish)
- Even when it works, conversion takes 6+ minutes on shared-cpu machine
- Fly auto-stop kills the machine during/after conversion, causing re-conversion loops
- Three BEAM boots per deploy (migrate eval + convert eval + server) is fragile

**Needs a new approach.** Options to evaluate:
1. pg_dump locally → upload to S3 → pg_restore in entrypoint (no BEAM needed)
2. pg_dump from CI pipeline
3. Direct Postgres-to-Postgres replication
4. fly proxy + local pg_restore

### Backups
Not configured or tested. Fly postgres-flex includes barman but needs verification.

### Production provisioning checklist (for matter cead)
- `fly postgres create --name gallformers-db-prod --region iad --vm-size shared-cpu-1x --volume-size 10 --initial-cluster-size 1`
- Bump RAM to 1GB+: `fly machine update <id> --memory 1024 -a gallformers-db-prod`
- Do NOT enable auto-stop for production
- `fly postgres attach gallformers -a gallformers-db-prod`
- Clean up Litestream secrets
- Rename S3 IAM user

