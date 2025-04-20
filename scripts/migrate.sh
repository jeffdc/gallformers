#!/bin/bash
set -e

# Variables
APP_PATH="/path/to/your/app"
EMAIL_TO="your-email@example.com"

# Function to send email notification
send_notification() {
    local message="$1"
    local status="$2"
    echo "[Gallformers Migration] $message - Status: $status" | mail -s "Gallformers Migration Notification" "$EMAIL_TO"
}

# Stop the application
pm2 stop gallformers

# Run migrations
cd "$APP_PATH"
yarn migrate

# Generate new Prisma client
yarn generate

# Start the application
pm2 start gallformers

# Verify application
if curl -s -f "https://www.gallformers.org" > /dev/null; then
    send_notification "Migration completed successfully" "SUCCESS"
else
    send_notification "Migration failed - site not responding" "ERROR"
    exit 1
fi 