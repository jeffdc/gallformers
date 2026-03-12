# Runbooks

Operational runbooks for Gallformers V2.

## Index

| Runbook | Purpose |
|---------|---------|
| [Diagnose Deployment Issue](./diagnose-deployment-issue.md) | Identify what's wrong after a deployment |
| [Rollback Deployment](./rollback-deployment.md) | Revert to a previous release |
| [Restore Database](./restore-database.md) | Recover PostgreSQL database from backup |
| [Reset Production Database](./reset-production-database.md) | Replace production database entirely |
| [Incident Response](./incident-response.md) | Coordinate response to production incidents |
| [Fly Operations](./fly-operations.md) | Fly.io infrastructure operations and safety rules |
| [WCVP](./wcvp.md) | WCVP secondary database (SQLite) operations |
| [Map Tiles](./map-tiles.md) | Range map tile generation and deployment |
| [OpenTofu Operations](./opentofu-operations.md) | AWS infrastructure management |
| [CloudFront V2 Cutover](./cloudfront-v2-cutover.md) | Domain cutover to CloudFront |

## Usage

Start with **Diagnose Deployment Issue** to identify the problem, then follow the appropriate runbook based on findings.

For active incidents affecting users, go directly to **Incident Response**.
