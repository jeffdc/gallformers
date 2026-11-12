---
plan: taxogall
phase: 726a
title: 'Merge main into taxogall (#596 role checks, #597 image upload events) and check both fixes hold'
stage: committed
created: "2026-11-09T20:38:18Z"
updated: "2026-11-12T02:23:22Z"
---

Merge `main` into `taxogall`, so that taxogall holds every production fix, then check that both fixes still hold on taxogall.

## What main has that taxogall lacks (as of a0434bcf)

`git log taxogall..main` shows four commits:
- **096fc5da**, "Enforce roles on live navigation into superadmin and operator screens", merged as **#596** (563313a4).
  - The bug: `/admin/users`, `/admin/filter-terms` (superadmin) and `/admin/ops` (operator) relied only on pipeline plugs and shared LiveView's default live session with the other admin screens. So an ordinary admin could live-navigate into them: live navigation sends no HTTP request, so the plugs never ran.
  - The fix: role-restricted `live_session`s (`:superadmin`, `:operator`), each with an `on_mount` role check: `GallformersWeb.Live.UserAuth` `:require_superadmin` / `:require_operator`, using `Accounts.superadmin?/1` / `Accounts.operator?/1`.
  - A user without the role goes to `/admin` with an error flash; a signed-out user goes to log in.
  - Tests: `test/gallformers_web/live/admin/role_live_session_test.exs` and `test/gallformers_web/live/user_auth_test.exs`.
- **631fdd7e**, "Send content image upload events to their component", merged as **#597** (22c68c81).
  - The bug: the `ContentImageUpload` and `SortableImages` hooks pushed `request_presigned_urls`, `uploads_completed`, `refresh_images` and `reorder_images` with `pushEvent`, which goes to the parent LiveView. The handlers live in the `ContentImageManager` LiveComponent, so uploading or reordering a content image on the article and key admin forms crashed the page (`FunctionClauseError`).
  - The fix: `pushEventTo(this.el, …)`.
  - Tests: `assets/js/hooks/content_image_upload.test.js`, `sortable_images.test.js`, `test/gallformers_web/live/admin/article_live/form_content_images_test.exs` and `content_image_manager_test.exs`.

**taxogall already has its own versions of both fixes:** 1b9b2a0e (role checks) and b0c4e559 (upload events). They were adapted to the new back end. The `:superadmin` session holds `/admin/users` and `/admin/vocabulary`. `/admin/filter-terms` was deleted with the old admin (a856). `UserAuth` adds `:fetch_curator` and `:require_admin_actor`. The hooks are on design-system tokens.

## Expect conflicts

A trial merge (`git merge-tree`, read only) conflicts in three files:
- `lib/gallformers_web/live/user_auth.ex`
- `lib/gallformers_web/router.ex`
- `test/gallformers_web/live/admin/role_live_session_test.exs` (add/add).

`assets/js/hooks/content_image_upload.js` auto-merges. In each conflict taxogall's side is the superset, so keep it. Main's role test lists `/admin/filter-terms` and has a "live-navigates between the superadmin screens" test through it; taxogall dropped both because the route is gone. Its operator test expects "Site Operations"; taxogall's expects "Site operations". Don't bring back anything taxogall deleted.

A merge commit passes the pre-commit review gate (the gate lets merges through). Never push main.

## Done when

- `git log taxogall..main` is empty.
- These tests pass on taxogall:
  - `role_live_session_test.exs`: an admin without the role is refused on live navigation into `/admin/users` and `/admin/ops`; superadmins and operators get in;
  - `user_auth_test.exs`;
  - the two JS hook tests;
  - `form_content_images_test.exs` and `content_image_manager_test.exs`.
- `mix precommit` is clean.

From git at intake (2026-11-09): main has 4 commits taxogall lacks (096fc5da, 563313a4, 631fdd7e, 22c68c81). Matter 2c8c items 3 and 4. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
