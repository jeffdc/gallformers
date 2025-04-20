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

3. **Document Current Integrations**
   - Auth0 configuration and environment variables
   - AWS S3 image storage configuration
   - SSL certificate renewal process
   - Existing monitoring systems (Lambda, DO alarms, Slack)
   - Database migration system and process
   - Current backup strategy and requirements

4. **Development Environment Setup**
   - Document Node.js version requirements (20.x)
   - Document yarn version requirements (berry)
   - Document required development dependencies:
     ```json
     {
       "better-sqlite3": "^7.1.1",
       "better-sqlite3-helper": "^3.1.1",
       "sqlite": "^4.0.15"
     }
     ```
   - Document nvm setup process
   - Document corepack enable process
   - Document yarn berry setup process

5. **Domain and SSL Configuration**
   - Document domain registration (namecheap)
   - Document SSL certificate setup (Let's Encrypt)
   - Document domain DNS configuration
   - Document SSL certificate renewal process (3-month cycle)
   - Document domain routing configuration:
     - Primary domain: gallformers.org
     - Secondary domain: gallformers.com
     - DNS records:
       - A record for @ pointing to server IP
       - A record for www pointing to server IP
       - CNAME record for www.gallformers.com pointing to www.gallformers.org
     - SSL certificate configuration:
       - Primary certificate for gallformers.org and www.gallformers.org
       - Secondary certificate for gallformers.com and www.gallformers.com
     - Nginx configuration for both domains
     - HTTPS redirect configuration
     - SSL certificate renewal hooks

## Phase 2: Create New Deployment Infrastructure

1. **Create PM2 Configuration** (`ecosystem.config.js`) ✅
   - Created with specified settings
   - ✅ Update ESLint configuration to include this file in TypeScript configuration

2. **Create Environment Configuration Files** ✅
   - Created `.env.shared` with common configuration
   - Created `.env.development.example` with development-specific settings
   - Created `.env.production.example` with production-specific settings
   - Created `.env.local.example` with sensitive information template
   - Added `.env.local` to `.gitignore`

3. **Create Environment Loading Script** (`scripts/load_env.sh`) ✅
   - Created with specified settings
   - Made executable
   - Loads variables from `.env.shared` first
   - Then loads environment-specific `.env.$ENV` file
   - Finally loads `.env.local` if it exists (for local overrides)
   - Environment-specific values take precedence over shared values
   - Validates required variables
   - Sets up required directories and permissions

4. **Create Enhanced Backup Script** (`scripts/backup.sh`) ✅
   - Created with specified settings
   - Made executable
   - Uses variables from .env files via load_env.sh

5. **Create Backup Monitoring Script** (`scripts/monitor_backups.sh`) ✅
   - Created with specified settings
   - Made executable
   - Uses variables from .env files via load_env.sh

6. **Create Backup Restoration Script** (`scripts/restore.sh`) ✅
   - Created with specified settings
   - Made executable
   - Uses variables from .env files via load_env.sh

7. **Add AWS Configuration** (`scripts/setup_aws.sh`) ✅
   - Created with specified settings
   - Made executable
   - Uses variables from .env files via load_env.sh

8. **Create Migration Helper Script** (`scripts/migrate.sh`) ✅
   - Created with specified settings
   - Made executable
   - Uses variables from .env files via load_env.sh

9. **Create Integration Verification Script** (`scripts/verify_integrations.sh`) ✅
   - Created with specified settings
   - Made executable
   - Uses variables from .env files via load_env.sh

10. **Create Development Environment Setup Script** (`scripts/setup_dev.sh`) ✅
    - Created with specified settings
    - Made executable
    - Uses variables from .env files via load_env.sh

11. **Create Prisma Setup Script** (`scripts/setup_prisma.sh`) ✅
    - Created with specified settings
    - Made executable
    - Uses variables from .env files via load_env.sh
    - ℹ️ INFO: This script is used by both the development setup and migration processes

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

3. **Setup SSL Certificate Renewal**:
```bash
# Create certbot renewal hook
sudo tee /etc/letsencrypt/renewal-hooks/post/01-restart-nginx << EOF
#!/bin/bash
systemctl restart nginx
EOF

sudo chmod +x /etc/letsencrypt/renewal-hooks/post/01-restart-nginx
```

4. **Setup Monitoring Integration**:
```bash
# Create monitoring configuration
sudo tee /etc/pm2/conf.d/monitoring.json << EOF
{
  "apps": [{
    "name": "gallformers",
    "script": "yarn",
    "args": "start",
    "env": {
      "NODE_ENV": "production"
    },
    "merge_logs": true,
    "log_date_format": "YYYY-MM-DD HH:mm:ss",
    "error_file": "logs/error.log",
    "out_file": "logs/out.log",
    "max_memory_restart": "1G",
    "restart_delay": 4000,
    "max_restarts": 10,
    "min_uptime": "5s",
    "listen_timeout": 8000,
    "kill_timeout": 2000,
    "wait_ready": true,
    "listen_timeout": 10000
  }]
}
EOF

# Add PM2 monitoring to Digital Ocean alarms
# Note: This will be configured through the Digital Ocean dashboard
# - CPU Usage
# - Memory Usage
# - Disk Usage
# - Process Status
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

3. **Verify Integrations**:
   - Test Auth0 login flow
   - Verify image uploads to S3
   - Check SSL certificate renewal process
   - Verify all monitoring systems are working
   - Test Slack notifications
   - Run integration verification script
   ```bash
   ./scripts/verify_integrations.sh
   ```

4. **Domain and SSL Verification**:
   - Verify domain DNS configuration
   - Verify SSL certificate installation
   - Test SSL certificate renewal process
   - Verify domain routing (gallformers.org and gallformers.com)
   - Test HTTPS redirects
   - Verify SSL certificate auto-renewal daemon

## Phase 5: Cleanup

1. **Remove Docker Files**:
   ```bash
   # Remove Docker-related files
   rm Dockerfile docker-compose.yml .dockerignore
   
   # Remove Docker-related scripts from package.json
   ```

2. **Update Documentation**:
   - Document Auth0 configuration and environment variables
   - Document AWS S3 setup for both images and backups
   - Document SSL certificate renewal process
   - Document monitoring system integration
   - Document database migration process
   - Update README.md with new deployment process
   - Document PM2 commands and maintenance procedures
   - Document backup and restore procedures
   - Document database migration procedures
   - Document development environment setup process
   - Document domain configuration process:
     - Domain registration and DNS setup
     - SSL certificate installation and renewal
     - Nginx configuration for multiple domains
     - HTTPS redirect configuration
     - SSL certificate renewal hooks
     - Domain routing and fallback configuration

## Pending Questions

1. What email address should be used for backup notifications? 