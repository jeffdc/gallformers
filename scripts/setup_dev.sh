#!/bin/bash
set -e

# Variables
APP_PATH="/path/to/your/app"
EMAIL_TO="your-email@example.com"

# Function to send email notification
send_notification() {
    local message="$1"
    local status="$2"
    echo "[Gallformers Dev Setup] $message - Status: $status" | mail -s "Gallformers Dev Setup Notification" "$EMAIL_TO"
}

# Check if running on Mac
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Install Homebrew if not present
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Install nvm
    if ! command -v nvm &> /dev/null; then
        echo "Installing nvm..."
        brew install nvm
    fi
else
    # Install nvm on Linux
    if ! command -v nvm &> /dev/null; then
        echo "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    fi
fi

# Source nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install Node.js 20
echo "Installing Node.js 20..."
nvm install 20
nvm use 20

# Enable corepack
echo "Enabling corepack..."
corepack enable

# Setup yarn berry
echo "Setting up yarn berry..."
cd "$APP_PATH"
yarn set version berry

# Install dependencies
echo "Installing dependencies..."
yarn install

# Install development dependencies
echo "Installing development dependencies..."
yarn add -D better-sqlite3@^7.1.1 better-sqlite3-helper@^3.1.1 sqlite@^4.0.15

# Generate Prisma client
echo "Generating Prisma client..."
yarn generate

# Remove development dependencies
echo "Removing development dependencies..."
yarn remove better-sqlite3 better-sqlite3-helper sqlite

# Verify setup
if [ -d "node_modules/.prisma" ] && [ -f "yarn.lock" ]; then
    echo "Development environment setup completed successfully"
    send_notification "Development environment setup completed successfully" "SUCCESS"
else
    echo "Development environment setup failed"
    send_notification "Development environment setup failed" "ERROR"
    exit 1
fi 