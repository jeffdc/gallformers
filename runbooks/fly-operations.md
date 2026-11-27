# Fly.io Operations

**IMPORTANT**: Before performing ANY Fly.io operation, read the safety rules below. They are non-negotiable.

**CONTEXT**: These procedures exist because of a production incident (docs/incidents/20260203-production-database-recovery.md) where an agent caused significant downtime by violating these principles.

## Safety rules

### Fly.io

- **STOP MEANS STOP** — if the user says "STOP", immediately cease all tool execution. No exceptions.
- **NEVER destroy machines** — causes volume attachment issues and crash loops. Use stop/update/restart.
- **NEVER use `fly machine run`** — bypasses fly.toml config. Always use `fly deploy`.
- **Always check machine state first** — `fly machine list` before SSH/SFTP operations.
- **Always get user approval** before machine stop/start/update operations.
- **Execute ONE step at a time** — verify success before proceeding to the next step.
- **NEVER query the production database directly** — no `fly ssh console` with `rpc` or `eval` for database queries. Use a local dev database and refresh with `make download-db`.

### Databases

- **NEVER drop, reset, or recreate the `wcvp` database.** It contains 1.4M+ reference records loaded from Kew Gardens data. Restoring it takes significant time (`make wcvp-restore`). It is NOT managed by Ecto migrations and is NOT in `ecto_repos`.
- **NEVER run `dropdb`, `DROP DATABASE`, or `DROP TABLE` on any database** without explicit user approval.
- **NEVER run `mix ecto.reset`** — use `mix ecto.migrate` to apply pending migrations. If you think a reset is needed, ask first.
- **The only safe database commands** are: `mix ecto.migrate`, `mix ecto.rollback` (with user approval), and read-only queries on the dev database.

## Deploy Commands

```bash
fly deploy              # Deploy to production
fly status              # Check deployment status
fly logs                # View application logs (STREAMS - see note below)
fly ssh console         # SSH into running machine
```

## Troubleshooting an Outage

**Check this first** before diving into app metrics or dashboards:

```bash
fly incidents hosts list    # Host-level maintenance/incidents affecting YOUR machines
```

Host-level events (emergency maintenance, hardware issues) are invisible to app metrics,
Grafana dashboards, and status.flyio.net. This command is the only way to see them.
See `docs/incidents/20260309-unresponsive-crash-cpu-investigation.md` for a case
where this would have saved hours of investigation.

**Note on `fly logs`**: This command streams logs continuously and never terminates. Do NOT run it in the background or pipe to `tail`. To check recent errors, either:
- Run interactively and Ctrl+C after seeing what you need
- Use `fly logs 2>&1 | timeout 5 cat` to get a 5-second snapshot
- Check the application log file via SFTP: `fly ssh sftp get /data/logs/app.log` (see [Application logging](#application-logging))

## Application logging

All application logs (requests, errors, Postgrex events, crash reports, HealthWatchdog alerts) are structured JSON in one stream, through LoggerJSON's `Basic` formatter (`config/runtime.exs`, prod only). Phoenix's own request logging is off (`config/prod.exs`); `LoggerJSON.Plug` logs each request instead (`application.ex`), with the client IP taken from Fly's `fly-client-ip` header (`endpoint.ex`). Development logs to the console, human-readable.

- **Production file:** `/data/logs/app.log` on the volume, size-rotated (50 MB × 20 files, 1 GB at most, gzipped on rotate). Preview deploys write no file.
- **Retrieve:** `fly ssh sftp get /data/logs/app.log`
- **Shape:** each line has `time`, `severity`, `message` and `metadata`; a request line adds `request.connection` (`method`, `path`, `status`, `protocol`) and `request.client` (`ip`, `user_agent`), and its duration is `metadata.duration_us`.

```bash
# Request entries
jq -c 'select(.request)' app.log

# 500 errors
jq -c 'select(.request.connection.status >= 500)' app.log

# The ten slowest requests
jq -cs '[.[] | select(.request)] | sort_by(.metadata.duration_us) | reverse | .[0:10]' app.log

# Application errors
jq -c 'select(.severity == "error")' app.log

# Postgrex connection events
jq -c 'select(.message | test("Postgrex"; "i"))' app.log
```

## Configuration

Key settings in `fly.toml`:

| Setting | Value | Purpose |
|---------|-------|---------|
| `app` | `gallformers` | App name |
| `primary_region` | `ewr` | Production region |
| `[[vm]]` | shared CPU, 1 CPU, `1024mb` | The one machine's size |
| `[mounts]` | `gallformers_data` at `/data` | Volume; the app writes only its logs there |
| `PHX_HOST` | `www.gallformers.org` | Host the app generates URLs for |
| `min_machines_running` | `1` | Always keep one machine running |

The database connection string, `DATABASE_URL`, is a Fly secret, not a `fly.toml` setting. It points at the self-managed Fly Postgres app `gallformers-db` (postgres-flex 17), reached over Fly's private IPv6 network (`ECTO_IPV6`).

## Secrets

```bash
fly secrets list
fly secrets set DATABASE_URL=xxx
fly secrets set SECRET_KEY_BASE=xxx
fly secrets set AUTH0_CLIENT_ID=xxx AUTH0_CLIENT_SECRET=xxx AUTH0_DOMAIN=xxx
fly secrets set S3_PUT_AWS_ACCESS_KEY_ID=xxx S3_PUT_AWS_SECRET_ACCESS_KEY=xxx
# WCVP data lives in a separate Postgres database — no secret needed
```

## Infrastructure Operations

### Why machines must never be destroyed

Destroying machines causes volume attachment issues. When `fly deploy` runs with no machine, it may create a NEW empty volume instead of using the existing one. This leads to crash loops with no database until retries are exhausted. Use machine stop/update/restart instead.

### Why `fly machine run` must never be used

Manual machine creation bypasses fly.toml configuration. Results in a machine without fly.toml's 1GB of memory, missing health checks, wrong process group. **Always use `fly deploy`** which applies fly.toml config correctly.

### The "sleep infinity" pattern for volume file operations

This is the correct way to perform file operations on the volume of a running machine, but it creates prod downtime so make sure it's what really needs to happen. It is rarely needed now: the database is in Fly Postgres, and the app writes only its logs to the volume (`/data/logs`), which `fly ssh sftp get` reads without stopping the app.

1. Stop machine (if running)
2. Update machine command: `fly machine update --command "sleep infinity"`
3. Start machine (now runs `sleep infinity` instead of app)
4. Perform file operations (backup, upload, verify)
5. Clear command override: `fly machine update --command ""`
6. Restart machine (reverts to Dockerfile CMD with fly.toml config)

**Why this works:**
- Machine starts successfully (sleep infinity never fails)
- App is not running, so volume files can be safely modified
- Machine keeps all its configuration (memory, health checks, etc.)
- Clearing command override reverts to original Dockerfile CMD
- No machine destruction/recreation needed

## Volume Data Files

The app writes only its logs to the `/data` volume (`/data/logs`, `config/runtime.exs`). The main database is in Fly Postgres (not on the volume).

**WCVP** data lives in a separate Postgres database (`wcvp`) on the same cluster. See `runbooks/wcvp.md` for setup and update procedures.

**Boundaries PMTiles** is served directly via CloudFront from S3 — no longer stored on the volume. See `runbooks/map-tiles.md` for details.

## Before ANY Fly.io operation

1. **State verification** — What's the current state? (`fly machine list`, volume status)
2. **Clear plan** — What are we trying to achieve? What's the algorithm?
3. **User approval** — Especially for machine stop/start/update/destroy operations
4. **Execute ONE step at a time** — Do not run multiple commands in parallel
5. **Verify success** — Check the result before proceeding to next step
6. **If anything unexpected happens** — STOP and report to user

### Example of correct approach

```
User: "Restart production"

Agent: "Here's my plan:
1. Check current machine state (fly machine list)
2. Restart the machine
3. Verify it is healthy (fly status, /health)

Should I proceed?"

User: "Yes"

Agent: [Executes step 1, reports result]
Agent: [Executes step 2, reports result]
... etc
```

### Example of WRONG approach

```
User: "Restart production"

Agent: [Immediately starts running commands]
Agent: [Tries SFTP to stopped machine - fails]
Agent: [Creates temp machine with fly machine run - wrong config]
Agent: [Makes changes without verification]
User: "STOP!!!"
Agent: [Keeps running commands anyway]
```
