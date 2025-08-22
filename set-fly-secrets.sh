#!/bin/bash

# Script to read .env.local file and set secrets in Fly.io
# Usage: ./set-fly-secrets.sh

set -e  # Exit on any error

ENV_FILE=".env.local"

# Check if .env.local file exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE file not found!"
    echo "Please create a $ENV_FILE file with your secrets in the format:"
    echo "KEY_NAME=SECRET_VALUE"
    exit 1
fi

echo "Reading secrets from $ENV_FILE..."
echo "Setting secrets in Fly.io..."

# Read the .env.local file line by line
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines
    if [[ -z "$line" ]]; then
        continue
    fi
    
    # Skip comment lines (lines starting with #)
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Check if line contains an equals sign
    if [[ "$line" == *"="* ]]; then
        # Extract key and value
        KEY=$(echo "$line" | cut -d'=' -f1 | xargs)  # xargs trims whitespace
        VALUE=$(echo "$line" | cut -d'=' -f2- | xargs)  # f2- gets everything after first =
        
        # Skip if key or value is empty
        if [[ -z "$KEY" || -z "$VALUE" ]]; then
            echo "Skipping invalid line: $line"
            continue
        fi
        
        # Remove quotes from value if present
        VALUE=$(echo "$VALUE" | sed 's/^"//; s/"$//')
        VALUE=$(echo "$VALUE" | sed "s/^'//; s/'$//")
        
        echo "Setting secret: $KEY"
        
        # Set the secret in Fly.io
        if fly secrets set "$KEY=$VALUE" --stage; then
            echo "✓ Successfully set $KEY"
        else
            echo "✗ Failed to set $KEY"
            exit 1
        fi
    else
        echo "Skipping invalid line (no = found): $line"
    fi
done < "$ENV_FILE"

echo ""
echo "✅ All secrets have been set successfully!"
echo ""
echo "You can verify the secrets with:"
echo "fly secrets list"
