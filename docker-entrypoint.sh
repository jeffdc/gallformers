#!/bin/sh
# Docker entrypoint for Gallformers V2
# Restores DB if needed, creates pre-migration backup, runs migrations,
# then starts the app with Litestream replication

set -e

DATABASE_PATH="${DATABASE_PATH:-/data/gallformers.sqlite}"
BACKUP_DIR="/data/backups"
MAX_BACKUPS=3
DISK_WARN_PERCENT=80

# Check disk usage and warn if above threshold
check_disk_usage() {
  usage=$(df /data | awk 'NR==2 {gsub(/%/,""); print $5}')
  if [ "$usage" -ge "$DISK_WARN_PERCENT" ]; then
    echo "WARNING: /data volume is ${usage}% full — consider extending the volume"
  fi
}

# Fix ownership of data directory and any existing litestream files
# This handles the case where the volume was created by a different deployment
if [ -d /data ]; then
  chown -R gallformers:gallformers /data 2>/dev/null || echo "WARNING: Could not chown all files in /data — continuing"
fi

check_disk_usage

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"
chown gallformers:gallformers "$BACKUP_DIR"

# Restore from Litestream if no database exists
if [ ! -f "$DATABASE_PATH" ]; then
  echo "No database found, attempting restore from Litestream..."
  if litestream restore -if-replica-exists -o "$DATABASE_PATH" s3://gallformers-backups/litestream; then
    chown gallformers:gallformers "$DATABASE_PATH"
    echo "Database restored from Litestream."
  else
    echo "ERROR: No database and no Litestream backup available."
    echo "Use the 'Reset Production Database' workflow to bootstrap."
    exit 1
  fi
fi

# Pre-migration backup (non-fatal — Litestream provides continuous replication to S3,
# so a missing local backup is not worth an outage)
BACKUP_NAME="pre-migrate-$(date +%Y%m%d-%H%M%S).sqlite"
echo "Creating pre-migration backup: $BACKUP_NAME"
if sqlite3 "$DATABASE_PATH" ".backup '$BACKUP_DIR/$BACKUP_NAME'"; then
  chown gallformers:gallformers "$BACKUP_DIR/$BACKUP_NAME"
else
  echo "WARNING: Pre-migration backup failed (disk full?) — continuing without backup"
  rm -f "$BACKUP_DIR/$BACKUP_NAME"
fi

# Cleanup old backups (keep only MAX_BACKUPS most recent)
cd "$BACKUP_DIR"
ls -t pre-migrate-*.sqlite 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f 2>/dev/null || echo "WARNING: Could not clean up all old backups — continuing"
cd /app

# Run database migrations
# Note: release_command doesn't work with SQLite volumes on Fly.io because
# the release machine gets a forked snapshot that doesn't persist changes
echo "Running database migrations..."
su-exec gallformers /app/bin/gallformers eval 'Gallformers.Release.migrate()'

# Switch to gallformers user and start litestream with the app
exec su-exec gallformers litestream replicate -exec "/app/bin/server"
