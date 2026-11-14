---
plan: taxogall
title: iNat observation import allows importing when the selected species doesn't match the observation; block it, and offer to redirect to the matching species if we have it
stage: captured
kind: bug
category: import
source: Jeff, 2026-11-14
created: "2026-11-14T19:11:03Z"
updated: "2026-11-14T19:11:03Z"
---

Jeff: if a non-matching species is selected we should not allow the import to happen, perhaps offer to redirect to the correct species if we have it. Code: lib/gallformers_web/live/admin/observation_live.ex, lib/gallformers/curation/from_observation.ex.
