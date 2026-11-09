---
plan: general
title: 'Dev image storage without production keys: a local adapter for Storage.Images'
state: open
docs:
  - .mull/matters/b4d8-dev-image-storage-without-production-keys.md
created: "2026-11-09T23:35:21Z"
updated: "2026-11-09T23:35:21Z"
---

From matter b4d8 (option A, recommended; 'Done when' is in the matter). At intake: a44c9918 already removed the production keys from dev, but no adapter exists (lib/gallformers/storage/images.ex calls ExAws directly), so dev image uploads have no backend. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
