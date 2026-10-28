---
status: raw
created: 2026-10-28
updated: 2026-10-28
epic: platform
---

# Backup workflow on GitHub OIDC; retire the litestream-gallformers IAM user

## Why (2026-10-28)

The daily `Database Snapshot` workflow (`.github/workflows/db-snapshot.yml`) uploads the full private dump to `gallformers-full-backups` and the public snapshot to `gallformers-backups`. It authenticates with long-lived access keys of the IAM user `litestream-gallformers` (a historical name), stored as the GitHub secrets `LITESTREAM_ACCESS_KEY_ID` and `LITESTREAM_SECRET_ACCESS_KEY`. Those keys were exposed in a session transcript on 2026-10-28 and rotated the same day. A long-lived key is a standing risk, and GitHub Actions doesn't need one.

## Plan

GitHub's OIDC federation: each job gets a short-lived identity token; an IAM role trusts tokens from this repository only, and AWS returns temporary credentials. No secret is stored anywhere.

- **`infra/iam.tf`:**
  - An IAM OIDC provider for `token.actions.githubusercontent.com` (audience `sts.amazonaws.com`).
  - A role `gallformers-db-snapshot` whose trust policy allows `sts:AssumeRoleWithWebIdentity` only for this repository's `main` branch and its scheduled or manual runs. Check the exact `sub` claim formats in GitHub's docs.
  - The existing `LitestreamGallformersBackup` policy attached to the role (consider renaming it).
- **`db-snapshot.yml`:**
  - `permissions: id-token: write, contents: read`.
  - An `aws-actions/configure-aws-credentials` step with `role-to-assume` and `aws-region: us-east-1`, replacing the `AWS_*` env blocks on both upload steps.
- **Verify:** run the workflow manually (`gh workflow run db-snapshot.yml`) and check both uploads.
- **Retire:**
  - delete the `litestream-gallformers` user's access keys;
  - remove the user from `iam.tf`;
  - delete the two GitHub secrets.

## Out of scope

- **The Fly app's `s3-upload` key.** Fly doesn't run on AWS. IAM Roles Anywhere (X.509 certificates from a CA) would replace the key with a certificate and its private key, plus a CA to run. That's not worth it at this scale; revisit only if Fly's own OIDC proves usable with AWS.
- **The database password used by the same workflow** (`PG_PASSWORD`, through `fly proxy`): separate.

