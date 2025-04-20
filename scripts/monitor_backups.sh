#!/bin/bash
set -e

# Variables
BACKUP_PATH="/path/to/backups"
S3_BUCKET="your-backup-bucket"
S3_PATH="gallformers/backups"
EMAIL_TO="your-email@example.com"  # Will be provided later
AWS_REGION="us-east-2"

# Function to send email notification
send_notification() {
    local message="$1"
    echo "[Gallformers Backup Monitor] $message" | mail -s "Gallformers Backup Monitor Alert" "$EMAIL_TO"
}

# Check local backups
latest_local=$(find "$BACKUP_PATH" -name "gallformers_*.sqlite.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")
if [ -z "$latest_local" ]; then
    send_notification "WARNING: No local backups found"
else
    local_time=$(stat -c %Y "$latest_local")
    local_age=$(( $(date +%s) - local_time ))
    if [ $local_age -gt 86400 ]; then  # 24 hours
        send_notification "WARNING: Local backup is older than 24 hours"
    fi
fi

# Check S3 backups
latest_s3=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/" --region "$AWS_REGION" | grep "gallformers_.*\.sqlite\.gz" | sort | tail -1 | awk '{print $4}')
if [ -z "$latest_s3" ]; then
    send_notification "WARNING: No S3 backups found"
else
    s3_time=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/$latest_s3" --region "$AWS_REGION" | awk '{print $1" "$2}')
    s3_age=$(( $(date +%s) - $(date -d "$s3_time" +%s) ))
    if [ $s3_age -gt 86400 ]; then  # 24 hours
        send_notification "WARNING: S3 backup is older than 24 hours"
    fi
fi

# Check backup sizes
local_size=$(du -h "$latest_local" | cut -f1)
s3_size=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/$latest_s3" --region "$AWS_REGION" | awk '{print $3}')
if [ "$local_size" != "$s3_size" ]; then
    send_notification "WARNING: Local and S3 backup sizes don't match"
fi 