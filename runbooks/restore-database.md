# Runbook: Restore Database

## Purpose
Restore the PostgreSQL database from backup after corruption or data loss.

## When to Use
- Migration failed and corrupted data
- Accidental data deletion
- Need to recover to a point-in-time state

## Prerequisites
- `flyctl` CLI installed and authenticated
- Access to Fly.io app `gallformers`
- Access to backup storage (S3 bucket `gallformers-backups`)

## Important
Database restoration will cause **data loss** for any changes made after the backup point. Coordinate with stakeholders before proceeding.

## Understanding the Setup

- Database: Fly Postgres (managed by Fly.io)
- Backup strategy: TBD (previously Litestream for SQLite; Postgres backup approach pending)

## Procedure

### 1. Assess the Situation

Determine:
- [ ] What caused the corruption/loss?
- [ ] When did the problem start?
- [ ] What is the acceptable data loss window?

### 2. Stop the Application

Prevent further writes while restoring:

```bash
fly machines list -a gallformers
fly machines stop <MACHINE_ID> -a gallformers
```

### 3. Restore from Backup

If restoring from a daily snapshot (pg_dump format):

```bash
# Download the backup from S3
aws s3 cp s3://gallformers-backups/public/<date>/gallformers.dump .

# Restore via pg_restore or psql (exact command depends on backup format and Fly Postgres setup)
# This section will be updated once the Postgres backup strategy is finalized.
```

### 4. Restart Application

```bash
fly machines start <MACHINE_ID> -a gallformers
```

### 5. Verify Application

```bash
curl -s -o /dev/null -w "%{http_code}" https://gallformers.fly.dev/health
```

Expected: `200`

Check logs:

```bash
fly logs -a gallformers --no-tail | head -30
```

## Verification Checklist

- [ ] Application starts without errors
- [ ] Health endpoint returns 200
- [ ] Data appears correct (spot check key records)

## If Restoration Fails

1. Try an older backup
2. If no valid backup available, escalate immediately

## Post-Restoration

1. Document the incident and data loss window
2. Notify affected users if data was lost
3. Investigate root cause
4. Verify backup system is functioning correctly
5. Consider if code rollback is also needed (see [Rollback Deployment](./rollback-deployment.md))
