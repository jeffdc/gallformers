---
title: Move the database snapshot workflow onto GitHub OIDC and retire the litestream-gallformers IAM user
stage: committed
docs:
  - .mull/matters/6ee3-backup-workflow-on-github-oidc-retire-the-litestream-gallformers-iam-user.md
created: "2026-11-09T23:35:21Z"
updated: "2026-11-12T02:23:22Z"
---

Move the daily `Database Snapshot` workflow off long-lived AWS access keys onto GitHub's OIDC federation, then retire the `litestream-gallformers` IAM user.

## Why

`.github/workflows/db-snapshot.yml` runs daily at 06:00 UTC and on `workflow_dispatch`. It uploads the full private dump to `s3://gallformers-full-backups/<date>/gallformers.dump` and the public snapshot to `s3://gallformers-backups/public/gallformers.dump`.
- **How it authenticates:** with long-lived access keys of the IAM user `litestream-gallformers` (a historical name from the SQLite/Litestream era). They are stored as the GitHub secrets `LITESTREAM_ACCESS_KEY_ID` and `LITESTREAM_SECRET_ACCESS_KEY`, and passed as `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_DEFAULT_REGION: us-east-1` env blocks on the two `aws s3 cp` steps.
- **Why now:** those keys were exposed in a session transcript on 2026-10-28 and rotated the same day. A long-lived key is a standing risk, and GitHub Actions doesn't need one.

With OIDC, each job gets a short-lived identity token, an IAM role trusts tokens from this repository only, and AWS returns temporary credentials. No secret is stored anywhere.

## Plan

**`infra/iam.tf`** (OpenTofu)
- An IAM OIDC provider for `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`. As of a0434bcf, `infra/` has none.
- A role `gallformers-db-snapshot`. Its trust policy allows `sts:AssumeRoleWithWebIdentity` only for this repository's `main` branch and its scheduled or manual runs. Check the exact `sub` claim formats in GitHub's docs.
- Attach the existing `LitestreamGallformersBackup` policy (`aws_iam_policy.litestream_gallformers_backup`) to the role; consider renaming it. Its permissions:
  - Actions: `s3:GetObject`, `PutObject`, `DeleteObject`, `ListBucket`, `GetBucketLocation`.
  - Resources: `gallformers-backups` and `gallformers-full-backups`, plus their objects.

**`db-snapshot.yml`**
- Add `permissions: id-token: write, contents: read`.
- Add an `aws-actions/configure-aws-credentials` step with `role-to-assume` and `aws-region: us-east-1`. It replaces the `AWS_*` env blocks on both upload steps.

**Verify:** run the workflow by hand (`gh workflow run db-snapshot.yml`) and check both uploads landed.

**Retire:**
- delete the `litestream-gallformers` user's access keys;
- remove the user (`aws_iam_user.litestream_gallformers`) and its policy attachment from `iam.tf`, and fix the header comment that lists it;
- delete the two GitHub secrets.

**Who does what:** Jeff does the outward-facing steps: `tofu apply`, the manual workflow run, deleting the access keys and the two GitHub secrets.

**Where it ships:** `db-snapshot.yml` runs from main, so this ships through main, not taxogall. taxogall also changed this workflow (84aa2eeb, the catalog data migration and the public snapshot rebuild), though not its AWS steps. So the OIDC change has to be carried into taxogall's version at the next main → taxogall merge.

## Out of scope

- **The Fly app's `s3-upload` key** (`aws_iam_user.s3_upload`). Fly doesn't run on AWS. IAM Roles Anywhere (X.509 certificates from a CA) would replace the key with a certificate and its private key, plus a CA to run. That isn't worth it at this scale. Revisit only if Fly's own OIDC proves usable with AWS.
- **The database password used by the same workflow** (`PG_PASSWORD`, through `fly proxy`): separate.

## Done when

- A manual run of the workflow uploads both dumps using only the OIDC role.
- The `litestream-gallformers` user, its keys and the two `LITESTREAM_*` secrets are gone.

From matter 6ee3 (the plan is there). Jeff does the outward-facing steps: tofu apply, the manual workflow run, deleting the access keys and the two GitHub secrets. db-snapshot.yml runs from main, so this ships through main, not taxogall. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
