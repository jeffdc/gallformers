---
status: raw
created: 2026-03-11
updated: 2026-03-12
epic: postgres
needs: [1858]
parent: 4474
---

# Phase 4: Cutover

## Goal

Production running on Postgres. Clean, rehearsed, monitored.

## Production Postgres provisioning checklist

These steps were done for preview during Phase 3a. Repeat for production:

1. `fly postgres create --name gallformers-prod-db --region iad --vm-size shared-cpu-1x --volume-size 2` (save credentials!)
2. `fly machine update <id> --memory 1024 -a gallformers-prod-db --yes` (bump RAM to 1GB — create wizard defaults to 256MB)
3. **Do NOT set auto-stop** — production must stay running. Verify min_machines_running = 1.
4. `fly postgres attach gallformers-prod-db --app gallformers` (creates DB, user, sets DATABASE_URL secret)
5. Clean up orphaned Litestream secrets: `fly secrets unset LITESTREAM_ACCESS_KEY_ID LITESTREAM_SECRET_ACCESS_KEY -a gallformers`
6. Rename IAM user/policy from "litestream-gallformers" to something generic (cosmetic, not blocking)

**Preview instance reference:** `gallformers-db` in iad, shared-cpu-1x/1GB, 2GB vol, auto-stop enabled, attached to `gallformers-preview`.

## Pre-cutover preparation

- Turn on maintenance banner a week before (built in Phase 0)
- Announce on Discord a week before
- Update status page
- Optionally update CloudFront maintenance page with estimated return time
- Rehearse the cutover procedure on preview site
- Confirm Fly Postgres machine is healthy and has data from most recent conversion

## Cutover procedure

1. Turn on maintenance banner (a week before)
2. Day of: put site in read-only mode (auth plug flag, built in Phase 0)
3. Grab prod SQLite DB (guaranteed no new writes). **Must checkpoint WAL first** — run `PRAGMA wal_checkpoint(TRUNCATE)` to flush WAL into the main DB file before copying. Otherwise the copy may be missing recent writes.
4. Run conversion tool → Fly Postgres
5. Verify data in Postgres (row counts, spot checks)
6. `fly deploy` the Postgres-backed release (site comes up in read-only mode, talking to Fly Postgres)
7. Soak under real traffic — browse pages, search, maps, keys, species pages. Check Fly dashboard for Postgres machine health. Tail fly logs for errors. Have Adam poke at it too.
8. If something is wrong — `fly deploy` previous release, turn off read-only, back on SQLite. Zero data loss. **Note:** read-only mode escape hatch needed — if the flag is DB-stored, rolling back to SQLite leaves read-only ON and admin UI can't turn it off. Need an out-of-band mechanism (env var override, mix task via `fly ssh console`, or direct sqlite3 update). Decision deferred to implementation.
9. When confident — turn off read-only mode on the site (writes now go to Postgres)
10. Turn off maintenance banner
11. Update status page — back to normal

## Monitoring post-cutover

No new monitoring infrastructure — use what we have:
- Fly dashboard (CPU, memory, disk on both app and Postgres machines)
- Fly logs (tail for errors)
- Health check (/health, Fly pings every 30s)
- Request logs (JSON Lines files)
- Manual spot-checking
- Watch for a few days, not hours

## Cleanup (after soak period proves out)

- Delete old SQLite data from the volume (volume stays — used for request logs, WCVP, boundaries)
- Remove Litestream Fly secrets (LITESTREAM_ACCESS_KEY_ID, LITESTREAM_SECRET_ACCESS_KEY)
- Remove Litestream infrastructure: update OpenTofu definitions in `infra/` (S3 paths, IAM user), `tofu apply`, commit changes to git

Note: code cleanup (dead code, Litestream removal from Dockerfile/entrypoint, doc updates, migration linter) all happens in Phase 2 on the branch. It's deployed as part of step 6 above.

## Open questions (to be answered during Phase 3a research)

- Fly cert swap vs in-place deploy: leaning in-place (`fly deploy`) which requires no routing changes. Validate this works as expected.
- Rollback: `fly deploy` previous release, SQLite still on volume. How long do we keep the ability to roll back?
- How long should the read-only soak period be before enabling writes? Hours? A day?

