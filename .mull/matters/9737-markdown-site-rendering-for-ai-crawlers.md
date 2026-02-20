---
status: raw
created: 2026-02-19
updated: 2026-02-19
epic: external
relates: [29dc, 2a27, 5d49]
docket: true
---

# Markdown site rendering for AI crawlers

Research serving markdown versions of data pages for AI crawlers/LLMs. Current markup is mostly semantic, so a text-only markdown rendering of species/gall/host pages should be straightforward. Investigate: content negotiation (Accept header), alternate routes, or sitemap hints. Look at how other sites handle this (llms.txt, etc).

Consider building this as a reusable Phoenix-level pattern or library — not gallformers-specific. Same pattern applies to the Oaks site (5d49). Core pieces: plug/pipeline for .md route matching, convention for .text.eex templates, helpers for markdown formatting, llms.txt generation, <link rel=alternate> injection.

Static generation angle: data changes infrequently, so pre-render markdown to static files served via Plug.Static. Regenerate on deploy (mix task) + incremental via PubSub on data change. Eliminates server round-trips entirely. Cache-Control headers as a simpler first layer. Both approaches are part of the reusable library story.

Strategy: prove out in gallformers first, extract to standalone package when adding to oaks site. The second consumer validates the abstraction. Extraction is mechanical once the boundaries are clear from real usage.
