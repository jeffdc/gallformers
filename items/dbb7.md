---
plan: taxogall
phase: ec10
rank: 40
title: 'Web-page documents by URL: the Sprite fetches, stores and dates the page, and the curator verifies the capture'
stage: committed
created: "2026-11-22T01:26:34Z"
updated: "2026-11-22T01:26:34Z"
---

Decision 76ef on item 274b: URL in, an Oban job has the Sprite fetch the page, keep the HTML as captured with URL and access date, and convert it (produce convert-url); saved HTML or a PDF is the fallback for pages that won't fetch. A Source takes any number of page documents.

Deletes: nothing. Calls: the Sprite conversion job (its own item), produce convert-url.
