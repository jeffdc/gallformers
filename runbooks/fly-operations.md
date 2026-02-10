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
| `DATABASE_PATH` | `/data/gallformers.sqlite` | SQLite on persistent volume |
| `min_machines_running` | `1` | Always keep one machine running |

## Secrets

```bash
fly secrets list
fly secrets set SECRET_KEY_BASE=xxx
fly secrets set AUTH0_CLIENT_ID=xxx AUTH0_CLIENT_SECRET=xxx AUTH0_DOMAIN=xxx
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
3. Start machine (now runs `sleep infinity` instead of app — releases DB lock)
4. Perform file operations (backup, upload, verify)
5. Clear command override: `fly machine update --command ""`
6. Restart machine (reverts to Dockerfile CMD with fly.toml config)

**Why this works:**
- Machine starts successfully (sleep infinity never fails)
- App is not running, so DB lock is released
- Machine keeps all its configuration (memory, health checks, etc.)
- Clearing command override reverts to original Dockerfile CMD
- No machine destruction/recreation needed

## SQLite on Fly.io

**WAL mode requires 3 files:**
- `.sqlite` - main database
- `.sqlite-shm` - shared memory file
- `.sqlite-wal` - write-ahead log

Uploading or downloading only the `.sqlite` file will result in database corruption.

**Creating a clean single-file copy:**
```bash
sqlite3 db.sqlite "PRAGMA wal_checkpoint(TRUNCATE); VACUUM;"
# Now you can upload just the .sqlite file
```

**Backup strategy:**
- Use `mv` not `cp` for backups (SFTP cannot overwrite existing files)
- `mv /data/gallformers.sqlite /data/gallformers-TIMESTAMP.sqlite.bak`
- Now you can upload to `/data/gallformers.sqlite`

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

Agent: "I need to update the production database. Here's my plan:
1. Validate local DB (integrity + species count)
2. Stop production machine
3. Update to sleep infinity mode
4. Start machine (releases DB lock)
5. Backup existing DB (mv to timestamped file)
6. Upload new DB
7. Verify remote DB
8. Clear Litestream backups
9. Restart normally

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
Agent: [Uploads only .sqlite file - missing WAL/SHM]
Agent: [Database corrupted]
User: "STOP!!!"
Agent: [Keeps running commands anyway]
```
