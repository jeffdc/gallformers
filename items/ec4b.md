---
title: 'JS bundle size: production bundle ~1.2 MB uncompressed (341 KB gzipped) since MapLibre'
stage: captured
kind: idea
source: matter 96b1; kept by Jeff at intake, 2026-11-09
from: fdf1
created: "2026-11-09T23:47:44Z"
updated: "2026-11-12T02:23:22Z"
---

The JavaScript bundle grew about 5× when MapLibre GL was added. In March 2026 the production bundle was about 1.2 MB uncompressed and 341 KB gzipped. The dev build shows esbuild's 2 MB warning, inflated by inline source maps.

**Breakdown then:**
- MapLibre GL (WebGL maps): about 500–600 KB (~45%);
- D3 (the admin bar chart): about 300–400 KB (~30%);
- Phoenix and LiveView: about 200–300 KB (~20%);
- custom code and PMTiles: about 100 KB (~5%).

**Opportunities:**
1. **Code splitting / lazy loading (the biggest win).** MapLibre is used on only a few pages but loaded everywhere. A dynamic `import()` in the hooks would spare most visitors the map library.
2. **Replace D3 for the admin chart.** That's done: bc0d replaced the analytics chart with a server-rendered SVG `bar_chart` and removed d3 from `assets/package.json`.
3. **Brotli pre-compression**, 15–20% better than gzip on JS.

**As of a0434bcf:**
- `assets/js/hooks/range_map.js` still imports `maplibre-gl` statically (now `^6.15.0`). Its worker is built as a separate file by the `maplibre_worker` esbuild profile.
- `Plug.Static` in `endpoint.ex` serves gzip only (`gzip: not code_reloading?`).
- The bundle hasn't been re-measured since D3 went.

**Not urgent:** 341 KB gzipped is within normal range for an app with maps. Act when it starts hurting real users or crosses 500 KB gzipped.

Source: matter 96b1.
