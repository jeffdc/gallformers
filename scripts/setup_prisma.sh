#!/bin/bash
set -e

# Variables
APP_PATH="/path/to/your/app"
EMAIL_TO="your-email@example.com"

# Function to send email notification
send_notification() {
    local message="$1"
    local status="$2"
    echo "[Gallformers Prisma Setup] $message - Status: $status" | mail -s "Gallformers Prisma Setup Notification" "$EMAIL_TO"
}

# Install required dependencies
cd "$APP_PATH"
yarn add -D better-sqlite3@^7.1.1 better-sqlite3-helper@^3.1.1 sqlite@^4.0.15

# Generate Prisma client
yarn generate

# Remove development dependencies
yarn remove better-sqlite3 better-sqlite3-helper sqlite

# Verify Prisma client generation
if [ -d "node_modules/.prisma" ]; then
    echo "Prisma client generated successfully"
    send_notification "Prisma client generated successfully" "SUCCESS"
else
    echo "Prisma client generation failed"
    send_notification "Prisma client generation failed" "ERROR"
    exit 1
fi 