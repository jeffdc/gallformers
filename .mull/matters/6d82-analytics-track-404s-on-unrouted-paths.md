---
status: raw
created: 2026-05-12
updated: 2026-05-12
epic: platform
---

# Analytics: track 404s on unrouted paths

## Problem

The Analytics plug lives in `pipeline :browser` (`lib/gallformers_web/router.ex:16`). When a request hits an unrouted path, Phoenix raises `NoRouteError` *before any pipeline runs*. The plug's `register_before_send` callback is never attached, so the 404 response is never recorded. Gallformers has no 404 dashboard today, but adding one would surface an empty panel until this is fixed.

## Why this matters less than the other two analytics bugs

The two high-blast-radius bugs (live_redirect blind spot, push_patch over-counting) are fixed:
- Hook now tracks every connected mount's first `handle_params`
- Plug skips LV routes via `conn.private[:phoenix_live_view]` check
- Hook dedupes same-path patches via `:analytics_last_path`

See `lib/gallformers_web/plugs/analytics.ex`, `lib/gallformers_web/analytics/track_page_view.ex`, and `test/gallformers_web/analytics/integration_test.exs` for the current state.

This matter covers what was deliberately left out.

## Fix shape

The basic move is well-understood — relocate the plug from the `:browser` pipeline to the Endpoint so unrouted paths still hit it. Mechanical changes required:

1. **Move plug to Endpoint**, between `Plug.Session, @session_options` and `plug GallformersWeb.Router` in `lib/gallformers_web/endpoint.ex`.
2. **Plug must call `Plug.Conn.fetch_session(conn)` itself** before any `put_session` — at Endpoint position, the `:browser` pipeline's `fetch_session` step hasn't run yet.
3. **Remove the `:browser` pipeline entry** for the plug (`router.ex:16`).
4. **Relax the `conn.status == 200` filter** in `register_before_send` so non-200 statuses get through. The `live_view_route?` check stays (LV routes are still handled by the hook).

Existing plug tests assume the plug runs in `:browser`. They use `get(conn, "/")` through the router — moving the plug to Endpoint shouldn't break them since the endpoint is still in front of the router. Worth re-running them to verify session storage still works.

## Design choice that needs a decision

The `page_views` schema (`lib/gallformers/analytics/page_view.ex`) has no `status` field. So once 404s are tracked, they're indistinguishable from successful page views unless we add one.

**Option A — schema-light**: track 404 paths as plain rows. Easy, but `/galls`-the-real-page and `/galls/typo-404` look identical in the analytics dashboard. Top Pages will include garbage paths from typos and probes.

**Option B — add `status` column**: migration adds `:status, :integer`, default 200, on `page_views`. Plug includes `conn.status` in attrs. Dashboard queries gain a status filter. More invasive but actually useful — would enable a "Top 404s" panel that's the original motivation for tracking them.

Recommend **Option B** if a 404 dashboard is the goal. Otherwise Option A is a 30-minute change but adds noise.

## Companion test (writeup recommended)

The oaks fix also added a "route audit" test that loops over every public LV route family plus one unrouted 404 path, asserting exactly one `page_views` row per visit. This is the regression guard that would have caught all three bugs at once. Worth porting whether or not we do Option A or B.

## Related work

Two analytics bugs fixed in the same session that prompted this matter:
- Bug 2 (live_redirect blind spot): cross-LV `<.link navigate>` was untracked because the `:analytics_skip_initial` flag skipped the only `handle_params` a live_redirect arrival produces.
- Bug 3 (push_patch over-counting): `/id`, `/globalsearch`, and other LVs that update query state via `push_patch` were counting each patch as a page view.

See git log for the fix commits once they land.

