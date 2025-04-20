#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default to development if no environment is specified
ENV=${1:-development}

# Function to load environment variables from a file
load_env_file() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        echo "Loading environment from $env_file"
        # Export all variables from the .env file
        while IFS='=' read -r key value || [ -n "$key" ]; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            
            # Remove any quotes from the value
            value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            
            # Export the variable
            export "$key=$value"
        done < "$env_file"
        return 0
    else
        echo "Warning: $env_file not found!"
        return 1
    fi
}

# Load the shared environment first
SHARED_ENV_FILE="$PROJECT_ROOT/.env.shared"
if ! load_env_file "$SHARED_ENV_FILE"; then
    echo "Error: Shared environment file not found!"
    exit 1
fi

# Load environment-specific overrides
ENV_FILE="$PROJECT_ROOT/.env.$ENV"
load_env_file "$ENV_FILE"

# Load local overrides if they exist (for local development)
LOCAL_ENV_FILE="$PROJECT_ROOT/.env.local"
if [ -f "$LOCAL_ENV_FILE" ]; then
    load_env_file "$LOCAL_ENV_FILE"
fi

# Set some common variables that might be derived from .env variables
export APP_PATH="${APP_PATH:-$PROJECT_ROOT}"
export BACKUP_PATH="${BACKUP_PATH:-$APP_PATH/backups}"
export LOG_PATH="${LOG_PATH:-$APP_PATH/logs}"
export DB_PATH="${DB_PATH:-$APP_PATH/gallformers.sqlite}"

# Create required directories if they don't exist
mkdir -p "$APP_PATH"
mkdir -p "$BACKUP_PATH"
mkdir -p "$LOG_PATH"

# Ensure proper permissions
chmod 755 "$APP_PATH"
chmod 755 "$BACKUP_PATH"
chmod 755 "$LOG_PATH"

# Validate required variables
required_vars=(
    "APP_PATH"
    "BACKUP_PATH"
    "LOG_PATH"
    "DB_PATH"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set!"
        exit 1
    fi
done 