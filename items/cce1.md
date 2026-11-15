---
plan: taxogall
phase: 726a
title: Store dev import packages outside the checkout
stage: committed
created: "2026-11-15T18:48:20Z"
updated: "2026-11-15T18:48:20Z"
---

Gallformers.Storage.Private.LocalAdapter.root/0 defaults to the relative path tmp/private_storage (lib/gallformers/storage/private.ex about 121-127; config/dev.exs about 121 sets no :local_root). A server or iex run from a worktree writes packages inside that worktree, and removing the worktree loses them; one change package was lost this way (2026-11-07). Jeff: establish a place outside source control. Set an absolute dev root outside any checkout (failing test first), and say where in the README.

Deletes: nothing. Calls: Storage.Private.
