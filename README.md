# Gallformers

[![Uptime](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjeffdc%2Fgallformers-status%2Fmaster%2Fapi%2Fgallformers-production%2Fuptime.json)](https://jeffdc.github.io/gallformers-status/)
[![Response Time](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjeffdc%2Fgallformers-status%2Fmaster%2Fapi%2Fgallformers-production%2Fresponse-time.json)](https://jeffdc.github.io/gallformers-status/)

The gallformers.org website — a comprehensive database and reference guide for galls.

## Prerequisites

- **Elixir 1.19+** with **OTP 28+**
- **Node.js 20+** (asset compilation)
- **PostgreSQL 16+**
- **libvips** (image processing)
- **make** and a POSIX shell (bash/zsh)
- **Playwright** — E2E tests only; install on demand with `make e2e-setup`
- **gdal**, **tippecanoe**, **jq** — only if you want to build map tiles locally (otherwise see [Boundary Tiles](#boundary-tiles))

### Platform notes

- **macOS**: `brew` for all the prereqs below.
- **Ubuntu/Debian**: `apt-get` for all the prereqs below.
- **Windows**: install [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) with an Ubuntu distro and run everything inside the WSL shell. Native Windows isn't supported — the Makefile, shell scripts, and several CLI tools assume a Unix environment.

### Installing Elixir

macOS:

```bash
brew install elixir
```

Or use [asdf](https://asdf-vm.com/) for version management:

```bash
asdf plugin add elixir
asdf plugin add erlang
asdf install erlang 28.0
asdf install elixir 1.19.0-otp-28
```

### Installing PostgreSQL

```bash
# macOS
brew install postgresql@16
brew services start postgresql@16

# Ubuntu/Debian (and WSL2)
sudo apt-get install postgresql postgresql-contrib
sudo service postgresql start
```

### Creating a Postgres role for yourself

`config/dev.exs` reads `PGUSER` (falling back to `$USER`) and `PGPASSWORD`. Fresh Postgres installs usually don't ship with a role matching your OS user, so create one before running `mix setup`:

```bash
# macOS Homebrew: your OS user usually already has superuser access
createuser -s "$USER" 2>/dev/null || true
createdb "$USER" 2>/dev/null || true

# Ubuntu/Debian/WSL2: become the postgres OS user first
sudo -u postgres psql -c "CREATE ROLE \"$USER\" WITH SUPERUSER LOGIN;"
sudo -u postgres createdb "$USER"
```

If your role needs a password, set `PGPASSWORD=...` in `.env` (see [Environment Variables](#environment-variables)). Otherwise leave it unset.

### Installing libvips (image processing)

```bash
# macOS
brew install libvips

# Ubuntu/Debian/WSL2
sudo apt-get install libvips libvips-dev
```

### Installing Playwright browsers (E2E only)

```bash
make e2e-setup
```

## Quick Start

```bash
# Copy the env template (only secrets you don't need can stay blank)
cp .env.sample .env

# Install Elixir + JS deps, create + migrate the dev DB, build assets
mix setup

# Start the dev server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000).

### What `mix setup` does

It chains four tasks (see `mix.exs`):

1. `mix deps.get` — fetch Elixir dependencies
2. `mix ecto.setup` — create `gallformers_dev`, run migrations, run `priv/repo/seeds.exs`
3. `mix assets.setup` — install Tailwind + esbuild binaries
4. `mix assets.build` — compile JS/CSS for dev

### Authentication in local dev

`config/dev.exs` sets `config :gallformers, dev_auth_bypass: true`. With this enabled, every request gets a fake admin/superadmin/operator user injected into the session, so the admin and ingestion-review pages work locally with no Auth0 setup.

To exercise the real Auth0 flow locally, set `AUTH0_DOMAIN` / `AUTH0_CLIENT_ID` / `AUTH0_CLIENT_SECRET` in `.env` and flip the bypass off in `config/dev.exs`.

## Local Data

`priv/repo/seeds.exs` is currently empty — `mix ecto.setup` leaves you with schema only and no records. Pick one of:

1. **Test seeds** — minimal but functional data, defined in `priv/repo/test_seeds.sql`. Load into dev with:
   ```bash
   psql gallformers_dev -f priv/repo/test_seeds.sql
   ```
2. **Production snapshot** — `make download-db` pulls and restores a sanitized public snapshot from `s3://gallformers-backups/public/`. Requires AWS credentials with read access — set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in `.env`.
3. **Roll your own** — add inserts to `priv/repo/seeds.exs`.

## Environment Variables

`.env.sample` lists every env var the app understands. Copy it to `.env` and fill in what you need; nothing in it is required for the public site to render. Loaders:

```bash
# Plain bash/zsh
set -a; source .env; set +a

# direnv
direnv allow .
```

Common dev-only entries:

| Variable | Used for |
|---|---|
| `PGUSER`, `PGPASSWORD`, `PGHOST` | Override default `$USER` / no-password / localhost Postgres connection |
| `AUTH0_DOMAIN` / `_CLIENT_ID` / `_CLIENT_SECRET` | Only if testing the real Auth0 flow (dev bypass is on by default) |
| `S3_PUT_AWS_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` / `S3_IMAGE_PREFIX` | Image-upload features |
| `AWS_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` | `make download-db` and other AWS-backed scripts |
| `TILES_URL` | Use the production map tiles instead of building locally |

## Development

```bash
mix phx.server          # Start dev server
make test               # Rebuild test DB + run tests (excludes E2E)
mix test                # Run tests without rebuilding the DB
mix format              # Format code
mix credo --strict      # Code quality
mix precommit           # Run all checks (do this before committing)
make ci                 # Full CI check (same as GitHub Actions)
```

### Test Database

Tests use a separate PostgreSQL database (`gallformers_test`) built from:
- Ecto migrations — schema only (no production data)
- `priv/repo/test_seeds.sql` — minimal seed data for tests

`make test` rebuilds this automatically. Use `make test-db` to rebuild manually.

## E2E Testing

Browser-based E2E tests use [phoenix_test_playwright](https://hex.pm/packages/phoenix_test_playwright) with Firefox. All tests run against a production data copy and are **excluded from regular test runs** and CI.

Requires Playwright browsers — see [Prerequisites → Installing Playwright browsers](#installing-playwright-browsers-e2e-only).

### Running E2E Tests

```bash
make e2e                # Run all E2E tests
make e2e-changed        # Run only tests affected by changed files (smart)
make e2e-public         # Public pages only
make e2e-search         # Search functionality only
make e2e-browse         # Species/hosts/galls browsing only
make e2e-admin          # Admin pages only
make e2e-auth           # Authentication flows only
```

### Debugging

```bash
make e2e-headed         # Run with visible browser
E2E_HEADED=1 make e2e-public   # Specific area with visible browser
```

### Test Organization

E2E tests are organized by functional area in `test/e2e/`:

| Directory | Coverage |
|-----------|----------|
| `public/` | Home, about, glossary, resources, explore |
| `search/` | Global search, ID tool |
| `browse/` | Species, hosts, galls detail pages |
| `admin/`  | Admin dashboard, taxonomy admin, reclassify modal |
| `auth/`   | Login, logout, protected routes |

### Writing E2E Tests

See `test/support/e2e_case.ex` for documentation. All E2E tests must be tagged:

```elixir
defmodule GallformersWeb.E2E.MyTest do
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_public  # Area tag

  test "page loads", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("h1", text: "Welcome")
  end
end
```

## Project Structure

```
gallformers/
├── lib/                 # Elixir application code
├── assets/              # Frontend (JS, CSS, Tailwind)
├── priv/                # Static files, migrations, database
├── test/                # Tests
├── config/              # Phoenix configuration
└── services/            # Auxiliary services (boundaries, source-ingestion)
```

## Boundary Tiles (Range Maps)

Range maps use PMTiles vector tiles generated from Natural Earth shapefiles. In production, tiles are served via CloudFront from S3. In dev, tiles are served locally from `priv/static/data/boundaries.pmtiles`.

```bash
# Build tiles locally (~2 minutes)
cd services/boundaries
./build_boundaries.sh ../../priv/static/data/boundaries.pmtiles

# Or skip the local build and use production tiles:
TILES_URL=https://gallformers.org/tiles/boundaries.pmtiles mix phx.server
```

Requires: `gdal`, `tippecanoe`, `jq`. See [services/boundaries/README.md](services/boundaries/README.md) and [runbooks/map-tiles.md](runbooks/map-tiles.md) for full details.

## Troubleshooting

**`mix ecto.setup` fails with `role "<name>" does not exist`**
Your OS user doesn't have a matching Postgres role. See [Creating a Postgres role for yourself](#creating-a-postgres-role-for-yourself).

**`mix ecto.setup` fails with `password authentication failed`**
The Postgres role needs a password and `PGPASSWORD` isn't set. Either add `PGPASSWORD=...` to `.env` and re-source it, or change `pg_hba.conf` to `trust` local connections during dev.

**Admin pages redirect to Auth0 / 401 in local dev**
`config :gallformers, dev_auth_bypass: true` was removed or you're running `MIX_ENV` other than `dev`. Restore the line in `config/dev.exs` or unset `MIX_ENV`.

**`Address already in use` on port 4000**
Another process is bound to 4000. `PORT=4001 mix phx.server` to pick a different port, or kill the existing process.

**Map tiles missing / 404s in dev**
Either build them locally (see [Boundary Tiles](#boundary-tiles)) or use production tiles: `TILES_URL=https://gallformers.org/tiles/boundaries.pmtiles mix phx.server`.

**Image-upload features error out**
Set `S3_PUT_AWS_ACCESS_KEY_ID` / `S3_PUT_AWS_SECRET_ACCESS_KEY` / `S3_IMAGE_PREFIX` in `.env`. Without them, the dev server runs fine but anything that writes to S3 will fail.

**`make download-db` fails with Access Denied**
Set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for an account with read access to `s3://gallformers-backups/public/`. Without those, use the test seeds instead (see [Local Data](#local-data)).

## Deployment

Production runs on Fly.io:

```bash
fly deploy              # Deploy to production
fly logs                # View logs
fly status              # Check status
```

See [runbooks/](runbooks/) for operational procedures.

### Creating Releases

The full release workflow:

1. **Commit and push to main** — `git push origin main`
2. **Wait for CI** — The "CI V2" workflow runs format, compile, credo, and tests
3. **Wait for deploy** — On CI success, "Deploy V2" automatically deploys to Fly.io and runs smoke tests
4. **Verify deploy** — Check that the site is working: `fly status` or visit [gallformers.org](https://gallformers.org)
5. **Create the release** — Run `/release` in Claude Code, review the generated notes, and approve

The `/release` skill handles tag naming, commit collection, and release note generation. Tags use CalVer format: `v2026.2.6`, with `.2`, `.3` suffixes for multiple same-day releases. Release notes are published at [github.com/jeffdc/gallformers/releases](https://github.com/jeffdc/gallformers/releases).

## Backup Strategy

The PostgreSQL database backup strategy is TBD as part of the Postgres migration. Daily snapshots continue to be stored in S3:

- **Public** (`s3://gallformers-backups/public/`) — Sanitized, PII removed
- **Private** (`s3://gallformers-full-backups/`) — Full backup with PII

For restore procedures, see [runbooks/restore-database.md](runbooks/restore-database.md). For AWS bucket details, see [docs/ops/aws-private-backup-bucket.md](docs/ops/aws-private-backup-bucket.md).

## PII Handling

The `users` table contains personally identifiable information:

| Field | Description |
|-------|-------------|
| `auth0_id` | Unique identifier from Auth0 |
| `display_name` | User's chosen display name |
| `nickname` | Fallback name from Auth0 |
| `inaturalist_url` | Link to iNaturalist profile |
| `social_url` | Link to social media |
| `personal_url` | Link to personal website |

**Public database downloads are sanitized** — all PII fields are set to NULL and `auth0_id` is replaced with a placeholder.

## Authentication

- Public site requires no authentication
- Admin/curation features require Auth0 login in production; local dev bypasses Auth0 by default (see [Authentication in local dev](#authentication-in-local-dev))
- User management is handled via Auth0 console

## External Resources

- **Production**: [gallformers.org](https://gallformers.org)
- **Images**: AWS S3
- **Auth**: Auth0
- **Domains**: Namecheap (gallformers.org, gallformers.com)

## Monitoring

- **Status page**: [jeffdc.github.io/gallformers-status](https://jeffdc.github.io/gallformers-status/) — Uptime monitoring via Upptime
- **Metrics dashboard**: [fly-metrics.net](https://fly-metrics.net/d/fly-app/fly-app?orgId=932898) — CPU, memory, HTTP metrics (view-only, no alerting)

Fly.io also sends automatic email alerts on OOM (out-of-memory) events.

## Application Logs

All application logs (requests, errors, crashes) are structured JSON via LoggerJSON, written to a persistent file in production.

- **Production**: `/data/logs/app.log` (size-rotated, 1 GB max)

Retrieve logs from production:
```bash
fly ssh sftp get /data/logs/app.log
```

Analyze with jq:
```bash
# Find request errors
cat app.log | jq -c 'select(.conn.status >= 500)'

# Find application errors
cat app.log | jq -c 'select(.severity == "error")'
```

See [CODING_STANDARDS.md](CODING_STANDARDS.md#application-logging) for detailed format and analysis examples.

## Contributing

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines.
