# Runbook: Rollback Deployment

## Purpose
Revert the application to a previous known-good release.

## When to Use
- Deployment introduced a breaking bug
- Application crashes after deployment
- Critical functionality broken after release
- Diagnosis confirmed bad code (see [Diagnose Deployment Issue](./diagnose-deployment-issue.md))

## Prerequisites
- `flyctl` CLI installed and authenticated
- Access to Fly.io app `gallformers`
- Known-good release version (or will identify in Step 1)

## Important
This runbook rolls back **code only**. Database changes persist across deployments. If the database is corrupted, see [Restore Database](./restore-database.md) first.

## Choose Your Approach

**Option A: Emergency rollback (minutes)** — Redeploy a previous Fly.io image. Use when the site is down and you need it back NOW. See Procedure below.

**Option B: Git revert (slower but cleaner)** — `git revert <bad-commit>` and push to main. CI/CD handles the rest. Keeps git history as source of truth. Preferred when you have time.

## Procedure (Option A: Image Rollback)

### 1. Identify Target Release and Image

List recent releases with their images:

```bash
fly releases -a gallformers --image
```

Output example:
```
VERSION STABLE  TYPE    STATUS    DESCRIPTION   IMAGE
v15     true    release succeeded Deploy image  registry.fly.io/gallformers:deployment-01ABC123
v14     true    release succeeded Deploy image  registry.fly.io/gallformers:deployment-01XYZ789
v13     true    release succeeded Deploy image  registry.fly.io/gallformers:deployment-01DEF456
```

Identify the last known-good version and record its image reference.

### 2. Execute Rollback

```bash
fly deploy --image registry.fly.io/gallformers:deployment-<ID> -a gallformers
```

Wait for deployment to complete.

### 3. Verify Rollback

Run health check:

```bash
curl -s -o /dev/null -w "%{http_code}" https://www.gallformers.org/health
```

Expected: `200`

Check logs for clean startup (runs for 5 seconds then stops):

```bash
fly logs -a gallformers 2>&1 | timeout 5 cat
```

Verify no errors in recent log output.

### 5. Confirm Application Functionality

- [ ] Health endpoint returns 200
- [ ] Homepage loads
- [ ] Key functionality works (search, species pages)

## Verification Checklist

- [ ] `fly status -a gallformers` shows healthy machines
- [ ] Health check returns 200
- [ ] No error patterns in logs
- [ ] User-reported issue resolved

## Rollback Failed?

If rollback deployment fails:

1. Try direct machine update:
   ```bash
   fly machines list -a gallformers
   fly machines update <MACHINE_ID> --image registry.fly.io/gallformers:deployment-<ID> -a gallformers
   ```

2. If still failing, see [Incident Response](./incident-response.md)

## Post-Rollback

1. Communicate resolution to affected users if applicable
2. Create issue to investigate root cause
3. Fix forward—do not redeploy broken code
