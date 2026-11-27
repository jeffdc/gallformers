# WCVP (World Checklist of Vascular Plants) Operations

## Overview

The WCVP integration uses a **separate Postgres database** (`wcvp`) on the same cluster as the main gallformers database. It contains plant taxonomy and distribution data from Kew Gardens, used for host plant lookups, POWO-WCVP refresh, and range reconciliation.

One supporting file works alongside the database:

| File | Purpose | Location |
|------|---------|----------|
| `tdwg_to_places.json` | Static mapping from all 368 TDWG L3 botanical region codes to gallformers place codes (global coverage) | Bundled in release under `priv/repo/data/` |

## Architecture

```
Wcvp.Lookup          — search/get queries against Repo.WCVP (wcvp database)
Wcvp.Tdwg            — TDWG-to-places mapping (reads tdwg_to_places.json)
Wcvp.WcvpName        — Ecto schema for wcvp_names table (typed structs)
Wcvp.WcvpDistribution — Ecto schema for wcvp_distributions table
Repo.WCVP            — read-only Ecto repo for the separate wcvp database
```

## Environment-Specific Flow

### Local Development

| Item | Details |
|------|---------|
| **wcvp database** | Local Postgres database named `wcvp` |
| **tdwg_to_places.json** | `priv/repo/data/tdwg_to_places.json` — checked into repo |
| **Config** | `config/dev.exs` sets `database: "wcvp"` for Repo.WCVP |
| **Repo startup** | Repo.WCVP starts unconditionally in supervision tree |

**Setting up WCVP locally:**

```bash
# Option A: Restore from S3 (recommended — gives you the same data as production)
make wcvp-restore

# Option B: Build from Kew CSVs
mix gallformers.wcvp.download          # download ~85MB zip from Kew
mix gallformers.wcvp.build_db          # process CSVs, load into local wcvp DB

# Option C: Build and upload to S3 (for distributing to other environments)
mix gallformers.wcvp.build_db --upload  # builds locally + pg_dump + upload to S3
```

### Preview (gallformers-preview.fly.dev)

| Item | Details |
|------|---------|
| **wcvp database** | `wcvp` database on the same Fly Postgres cluster |
| **tdwg_to_places.json** | Bundled in release |
| **Config** | Derived from `DATABASE_URL` in `config/runtime.exs` |

**Loading data**: pg_restore via fly proxy from the S3 dump artifact.

### Production (gallformers.fly.dev)

| Item | Details |
|------|---------|
| **wcvp database** | `wcvp` database on the gallformers-db Fly Postgres cluster |
| **tdwg_to_places.json** | Bundled in release |
| **Config** | Derived from `DATABASE_URL` in `config/runtime.exs` |

**Loading data**: pg_restore via fly proxy from the S3 dump artifact.

## Configuration

Repo.WCVP is configured per-environment:

- **dev/test**: `config/dev.exs` / `config/test.exs` — database name, local Postgres credentials
- **prod**: `config/runtime.exs` — derived from `DATABASE_URL` by replacing the database name with `wcvp`

The database is NOT managed by Ecto migrations. Tables are created and populated by the build task (`mix gallformers.wcvp.build_db`).

## Updating WCVP Data

When WCVP source data needs to be refreshed (new Kew release, corrections, etc.):

```bash
# 1. Download latest CSV files from Kew
mix gallformers.wcvp.download

# 2. Build into local wcvp database + pg_dump + upload to S3
mix gallformers.wcvp.build_db --upload

# 3. Fetch the uploaded dump (the upload deletes the local priv/data/wcvp.dump)
curl -fSL -o /tmp/wcvp.dump https://gallformers-backups.s3.amazonaws.com/public/wcvp.dump
```

**Step 4 replaces the production `wcvp` database's contents** (`--clean` drops each object before restoring it). Get explicit approval first, and run it one step at a time (see the database rules in [Fly Operations](./fly-operations.md)).

```bash
# 4. Restore on production via fly proxy (credentials typed for this terminal only, as in postgres-maintenance.md)
fly proxy 15432:5432 -a gallformers-db &
sleep 2
PGPASSWORD="$PG_PROD_PASSWORD" pg_restore --clean --if-exists --no-owner --no-acl \
  -h localhost -p 15432 -U "$PG_PROD_USERNAME" -d wcvp /tmp/wcvp.dump
kill %1

# 5. Same for preview if needed
```

## Plant Authorship from WCVP

**New back-end only:** this section describes the `taxogall` back-end. Production (`main`) does not have it until release.

Plants take their names' authorship (`taxon_names.authorship`, accepted names and synonyms) from WCVP (`Gallformers.Ranges.WcvpAuthorship`). A name takes WCVP's authors only when it has none and WCVP holds it unambiguously: the accepted name by the plant's WCVP link when the linked record is of the same name, otherwise by exact name and rank (several records with different authors are narrowed to the linked record's synonymy; if that still leaves more than one, the name is ambiguous and stays blank). A curator's authorship (the plant page's Edit mode) is never overwritten.

- The catalog migration fills them as one of its steps and reports the counts (filled, ambiguous with each name listed, not in WCVP). `Gallformers.Release.migrate_catalog/0` starts the WCVP repo for it; if WCVP cannot be read, the report says so and nothing is filled.
- A WCVP link change (adding a plant from WCVP, a match, a sync, replay) fills the plant's blank names from the new record, and moves its accepted name's authorship along when it was the old record's.
- To fill them on a database already migrated (idempotent; prints the counts):

```bash
MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.wcvp.authorship   # local
bin/gallformers eval "Gallformers.Release.backfill_wcvp_authorship()"         # preview/prod
```

After a WCVP data refresh, running it again fills only names that are still blank.

## First-Time Setup (New Environment)

For a new Fly Postgres cluster or local dev machine:

```bash
# 1. Create the wcvp database
createdb wcvp          # local
# OR via fly proxy: CREATE DATABASE wcvp;

# 2. Restore data from S3
mix gallformers.wcvp.restore   # local dev
# OR pg_restore via fly proxy for prod/preview
```

## Git and Docker Status

- `.gitignore`: `priv/data/` — WCVP CSV files not committed (build artifacts)
- `.dockerignore`: `priv/repo/data/wcvp/` — excluded from build context
- `docker-entrypoint.sh`: No WCVP steps (data lives in Postgres, not on the volume)

## File Path Resolution

`Wcvp.Tdwg.load/0` reads `tdwg_to_places.json` using `Application.app_dir/2`:

```elixir
Application.app_dir(:gallformers, "priv/repo/data/tdwg_to_places.json")
```

This resolves correctly in both dev (project root) and releases (inside the release lib directory). **Do not use relative paths like `"priv/..."` directly** — they break in releases where the CWD is `/app/` but priv files are nested under `/app/lib/gallformers-<version>/priv/`.

## Troubleshooting

### WCVP data missing

1. Check if the wcvp database exists and has data:
   ```bash
   psql -d wcvp -tAc "SELECT count(*) FROM wcvp_names"
   ```

2. If empty or missing, restore from S3:
   ```bash
   make wcvp-restore   # local dev
   ```

### WCVP button not showing in admin

The "Refresh from POWO-WCVP" button is gated on `@wcvp_available` which calls `Wcvp.Lookup.available?/0`. If the button is missing:

1. Check that Repo.WCVP is in the supervision tree (startup logs)
2. Check that the wcvp database has tables and data
3. Try `Wcvp.Lookup.available?()` from iex

### No WCVP match on refresh

The refresh looks the plant up by its WCVP link if it has one, otherwise by its name (synonyms resolved to the accepted name). If that finds nothing, it opens a search of WCVP names containing the plant's name to pick from. If the picked record can't be loaded, you get "WCVP species not found". Check that the plant's name matches a WCVP name.

### "WCVP refresh failed" on refresh

If the WCVP lookup succeeds but building the range comparison fails, check that `tdwg_to_places.json` is accessible (`Wcvp.Tdwg.load/0`). In a release, it must be resolved via `Application.app_dir/2`, not a relative path.
