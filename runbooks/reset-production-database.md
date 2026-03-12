# Runbook: Reset Production Database

## Purpose

Replace the production database with a completely new dataset. This is different from [restoring from backup](./restore-database.md), which recovers from existing backups.

## When to Use

- **Initial deployment**: Bootstrapping a new production environment
- **Major data migration**: Replacing the database with a transformed/migrated version
- **Disaster recovery**: When backups are unavailable or corrupted

## When NOT to Use

- **Point-in-time recovery**: Use [Restore Database](./restore-database.md) instead
- **Routine maintenance**: This is a destructive operation

## Prerequisites

- Access to Fly Postgres cluster
- The replacement database dump, validated and ready

## Important

This operation **replaces all production data**. There is no undo unless you have a backup. Coordinate with stakeholders before proceeding.

## Procedure

> **Note**: This runbook was previously written for the SQLite volume-swap approach. The exact procedure for Postgres (pg_dump/pg_restore via Fly Postgres) is TBD and will be updated once the Postgres backup strategy is finalized.

### 1. Prepare the Database Dump

The dump must be compatible with the current schema and migrations.

### 2. Create a Backup of Current State

Before resetting, back up the current database.

### 3. Restore the New Dump

Use `pg_restore` or `psql` to load the new data into the Fly Postgres database.

### 4. Verify Success

```bash
# Check health endpoint
curl -s https://gallformers.fly.dev/health

# Check machine status
flyctl status -a gallformers
```

## Verification Checklist

After reset or rollback:

- [ ] Health endpoint returns 200
- [ ] Species count matches expected
- [ ] Sample pages load correctly (e.g., `/species`, `/hosts`)
- [ ] Admin functions work (if applicable)

## Related Runbooks

- [Restore Database](./restore-database.md) - Recovery from backups
- [Rollback Deployment](./rollback-deployment.md) - Rolling back code changes
- [Diagnose Deployment Issue](./diagnose-deployment-issue.md) - General troubleshooting
