#!/bin/bash
set -e

# Variables
APP_PATH="/path/to/your/app"
BACKUP_PATH="/path/to/backups"
S3_BUCKET="your-backup-bucket"
S3_PATH="gallformers/backups"
DB_PATH="$APP_PATH/gallformers.sqlite"
EMAIL_TO="your-email@example.com"  # Will be provided later
AWS_REGION="us-east-2"

# Function to send email notification
send_notification() {
    local message="$1"
    local status="$2"
    echo "[Gallformers Restore] $message - Status: $status" | mail -s "Gallformers Restore Notification" "$EMAIL_TO"
}

# Stop the application
pm2 stop gallformers

# Create backup of current database
timestamp=$(date +%Y%m%d_%H%M%S)
cp "$DB_PATH" "$BACKUP_PATH/pre_restore_$timestamp.sqlite"

# If backup file is provided, use it; otherwise, get latest from S3
if [ -n "$1" ]; then
    backup_file="$1"
else
    backup_file=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/" --region "$AWS_REGION" | grep "gallformers_.*\.sqlite\.gz" | sort | tail -1 | awk '{print $4}')
    aws s3 cp "s3://$S3_BUCKET/$S3_PATH/$backup_file" "$BACKUP_PATH/" --region "$AWS_REGION"
    gunzip "$BACKUP_PATH/$backup_file"
    backup_file="${backup_file%.gz}"
fi

# Restore database
cp "$BACKUP_PATH/$backup_file" "$DB_PATH"

# Verify database integrity
if sqlite3 "$DB_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    echo "Database integrity verified"
    send_notification "Database restored successfully" "SUCCESS"
else
    echo "Database integrity check failed"
    send_notification "Database restore failed - integrity check failed" "ERROR"
    exit 1
fi

# Start the application
pm2 start gallformers

# Cleanup
rm -f "$BACKUP_PATH/$backup_file" 