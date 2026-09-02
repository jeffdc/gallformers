# Runbooks

Operational runbooks for Gallformers.

## Index

| Runbook | Purpose |
|---------|---------|
| [Diagnose Deployment Issue](./diagnose-deployment-issue.md) | Identify what's wrong after a deployment |
| [Rollback Deployment](./rollback-deployment.md) | Revert to a previous release |
| [Restore Database](./restore-database.md) | Recover PostgreSQL database from backup |
| [Restore Deleted Gall](./restore-deleted-gall.md) | Restore one deleted gall and its images without replacing current production data |
| [Postgres Maintenance](./postgres-maintenance.md) | Day-to-day Postgres operations, monitoring, and queries |
| [Oban Operations](./oban.md) | Inspect queues, retry jobs, and troubleshoot background work |
| [PostgreSQL Migration Cutover](./postgres-cutover.md) | Cutover procedures and post-migration cleanup |
| [Incident Response](./incident-response.md) | Coordinate response to production incidents |
| [Fly Operations](./fly-operations.md) | Fly.io infrastructure operations and safety rules |
| [WCVP](./wcvp.md) | WCVP secondary database operations |
| [Map Tiles](./map-tiles.md) | Range map tile generation and deployment |
| [OpenTofu Operations](./opentofu-operations.md) | AWS infrastructure management |
| [Planned Maintenance](./planned-maintenance.md) | Put the site into CDN-served maintenance mode for scheduled downtime |

## Usage

Start with **Diagnose Deployment Issue** to identify the problem, then follow the appropriate runbook based on findings.

For active incidents affecting users, go directly to **Incident Response**.
