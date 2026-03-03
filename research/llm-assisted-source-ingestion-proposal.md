---
status: raw
created: 2026-03-02
updated: 2026-03-02
epic: 1-foundation
relates: []
---

# LLM-assisted source ingestion

## The Need

The majority of gall literature hasn't been entered into Gallformers and realistically never will be through manual data entry. During COVID, Adam entered ~90% of the literature currently in the system. With the recent worldwide expansion, the backlog of relevant literature is large and growing. A tool that reduces the friction of getting published data into the system would make that backlog tractable.

## Context

- Source descriptions follow an informal but consistent pattern: name used by source, synonyms, gall description, hosts, range, phenology, comments. Not all sections appear in every entry — incomplete sources are the norm.
- Editorial conventions exist: `[square brackets]` for editor commentary, `[modern names]` for updated host taxonomy, `[]()` for linking other GF entries. Multiple entries per gall from the same source (pre-synonymization) are kept as separate blocks.
- A significant amount of source material comes from BHL, which has messy OCR that's human-painful but LLM-parseable.
- There is no formalized markdown template yet.
- A related phenology data layer proposal (PR #521) would benefit from structured phenology extraction from literature.

## Long-term vision

An incremental pipeline where each layer builds on the previous:

1. **Template formatting** — "Magic format button" on the source description field. Takes raw text, cleans up OCR, structures it against a markdown template. Available to all users.
2. **Full source reading** — Provide URL or PDF, LLM extracts per-species entries and matches to existing GF species.
3. **Structured data extraction** — Propose host associations, trait values, phenology observations, new species entries. Admin-reviewed.
4. **Proactive discovery** — Search vetted repositories (BHL) for relevant papers, feed into layers 2-3.

Each layer is independently useful. Nothing touches the database without human approval.

## Security and cost

Layer 1 is a one-shot text transform, not a conversational endpoint — minimal attack surface. A small cost-effective model handles formatting and isn't worth exploiting for free tokens. Simple rate limiting (X requests per user per day) caps cost exposure without complex tracking infrastructure. No database access or tooling is given to the model — worst case is wasted tokens, not data corruption.

API key funded by GF Patreon, managed through standard secrets infrastructure on Fly.io.

## Proposed first step

Before writing any feature code, validate the premise using existing data:

1. **Design template variants.** Take a sample of existing source entries and produce a few different markdown formatting proposals — different heading styles, section ordering, how to handle incomplete entries.
2. **Test LLM reformatting.** Run existing entries through candidate models to see how well they handle the domain text, OCR cleanup, and template application. Evaluate output quality across different entry types (complete vs sparse, clean text vs BHL OCR).
3. **Estimate cost and latency.** Measure per-entry cost and response time across model options. If reformatting is slow enough to be annoying, that affects the UX design.
4. **Pitch to community.** Present before/after examples to the GF community and get feedback on which template style they prefer and whether the output quality is good enough to be useful.

This produces concrete evidence — example outputs, cost numbers, community reaction — before committing to building anything into the site.

## Source description template

The template standardizes sections that already appear informally in most entries. Sections are included only when present in the source — incomplete entries are the norm. When a single source has multiple entries for the same gall (pre-synonymization), they appear as separate blocks, not interleaved.

Sections in order:

1. **Name used by source** — What the author calls this gall, which may differ from the current GF name.
2. **Synonyms** — The author's synonym list, kept as-is.
3. **Gall description** — Morphology, measurements, appearance.
4. **Host** — Host plant listing. Modern name corrections in `[brackets]` when the source uses an outdated name.
5. **Range** — Geographic distribution, with editorial notes on uncertain records.
6. **Phenology** — Timing, emergence, seasonality.
7. **Comments** — Ecology, taxonomic notes, editorial commentary in `[square brackets]`.

Exact markdown formatting (heading levels, bold/italic conventions, separator style) to be determined through the template variant testing described above.

## Open questions

- What do the template variants look like concretely? Needs a few proposals to compare side by side.
- Which models balance quality, cost, and speed for this domain? Needs empirical testing.
- What's the right UX for the format button? Inline preview? Side-by-side diff? Replace-in-place with undo?
- What daily rate limit per user is reasonable? Depends on typical source entry patterns.
- When do later layers get proposed? After layer 1 is proven and community feedback is in.
