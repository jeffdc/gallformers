---
title: Track 404s on unrouted paths in analytics
stage: committed
docs:
  - .mull/matters/6d82-analytics-track-404s-on-unrouted-paths.md
created: "2026-11-09T23:35:21Z"
updated: "2026-11-12T02:23:22Z"
---

Record page views for requests to unrouted paths (404s), which analytics misses today.

## The problem (as of a0434bcf)

The Analytics plug, `GallformersWeb.Plugs.Analytics` (`lib/gallformers_web/plugs/analytics.ex`), sits in `pipeline :browser` (`lib/gallformers_web/router.ex`, about line 16). When a request hits an unrouted path, Phoenix raises `NoRouteError` *before any pipeline runs*. So the plug's `register_before_send` callback is never attached, and the 404 is never recorded. Gallformers has no 404 dashboard yet, and one would show an empty panel until this is fixed.

How tracking works now:
- **The plug** stores analytics data in the session for LiveView navigations. Its `register_before_send` callback tracks only when `conn.status == 200`, the route isn't a LiveView (`live_view_route?/1`: `conn.private[:phoenix_live_view]`), and `Analytics.should_track?/2` passes.
- **LiveView pages** are tracked by the `GallformersWeb.Analytics.TrackPageView` on_mount hook. It tracks every connected mount's first `handle_params` and dedupes same-path patches via `:analytics_last_path`. Two earlier analytics bugs (the live_redirect blind spot and push_patch over-counting) were fixed that way, and this item is what was deliberately left out then.
- **The tests:** `test/gallformers_web/analytics/integration_test.exs` covers live_redirect and push_patch. Its moduledoc mentions "404s on unrouted paths", but it has no 404 test.

## The fix

1. **Move the plug to the Endpoint**, between `plug Plug.Session, @session_options` and `plug GallformersWeb.Router` in `lib/gallformers_web/endpoint.ex`. At that point the conn still reaches the 404 render: `Phoenix.Endpoint.RenderErrors` renders a `NoRouteError` from the conn the router raised with, which already carries the Endpoint's before-send callbacks.
2. **The plug must call `Plug.Conn.fetch_session(conn)` itself** before any `put_session`. At Endpoint position, the `:browser` pipeline's `fetch_session` step hasn't run yet.
3. **Remove the plug from the `:browser` pipeline** in `router.ex`.
4. **Relax the `conn.status == 200` filter** in `register_before_send`, so non-200 statuses get through. The `live_view_route?` check stays, because LiveView routes are still tracked by the hook.

The existing plug tests use `get(conn, "/")` through the router. Moving the plug to the Endpoint shouldn't break them, since the Endpoint is still in front of the router. Re-run them to check that session storage still works.

## Open decision: telling 404s apart (Jeff hasn't chosen; `mull ask` before building)

The `page_views` schema (`lib/gallformers/analytics/page_view.ex`) has no `status` field. Once 404s are tracked, they look exactly like successful page views unless one is added.
- **Option A, schema-light:** track 404 paths as plain rows. It's a 30-minute change. But `/galls`, the real page, and `/galls/typo-404` look the same in the dashboard, and Top Pages fills with typos and probes.
- **Option B, a `status` column (recommended if a 404 dashboard is the goal):**
  - a migration adds `:status, :integer`, default 200, to `page_views`;
  - the plug puts `conn.status` in the attrs;
  - the dashboard queries gain a status filter.

  It's more invasive, but it enables a "Top 404s" panel, which was the reason to track them.

  Since the matter was written, `Gallformers.Analytics.Rollup` has rolled raw `page_views` into daily summary tables: `daily_stats`, `daily_page_stats`, `daily_referrer_stats`, `daily_device_stats` and `daily_browser_stats`. `Analytics.stats/2`, `top_pages/3` and the others read those tables for older days. A status filter, or keeping 404s out of the existing totals, has to cover the rollup too.

## Companion test (recommended)

Add a "route audit" test. It visits every public LiveView route family plus one unrouted 404 path, and asserts exactly one `page_views` row per visit. That is the regression guard that would have caught all three analytics bugs at once. The matter recommends it whichever option is chosen. A version was written for the oaks site; none exists in this repo.

## Done when

- A request to an unrouted path records one page view (with its status, under option B).
- Routed pages and LiveView navigations still record exactly one each: the route-audit test passes.
- `mix precommit` is clean.

From matter 6d82 (diagnosed there: NoRouteError is raised before the :browser pipeline's Analytics plug runs). Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
