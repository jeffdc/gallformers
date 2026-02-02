#!/bin/bash
# Test the V1 to V2 migration script and apply to main database if successful

set -e

PRISTINE_V1="gallformers_v1_clean.sqlite"
TEMP_DB="test.sqlite"
PRIMARY_DB="gallformers.sqlite"
MIGRATION_SCRIPT="repo/migrate_v1_to_v2.sql"

echo "Restoring clean V1 database..."
if [ ! -f "$PRISTINE_V1" ]; then
  echo "Error: Pristine V1 database not found: $PRISTINE_V1"
  exit 1
fi
cp "$PRISTINE_V1" "$TEMP_DB"

echo "Running migration script..."
if ! sqlite3 "$TEMP_DB" < "$MIGRATION_SCRIPT"; then
  echo "Error: Migration failed!"
  exit 1
fi

echo "Migration completed successfully!"
echo ""

# If primary database exists, back it up and replace with migrated version
if [ -f "$PRIMARY_DB" ]; then
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  BACKUP_DB="gallformers_backup_${TIMESTAMP}.sqlite"

  echo "Backing up current database..."
  echo "  $PRIMARY_DB -> $BACKUP_DB"
  cp "$PRIMARY_DB" "$BACKUP_DB"

  echo "Replacing primary database with migrated version..."
  mv "$TEMP_DB" "$PRIMARY_DB"

  echo ""
  echo "✓ Primary database updated: $PRIMARY_DB"
  echo "✓ Backup saved: $BACKUP_DB"
else
  echo "No primary database found at $PRIMARY_DB"
  echo "Migrated database ready at: $TEMP_DB"
  echo ""
  echo "To use as primary database, run:"
  echo "  mv $TEMP_DB $PRIMARY_DB"
fi
