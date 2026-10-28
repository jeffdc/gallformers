# Runbook: Postgres Maintenance

Day-to-day operations, monitoring, and maintenance for the production Postgres database.

## Connecting to Production Postgres

**Never query production directly via `fly ssh console`.** Use `fly proxy` to connect from your local machine.

### Setup

Production credentials are never kept in `.env` or your shell profile. Type them for this terminal only; the password is not echoed, and the variables are not exported, so they reach only the commands that name them:

```bash
read -r -p "Postgres user: " PG_PROD_USERNAME
read -r -p "Database name: " PG_PROD_DBNAME
read -r -s -p "Postgres password: " PG_PROD_PASSWORD; echo
```

When you are done:

```bash
unset PG_PROD_PASSWORD PG_PROD_USERNAME PG_PROD_DBNAME
```

### Connect

```bash
fly proxy 15432:5432 -a gallformers-db &
PGPASSWORD="$PG_PROD_PASSWORD" psql -h localhost -p 15432 -U "$PG_PROD_USERNAME" -d "$PG_PROD_DBNAME"
```

When done, stop the proxy:

```bash
kill %1
```

### One-off query

For a quick query without an interactive session (after the Setup above):

```bash
fly proxy 15432:5432 -a gallformers-db &
sleep 2
PGPASSWORD="$PG_PROD_PASSWORD" psql -h localhost -p 15432 -U "$PG_PROD_USERNAME" -d "$PG_PROD_DBNAME" \
  -c "SELECT count(*) FROM species;"
kill %1
```

## Monitoring

### Fly machine health

```bash
fly status -a gallformers-db
fly machine list -a gallformers-db
fly checks list -a gallformers-db
```

### Database size

Connect via proxy, then:

```sql
-- Total database size
SELECT pg_size_pretty(pg_database_size(current_database()));

-- Size by table (largest first)
SELECT
  relname AS table,
  pg_size_pretty(pg_total_relation_size(relid)) AS total,
  pg_size_pretty(pg_relation_size(relid)) AS data,
  pg_size_pretty(pg_indexes_size(relid)) AS indexes
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

### Active connections

```sql
-- Connection count by state
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state;

-- Active queries (running longer than 5 seconds)
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE datname = current_database()
  AND state != 'idle'
  AND now() - pg_stat_activity.query_start > interval '5 seconds'
ORDER BY duration DESC;
```

### Table bloat and vacuum status

```sql
-- Last vacuum and analyze per table
SELECT
  relname AS table,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze,
  n_dead_tup AS dead_rows
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

## Backups

### Daily pg_dump snapshots

Automated via GitHub Actions (`db-snapshot.yml`). Runs daily at 6 AM UTC.

- **Full backup** (all tables, includes PII): `s3://gallformers-full-backups/<date>/gallformers.dump`
- **Public snapshot** (filtered, no PII): `s3://gallformers-backups/public/gallformers.dump`

To restore from a snapshot, see [Restore Database](./restore-database.md).

### Barman (Fly Postgres built-in backups)

Fly's `postgres-flex` image includes barman for continuous WAL-based backups. This provides lower RPO than the daily pg_dump snapshots.

Check barman status:

```bash
fly postgres barman check -a gallformers-db
fly postgres barman backup list -a gallformers-db
```

**Note:** Barman has not yet been verified as working. Check this and confirm backup frequency and retention before relying on it for disaster recovery.

## Maintenance Tasks

### Manual VACUUM (rarely needed)

Postgres autovacuum handles this automatically. Only run manually if you see significant table bloat:

```sql
-- Analyze and vacuum a specific table
VACUUM ANALYZE species;

-- Full vacuum (rewrites table, requires exclusive lock — use with caution)
VACUUM FULL species;
```

### Reindex (rarely needed)

If index bloat is suspected:

```sql
-- Reindex a specific table's indexes
REINDEX TABLE species;

-- Check index sizes vs table sizes (high ratio may indicate bloat)
SELECT
  indexrelname AS index,
  pg_size_pretty(pg_relation_size(indexrelid)) AS size,
  idx_scan AS scans
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Kill a stuck query

```sql
-- Find the PID first
SELECT pid, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE datname = current_database() AND state = 'active';

-- Cancel gracefully
SELECT pg_cancel_backend(<pid>);

-- Force terminate if cancel doesn't work
SELECT pg_terminate_backend(<pid>);
```
