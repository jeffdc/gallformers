# Runbook: Restore a Deleted Gall

Restore one deleted gall from a full production backup without replacing the current production database.

> **Validated:** This procedure restored a deleted gall end to end on 2026-09-02. It remains limited to deleted galls; restoring a deleted host is out of scope.

## Purpose

`Species.delete_species/1` deletes the gall’s S3 image objects before deleting the `species` row. Database foreign-key cascades remove the gall traits, images, gall-host relationships, source links, taxonomy links, ranges, morphology links, and alias links. Application cleanup may then delete aliases that no longer belong to any species.

This procedure restores the deleted gall at its original ID, restores every deleted database row from the chosen backup, and then restores the retained S3 object versions. It never replaces production with an old database backup.

## Safety Rules

1. Rehearse the exact SQL against an isolated local copy of current production before any production write.
2. Use the private full backup only. The public snapshot excludes data required for recovery.
3. Keep application read-only mode enabled from Step 0 until production checks finish. Direct `psql` writes intentionally bypass application read-only mode; only the designated operator may run them.
4. Do not use the whole-database process in [Restore Database](./restore-database.md). It discards unrelated production changes made after the backup.
5. Do not use `fly ssh console` for database work. Use `fly proxy`.
6. Do not use `pg_restore --clean`, `INSERT ... ON CONFLICT`, `UPDATE`, `DELETE`, `TRUNCATE`, or schema changes. A mismatch is a stop condition, not a reason to overwrite current data.
7. Execute Fly operations one at a time. Stop and investigate any result that differs from this runbook.

## Inputs and Evidence Directory

```bash
export GALL_ID='<gall_id>'
export RECOVERY_ROOT="/tmp/gall-recovery-${GALL_ID}-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$RECOVERY_ROOT"
chmod 700 "$RECOVERY_ROOT"
```

Retain the selected backup, current-production dump, generated SQL, logs, checksums, S3 version listing, and UI evidence under `$RECOVERY_ROOT` until the incident is closed.

The evidence directory is working storage, not the operational record. Record decisions, selected backup, approvals, unexpected results, and final verification in the incident document created for this recovery.

## Step 0: Enable Application Read-Only Mode

Before taking either database copy:

1. Enable the site’s application read-only mode, from the Op tab in Admin.
2. Confirm non-Op admin is inaccessible while public pages remain readable.
3. Record the time and operator in `docs/incidents/YYYYMMDD-deleted-gall-recovery.md`.

## Step 1: Fetch and Preserve the Full Backup

The `make download-db` target downloads the latest daily object from the private bucket `gallformers-full-backups` into `/tmp/gallformers.dump` and restores it into `gallformers_dev`. It does not use the public snapshot. This must be done between when the deletion happens and BEFORE the next scheduled backup. If a backup has already happened, then one of the archived backups will need to be used. That process is not covered here at this time.

It replaces local `gallformers_dev`, so stop local processes that use that database first. Also make sure that you are not on a branch with pending/unmerged changes as it will potentially inhibit testing and/or cause erroneous test results.

```bash
make download-db
cp /tmp/gallformers.dump "$RECOVERY_ROOT/backup-full.dump"
chmod 600 "$RECOVERY_ROOT/backup-full.dump"
pg_restore --list "$RECOVERY_ROOT/backup-full.dump" > "$RECOVERY_ROOT/backup-full.toc"
shasum -a 256 "$RECOVERY_ROOT/backup-full.dump" > "$RECOVERY_ROOT/backup-full.dump.sha256"
```

`/tmp/gallformers.dump` is the Make target’s fixed temporary download path. It is not an authoritative incident artifact after the copy above. Never use it for the current-production dump in Step 4.

Record the selected S3 backup date/object in the incident document.

## Step 2: Verify the Backup Through the Local UI

Start the development application against the restored `gallformers_dev` database and open:

```text
http://localhost:4000/gall/<gall_id>
```

Confirm and record:

- The intended gall loads at its historical numeric URL.
- Name, taxonomy, hosts, aliases, sources/excerpts, range, and morphology are correct.
- Image metadata, ordering, paths, and attribution are present.
- Image URLs may 404 because they resolve against the current S3 bucket, not the point-in-time database backup. That is expected after the deletion and is not a failure of the database backup.

Record the backup UI review and the expected pre-image 404 state in the incident document.

## Step 3: Generate the Restore SQL

Run the committed generator against the backup database. The only input is the gall ID:

```bash
psql -X -qAt -v ON_ERROR_STOP=1 -v gall_id="$GALL_ID" \
  -d gallformers_dev \
  -f runbooks/sql/generate-deleted-gall-restore.sql \
  -o "$RECOVERY_ROOT/restore-gall.sql"

test -s "$RECOVERY_ROOT/restore-gall.sql"
shasum -a 256 "$RECOVERY_ROOT/restore-gall.sql" \
  > "$RECOVERY_ROOT/restore-gall.sql.sha256"
```

The generator verifies that the backup contains one gall and its `gall_traits` row. It also discovers every foreign key to `species.id` and stops if the gall has data in a relationship this procedure does not support.

The generated file contains:

- the complete historical gall and dependent rows, including image rows;
- SQL-safe literal values produced by PostgreSQL;
- conditional restoration of aliases that may still be shared;
- inserts in foreign-key order inside one transaction;
- sequence synchronization for tables with explicit IDs.

Primary-key, unique-key, and foreign-key constraints are the runtime preflight. If the gall or one of its deleted row IDs is already present, or a required shared host, source, taxonomy, place, abundance, or vocabulary row is missing, the transaction aborts without committing a partial restore.

Review the generated SQL. It must contain only the expected gall, begin with `\set ON_ERROR_STOP on` and `BEGIN`, and end with `COMMIT`. Do not hand-edit it after review. Record its checksum and review outcome in the incident document.

## Step 4: Dump Current Production Separately

The daily backup is the source of restored data. This new dump captures production as it exists immediately before recovery.

Verify Fly authentication before starting the proxy:

```bash
fly auth whoami
```

If the session has expired, run `fly auth login` and complete the browser flow.

Terminal 1:

```bash
set -a; [ -f .env ] && . .env; set +a
fly proxy 15432:5432 -a "$PG_PROD_DB_APP"
```

Keep the proxy running. In Terminal 2:

```bash
set -a; [ -f .env ] && . .env; set +a

PGPASSWORD="$PG_PROD_PASSWORD" psql \
  -h localhost -p 15432 -U "$PG_PROD_USERNAME" -d postgres \
  -c 'SELECT 1'

PGPASSWORD="$PG_PROD_PASSWORD" pg_dump \
  --format=custom --no-owner --no-acl \
  -h localhost -p 15432 -U "$PG_PROD_USERNAME" "$PG_PROD_DBNAME" \
  -f "$RECOVERY_ROOT/production-current.dump"

chmod 600 "$RECOVERY_ROOT/production-current.dump"
shasum -a 256 "$RECOVERY_ROOT/production-current.dump" \
  > "$RECOVERY_ROOT/production-current.dump.sha256"
test -s "$RECOVERY_ROOT/production-current.dump"
pg_restore --list "$RECOVERY_ROOT/production-current.dump" \
  --file="$RECOVERY_ROOT/production-current.toc"
```

Stop the proxy in Terminal 1 with `Ctrl-C`.

Never write this dump to `/tmp/gallformers.dump` and never overwrite `backup-full.dump`. Record the dump time and checksum in the incident document.

## Step 5: Rehearse Against Current Production Locally

Restore the current-production dump into a separate local database. Do not overwrite `gallformers_dev`, which remains the recovery source:

```bash
createdb gallformers_recovery_current
pg_restore --no-owner --no-acl \
  -d gallformers_recovery_current \
  "$RECOVERY_ROOT/production-current.dump"
```

Run the generated transaction:

```bash
psql -X -v ON_ERROR_STOP=1 \
  -d gallformers_recovery_current \
  -f "$RECOVERY_ROOT/restore-gall.sql" \
  | tee "$RECOVERY_ROOT/local-restore.log"
```

Any SQL error is a stop condition. Do not alter the generated file to force it through.

Start the local application against `gallformers_recovery_current`:

```bash
PGDATABASE=gallformers_recovery_current make dev
```

Open:

```text
http://localhost:4000/gall/<gall_id>
```

Compare it with the backup review from Step 2. Name, taxonomy, hosts, aliases, sources/excerpts, range, morphology, image metadata, attribution, source links, and image ordering must match. Image URLs should still 404 because the database rows are restored but the S3 objects remain deleted.

Record the SQL and UI results in the incident document.

## Step 6: Restore Images and Verify Locally

The generated SQL already restores the `image` rows. This step restores only the S3 objects, before any production database write.

Generate the expected object keys from the backup database:

```bash
psql -X -qAt -v ON_ERROR_STOP=1 -v gall_id="$GALL_ID" \
  -d gallformers_dev \
  -o "$RECOVERY_ROOT/image-keys.txt" <<'SQL'
SELECT replace(i.path, '_original', '_' || variant.name)
FROM image i
CROSS JOIN (
  VALUES ('original'), ('small'), ('medium'), ('large'), ('xlarge')
) AS variant(name)
WHERE i.species_id = :'gall_id'::bigint
ORDER BY i.path, variant.name;
SQL
```

Capture the current S3 version history:

```bash
aws s3api list-object-versions \
  --bucket gallformers-images-us-east-1 \
  --prefix "gall/${GALL_ID}/" \
  --output json \
  > "$RECOVERY_ROOT/image-versions.json"
```

For every key in `image-keys.txt`, verify that the current version is the deletion marker created when the gall was deleted and that a prior object version exists.

Create `$RECOVERY_ROOT/restore-image-markers.sh` with one reviewed command per key:

```bash
aws s3api delete-object \
  --bucket gallformers-images-us-east-1 \
  --key '<exact-object-key>' \
  --version-id '<current-delete-marker-version-id>'
```

Deleting the current deletion marker exposes the retained object version. It does not modify the image database rows. The command requires `s3:DeleteObjectVersion`.

After review, run the image restoration:

```bash
bash "$RECOVERY_ROOT/restore-image-markers.sh"
```

Verify every expected object:

```bash
while IFS= read -r key; do
  printf '%s\t' "$key"
  aws s3api head-object \
    --bucket gallformers-images-us-east-1 \
    --key "$key" \
    --query '[ContentLength, ContentType]' \
    --output text
done < "$RECOVERY_ROOT/image-keys.txt"
```

Reload the recovery-backed local page at `http://localhost:4000/gall/<gall_id>`. All images must now load. If S3 succeeds but CloudFront still serves cached 404s, stop and resolve that before restoring the production database.

Record the image-key count, restored marker count, object verification, and local UI result in the incident document.

## Step 7: Approve and Restore the Production Database

Before writing production, confirm:

- application read-only mode remains enabled;
- the complete local rehearsal, including images, passed;
- the restore SQL checksum is unchanged;
- the current-production dump and checksum are retained.

Record approval and the operator in the incident document.

Verify the SQL checksum:

```bash
shasum -a 256 -c "$RECOVERY_ROOT/restore-gall.sql.sha256"
```

In Terminal 1, start the proxy and keep it running:

```bash
set -a; [ -f .env ] && . .env; set +a
fly proxy 15432:5432 -a "$PG_PROD_DB_APP"
```

In Terminal 2, run the same generated SQL that passed locally:

```bash
set -o pipefail
set -a; [ -f .env ] && . .env; set +a

PGPASSWORD="$PG_PROD_PASSWORD" psql \
  -h localhost -p 15432 -U "$PG_PROD_USERNAME" -d "$PG_PROD_DBNAME" \
  -c 'SELECT 1'

PGPASSWORD="$PG_PROD_PASSWORD" psql \
  -X -v ON_ERROR_STOP=1 \
  -h localhost -p 15432 -U "$PG_PROD_USERNAME" -d "$PG_PROD_DBNAME" \
  -f "$RECOVERY_ROOT/restore-gall.sql" \
  | tee "$RECOVERY_ROOT/production-restore.log"
```

Stop the proxy in Terminal 1 with `Ctrl-C`.

Any SQL error is a stop condition. Record the transaction result in the incident document.

## Step 8: Verify Production

Open:

```text
https://gallformers.org/gall/<gall_id>
```

Confirm:

- the gall loads at its historical URL;
- all images load;
- hosts, aliases, sources/excerpts, range, morphology, related galls, and search are correct;
- no application or database error appears.

Record production verification in the incident document.

## Step 9: Close Out

1. Record the gall ID, backup timestamp, restored database-row and image-key counts, operators, and recovery window in the incident document.
2. Confirm no unexpected production data changed.
3. After approval, disable application read-only mode and confirm normal admin and public access.
4. Retain the backup, pre-write production dump, generated SQL, checksums, logs, and S3 version listing until the incident is closed.
5. Remove temporary local databases and working files only after evidence retention is complete.

## Failure Handling

- **Generator rejects the backup:** Stop. It either lacks the gall or contains a dependency this procedure does not support.
- **Generated SQL fails locally:** Keep production untouched. Investigate the reported constraint or dependency conflict; do not bypass it.
- **Generated SQL fails in production:** Stop immediately and confirm the transaction rolled back before considering a retry.
- **S3 object version is missing:** Record the unavailable image and recover it only from an approved alternate source.
