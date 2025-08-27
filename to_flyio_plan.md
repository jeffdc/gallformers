# Gallformers.org Fly.io Migration Plan

## Current State Analysis

Based on the repository analysis, gallformers.org currently runs on:
- **Platform**: Digital Ocean Droplet
- **Tech Stack**: Next.js, SQLite database, Prisma ORM
- **Image Storage**: AWS S3
- **Auth**: Auth0
- **SSL**: Let's Encrypt with auto-renewal
- **Monitoring**: AWS Lambda health checks + Slack notifications
- **Deployment**: Manual deployment to DO Droplet

## Migration Overview

The plan implements a **blue-green deployment strategy** using Fly.io's built-in capabilities with GitHub Actions for CI/CD automation.

## Phase 1: Initial Setup & Configuration

### 1.1 Fly.io Application Setup

1. **Install Fly CLI** and initialize the application:
   ```bash
   fly auth login
   fly launch --name gallformers-prod --region iad --no-deploy
   ```

2. **Create staging application**:
   ```bash
   fly apps create gallformers-staging --org personal
   ```

### 1.2 Database Migration Strategy

Since the current setup uses SQLite on a mounted volume, we have two options:

**Option A: Continue with SQLite on Fly Volumes**
- Use Fly.io persistent volumes for SQLite
- Simpler migration, minimal code changes
- Good for current scale

**Option B: Migrate to PostgreSQL**
- Use Fly PostgreSQL for better scalability
- Requires database migration and schema updates
- Better long-term solution

**Recommendation**: Start with Option A for faster migration, plan Option B for future.

### 1.3 Configuration Files

Create the following configuration files:

#### `fly.toml` (Production)
```toml
app = "gallformers-prod"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[env]
  NODE_ENV = "production"
  DATABASE_URL = "/data/production/gallformers.db"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

[[mounts]]
  source = "gallformers_data"
  destination = "/data"

[vm]
  memory = "2gb"
  cpu_kind = "performance"
  cpus = 2

[[services]]
  http_checks = []
  internal_port = 3000
  processes = ["app"]
  protocol = "tcp"
  script_checks = []

  [services.concurrency]
    hard_limit = 25
    soft_limit = 20
    type = "connections"

  [[services.ports]]
    force_https = true
    handlers = ["http"]
    port = 80

  [[services.ports]]
    handlers = ["tls", "http"]
    port = 443

  [[services.tcp_checks]]
    grace_period = "10s"
    interval = "15s"
    restart_limit = 0
    timeout = "2s"
```

#### `fly.staging.toml` (Staging)
```toml
app = "gallformers-staging"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[env]
  NODE_ENV = "production"
  DATABASE_URL = "/data/staging/gallformers.db"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0

[[mounts]]
  source = "gallformers_data"
  destination = "/data"

[vm]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1
```

## Phase 2: GitHub Actions CI/CD Pipeline

### 2.1 Secrets Configuration

Add these secrets to your GitHub repository:

```
FLY_API_TOKEN          # Fly.io API token
AUTH0_SECRET           # Auth0 configuration
AUTH0_BASE_URL         # Auth0 base URL
AUTH0_ISSUER_BASE_URL  # Auth0 issuer URL
AUTH0_CLIENT_ID        # Auth0 client ID
AUTH0_CLIENT_SECRET    # Auth0 client secret
AWS_ACCESS_KEY_ID      # For S3 access
AWS_SECRET_ACCESS_KEY  # For S3 access
```

### 2.2 Workflow Files

#### `.github/workflows/deploy-staging.yml`
```yaml
name: Deploy to Staging

on:
  pull_request:
    types: [opened, synchronize, reopened]
    branches: [main]

env:
  FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'yarn'
      
      - name: Install dependencies
        run: |
          corepack enable
          yarn install
      
      - name: Generate Prisma client
        run: npx prisma generate
      
      - name: Run tests
        run: yarn test
      
      - name: Build application
        run: yarn build

  deploy-staging:
    needs: test
    runs-on: ubuntu-latest
    outputs:
      staging-url: ${{ steps.deploy.outputs.staging-url }}
    steps:
      - uses: actions/checkout@v4
      
      - uses: superfly/flyctl-actions/setup-flyctl@master
      
      - name: Deploy to staging
        id: deploy
        run: |
          flyctl deploy --config fly.staging.toml --app gallformers-staging
          
          # Ensure staging database directory exists and initialize if needed
          flyctl ssh console --app gallformers-staging --command "mkdir -p /data/staging"
          
          # Copy production DB to staging for testing (optional, or use test data)
          flyctl ssh console --app gallformers-staging --command "
            if [ ! -f /data/staging/gallformers.db ] && [ -f /data/production/gallformers.db ]; then
              cp /data/production/gallformers.db /data/staging/gallformers.db
              echo 'Copied production DB to staging for testing'
            fi
          "
          
          STAGING_URL="https://gallformers-staging.fly.dev"
          echo "staging-url=$STAGING_URL" >> $GITHUB_OUTPUT
          
          # Add comment to PR with staging URL
          gh pr comment ${{ github.event.number }} --body "🚀 **Staging deployment ready!**
          
          **Staging URL**: $STAGING_URL
          **Commit**: ${{ github.event.pull_request.head.sha }}
          **Database**: Isolated staging database in \`/data/staging/\`
          
          Test your changes and then promote to production when ready."
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  notify-slack:
    needs: deploy-staging
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Notify Slack
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          channel: '#site-monitoring'
          text: |
            Staging deployment ${{ job.status }}!
            Staging URL: ${{ needs.deploy-staging.outputs.staging-url }}
            PR: ${{ github.event.pull_request.html_url }}
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

#### `.github/workflows/deploy-production.yml`
```yaml
name: Deploy to Production

on:
  workflow_dispatch:
    inputs:
      staging_app:
        description: 'Staging app to promote'
        required: true
        default: 'gallformers-staging'
      confirm_promotion:
        description: 'Type "PROMOTE" to confirm'
        required: true

env:
  FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

jobs:
  validate-promotion:
    runs-on: ubuntu-latest
    steps:
      - name: Validate promotion confirmation
        run: |
          if [ "${{ github.event.inputs.confirm_promotion }}" != "PROMOTE" ]; then
            echo "❌ Promotion not confirmed. Please type 'PROMOTE' to proceed."
            exit 1
          fi

  deploy-production:
    needs: validate-promotion
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: superfly/flyctl-actions/setup-flyctl@master
      
      - name: Deploy to production
        run: |
          # Create a new production deployment
          flyctl deploy --config fly.toml --app gallformers-prod
          
          # Health check
          flyctl status --app gallformers-prod
          
          echo "✅ Production deployment completed successfully!"

  cleanup-staging:
    needs: deploy-production
    runs-on: ubuntu-latest
    steps:
      - uses: superfly/flyctl-actions/setup-flyctl@master
      
      - name: Scale down staging
        run: |
          flyctl scale count 0 --app ${{ github.event.inputs.staging_app }}
          echo "🧹 Staging app scaled down to save resources"

  notify-success:
    needs: [deploy-production, cleanup-staging]
    runs-on: ubuntu-latest
    if: success()
    steps:
      - name: Notify successful production deployment
        uses: 8398a7/action-slack@v3
        with:
          status: success
          channel: '#site-monitoring'
          text: |
            🚀 **Production deployment successful!**
            
            **URL**: https://gallformers.org
            **Commit**: ${{ github.sha }}
            **Deployed by**: ${{ github.actor }}
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

  notify-failure:
    needs: deploy-production
    runs-on: ubuntu-latest
    if: failure()
    steps:
      - name: Notify failed production deployment
        uses: 8398a7/action-slack@v3
        with:
          status: failure
          channel: '#site-monitoring'
          text: |
            ❌ **Production deployment failed!**
            
            **Workflow**: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
            **Commit**: ${{ github.sha }}
            **Triggered by**: ${{ github.actor }}
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### 2.3 Updated Dockerfile

Update your existing Dockerfile to work optimally with Fly.io:

```dockerfile
# Use official Node.js runtime as base image
FROM node:20-alpine AS base

# Install dependencies only when needed
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Copy package files
COPY package.json yarn.lock* ./
COPY .yarnrc.yml ./
COPY .yarn .yarn

# Install dependencies
RUN corepack enable && yarn install --immutable

# Build the application
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Generate Prisma client
RUN npx prisma generate

# Build Next.js
ENV NEXT_TELEMETRY_DISABLED 1
RUN yarn build

# Production image
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy built application
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/prisma ./prisma

# Create data directories for SQLite (both prod and staging)
RUN mkdir -p /data/production /data/staging && chown -R nextjs:nodejs /data

USER nextjs

EXPOSE 3000

ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

CMD ["node", "server.js"]
```

## Phase 3: Migration Execution

### 3.1 Pre-Migration Checklist

- [ ] Backup current production database
- [ ] Test Docker build locally
- [ ] Verify all environment variables are configured
- [ ] Set up Fly.io volumes for data persistence
- [ ] Configure custom domains in Fly.io

### 3.2 Domain Configuration

```bash
# Add custom domains
fly certs create gallformers.org --app gallformers-prod
fly certs create gallformers.com --app gallformers-prod

# Verify SSL certificates
fly certs show gallformers.org --app gallformers-prod
```

### 3.3 Database Migration

```bash
# Create single shared volume for both environments
fly volumes create gallformers_data --region iad --size 15 --app gallformers-prod

# Copy existing database to production directory
# This would involve SCP/rsync from current DO droplet to local, then:
# 1. fly ssh console --app gallformers-prod
# 2. mkdir -p /data/production /data/staging
# 3. Copy database file to /data/production/gallformers.db
# 4. Optionally copy to staging: cp /data/production/gallformers.db /data/staging/gallformers.db
```

## Phase 4: Monitoring & Observability

### 4.1 Health Checks

Add to your Next.js application (`pages/api/health.js`):

```javascript
export default function handler(req, res) {
  // Add database connectivity check
  // Add any other critical service checks
  res.status(200).json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.npm_package_version || 'unknown'
  });
}
```

### 4.2 Fly.io Monitoring

```bash
# Set up log aggregation
fly logs --app gallformers-prod

# Monitor metrics
fly dashboard --app gallformers-prod
```

## Phase 5: Deployment Workflow

### 5.1 Day-to-Day Operations

1. **Feature Development**:
   - Create feature branch
   - Open PR against `main`
   - Automatic staging deployment triggers
   - Test on staging URL provided in PR comment

2. **Production Promotion**:
   - Go to GitHub Actions
   - Run "Deploy to Production" workflow
   - Enter staging app name and type "PROMOTE"
   - Monitor deployment in Slack

3. **Rollback Process**:
   ```bash
   # Quick rollback using Fly.io
   fly releases --app gallformers-prod
   fly releases rollback <version> --app gallformers-prod
   ```

## Phase 6: Cost Optimization

### 6.1 Resource Scaling

- **Production**: Always-on with auto-scaling
- **Staging**: Auto-stop when inactive
- **Database**: Shared volumes with backup strategy

### 6.2 Estimated Costs

- **Production app**: ~$30-50/month (2GB RAM, performance CPU)
- **Staging app**: ~$5-15/month (1GB RAM, shared CPU, auto-stop)
- **Volumes**: ~$2-5/month per 10GB
- **Bandwidth**: Included in base pricing

## Phase 7: Migration Timeline

### Week 1: Setup & Configuration
- [ ] Set up Fly.io applications
- [ ] Configure GitHub Actions workflows
- [ ] Test staging deployments

### Week 2: Testing & Refinement
- [ ] Deploy test applications
- [ ] Validate promotion workflow
- [ ] Performance testing

### Week 3: Production Migration
- [ ] Database migration
- [ ] DNS cutover
- [ ] Monitor and verify

### Week 4: Cleanup & Documentation
- [ ] Decommission DO droplet
- [ ] Update documentation
- [ ] Team training on new workflow

## Next Steps

1. **Immediate**: Set up Fly.io account and install CLI
2. **Phase 1**: Create staging environment and test deployment
3. **Phase 2**: Implement GitHub Actions workflows
4. **Phase 3**: Execute production migration during low-traffic period

This plan provides a robust, automated deployment pipeline with proper testing and promotion workflows while maintaining the current technology stack and adding modern DevOps practices.