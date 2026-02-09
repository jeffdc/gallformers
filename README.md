# Gallformers

[![Uptime](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjeffdc%2Fgallformers-status%2Fmaster%2Fapi%2Fgallformers-production%2Fuptime.json)](https://jeffdc.github.io/gallformers-status/)
[![Response Time](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjeffdc%2Fgallformers-status%2Fmaster%2Fapi%2Fgallformers-production%2Fresponse-time.json)](https://jeffdc.github.io/gallformers-status/)

The gallformers.org website - a comprehensive database and reference guide for galls.

## Quick Start

```bash
# Install Elixir dependencies
mix setup

# Start the dev server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) in your browser.

## Prerequisites

- **Elixir 1.19+** and **OTP 28+**
- **Node.js 20+** (for asset compilation)
- **SQLite** (bundled via ecto_sqlite3)
- **libvips** (for image processing - resizing uploaded images)
- **ChromeDriver** (for E2E tests only)

### Installing Elixir

The easiest way on macOS:

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

### Installing libvips (for image processing)

```bash
# macOS
brew install libvips

# Ubuntu/Debian
sudo apt-get install libvips libvips-dev
```

### Installing ChromeDriver (for E2E tests)

```bash
# macOS
brew install chromedriver
xattr -d com.apple.quarantine $(which chromedriver)  # Allow through Gatekeeper

# Ubuntu/Debian
sudo apt-get install chromium-chromedriver
```

Verify with `make e2e-setup`.

## Database Setup

The database file is not committed. To get started:

```bash
# Download from S3 (recommended - daily snapshot from production)
make download-db
```

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

Tests use a separate database (`priv/gallformers_test.sqlite`) built from:
- `priv/repo/structure.sql` - Schema only (no production data)
- `priv/repo/test_seeds.sql` - Minimal seed data for tests

`make test` rebuilds this automatically. Use `make test-db` to rebuild manually.

## E2E Testing

Browser-based E2E tests use [Wallaby](https://github.com/elixir-wallaby/wallaby) with Chrome. These tests are **excluded from regular test runs** to keep the dev loop fast.

Requires ChromeDriver - see [Prerequisites](#installing-chromedriver-for-e2e-tests).

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
| `admin/`  | Admin dashboard, CRUD operations |
| `auth/`   | Login, logout, protected routes |

### Writing E2E Tests

See `test/support/e2e_case.ex` for documentation. All E2E tests must be tagged:

```elixir
defmodule GallformersWeb.E2E.MyTest do
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_public  # Area tag

  test "page loads", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("body.phx-connected"))
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
└── services/            # Auxiliary services (tileserver, usda_plants)
```

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

The database is backed up using two complementary approaches:

1. **Litestream** - Continuous replication to S3 (near real-time)
2. **Daily snapshots** - GitHub Actions workflow creating point-in-time snapshots

Daily snapshots are stored in two locations:
- **Public** (`s3://gallformers-backups/public/`) - Sanitized, PII removed
- **Private** (`s3://gallformers-full-backups/`) - Full backup with PII

See [docs/backup-setup.md](docs/backup-setup.md) for complete backup documentation.

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

## Request Logs

HTTP requests are logged to daily JSON Lines files for incident investigation:

- **Production**: `/data/logs/requests-YYYY-MM-DD.log`
- **Development**: `priv/logs/requests-YYYY-MM-DD.log`

Retrieve logs from production:
```bash
fly ssh sftp get /data/logs/requests-2026-02-05.log
```

Analyze with jq:
```bash
# Find slow requests
cat requests-*.log | jq -c 'select(.duration_ms > 1000)'

# Find errors
cat requests-*.log | jq -c 'select(.status >= 500)'
```

Logs are automatically cleaned up after 30 days. See [CLAUDE.md](CLAUDE.md#request-logging) for detailed usage.

## Contributing

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines.
