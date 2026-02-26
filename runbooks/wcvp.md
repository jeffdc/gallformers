# WCVP (World Checklist of Vascular Plants) Operations

## Overview

The WCVP integration uses a **secondary SQLite database** (`wcvp.sqlite`) containing filtered plant taxonomy and distribution data from Kew Gardens. This is separate from the main gallformers database and is used for host plant lookups, POWO-WCVP refresh, and range reconciliation.

Two supporting files work alongside the database:

| File | Purpose | Location |
|------|---------|----------|
| `wcvp.sqlite` | Secondary Ecto repo with plant names and distributions | Varies by environment (see below) |
| `tdwg_to_places.json` | Static mapping from all 368 TDWG L3 botanical region codes to gallformers place codes (global coverage) | Bundled in release under `priv/repo/data/` |

## Architecture

```
Wcvp.Lookup          — search/get queries against Repo.WCVP (wcvp.sqlite)
Wcvp.Tdwg            — TDWG-to-places mapping (reads tdwg_to_places.json)
Wcvp.Refresh         — downloads wcvp.sqlite from S3, hot-swaps the repo
Wcvp.Matcher         — three-pass name matching (exact, fuzzy, synonym)
Wcvp.Reader          — streams raw WCVP CSV files (pipe-delimited)
Repo.WCVP            — read-only Ecto repo for the secondary database
```

## Environment-Specific Flow

### Local Development

| Item | Details |
|------|---------|
| **wcvp.sqlite** | `priv/data/wcvp.sqlite` — built locally from CSV source files |
| **tdwg_to_places.json** | `priv/repo/data/tdwg_to_places.json` — checked into repo |
| **Config** | `config/dev.exs` does not set WCVP config; `runtime.exs` reads `WCVP_DATABASE_PATH` env var |
| **Repo startup** | `Application.start` checks if the configured DB path exists; skips `Repo.WCVP` if missing |

**Building the WCVP database locally:**

```bash
# 1. Download raw WCVP CSV files from Kew
mix gallformers.wcvp.download

# 2. Build filtered SQLite database
mix gallformers.wcvp.build_db

# 3. (Optional) Upload to S3 for production use
mix gallformers.wcvp.build_db --upload
```

### Preview (gallformers-preview.fly.dev)

| Item | Details |
|------|---------|
| **wcvp.sqlite** | `/app/data/wcvp.sqlite` — copied from build context during Docker build |
| **tdwg_to_places.json** | Bundled in release at `<release>/lib/gallformers-<vsn>/priv/repo/data/` |
| **Config** | `fly.preview.toml` sets `WCVP_DATABASE_PATH = "/app/data/wcvp.sqlite"` |
| **Repo startup** | Same `File.exists?` check — starts because the file is baked into the image |

**How the DB gets into the image** (`Dockerfile.preview`):
1. Builder stage: `COPY priv priv` brings in `priv/data/wcvp.sqlite` from the local build context
2. Runtime stage: `COPY --from=builder /app/priv/data/wcvp.sqlite /app/data/wcvp.sqlite`

This means the preview WCVP data matches whatever is in your local `priv/data/wcvp.sqlite` at build time. To update it, rebuild locally first (`mix gallformers.wcvp.build_db`), then redeploy preview.

### Production (gallformers.fly.dev)

| Item | Details |
|------|---------|
| **wcvp.sqlite** | `/data/wcvp.sqlite` — on the persistent Fly volume |
| **tdwg_to_places.json** | Bundled in release at `<release>/lib/gallformers-<vsn>/priv/repo/data/` |
| **Config** | `fly.toml` sets `WCVP_DATABASE_PATH = "/data/wcvp.sqlite"` |
| **Repo startup** | Same `File.exists?` check — starts only if the file has been placed on the volume |

**How the DB gets to production:**

The WCVP database is **not** baked into the production Docker image. It lives on the persistent Fly volume and is managed via:

1. **Initial setup**: Upload from local via `mix gallformers.wcvp.build_db --upload`, then use `Wcvp.Refresh.refresh/0` from a remote console to download from S3
2. **Updates**: Call `Wcvp.Refresh.refresh/0` which downloads from `s3://gallformers-backups/wcvp/wcvp.sqlite`, stops the repo, swaps the file, and restarts

**If the DB is missing on production**, WCVP features degrade gracefully:
- `Repo.WCVP` is not started (no crash)
- `Wcvp.Lookup.available?/0` returns `false`
- UI buttons gated on `@wcvp_available` are hidden
- Search/get functions return `[]`/`nil` instead of errors

## Configuration

The WCVP database path is configured in `config/runtime.exs` (runtime, not compile-time):

```elixir
if wcvp_path = System.get_env("WCVP_DATABASE_PATH") do
  config :gallformers, Gallformers.Repo.WCVP, database: wcvp_path
end
```

This is intentionally in `runtime.exs` because `prod.exs` is evaluated at compile time during `mix release`. Environment variables set in `fly.toml` / `fly.preview.toml` are only available at runtime.

## File Path Resolution

`Wcvp.Tdwg.load/0` reads `tdwg_to_places.json` using `Application.app_dir/2`:

```elixir
Application.app_dir(:gallformers, "priv/repo/data/tdwg_to_places.json")
```

This resolves correctly in both dev (project root) and releases (inside the release lib directory). **Do not use relative paths like `"priv/..."` directly** — they break in releases where the CWD is `/app/` but priv files are nested under `/app/lib/gallformers-<version>/priv/`.

## Troubleshooting

### WCVP button not showing in admin

The "Refresh from POWO-WCVP" button is gated on `@wcvp_available` which calls `Wcvp.Lookup.available?/0`. If the button is missing:

1. Check that `WCVP_DATABASE_PATH` is set in the environment
2. Check that the file exists at that path
3. Check startup logs for `Repo.WCVP` — it should appear in the supervision tree

### "No matching species found" error

The refresh handler looks up the host by `wcvp_id` first, then falls back to name search. If neither matches, you get this error. Check that the host name in gallformers matches a WCVP accepted name.

### Crash on refresh button click

If the WCVP lookup succeeds but `build_wcvp_diff` crashes, check that `tdwg_to_places.json` is accessible. In a release, it must be resolved via `Application.app_dir/2`, not a relative path.
