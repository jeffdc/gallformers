# Runbook: Diagnose Deployment Issue

## Purpose
Determine whether a deployment has failed and identify the root cause.

## When to Use
- Health check alerts firing
- User reports of errors or unavailability
- Monitoring shows elevated error rates
- Post-deployment verification fails

## Prerequisites
- `flyctl` CLI installed and authenticated
- Access to Fly.io app `gallformers`

## Procedure

### 1. Check Application Health

```bash
curl -s -o /dev/null -w "%{http_code}" https://gallformers.fly.dev/health
```

| Result | Meaning |
|--------|---------|
| `200` | Application healthy |
| `5xx` | Application error |
| `000` or timeout | Application unreachable |

### 2. Check Application Status

```bash
fly status -a gallformers
```

Verify:
- [ ] Machines are in `started` state
- [ ] No machines in `failed` or `crashed` state
- [ ] Expected number of machines running

### 3. Check Recent Logs

```bash
fly logs -a gallformers --no-tail
```

Look for:
- `** (EXIT)` or `** (RuntimeError)` - Elixir process crashes
- `GenServer terminating` - GenServer failures
- `FATAL` or `ERROR` - Application errors
- `database` or `postgres` - Database connection issues
- `migration` - Migration failures
- `bind` or `listen` - Port binding issues

### 4. Check Recent Releases

```bash
fly releases -a gallformers
```

Note:
- When was the last deployment?
- Does timing correlate with reported issues?

### 5. Check Machine Health

```bash
fly machines list -a gallformers
```

For each machine, verify:
- [ ] State is `started`
- [ ] Region is correct
- [ ] Image version matches expected release

## Decision Tree

```
Health check fails?
├─ Yes → Check logs for errors
│        ├─ Panic/crash → See: rollback-deployment.md
│        ├─ Database error → See: restore-database.md
│        └─ Unknown → Escalate
└─ No → Check for partial failures
         ├─ Some endpoints fail → Check specific route logs
         └─ Intermittent → Check resource limits, scaling
```

## Next Steps

| Finding | Action |
|---------|--------|
| Bad code deployed | [Rollback Deployment](./rollback-deployment.md) |
| Database corruption | [Restore Database](./restore-database.md) |
| Active incident | [Incident Response](./incident-response.md) |
| Resource exhaustion | Scale machines or investigate memory leaks |

## Escalation
If unable to diagnose after 15 minutes, escalate to project owner.
