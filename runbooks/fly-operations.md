# Fly.io Operations

**IMPORTANT**: Before performing ANY Fly.io operation, read the safety rules in CLAUDE.md under "Fly.io Safety Rules." Those rules are non-negotiable.

**CONTEXT**: These procedures exist because of a production incident (docs/investigations/20260203-production-database-recovery.md) where an agent caused significant downtime by violating these principles.

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
See `docs/investigations/20260309-unresponsive-crash-cpu-investigation.md` for a case
where this would have saved hours of investigation.

**Note on `fly logs`**: This command streams logs continuously and never terminates. Do NOT run it in the background or pipe to `tail`. To check recent errors, either:
- Run interactively and Ctrl+C after seeing what you need
- Use `fly logs 2>&1 | timeout 5 cat` to get a 5-second snapshot
- Check the request logger files via SFTP (see Request Logging in CODING_STANDARDS.md)

## Configuration

Key settings in `fly.toml`:

| Setting | Value | Purpose |
|---------|-------|---------|
| `app` | `gallformers` | App name |
| `primary_region` | `iad` | US East (matches S3 region) |
| `DATABASE_URL` | Fly Postgres connection string | Managed Postgres database |
| `min_machines_running` | `1` | Always keep one machine running |

## Secrets

```bash
fly secrets list
fly secrets set SECRET_KEY_BASE=xxx
fly secrets set AUTH0_CLIENT_ID=xxx AUTH0_CLIENT_SECRET=xxx AUTH0_DOMAIN=xxx
fly secrets set WCVP_DATABASE_PATH=/data/wcvp.sqlite
```

## Infrastructure Operations

### Why machines must never be destroyed

Destroying machines causes volume attachment issues. When `fly deploy` runs with no machine, it may create a NEW empty volume instead of using the existing one. This leads to crash loops with no database until retries are exhausted. Use machine stop/update/restart instead.

### Why `fly machine run` must never be used

Manual machine creation bypasses fly.toml configuration. Results in wrong memory (256MB instead of 512MB), missing health checks, wrong process group. **Always use `fly deploy`** which applies fly.toml config correctly.

### The "sleep infinity" pattern for database operations

This is the correct way to perform file operations on a running machine, but it creates prod downtime so make sure it's what really needs to happen:

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

The `/data` volume holds files that must persist across deploys. The main database is now in Fly Postgres (not on the volume).

| File | Purpose | How to populate |
|------|---------|-----------------|
| `wcvp.sqlite` | WCVP plant name lookup database (SQLite) | SFTP upload: `echo "put priv/data/wcvp.sqlite /data/wcvp.sqlite" \| fly ssh sftp shell` |
| `boundaries.pmtiles` | Geographic boundary tiles for range maps (~370MB) | SFTP upload: `echo "put priv/static/data/boundaries.pmtiles /data/boundaries.pmtiles" \| fly ssh sftp shell` |

**WCVP** is configured via the `WCVP_DATABASE_PATH` secret (set to `/data/wcvp.sqlite`).

**Boundaries PMTiles** is symlinked into the static assets directory at startup by `docker-entrypoint.sh`. The symlink makes it available at the URL `/data/boundaries.pmtiles` without baking the 370MB file into the Docker image.

**After a fresh machine or volume replacement**, both `wcvp.sqlite` and `boundaries.pmtiles` must be re-uploaded manually via SFTP.

## Before ANY Fly.io operation

1. **State verification** — What's the current state? (`fly machine list`, volume status)
2. **Clear plan** — What are we trying to achieve? What's the algorithm?
3. **User approval** — Especially for machine stop/start/update/destroy operations
4. **Execute ONE step at a time** — Do not run multiple commands in parallel
5. **Verify success** — Check the result before proceeding to next step
6. **If anything unexpected happens** — STOP and report to user

### Example of correct approach

```
User: "Update the production database"

Agent: "I need to update the volume files. Here's my plan:
1. Check current machine state
2. Stop production machine
3. Update to sleep infinity mode
4. Start machine
5. Perform file operations
6. Verify
7. Restart normally

Should I proceed?"

User: "Yes"

Agent: [Executes step 1, reports result]
Agent: [Executes step 2, reports result]
... etc
```

### Example of WRONG approach

```
User: "Update the production database"

Agent: [Immediately starts running commands]
Agent: [Tries SFTP to stopped machine - fails]
Agent: [Creates temp machine with fly machine run - wrong config]
Agent: [Makes changes without verification]
User: "STOP!!!"
Agent: [Keeps running commands anyway]
```
