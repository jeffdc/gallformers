# Gallformers

[![Uptime](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjeffdc%2Fgallformers-status%2Fmaster%2Fapi%2Fgallformers-production%2Fuptime.json)](https://jeffdc.github.io/gallformers-status/)
[![Response Time](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjeffdc%2Fgallformers-status%2Fmaster%2Fapi%2Fgallformers-production%2Fresponse-time.json)](https://jeffdc.github.io/gallformers-status/)

The gallformers.org website - a comprehensive database and reference guide for galls.

## Quick Start

The whole toolchain (Elixir, Erlang/OTP, Node, Postgres, libvips, Typst, Tailwind, Python/uv) comes from a Nix flake, pinned in `flake.lock` and shared with CI. The Dockerfiles use the same versions; CI checks that with `scripts/check-toolchain`.

```bash
direnv allow            # once per checkout: loads the dev shell from flake.nix
make db-start           # start the dev Postgres 17 (127.0.0.1:54317)
make download-db        # restore the latest production snapshot (needs AWS credentials)
make wcvp-restore       # restore the WCVP plant-name database
make dev                # start the dev server
```

Visit [localhost:4000](http://localhost:4000) in your browser.

## Prerequisites

- **[Nix](https://github.com/NixOS/nix-installer)** with flakes enabled. The NixOS community installer: `curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes`
- **[direnv](https://direnv.net/)** hooked into your shell (`eval "$(direnv hook zsh)"`), plus **[nix-direnv](https://github.com/nix-community/nix-direnv)** for caching (`nix profile install nixpkgs#nix-direnv`, then `source $HOME/.nix-profile/share/nix-direnv/direnvrc` in `~/.config/direnv/direnvrc`)
- **AWS credentials** for `make download-db` (private backups bucket)
- **Playwright browsers** for E2E tests only: `make e2e-setup`

Without direnv, `nix develop` opens the same shell.

**Claude Code:** its Bash tool doesn't run direnv's prompt hook. Add `SessionStart` and `CwdChanged` hooks that run `direnv export bash > "$CLAUDE_ENV_FILE"` (see the direnv section of the [hooks guide](https://code.claude.com/docs/en/hooks-guide)) so commands and subagents get the dev shell.

## Database

The dev shell runs its own Postgres 17, separate from any other Postgres on the machine:

```bash
make db-start           # start (initializes the cluster on first run)
make db-status          # running? which port, data dir, version
make db-stop            # stop
```

- Listens on TCP only at `127.0.0.1:54317`, never 5432, so it can run next to Postgres.app or a Homebrew Postgres.
- Data lives in `~/.local/share/gallformers/postgres-17`, shared by all worktrees.
- Override the port, host or data directory in a gitignored `.envrc.local`, then `direnv reload`:

  ```bash
  export GALLFORMERS_PG_PORT=55432
  export GALLFORMERS_PG_DATA=/some/other/dir
  ```

To create an empty database instead of restoring production data, run `mix ecto.setup`.

## Development

```bash
mix phx.server          # Start dev server
make test               # Rebuild test DB + run tests (excludes E2E)
mix test                # Run tests without rebuilding DB
mix format              # Format code
mix credo --strict      # Code quality
mix precommit           # Run all checks (do this before committing)
make ci                 # Full CI check (same as GitHub Actions)
```

### Test Database

Tests use a separate PostgreSQL database (`gallformers_test`) built from:
- Ecto migrations - Schema only (no production data)
- `priv/repo/test_seeds.sql` - Minimal seed data for tests

`make test` rebuilds this automatically. Use `make test-db` to rebuild manually.

## E2E Testing

Browser-based E2E tests use [phoenix_test_playwright](https://hex.pm/packages/phoenix_test_playwright) with Firefox. All tests run against a production data copy and are **excluded from regular test runs** and CI.

Requires Playwright browsers — see [Prerequisites](#installing-playwright-browsers-for-e2e-tests).

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
└── services/            # Auxiliary services (boundaries, usda_plants)
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

- **Public** (`s3://gallformers-backups/public/`) - Sanitized, PII removed
- **Private** (`s3://gallformers-full-backups/`) - Full backup with PII

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

**Public database downloads are sanitized** - all PII fields are set to NULL and auth0_id is replaced with a placeholder.

## Authentication

- Public site requires no authentication
- Admin/curation features require Auth0 login
- User management is handled via Auth0 console

## External Resources

- **Production**: [gallformers.org](https://gallformers.org)
- **Images**: AWS S3
- **Auth**: Auth0
- **Domains**: Namecheap (gallformers.org, gallformers.com)

## Monitoring

- **Status page**: [jeffdc.github.io/gallformers-status](https://jeffdc.github.io/gallformers-status/) - Uptime monitoring via Upptime
- **Metrics dashboard**: [fly-metrics.net](https://fly-metrics.net/d/fly-app/fly-app?orgId=932898) - CPU, memory, HTTP metrics (view-only, no alerting)

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
