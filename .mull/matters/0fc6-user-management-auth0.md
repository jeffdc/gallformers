---
status: planned
effort: 2 days
created: 2026-02-13
updated: 2026-02-25
epic: admin
docs: ['']
blocks: [ec68]
---

# User management (Auth0)

Design doc: docs/plans/2026-02-11-user-management.md

## Context

Currently the 2 SuperAdmins manage all users via the Auth0 dashboard directly. The app has login/logout integration with Auth0 (via Ueberauth/OAuth2) but zero Auth0 Management API integration. The existing admin Users screen can only toggle "show on about page". The existing Profile screen lets users edit display name, bio, and links.

## Current Architecture

```
Auth0 (source of truth for auth)
  ├── Authentication API ← Ueberauth integration (login/logout) ✅
  └── Management API ← NOT integrated ❌

Local DB (profile storage only)
  └── users table: auth0_id, display_name, nickname, about_me, URLs, show_on_about
```

Roles (admin, superadmin) live in Auth0 custom claims, not in the local DB. They arrive via `https://gallformers.org/roles` claim on each login.

## Proposed Features (Tiered)

### Tier 0: Quick Win (~30 min)

Add a "Reset Password" link to the user profile page that triggers Auth0's password reset email flow. Single API call or link to Auth0's hosted reset page. No Management API needed.

### Tier 1: SuperAdmin User Management (3-5 sessions)

Expand `/admin/users` so SuperAdmins can create, modify, and delete users and assign roles — all backed by the Auth0 Management API.

**Prerequisites:**
1. Auth0 M2M Application with scopes: read/create/update/delete users, read roles, create/delete role_members
2. New Fly.io secrets: AUTH0_MGMT_CLIENT_ID, AUTH0_MGMT_CLIENT_SECRET

**Components:**
- `Gallformers.Auth0.Management` — HTTP client, M2M token acquisition/caching/refresh
- `Gallformers.Auth0.Management.Users` — CRUD operations
- `Gallformers.Auth0.Management.Roles` — List roles, assign/remove
- `Gallformers.AuditLog` — who did what to whom and when
- UsersLive expansion — create/edit/delete UI
- Test mocks — wrap calls similar to `Gallformers.S3.request/1` pattern

**Auth0 Management API Endpoints:**
- POST /oauth/token — M2M access token
- GET/POST/PATCH/DELETE /api/v2/users — user CRUD
- GET /api/v2/roles — list roles
- POST/DELETE /api/v2/roles/{id}/users — assign/remove role

**Gotchas:**
- Rate limits: Auth0 free/essential tier = 2 req/s on Management API. Handle 429 with backoff.
- Token caching: M2M tokens valid ~24h. Cache in Agent or ETS.
- Eventual consistency: Role changes won't reflect until next login. May need session invalidation or notice.
- User creation: `POST /tickets/password-change` sends invite-style email (better UX than setting password directly).

### Tier 2: User Self-Service (~1 session, depends on Tier 1)

Let users change email and trigger password resets from Profile page using the Management API client from Tier 1.

## Recommendation

Defer Tiers 1-2. Do Tier 0 anytime. ROI is low while admin pool is small (2 SuperAdmins, handful of admins). Auth0 dashboard works fine for occasional user management. Inflection point: contributor growth (e.g., Western Hemisphere expansion) makes dashboard management a regular chore.

The Management API integration adds maintenance surface: new secrets, token lifecycle, rate limits, external dependency mocks, Auth0 plan tier constraints.

When the time comes, the `S3.request/1` wrapper pattern provides a good template for testable external API integration.

**References:** Auth0 Management API docs, existing code in `lib/gallformers/accounts/` and `lib/gallformers_web/live/admin/users_live.ex`.

**Update:** Tier 0 (password reset link) is done. Effort estimate covers Tiers 1-2.


---

## Full Design Document

# User Management Features — Feasibility & Plan

**Date**: 2026-02-11
**Status**: Assessment complete, deferred pending contributor growth

## Context

Currently the 2 SuperAdmins manage all users via the Auth0 dashboard directly.
The app has login/logout integration with Auth0 (via Ueberauth/OAuth2) but zero
Auth0 Management API integration. The existing admin Users screen can only toggle
"show on about page". The existing Profile screen lets users edit display name,
bio, and links.

The question: should we build in-app user management, and if so, when?

## Current Architecture

```
Auth0 (source of truth for auth)
  ├── Authentication API ← Ueberauth integration (login/logout) ✅
  └── Management API ← NOT integrated ❌

Local DB (profile storage only)
  └── users table: auth0_id, display_name, nickname, about_me, URLs, show_on_about
```

**Roles** (`admin`, `superadmin`) live in Auth0 custom claims, not in the local DB.
They arrive via `https://gallformers.org/roles` claim on each login.

## Proposed Features (Tiered)

### Tier 0: Quick Win (trivial, do anytime)

Add a "Reset Password" link to the user profile page that triggers Auth0's
password reset email flow. This is a single API call or even just a link to
Auth0's hosted reset page. No Management API needed.

**Effort**: ~30 minutes

### Tier 1: SuperAdmin User Management (medium-high complexity)

Expand `/admin/users` so SuperAdmins can create, modify, and delete users and
assign roles — all backed by the Auth0 Management API.

#### Prerequisites

1. **Auth0 M2M Application** — Create in Auth0 dashboard with scopes:
   - `read:users`, `create:users`, `update:users`, `delete:users`
   - `read:roles`, `create:role_members`, `delete:role_members`
2. **New secrets** on Fly.io: `AUTH0_MGMT_CLIENT_ID`, `AUTH0_MGMT_CLIENT_SECRET`

#### Implementation

| Component | Description |
|-----------|-------------|
| `Gallformers.Auth0.Management` | HTTP client for Auth0 Management API. Handles M2M token acquisition, caching (tokens expire ~24h), and refresh. Uses Tesla or Req. |
| `Gallformers.Auth0.Management.Users` | CRUD operations: list, create, update, delete users |
| `Gallformers.Auth0.Management.Roles` | List roles, assign/remove role from user |
| `Gallformers.AuditLog` | New context + schema. Records who did what to whom and when. |
| `UsersLive` expansion | Add create/edit/delete UI to existing `/admin/users` LiveView |
| Test mocks | Wrap Management API calls similar to `Gallformers.S3.request/1` pattern — disabled in test env |

#### Auth0 Management API Endpoints Used

```
POST   /oauth/token                    → Get M2M access token
GET    /api/v2/users                   → List users (with search)
POST   /api/v2/users                   → Create user
PATCH  /api/v2/users/{id}              → Update user
DELETE /api/v2/users/{id}              → Delete user
GET    /api/v2/roles                   → List available roles
POST   /api/v2/roles/{id}/users        → Assign role to user
DELETE /api/v2/roles/{id}/users        → Remove role from user
```

#### Gotchas

- **Rate limits**: Auth0 free/essential tier allows 2 req/s on Management API.
  Must handle 429 responses gracefully (retry with backoff).
- **Token caching**: M2M tokens are valid ~24h. Cache in an Agent or ETS to
  avoid re-fetching on every request.
- **Eventual consistency**: Role changes in Auth0 won't be reflected in the
  user's session until their next login. May need to invalidate sessions or
  show a "changes take effect on next login" notice.
- **User creation flow**: Auth0 `POST /users` creates a user with a password.
  Alternative: `POST /tickets/password-change` sends an invite-style email
  where the user sets their own password. The invite approach is better UX.

#### Effort Estimate

~3-5 working sessions:
- Session 1: Auth0 M2M setup, token management, basic HTTP client
- Session 2: User CRUD operations + tests with mocks
- Session 3: Role management + audit log
- Session 4-5: UI work on UsersLive, error handling, polish

### Tier 2: User Self-Service (medium complexity, depends on Tier 1)

Let users change their own email and trigger password resets from the Profile
page, using the Management API client built in Tier 1.

| Feature | Implementation |
|---------|---------------|
| Email change | `PATCH /api/v2/users/{id}` with new email. Requires email verification flow. |
| Password change | `POST /api/v2/tickets/password-change` sends reset email. Auth0 handles the rest. |

**Effort**: ~1 session (Management API client already exists from Tier 1)

## Recommendation

**Defer Tiers 1-2. Do Tier 0 now if desired.**

The ROI is low while the admin pool is small (2 SuperAdmins, handful of admins).
Auth0's dashboard works fine for occasional user management. The inflection point
is when contributor growth (e.g., Western Hemisphere expansion) makes Auth0
dashboard management a regular chore rather than an occasional task.

The Management API integration adds a meaningful maintenance surface:
- New secrets to manage
- Token lifecycle to handle
- Auth0 rate limits to respect
- Another external dependency to mock in tests
- Auth0 plan tier constraints to be aware of

When the time comes, the implementation path is straightforward — the existing
`S3.request/1` wrapper pattern provides a good template for testable external
API integration.

## References

- [Admin User Provisioning Requirements](../admin-user-provisioning.md)
- [Auth0 Management API docs](https://auth0.com/docs/api/management/v2)
- Existing code: `lib/gallformers/accounts/`, `lib/gallformers_web/live/admin/users_live.ex`
