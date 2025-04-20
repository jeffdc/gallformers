# Deployment Re-architecture Plan: Docker to PM2-based Deployment

## Overview
This document outlines the plan to migrate from Docker-based deployment to a PM2-based deployment system with enhanced backup and monitoring capabilities.

## Phase 1: Preparation and Documentation

1. **Create Migration Documentation**
   - Document current deployment process
   - Document all environment variables
   - Create rollback plan
   - Document SQLite database location (`./gallformers.sqlite`)
   - Document current manual backup process

2. **Server Requirements**
   - Node.js 20.x
   - PM2 (`npm install -g pm2`)
   - SQLite3
   - Required system dependencies:
     - Python3 and build-essential (for native module compilation)
     - libvips-dev (for Sharp image processing)
     - libsqlite3-dev (for SQLite3)
     - mailutils (for email notifications)
     - awscli (for S3 backup operations)
     - git (for deployment)
     - nginx (for reverse proxy)
     - certbot (for SSL certificates)

   Installation commands for Ubuntu 20.04:
   ```bash
   # Update package list
   sudo apt-get update

   # Install system dependencies
   sudo apt-get install -y \
     python3 \
     build-essential \
     libvips-dev \
     libsqlite3-dev \
     mailutils \
     awscli \
     git \
     nginx \
     certbot

   # Install Node.js 20.x
   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
   sudo apt-get install -y nodejs

   # Install PM2 globally
   sudo npm install -g pm2
   ```

## Phase 2: Create New Deployment Infrastructure

1. **Create PM2 Configuration** (`ecosystem.config.js`):
```javascript
module.exports = {
  apps: [{
    name: 'gallformers',
    script: 'yarn',
    args: 'start',
    env: {
      NODE_ENV: 'production',
      PORT: 3000,
      DATABASE_URL: 'file:./gallformers.sqlite',
      API_URL: 'https://www.gallformers.org',
      NEXTAUTH_URL: 'https://www.gallformers.org'
    },
    max_memory_restart: '1G',
    autorestart: true,
    watch: false,
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    error_file: 'logs/error.log',
    out_file: 'logs/out.log',
    merge_logs: true,
    instances: 1,
    exec_mode: 'fork'
  }]
}
```

2. **Create Enhanced Backup Script** (`scripts/backup.sh`):
```bash
#!/bin/bash
set -e

# Variables
APP_PATH="/path/to/your/app"
BACKUP_PATH="/path/to/backups"
DB_PATH="$APP_PATH/gallformers.sqlite"
S3_BUCKET="your-backup-bucket"
S3_PATH="gallformers/backups"
EMAIL_TO="your-email@example.com"  # Will be provided later

# Create timestamp
timestamp=$(date +%Y%m%d_%H%M%S)

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

# Backup database
echo "Creating database backup..."
cp "$DB_PATH" "$BACKUP_PATH/gallformers_$timestamp.sqlite"

# Compress the backup
gzip "$BACKUP_PATH/gallformers_$timestamp.sqlite"

# Upload to S3 with public-read ACL
echo "Uploading to S3..."
aws s3 cp "$BACKUP_PATH/gallformers_$timestamp.sqlite.gz" "s3://$S3_BUCKET/$S3_PATH/" --acl public-read

# Verify S3 upload
if aws s3 ls "s3://$S3_BUCKET/$S3_PATH/gallformers_$timestamp.sqlite.gz" > /dev/null; then
    echo "S3 upload verified"
    send_notification "Backup completed successfully" "SUCCESS"
else
    echo "S3 upload failed"
    send_notification "S3 upload failed" "ERROR"
    exit 1
fi

# Cleanup old backups (keep last 7 days)
find "$BACKUP_PATH" -name "gallformers_*.sqlite.gz" -mtime +7 -delete

# Cleanup old S3 backups (keep last 30 days)
aws s3 ls "s3://$S3_BUCKET/$S3_PATH/" | \
    awk '{print $4}' | \
    grep "gallformers_.*\.sqlite\.gz" | \
    sort -r | \
    tail -n +31 | \
    while read -r file; do
        aws s3 rm "s3://$S3_BUCKET/$S3_PATH/$file"
    done

# Log backup completion
echo "Backup completed: gallformers_$timestamp.sqlite.gz"
```

3. **Create Backup Monitoring Script** (`scripts/monitor_backups.sh`):
```bash
#!/bin/bash
set -e

# Variables
BACKUP_PATH="/path/to/backups"
S3_BUCKET="your-backup-bucket"
S3_PATH="gallformers/backups"
EMAIL_TO="your-email@example.com"  # Will be provided later

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
latest_s3=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/" | grep "gallformers_.*\.sqlite\.gz" | sort | tail -1 | awk '{print $4}')
if [ -z "$latest_s3" ]; then
    send_notification "WARNING: No S3 backups found"
else
    s3_time=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/$latest_s3" | awk '{print $1" "$2}')
    s3_age=$(( $(date +%s) - $(date -d "$s3_time" +%s) ))
    if [ $s3_age -gt 86400 ]; then  # 24 hours
        send_notification "WARNING: S3 backup is older than 24 hours"
    fi
fi

# Check backup sizes
local_size=$(du -h "$latest_local" | cut -f1)
s3_size=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/$latest_s3" | awk '{print $3}')
if [ "$local_size" != "$s3_size" ]; then
    send_notification "WARNING: Local and S3 backup sizes don't match"
fi
```

4. **Create Backup Restoration Script** (`scripts/restore.sh`):
```bash
#!/bin/bash
set -e

# Variables
APP_PATH="/path/to/your/app"
BACKUP_PATH="/path/to/backups"
S3_BUCKET="your-backup-bucket"
S3_PATH="gallformers/backups"
DB_PATH="$APP_PATH/gallformers.sqlite"
EMAIL_TO="your-email@example.com"  # Will be provided later

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
    backup_file=$(aws s3 ls "s3://$S3_BUCKET/$S3_PATH/" | grep "gallformers_.*\.sqlite\.gz" | sort | tail -1 | awk '{print $4}')
    aws s3 cp "s3://$S3_BUCKET/$S3_PATH/$backup_file" "$BACKUP_PATH/"
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
```

5. **Add AWS Configuration** (`scripts/setup_aws.sh`):
```bash
#!/bin/bash
set -e

# Variables
AWS_ACCESS_KEY_ID="your-access-key"
AWS_SECRET_ACCESS_KEY="your-secret-key"
AWS_REGION="your-region"  # Same as used for image uploads
S3_BUCKET="your-backup-bucket"

# Configure AWS CLI
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set region "$AWS_REGION"

# Create S3 bucket if it doesn't exist
if ! aws s3 ls "s3://$S3_BUCKET" 2>&1 > /dev/null; then
    aws s3 mb "s3://$S3_BUCKET"
    # Make bucket public
    aws s3api put-bucket-policy --bucket "$S3_BUCKET" --policy '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "PublicReadGetObject",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::'$S3_BUCKET'/*"
            }
        ]
    }'
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --lifecycle-configuration '{
            "Rules": [
                {
                    "ID": "Delete old backups",
                    "Status": "Enabled",
                    "Expiration": {
                        "Days": 30
                    }
                }
            ]
        }'
fi
```

## Phase 3: Server Setup

1. **Initial Server Setup**:
```bash
# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2
sudo npm install -g pm2

# Install SQLite3
sudo apt-get install -y sqlite3

# Create necessary directories
sudo mkdir -p /path/to/your/app
sudo mkdir -p /path/to/backups
sudo mkdir -p /path/to/your/app/logs
sudo chown -R $USER:$USER /path/to/your/app
sudo chown -R $USER:$USER /path/to/backups

# Setup log rotation
sudo tee /etc/logrotate.d/gallformers << EOF
/path/to/your/app/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 $USER $USER
    missingok
}
EOF
```

2. **Setup Monitoring Cron Jobs**:
```bash
# Add to /etc/cron.d/gallformers
# Daily backup at 2 AM
0 2 * * * /path/to/your/app/scripts/backup.sh >> /path/to/your/app/logs/backup.log 2>&1

# Check backups every 6 hours
0 */6 * * * /path/to/your/app/scripts/monitor_backups.sh >> /path/to/your/app/logs/monitor.log 2>&1
```

## Phase 4: Migration Process

1. **Pre-Migration Steps**:
   ```bash
   # 1. Create initial backup
   ./scripts/backup.sh

   # 2. Verify backup
   ./scripts/verify_backup.sh $(date +%Y%m%d_%H%M%S)

   # 3. Stop current Docker container
   docker-compose down
   ```

2. **Migration Steps**:
   ```bash
   # 1. Deploy new version
   ./scripts/deploy.sh

   # 2. Verify application
   curl -I https://www.gallformers.org

   # 3. Verify database integrity
   sqlite3 ./gallformers.sqlite "PRAGMA integrity_check;"
   ```

3. **Post-Migration Steps**:
   - Verify all functionality
   - Monitor logs for errors
   - Keep Docker setup for 24 hours before removal
   - Verify automated backups are working

## Phase 5: Cleanup

1. **Remove Docker Files**:
   ```bash
   # Remove Docker-related files
   rm Dockerfile docker-compose.yml .dockerignore
   
   # Remove Docker-related scripts from package.json
   ```

2. **Update Documentation**:
   - Update README.md with new deployment process
   - Document PM2 commands and maintenance procedures
   - Document backup and restore procedures
   - Document database migration procedures

## Pending Questions

1. What email address should be used for backup notifications?
2. What AWS region should be used for S3 backups? (Should be the same as used for image uploads)
3. Would you like to implement any additional backup verification steps?
4. Should we add any specific database maintenance procedures beyond VACUUM and ANALYZE? 