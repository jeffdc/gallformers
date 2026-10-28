# Runbook: Restore Postgres Database

## Purpose

Restore the Fly Postgres database from a pg_dump backup after corruption, data loss, or for testing.

## When to Use

- Accidental data deletion or corruption
- Need to recover to a known-good state
- Testing backup/restore as part of operational readiness
- Refreshing preview data

## Prerequisites

- `psql`, `pg_dump`, `pg_restore` installed locally
- Fly CLI authenticated (`fly auth login`)
- A pg_dump backup file (`.dump` in custom format)

## Important

Database restoration will cause **data loss** for any changes made after the backup was taken. For production, coordinate with stakeholders and consider putting the site in read-only mode first.

## Setup

### 1. Enter the credentials for this terminal

Production credentials are never kept in `.env` or your shell profile. Type them here, for this terminal only; the password is not echoed, and the variables are not exported, so they reach only the commands below that name them.

For production:

```bash
PG_DB_APP=gallformers-db
read -r -p "Postgres user: " PG_USERNAME
read -r -p "Database name: " PG_DBNAME
read -r -s -p "Postgres password: " PG_PASSWORD; echo
```

When you are done (after stopping the proxy):

```bash
unset PG_PASSWORD PG_USERNAME PG_DBNAME PG_DB_APP
```

### 2. Start the proxy

Run the proxy in the background:

```bash
fly proxy 15432:5432 -a "$PG_DB_APP" &
PROXY_PID=$!
sleep 2
```

Verify it's working:

```bash
PGPASSWORD="$PG_PASSWORD" psql -h localhost -p 15432 -U "$PG_USERNAME" -d postgres -c "SELECT 1"
```

When done with all steps, stop the proxy:

```bash
kill $PROXY_PID
```

## Getting a Backup

> **TODO:** Automated backup infrastructure (pg_dump cron to S3) is not yet in place. For now, backups must be created manually before they are needed.

### Create a manual backup

If the database is still accessible, dump it before proceeding:

```bash
PGPASSWORD="$PG_PASSWORD" pg_dump \
  --format=custom --no-owner --no-acl \
  -h localhost -p 15432 \
  -U "$PG_USERNAME" "$PG_DBNAME" \
  > /tmp/gallformers-backup.dump
```

If the database is in a bad state, this may not be possible — proceed directly to restore from whatever backup is available.

### Locate an existing backup

> **TODO:** Once automated backups are in place, document the S3 path and how to list/download available backups here.

## Restore Procedure

### 1. Drop and recreate the database

The `--clean` flag on pg_restore doesn't work reliably with Fly Postgres due to extension and schema ownership conflicts. Drop and recreate instead.

```bash
PGPASSWORD="$PG_PASSWORD" psql \
  -h localhost -p 15432 \
  -U "$PG_USERNAME" -d postgres <<SQL
SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = '$PG_DBNAME' AND pid <> pg_backend_pid();
DROP DATABASE $PG_DBNAME;
CREATE DATABASE $PG_DBNAME OWNER $PG_USERNAME;
SQL
```

### 2. Restore from backup

```bash
PGPASSWORD="$PG_PASSWORD" pg_restore \
  -h localhost -p 15432 \
  -U "$PG_USERNAME" -d "$PG_DBNAME" \
  --no-owner --no-acl \
  /tmp/gallformers-backup.dump
```

### 3. Verify data

```bash
PGPASSWORD="$PG_PASSWORD" psql \
  -h localhost -p 15432 \
  -U "$PG_USERNAME" -d "$PG_DBNAME" \
  -c "SELECT count(*) FROM species; SELECT count(*) FROM source; SELECT count(*) FROM image; SELECT count(*) FROM gall_traits;"
```

### 4. Verify the application

Browse the site and check:
- Species pages load with correct data
- Search returns results
- Maps render
- Admin pages work (if not in read-only mode)

### 5. Stop the proxy

```bash
kill $PROXY_PID
```

## If Restoration Fails

1. Check `pg_restore` output for errors — some non-fatal warnings about extensions are normal
2. Try an older backup if available
3. Rollback: see [Rollback Deployment](./rollback-deployment.md)

## Post-Restoration

1. Document the incident and data loss window
2. Notify affected users if data was lost
3. Investigate root cause
4. Verify the site is functioning correctly
