---
status: done
created: 2026-03-16
updated: 2026-09-13
epic: platform
---

# Upgrade CI GitHub Actions to Node.js 24 compatible versions

## Status (2026-03-17)

Waiting on two upstream actions before completing. Deadline: June 2, 2026.

## Ready to upgrade

| Action | Current | Target | Occurrences |
|--------|---------|--------|-------------|
| `actions/checkout` | `@v4` | `@v5` | 6 (ci.yml ×3, deploy.yml ×2, tileserver-deploy.yml ×1) |
| `actions/cache` | `@v4` | `@v5` | 3 (ci.yml ×2, deploy.yml ×1) |
| `actions/setup-node` | `@v4` | `@v5` | 1 (ci.yml assets job) |
| `docker/setup-buildx-action` | `@v3` | `@v4` | 1 (tileserver-deploy.yml — may be deleted) |

**Note on `setup-node@v5`**: Breaking change — auto-caches when `packageManager` is in package.json. Add `package-manager-cache: false` to preserve current behavior (we manage caching via `actions/cache`).

## Blocked on upstream

| Action | Current | Node 24 status | Occurrences |
|--------|---------|----------------|-------------|
| `erlef/setup-beam` | `@v1` | PR [#426](https://github.com/erlef/setup-beam/pull/426) open (2026-03-11), active | 3 (ci.yml ×2, deploy.yml ×1) |
| `superfly/flyctl-actions/setup-flyctl` | `@master` | Issues [#108](https://github.com/superfly/flyctl-actions/issues/108), [#109](https://github.com/superfly/flyctl-actions/issues/109) open, no PR | 2 (deploy.yml ×1, tileserver-deploy.yml ×1) |

## Not affected

`db-snapshot.yml` and `discord-release.yml` use no GitHub Actions (shell commands only).

## Files to touch

`ci.yml`, `deploy.yml`. `tileserver-deploy.yml` to be deleted (unused).

## Update (2026-04-29)

Completed the ready workflow upgrades:
- `actions/checkout` upgraded from `@v4` to `@v5` in `ci.yml` and `deploy.yml`
- `actions/cache` upgraded from `@v4` to `@v5` in `ci.yml` and `deploy.yml`
- `actions/setup-node` upgraded from `@v4` to `@v5` in `ci.yml`
- `package-manager-cache: false` added to preserve explicit cache management
- assets CI job moved to Node 22

Related deploy hardening completed while addressing the deployment warnings:
- deploy smoke test compile step now uses `mix compile --warnings-as-errors`
- Docker builder no longer relies on Alpine's older Node package; it now uses a Node 22 toolchain stage
- Docker asset install now uses `npm ci --omit=dev` so production builds exclude JS devDependencies

Remaining upstream-blocked items are unchanged:
- `erlef/setup-beam@v1`
- `superfly/flyctl-actions/setup-flyctl@master`
