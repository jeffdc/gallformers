---
plan: general
title: Track 404s on unrouted paths in analytics
state: open
docs:
  - .mull/matters/6d82-analytics-track-404s-on-unrouted-paths.md
created: "2026-11-09T23:35:21Z"
updated: "2026-11-09T23:35:21Z"
---

From matter 6d82 (diagnosed there: NoRouteError is raised before the :browser pipeline's Analytics plug runs). Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
