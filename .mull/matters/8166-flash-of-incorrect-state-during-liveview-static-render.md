---
status: raw
created: 2026-02-27
updated: 2026-02-27
epic: platform
relates: [8900]
---

# Flash of incorrect state during LiveView static render

LiveView components that depend on connect_params (e.g., localStorage values delivered via LiveSocket params) show incorrect default state during static render before the WebSocket connects. The region scope widget flashes 'All Regions' before showing the user's saved continent. This is a general problem — any component whose correct state depends on client-side data will flash wrong values during static render. Need to investigate the idiomatic Phoenix/LiveView solution (phx-connected, CSS strategies, or architectural changes).
