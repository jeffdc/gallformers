# PostgreSQL Migration Cutover

Procedures for loading data into Fly Postgres and cutting production over from SQLite.

**Related matters:** Phase 3a (1c9b — infrastructure), Phase 4 (cead — cutover)

## Architecture Overview

| Environment | App | Database | DB App |
|-------------|-----|----------|--------|
| Local dev | N/A | `gallformers_dev` (local Postgres) | N/A |
| Preview | `gallformers-preview` | Fly Postgres | `gallformers-db` |
| Production | `gallformers` | SQLite on volume (current) | N/A |
| Production (post-cutover) | `gallformers` | Fly Postgres | `gallformers-prod-db` (to be provisioned) |

The data pipeline is always: **SQLite (S3 snapshot) -> local Postgres -> pg_dump -> fly proxy -> pg_restore into Fly Postgres**.

Running the conversion on Fly machines directly is not viable (pool timeouts, slow CPUs, auto-stop interference). All conversion happens locally.

## Preview Data Loading

Use this procedure to load or refresh production data in the preview Postgres.

### Prerequisites

- Local Postgres running with `gallformers_dev` database
- Fly CLI authenticated (`fly auth login`)
- `psql` and `pg_dump`/`pg_restore` installed locally

### Step 1: Download production SQLite

```bash
make download-db
```

Downloads `priv/gallformers.sqlite` from S3 (updated daily by GitHub Actions).

### Step 2: Convert SQLite to local Postgres

```bash
mix ecto.reset        # Drop, create, migrate (clean slate)
mix convert_sqlite    # Reads priv/gallformers.sqlite, writes to gallformers_dev
```

The convert task truncates all tables first, then loads in FK dependency order with type conversions (booleans, deduplication, column filtering). Takes ~30 seconds locally.

Verify it worked:

```bash
psql -d gallformers_dev -c "SELECT count(*) FROM species;"
```

### Step 3: Dump local Postgres

```bash
pg_dump --format=custom --no-owner --no-acl gallformers_dev > /tmp/gallformers.dump
```

The `--format=custom` flag produces a compressed binary format that `pg_restore` can selectively restore. `--no-owner` and `--no-acl` drop ownership/permissions so the remote user can own everything.

### Step 4: Open a proxy to Fly Postgres

```bash
fly proxy 15432:5432 -a gallformers-db
```

This binds local port 15432 to the Fly Postgres machine. Leave this running in a separate terminal.

**If the Postgres machine is stopped** (auto-stop is enabled for preview):

```bash
fly machine list -a gallformers-db         # Check state
fly machine start <machine-id> -a gallformers-db   # Start if stopped
```

### Step 5: Restore into Fly Postgres

Get the connection credentials from the app's DATABASE_URL secret:

```bash
# fly secrets list only shows names, not values. To retrieve the URL:
fly ssh console -a gallformers-preview -C 'printenv DATABASE_URL'
# Format: postgres://gallformers_preview:PASSWORD@gallformers-db.flycast:5432/gallformers_preview?sslmode=disable
# Extract the username, password, and database name
```

Restore:

```bash
pg_restore \
  --host=localhost \
  --port=15432 \
  --username=gallformers_preview \
  --dbname=gallformers_preview \
  --no-owner \
  --no-acl \
  --clean \
  --if-exists \
  /tmp/gallformers.dump
```

Enter the password from DATABASE_URL when prompted. The `--clean --if-exists` flags drop existing objects before recreating them, making this safe to re-run.

**Note:** You will see errors about the `public` schema and extensions (pg_stat_statements, etc.) owned by `flypgadmin`. These are safe to ignore — Fly manages those objects.

### Step 6: Verify

```bash
psql \
  --host=localhost \
  --port=15432 \
  --username=gallformers_preview \
  --dbname=gallformers_preview \
  -c "SELECT count(*) FROM species;"
```

Compare the count against local dev:

```bash
psql -d gallformers_dev -c "SELECT count(*) FROM species;"
```

### Step 7: Deploy preview and test

```bash
make preview
```

Browse `https://gallformers-preview.fly.dev` and spot-check species pages, search, browse, maps.

## Production Cutover (Phase 4)

This section is a high-level plan. The exact commands will be refined during rehearsal on the preview environment.

### Pre-cutover (weeks before)

1. **Provision production Postgres** (see Phase 4 matter cead for checklist):
   ```bash
   fly postgres create --name gallformers-prod-db --region iad \
     --vm-size shared-cpu-1x --volume-size 10 --initial-cluster-size 1
   fly machine update <id> --memory 1024 -a gallformers-prod-db --yes
   fly postgres attach gallformers-prod-db --app gallformers
   ```
2. **Do NOT enable auto-stop** on production Postgres.
3. **Rehearse** the full cutover procedure on preview at least once.
4. **Announce** maintenance window on Discord and the site maintenance banner (built in Phase 0).

### Cutover procedure

| Step | Action | Verify |
|------|--------|--------|
| 1 | Put site in read-only mode (auth plug flag) | Admin pages reject writes |
| 2 | Wait for in-flight requests to drain (~1 min) | Check fly logs |
| 3 | Checkpoint WAL on production SQLite | `PRAGMA wal_checkpoint(TRUNCATE)` via fly ssh |
| 4 | Download final production SQLite | `make download-db` (or direct from Litestream S3) |
| 5 | Convert locally | `mix ecto.reset && mix convert_sqlite` |
| 6 | pg_dump | `pg_dump --format=custom --no-owner --no-acl gallformers_dev > /tmp/gallformers-cutover.dump` |
| 7 | Open proxy to prod Postgres | `fly proxy 15432:5432 -a gallformers-prod-db` |
| 8 | pg_restore | Same as preview procedure, using prod credentials |
| 9 | Verify row counts | Compare species, gall_traits, sources, images counts |
| 10 | Deploy Postgres-backed release | `fly deploy` (site comes up in read-only mode, talking to Fly Postgres) |
| 11 | Soak test under real traffic | Browse pages, search, maps, keys. Check Fly dashboard. Tail logs. |
| 12 | Turn off read-only mode | Writes now go to Postgres |
| 13 | Turn off maintenance banner | |

### Rollback plan

At any point before step 12 (enabling writes), rollback is zero-data-loss:

```bash
fly deploy --image <previous-release-image>   # Reverts to SQLite-backed release
```

The SQLite database on the volume is untouched. Litestream continues replicating. No data is lost because the site was in read-only mode the entire time.

**After writes are enabled on Postgres** (step 12), rollback means losing any new writes since cutover. This is why the soak period in read-only mode matters.

**Keep rollback capability for 7 days** after cutover:
- Do NOT delete SQLite from the volume
- Do NOT remove Litestream secrets
- Do NOT remove Litestream infrastructure

### Post-cutover cleanup (after soak period)

Only after 7+ days of stable operation:

1. Delete SQLite file from the volume (volume stays for WCVP, boundaries, request logs)
2. Remove Litestream secrets: `fly secrets unset LITESTREAM_ACCESS_KEY_ID LITESTREAM_SECRET_ACCESS_KEY -a gallformers`
3. Update OpenTofu definitions in `infra/` to remove Litestream S3 paths and IAM user
4. `tofu apply` and commit infra changes

## Ongoing Operations

### Refresh preview data

Re-run the preview data loading procedure (steps 1-7 above). The `--clean --if-exists` flags on pg_restore make it idempotent.

### Connect to preview Postgres for debugging

```bash
# Terminal 1: open proxy
fly proxy 15432:5432 -a gallformers-db

# Terminal 2: connect with psql
psql --host=localhost --port=15432 \
  --username=gallformers_preview \
  --dbname=gallformers_preview
```

### Connect to production Postgres for debugging (post-cutover)

```bash
# Terminal 1: open proxy
fly proxy 15432:5432 -a gallformers-prod-db

# Terminal 2: connect with psql
psql --host=localhost --port=15432 \
  --username=<prod-username> \
  --dbname=<prod-database>
```

Credentials are in the `DATABASE_URL` secret on the `gallformers` app.

**Reminder:** CLAUDE.md prohibits querying the production database directly via `fly ssh console` with `rpc` or `eval`. Use `fly proxy` + local psql instead.

### Check Fly Postgres health

```bash
fly status -a gallformers-db              # Preview
fly status -a gallformers-prod-db         # Production (post-cutover)
fly machine list -a gallformers-db        # Machine state
fly checks list -a gallformers-db         # Health checks
```

### Fly Postgres backups

Fly Postgres (postgres-flex) includes barman for automated backups, but this has not been verified yet. Before production cutover, confirm:

```bash
fly postgres barman check -a gallformers-prod-db
fly postgres barman backup list -a gallformers-prod-db
```

This is tracked in Phase 3a (matter 1c9b) as incomplete work.
