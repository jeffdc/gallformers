# Runbook: Incident Response

## Purpose
Coordinate response to a production incident affecting service availability.

## When to Use
- Complete service outage
- Partial outage affecting critical functionality
- Data integrity incident
- Security incident

## Severity Levels

| Level | Description | Response Time |
|-------|-------------|---------------|
| SEV1 | Complete outage, no users can access service | Immediate |
| SEV2 | Major feature broken, significant user impact | < 30 minutes |
| SEV3 | Minor feature broken, limited user impact | < 4 hours |

## Procedure

### 1. Acknowledge and Assess

Record:
- [ ] Time incident detected: `____:____`
- [ ] How detected (downdetector alert email, status page, user report, other): `____________`
- [ ] Initial symptoms: `____________`
- [ ] Severity level: `SEV__`

### 2. Communicate Status

If public-facing impact:

**Create incident on status page:**

1. Go to [gallformers-status issues](https://github.com/jeffdc/gallformers-status/issues)
2. Create new issue with title: `🛑 [Service Name]: Brief description`
   - Example: `🛑 Gallformers V2 API: Service unavailable`
3. Add label: `incident`
4. In the issue body, describe:
   - What is affected
   - When it started
   - Current status (investigating/identified/monitoring)

The incident will appear on the [status page](https://jeffdc.github.io/gallformers-status/) automatically.

**Acknowledge user reports** if any have been received.

### 3. Diagnose

Run through [Diagnose Deployment Issue](./diagnose-deployment-issue.md).

Quick checks:

```bash
# Health
curl -s -o /dev/null -w "%{http_code}" https://gallformers.fly.dev/health

# Status
fly status -a gallformers

# Recent logs
fly logs -a gallformers --no-tail | head -100
```

### 4. Mitigate

Choose appropriate action based on diagnosis:

| Cause | Action |
|-------|--------|
| Bad deployment | [Rollback Deployment](./rollback-deployment.md) |
| Database unreachable or erroring | [Postgres Maintenance](./postgres-maintenance.md) (check `gallformers-db`) |
| Data corrupted or lost | [Restore Database](./restore-database.md) |
| Infrastructure (Fly.io) | Check [Fly.io Status](https://status.fly.io) |
| Unknown | Continue to Step 5 |

### 5. Escalate If Needed

If not resolved within 15 minutes:
- Escalate to project owner
- Document what has been tried

### 6. Verify Resolution

- [ ] Health check returns 200
- [ ] Key user flows work
- [ ] Error rate returned to baseline
- [ ] Logs show clean operation

### 7. Communicate Resolution

**Update status page:**

1. Add a comment to the incident issue with resolution details:
   - What was the cause
   - How it was resolved
   - Any follow-up actions planned
2. Close the incident issue - this marks the incident as resolved on the status page

**Respond to user reports** with resolution summary.

- Note time of resolution: `____:____`

## Post-Incident

Complete within 48 hours of resolution:

### Incident Report

Write it in `docs/incidents/YYYYMMDD-<short-name>.md`. Document:
1. **Timeline**: When detected, when resolved, key actions taken
2. **Impact**: Users affected, duration, data loss (if any)
3. **Root cause**: What caused the incident
4. **Resolution**: How it was fixed
5. **Prevention**: What changes will prevent recurrence

### Follow-up Actions

- [ ] Create issues for preventive measures
- [ ] Update runbooks if gaps identified
- [ ] Review monitoring/alerting coverage
- [ ] Share learnings with team

## Emergency Contacts

| Role | Contact |
|------|---------|
| Project Owner | (add contact) |
| Fly.io Support | support@fly.io |

## Quick Reference

```bash
# Health check
curl https://gallformers.fly.dev/health

# App status
fly status -a gallformers

# Recent logs
fly logs -a gallformers --no-tail

# List releases (for rollback)
fly releases -a gallformers

# Status page
open https://jeffdc.github.io/gallformers-status/

# Create incident (opens GitHub issues)
open https://github.com/jeffdc/gallformers-status/issues/new

# Fly.io status page
open https://status.fly.io
```
