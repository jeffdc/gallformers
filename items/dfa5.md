---
title: Move the database snapshot workflow onto GitHub OIDC and retire the litestream-gallformers IAM user
stage: committed
docs:
  - .mull/matters/6ee3-backup-workflow-on-github-oidc-retire-the-litestream-gallformers-iam-user.md
created: "2026-11-09T23:35:21Z"
updated: "2026-11-11T13:31:56Z"
---

From matter 6ee3 (the plan is there). Jeff does the outward-facing steps: tofu apply, the manual workflow run, deleting the access keys and the two GitHub secrets. db-snapshot.yml runs from main, so this ships through main, not taxogall. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
