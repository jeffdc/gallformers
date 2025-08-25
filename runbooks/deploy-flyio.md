# Gallformers Fly.io Deployment Runbook

## Overview

Gallformers uses a modern deployment architecture with:
- **GitHub Actions** for CI/CD automation
- **Fly.io** for hosting (staging & production)
- **Python scripts** for environment and database management
- **Simplified Makefile** for local development

## Deployment Scenarios

### 1. Local Development (`make dev`)
- Uses `yarn dev` with hot reload
- Environment: `env/.env.shared` + `env/.env.development` + `env/.env.local`
- Database: Local SQLite file (`./prisma/gallformers.sqlite`)

### 2. Local Docker Testing (`make local-docker`)
- Production-like container running locally
- Environment: `env/.env.shared` + `env/.env.local-docker` + `env/.env.local`
- Database: Local volume mounted at `/data/gallformers.sqlite`

### 3. Staging Deployment (Automated)
- **Trigger**: PR opened/updated against `main` branch
- **URL**: https://gallformers-staging.fly.dev
- **Database**: Fresh copy of production data on each deployment
- **GitHub Action**: `.github/workflows/deploy-staging.yml`

### 4. Production Deployment (Manual)
- **Trigger**: Manual workflow dispatch
- **URL**: https://www.gallformers.org
- **Database**: Persistent production data with scheduled backups
- **GitHub Action**: `.github/workflows/deploy-production.yml`

## Environment Management

All environment configuration is in the `env/` directory:

- `env/.env.shared` - Common settings across all environments
- `env/.env.development` - Local development settings
- `env/.env.local-docker` - Local Docker settings
- `env/.env.staging` - Staging environment settings (Fly.io)
- `env/.env.production` - Production environment settings (Fly.io)
- `env/.env.local` - Local secrets (gitignored)

The Python environment loader (`scripts/config/env.py`) automatically loads the appropriate files based on `NODE_ENV`.

## Database Management

### Automated Backups
- **Production**: Daily backups at 2 AM UTC via GitHub Actions
- **Storage**: AWS S3 (`S3_BUCKET` environment variable)
- **Script**: `scripts/tasks/backup.py`

### Staging Database Refresh
- **When**: Every staging deployment
- **Process**: Downloads latest production backup and restores it
- **Script**: `scripts/tasks/refresh_staging.py`

### Manual Operations
```bash
# Create backup
make backup

# Restore from S3 backup
make restore S3_KEY=backups/gallformers_2025-01-01.zip

# Set secrets for staging
make set-secrets-staging

# Set secrets for production
make set-secrets-prod
```

## Deployment Workflows

### Staging Deployment Process
1. PR opened/updated against `main`
2. GitHub Actions builds and deploys to `gallformers-staging`
3. Installs Python dependencies on staging app
4. Downloads and restores latest production backup
5. Comments on PR with staging URL

### Production Deployment Process
1. Manual trigger via GitHub Actions UI
2. Requires typing "PROMOTE" to confirm
3. Deploys to `gallformers-prod`
4. Scales down staging to save resources
5. Sends Slack notification

## Local Development Commands

```bash
# Start development server
make dev

# Build and run production-like container locally
make local-docker

# View local Docker logs
make local-docker-logs

# Stop local Docker container
make local-docker-stop

# See all available commands
make help
```

## Secret Management

Secrets are managed via Python scripts instead of shell scripts:

```bash
# Set secrets for staging (reads from env/ directory)
cd scripts && NODE_ENV=production python main.py set-secrets gallformers-staging

# Set secrets for production
cd scripts && NODE_ENV=production python main.py set-secrets gallformers-prod
```

## Required Setup

### Prerequisites
1. Fly.io CLI installed and authenticated
2. Python 3.8+ with dependencies (`pip install -r scripts/requirements.txt`)
3. Environment files configured in `env/` directory
4. GitHub repository secrets configured:
   - `FLY_API_TOKEN`
   - Any Slack webhook tokens for notifications

### Initial Fly.io Setup
1. Create apps: `gallformers-prod` and `gallformers-staging`
2. Create volumes: `gallformers_data` and `gallformers_staging_data`
3. Set secrets using the Python scripts
4. Deploy using GitHub Actions

## Troubleshooting

### Common Issues

**Staging deployment fails with environment errors:**
- Check that all required env files exist in `env/` directory
- Verify `env/.env.local` contains all required secrets
- Check Python script logs in GitHub Actions

**Database refresh fails:**
- Verify S3 credentials are set correctly
- Check that production backups exist in S3
- Ensure staging app has Python dependencies installed

**Local Docker fails to start:**
- Ensure `env/.env.local-docker` exists
- Check that `data/` directory is created locally
- Verify no port conflicts on 3000

### Recovery Procedures

**Rollback production deployment:**
1. Use Fly.io dashboard or CLI to rollback to previous release
2. Check database integrity
3. Monitor application health

**Restore production from backup:**
```bash
cd scripts
python main.py restore <s3-backup-key>
```

## Migration Notes

This deployment system replaces the legacy SSH-based deployment documented in `runbooks/deploy.md`. Key improvements:

- ✅ Automated CI/CD with GitHub Actions
- ✅ Containerized deployment with Fly.io
- ✅ Consolidated environment management
- ✅ Automated database backups and staging refresh
- ✅ No more manual SSH access required
- ✅ Staging environment with production data