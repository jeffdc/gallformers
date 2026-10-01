---
status: raw
created: 2026-03-17
updated: 2026-09-13
epic: postgres
blocks: [1121]
---

# Preview Postgres setup with WCVP data

Set up a dedicated Postgres cluster for the preview environment (gallformers-preview). Currently preview has no Postgres — it was sharing gallformers-db which was repurposed for production during the main Postgres cutover.

Includes:
- Provision a new Fly Postgres app for preview
- Configure preview app to use it (DATABASE_URL, WCVP connection derivation)
- Load WCVP data via pg_restore from the S3 dump artifact
- Restore the main gallformers data for preview use
- Update runbooks/preview procedures
