#!/bin/bash
set -e

# Variables
APP_URL="https://www.gallformers.org"
EMAIL_TO="your-email@example.com"

# Function to send email notification
send_notification() {
    local message="$1"
    local status="$2"
    echo "[Gallformers Integration Check] $message - Status: $status" | mail -s "Gallformers Integration Check" "$EMAIL_TO"
}

# Check Auth0 integration
if curl -s -f "$APP_URL/api/auth/session" | grep -q "auth0"; then
    echo "Auth0 integration verified"
else
    send_notification "Auth0 integration check failed" "ERROR"
    exit 1
fi

# Check S3 image storage
if curl -s -f "$APP_URL/api/test-image-upload" | grep -q "success"; then
    echo "S3 image storage verified"
else
    send_notification "S3 image storage check failed" "ERROR"
    exit 1
fi

# Check SSL certificate
if openssl s_client -connect www.gallformers.org:443 -servername www.gallformers.org </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
    echo "SSL certificate verified"
else
    send_notification "SSL certificate check failed" "ERROR"
    exit 1
fi

# Check monitoring systems
if curl -s -f "$APP_URL/api/health" | grep -q "ok"; then
    echo "Health check endpoint verified"
else
    send_notification "Health check endpoint failed" "ERROR"
    exit 1
fi

send_notification "All integration checks passed" "SUCCESS" 