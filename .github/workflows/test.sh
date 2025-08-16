#!/bin/bash

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Copy the project files
cp -r . "$TEMP_DIR"
cd "$TEMP_DIR"

# Run act with proper configuration
act -P ubuntu-latest=catthehacker/ubuntu:act-latest \
    -W .github/workflows/CI.yml \
    --container-architecture linux/amd64 \
    --env NODE_VERSION=20 \
    --env CI=true

# Clean up
cd -
rm -rf "$TEMP_DIR" 