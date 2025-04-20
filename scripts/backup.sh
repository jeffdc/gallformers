#!/bin/bash
set -e

# Load environment variables
source "$(dirname "$0")/load_env.sh"

# Function to send email notification
send_notification() {
    local message="$1"
    local status="$2"
    echo "[Gallformers Backup] $message - Status: $status" | mail -s "Gallformers Backup Notification" "$EMAIL_TO"
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_PATH"

# Perform database maintenance
echo "Running database maintenance..."
sqlite3 "$DB_PATH" "VACUUM;"
sqlite3 "$DB_PATH" "ANALYZE;"

# Create timestamp
timestamp=$(date +%Y%m%d_%H%M%S)

# Backup database
echo "Creating database backup..."
cp "$DB_PATH" "$BACKUP_PATH/gallformers_$timestamp.sqlite"

# Compress the backup
gzip "$BACKUP_PATH/gallformers_$timestamp.sqlite"

# Upload to S3 with public-read ACL
echo "Uploading to S3..."
aws s3 cp "$BACKUP_PATH/gallformers_$timestamp.sqlite.gz" "s3://$S3_BUCKET/$S3_PATH/" --acl public-read --region "$AWS_REGION"

# Verify S3 upload
if aws s3 ls "s3://$S3_BUCKET/$S3_PATH/gallformers_$timestamp.sqlite.gz" --region "$AWS_REGION" > /dev/null; then
    echo "S3 upload verified"
    send_notification "Backup completed successfully" "SUCCESS"
else
    echo "S3 upload failed"
    send_notification "S3 upload failed" "ERROR"
    exit 1
fi

# Cleanup old backups (keep last 7 days)
find "$BACKUP_PATH" -name "gallformers_*.sqlite.gz" -mtime +7 -delete

# Cleanup old S3 backups (keep last 100 days)
aws s3 ls "s3://$S3_BUCKET/$S3_PATH/" --region "$AWS_REGION" | \
    awk '{print $4}' | \
    grep "gallformers_.*\.sqlite\.gz" | \
    sort -r | \
    tail -n +101 | \
    while read -r file; do
        aws s3 rm "s3://$S3_BUCKET/$S3_PATH/$file" --region "$AWS_REGION"
    done

# Log backup completion
echo "Backup completed: gallformers_$timestamp.sqlite.gz" 