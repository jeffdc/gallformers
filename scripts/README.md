# Gallformers Scripts Documentation

This directory contains various TypeScript scripts for managing the Gallformers application, including development setup, backups, database management, and deployment automation.

## Prerequisites

Before using these scripts, ensure you have:

1. Node.js 20 or higher installed
2. A properly configured `.env` file in the project root
3. Required system dependencies (as specified in `.env.shared`)
4. Appropriate AWS credentials for S3 operations
5. Email configuration for notifications

## Installation

The scripts are part of the main project and use the project's dependencies. No additional installation is needed beyond the main project setup:

```bash
yarn install
```

## Script Overview

### Development Setup

- `setup`: Sets up the development environment
  - Installs Node.js 20 via nvm
  - Configures yarn berry
  - Installs dependencies
  - Generates Prisma client
  - Sends email notification on completion

### Database Management

- `migrate`: Runs database migrations
  - Executes Prisma migrations
  - Verifies migration success

- `restore`: Restores database from backup
  - Downloads latest backup from S3
  - Restores to specified location
  - Verifies restoration

### Backup Management

- `backup`: Creates and manages database backups
  - Performs database maintenance (VACUUM, ANALYZE)
  - Creates timestamped backup
  - Compresses backup
  - Uploads to S3
  - Cleans up old backups based on retention policy
  - Sends email notification

## Running Scripts

All scripts are written in TypeScript and can be run from the project root using yarn commands:

```bash
# Development mode (using ts-node)
yarn scripts:dev

# Production mode (requires build first)
yarn build:scripts
yarn scripts:start

# Individual commands
yarn scripts:backup
yarn scripts:restore
yarn scripts:setup
```

## Testing

The scripts include a test suite to verify functionality:

1. Run tests:
   ```bash
   yarn test
   ```

2. Test environment setup:
   - Tests use a separate test environment configuration
   - Test data is stored in a temporary directory
   - AWS operations are mocked during tests

## Automated Execution

### Setting up Cron Jobs

To automate script execution, set up the following cron jobs on your DigitalOcean Droplet:

```bash
# Daily backup at 2 AM
0 2 * * * cd /path/to/project && yarn scripts:backup >> /path/to/logs/backup.log 2>&1

# Database maintenance weekly (Sunday at 1 AM)
0 1 * * 0 cd /path/to/project && yarn migrate >> /path/to/logs/migrate.log 2>&1
```

To set up these cron jobs:

1. Open the crontab editor:
   ```bash
   crontab -e
   ```

2. Add the above entries, adjusting paths as needed

3. Verify the cron jobs:
   ```bash
   crontab -l
   ```

### Log Management

Logs are automatically rotated based on the configuration in `.env.shared`:
- Log retention: 14 days (based on configuration)
- Log rotation configuration: `/etc/logrotate.d/gallformers`

## Troubleshooting

### Common Issues

1. **Build Issues**
   - Ensure TypeScript is properly installed
   - Check for type errors: `yarn build:scripts`
   - Verify Node.js version compatibility

2. **Script Execution Issues**
   - Check Node.js version: `node --version`
   - Verify environment variables are loaded
   - Check AWS credentials and permissions
   - Ensure sufficient disk space for operations

3. **Database Migration Issues**
   - Ensure Prisma schema is up to date
   - Check database file permissions
   - Verify SQLite is properly installed

### Monitoring and Alerts

- Email notifications are sent for:
  - Backup completion/failure
  - Development environment setup status
  - Integration verification results
- Check log files in `LOG_PATH` for detailed error information

## Security Considerations

1. **Environment Variables**
   - Never commit `.env` files with secrets in them to version control
   - Use appropriate file permissions (600) for sensitive files
   - Regularly rotate AWS credentials

2. **Backup Security**
   - Backups are stored with public-read ACL in S3
   - Local backups are retained for 7 days
   - S3 backups are retained for 100 days

## Project Structure

```
scripts/
├── config/         # Configuration files
├── tasks/          # Task implementations
├── tests/          # Test files
├── utils/          # Utility functions
├── index.ts        # Main entry point
└── tsconfig.json   # TypeScript configuration
```

## TODO

- [ ] Implement DigitalOcean-specific monitoring
- [ ] Set up alerting thresholds
- [ ] Add backup verification process
- [ ] Implement automated backup testing
- [ ] Add more comprehensive test coverage 