# Deployment Re-architecture Plan: Docker to PM2-based Deployment

## Overview
This document outlines the plan to migrate from Docker-based deployment to a PM2-based deployment system with enhanced backup and monitoring capabilities.

## Phase 1: Preparation and Documentation

1. **Create Migration Documentation**
   - **Document Current Deployment Process**:
     - **Development Setup**: The development environment is set up using Node.js, Yarn, and Prisma. Instructions are provided in the `README.md` for running the development server and building the production version.
     - **Docker-Based Deployment**: The `Makefile` contains targets for building and running Docker containers for both local and production environments. It includes commands for setting up the environment, building Docker images, and running containers.
     - **Server Deployment**: The `runbooks/deploy.md` outlines the steps for deploying the application to a production server. This involves building the Docker image locally, transferring it to the server, and running it in a Docker container. The server is put into maintenance mode during deployment.
     - **Database Management**: The `README.md` and `runbooks/deploy.md` describe the process for managing database schema changes using migration scripts. The database is backed up before applying changes, and the updated schema is committed to the repository.
     - **Backup Strategy**: The `README.md` mentions a backup strategy, with more details available in the `scripts/README.md`.
     - **Monitoring and Alerts**: The `README.md` describes a simple monitoring setup using AWS Lambda and Digital Ocean alarms to send alerts via email.
   - **Document All Environment Variables**:
     - `NODE_ENV`: Used to determine the environment (e.g., development, production).
     - `DATABASE_URL`: URL for the database connection.
     - `AWS_REGION`: AWS region for services.
     - `AWS_ACCESS_KEY_ID`: AWS access key ID.
     - `AWS_SECRET_ACCESS_KEY`: AWS secret access key.
     - `S3_BUCKET`: Name of the S3 bucket.
     - `BUCKET_NAME`: Another reference to an S3 bucket, possibly for a different purpose.
     - `AUTH0_CLIENT_ID`: Client ID for Auth0.
     - `AUTH0_SECRET`: Secret for Auth0.
     - `AUTH0_DOMAIN`: Domain for Auth0.
     - `NEXTAUTH_SECRET`: Secret for NextAuth.
     - `BUILD_ID`: Identifier for the build.
   - **Create Rollback Plan**:
     - **DNS Reversion**: Revert DNS settings to point back to the DigitalOcean deployment if any issues arise with the Fly.io deployment.
     - **Data Consistency**: Ensure that any data changes made during the Fly.io deployment are synchronized back to the DigitalOcean environment if needed.
     - **Monitoring and Alerts**: Keep monitoring and alerting systems active on both environments during the transition to quickly identify and respond to any issues.
     - **Communication**: Inform stakeholders about the potential for a rollback and ensure that the team is prepared to execute it quickly if necessary.
   - **Document SQLite Database Location**:
     - **Local Development**: The SQLite database is located at `./gallformers.sqlite`.
     - **Current Server (DigitalOcean)**: The database is located at `/mnt/gallformers_data/prisma/gallformers.sqlite`. 
   - **Document Current Manual Backup Process**:
     - **Database Location**: The SQLite database is stored on an attached volume on the DigitalOcean server.
     - **Manual Backup**:
       - Periodically, the database is manually downloaded via SSH to a local machine.
       - The downloaded database copy is then committed to the git repository whenever updates are made.

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
   - **Auth0 Configuration and Environment Variables**:
      - **Environment Variables**
         - `AUTH0_CLIENT_ID`: Client ID for Auth0.
         - `AUTH0_SECRET`: Secret for Auth0.
         - `AUTH0_DOMAIN`: Domain for Auth0.
         - `AUTH0_BASE_URL`: Base URL for Auth0 (used in some test scripts).
      - These variables are used in the `pages/api/auth/[...nextauth].ts` file to configure Auth0 authentication.
      - Missing Auth0 environment variables can lead to backup failures, as indicated in the `logs/ERROR.log` file.
   - **AWS S3 Image Storage Configuration**:
     - **Environment Variables**:
       - `AWS_REGION`: Specifies the AWS region for services.
       - `AWS_ACCESS_KEY_ID`: Access key ID for AWS.
       - `AWS_SECRET_ACCESS_KEY`: Secret access key for AWS.
       - `S3_PUT_AWS_ACCESS_KEY_ID`: Access key ID specifically for S3 PUT operations.
       - `S3_PUT_AWS_SECRET_ACCESS_KEY`: Secret access key specifically for S3 PUT operations.
     - These variables are used in the `libs/images/images.ts` file to configure AWS S3 access for image storage.
     - Missing AWS environment variables can lead to backup failures, as indicated in the `logs/ERROR.log` file.
   - **SSL Certificate Renewal Process**:
     - **Certbot Usage**: Certbot is used for managing SSL certificates, as indicated by the installation and usage commands found in the `Makefile`.
     - **Renewal Hook**: A renewal hook is set up to restart Nginx after certificate renewal. This is configured in the `/etc/letsencrypt/renewal-hooks/post/01-restart-nginx` script.
     - **Automation**: The `Makefile` includes commands to install Certbot and link it for use with Nginx, suggesting an automated setup for certificate management.
   - **Existing Monitoring Systems**:
     - **AWS Lambda**: A simple down detector is implemented as an AWS Lambda function. It checks the site every 2 minutes to see if it responds with an HTTP 200 response. If the site responds negatively more than once in the span of 5 minutes, an alert is sent out via AWS SQS to AWS SNS/CloudWatch. The CloudWatch alarm triggers another Lambda function that uses SNS to send an email to Jeff.
     - **DigitalOcean Alarms**: Several alarms are configured on the DigitalOcean Droplet that hosts the server. These are resource utilization alarms and will send emails to Jeff.
   - **Database Migration System and Process**:
     - **Migration Scripts**: Located in the `migrations` directory, these scripts manage database schema changes.
     - **Migration Process**: The `README.md` and `runbooks/deploy.md` describe the process for managing database schema changes using migration scripts. The process involves creating a new migration script, adding schema changes, and executing the migration using `yarn migrate`.
     - **Prisma Integration**: The `prisma/schema.prisma` file is used to define the database schema, and changes are reflected in the migration scripts.

4. **Development Environment Setup**
   - **Node.js and Yarn**:
     - **Node.js**: The required version is Node.js 20.x.
     - **Yarn**: Corepack is enabled to set up Yarn.
   - **Development Dependencies**:
     - The `yarn.lock` file contains a comprehensive list of dependencies.

5. **Domain and SSL Configuration**
   - **Domain Registration**:
     - The domains `gallformers.org` and `gallformers.com` are registered using Namecheap and are currently in Jeff's personal account.
   - **DNS Configuration**:
     - The domains `gallformers.org` and `gallformers.com` both resolve to the IP address `157.245.243.86`.
     - **A Record**: `gallformers.org` resolves to `157.245.243.86`.
     - **CNAME Record**: No CNAME records found.
     - **MX Record**: No MX records found.
     - **TXT Record**: No TXT records found.
     - **SOA Record**: Primary name server is `ns1.digitalocean.com`, with `hostmaster.gallformers.org` as the responsible party.
   - **Nginx Configuration**:
     - **Installation**: Nginx is installed using the command `apt-get install nginx-full`.
     - **Configuration**: The Nginx configuration file is linked to `/etc/nginx/conf.d/nginx.conf`.
     - **Certbot Integration**: Certbot is used to manage SSL certificates and automatically update the Nginx configuration with the command `certbot --nginx`.
     - **Renewal Hook**: A renewal hook is set up to restart Nginx after certificate renewal. This is configured in the `/etc/letsencrypt/renewal-hooks/post/01-restart-nginx` script.
   - **SSL Certificate Setup**:
     - Certbot is used for managing SSL certificates, with a renewal hook set up to restart Nginx after certificate renewal. This is configured in the `/etc/letsencrypt/renewal-hooks/post/01-restart-nginx` script.
   - **SSL Certificate Renewal**:
     - The renewal process is automated using Certbot, as indicated by the commands in the `Makefile`.

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

3. **Create Environment Loading Script** (`scripts/config/env.ts`) ✅
   - Created with specified settings
   - Loads variables from `.env.shared` first
   - Then loads environment-specific `.env.$ENV` file
   - Finally loads `.env.local` if it exists (for local overrides)
   - Environment-specific values take precedence over shared values
   - Validates required variables
   - Sets up required directories and permissions

4. **Create Enhanced Backup Script** (`scripts/tasks/backup.ts`) ✅
   - Created with specified settings
   - Uses TypeScript for type safety and better maintainability
   - Implements AWS S3 integration for backup storage
   - Includes error handling and logging
   - Returns structured backup results

5. **Create Backup Monitoring Script** (`scripts/tasks/monitor.ts`) ✅
   - Created with specified settings
   - Uses TypeScript for type safety and better maintainability
   - Implements monitoring logic with proper error handling
   - Includes structured logging

6. **Create Backup Restoration Script** (`scripts/tasks/restore.ts`) ✅
   - Created with specified settings
   - Uses TypeScript for type safety and better maintainability
   - Implements AWS S3 integration for backup retrieval
   - Includes database verification
   - Returns structured restore results

7. **Add AWS Configuration** (`scripts/config/aws.ts`) ✅
   - Created with specified settings
   - Uses TypeScript for type safety and better maintainability
   - Implements AWS S3 client configuration
   - Includes proper error handling

8. **Create Migration Helper Script** (`scripts/tasks/setup.ts`) ✅
   - Created with specified settings
   - Uses TypeScript for type safety and better maintainability
   - Implements environment setup and verification
   - Returns structured setup results

9. **Create Integration Verification Script** (`scripts/utils/logger.ts`) ✅
   - Created with specified settings
   - Uses TypeScript for type safety and better maintainability
   - Implements structured logging
   - Includes error handling and log rotation

10. **Create Development Environment Setup Script** (`scripts/tasks/setup.ts`) ✅
    - Created with specified settings
    - Uses TypeScript for type safety and better maintainability
    - Implements development environment setup
    - Returns structured setup results

11. **Create Prisma Setup Script** (`scripts/tasks/setup.ts`) ✅
    - Created with specified settings
    - Uses TypeScript for type safety and better maintainability
    - Implements Prisma setup and verification
    - Returns structured setup results
    - ℹ️ INFO: This script is used by both the development setup and migration processes

## Phase 3: Adapt Deployment for Fly.io with SQLite

1. **Install Flyctl**: ✅
   - Install the Fly.io command-line tool (`flyctl`) to manage deployments.
   - Follow the installation instructions for your operating system from the [Fly.io documentation](https://fly.io/docs/getting-started/).

2. **Initialize Fly.io Application**: ✅
   - Use `fly launch` to set up a new application on Fly.io.
   - Configure the `fly.toml` file with your app's settings, including environment variables and services.

3. **Configure SQLite Database**: ✅
   - Use Fly Volumes to create persistent storage for your SQLite database file.
   - Ensure your application is configured to access the database file from the Fly Volume.

4. **Set Up SSL Management and DNS Cutover**:
   - **SSL Management**:
     - Use Fly.io's built-in SSL management to handle SSL certificates.
     - Ensure your domain is correctly configured to use Fly.io's SSL features.
     - Verify SSL certificate installation and test SSL configuration using tools like SSL Labs.
     - Monitor SSL certificate renewal to ensure there are no issues.
   - **DNS Cutover Plan**:
     - **Preparation**:
       - Ensure all application configurations are complete and tested on Fly.io.
       - Verify that the application is fully functional and accessible via HTTPS.
     - **DNS Configuration**:
       - Update DNS records to point to Fly.io's servers. This typically involves changing the A record to Fly.io's IP address.
       - Set a low TTL (Time to Live) on DNS records to allow for quick propagation.
     - **Cutover Execution**:
       - Perform the DNS cutover during a low-traffic period to minimize impact.
       - Monitor the application closely after the cutover to ensure everything is functioning correctly.
     - **Post-Cutover Verification**:
       - Verify that the application is accessible via the new DNS settings.
       - Check SSL certificate status and ensure HTTPS is enforced.
       - Monitor application performance and address any issues promptly.

5. **Plan for Monitoring and Logging**:
   - Utilize Fly.io's monitoring tools or integrate with external services for comprehensive monitoring.
   - Set up logging to capture application logs and errors.

6. **Adapt Backup Strategy**:
   - Use external services or Fly.io's scheduling capabilities to manage database backups.
   - Ensure backups are stored securely and can be restored if needed.

7. **Testing and Verification**:
   - Deploy your application to Fly.io and verify that it functions correctly with SQLite.
   - Test database access, SSL configuration, and monitoring/logging setups.

8. **Documentation**:
   - Update your deployment documentation to reflect the changes made for Fly.io.
   - Include instructions for managing the SQLite database, SSL, and monitoring on Fly.io.

## Phase 4: Migration Process

1. **Pre-Migration Steps**:
   ```bash
   # 1. Create initial backup
   yarn backup

   # 2. Verify backup
   yarn restore --verify $(date +%Y%m%d_%H%M%S)

   # 3. Stop current Docker container
   docker-compose down
   ```

2. **Migration Steps**:
   ```bash
   # 1. Deploy new version
   yarn setup

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
   - Run integration verification script
   ```bash
   yarn setup --verify-integrations
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

