---
plan: taxogall
phase: "2e83"
title: Replace the old domain docs, and update AGENTS.md and the runbooks for the new model
stage: committed
created: "2026-11-15T21:51:13Z"
updated: "2026-11-15T21:51:13Z"
---

docs/domain/general.md and docs/domain/admin-domain-reference.md describe the old species model; replace them. Update AGENTS.md's domain-model section (it says the old tables stay until cutover) and the runbooks that assume the old tables (e.g. runbooks/restore-deleted-gall.md). The domain language stays in docs/domain/domain-model.md and the overview doc (plan doc: one source of truth).

Deletes: the old domain docs. Calls: none.
