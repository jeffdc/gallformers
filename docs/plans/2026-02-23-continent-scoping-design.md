# Continent Scoping Design

## Purpose

Define how the sticky continent selector interacts with Browse, Search, and other public pages. This is Stream 0.5 from the global expansion design — a design pass to check for architectural surprises before building global infrastructure.

**Key finding: No data model or schema changes needed.** Continent scoping is purely a query/UI concern layered on existing place hierarchy and range tables. Streams 1-4 of the global expansion are unaffected.

## Continent Selector

**Placement:** In the main site header. Always visible. Compact treatment — globe icon, continent name, change affordance. Exact sizing TBD during implementation.

**Persistence:** localStorage. Set on first visit, sticky across sessions. No account required.

**Options:** Match continent records in the place table — North America, Central America, Caribbean, South America, Europe, Africa, Asia, Oceania.

## Page Scoping Rules

### Scoped by continent

| Page | What's scoped | What stays global |
|------|---------------|-------------------|
| **ID tool** (`/id`) | Gall results filtered to species with ranges in the selected continent. Place typeahead limited to continent's countries/subdivisions. | All other filters (host, genus, morphology) remain global options. |
| **Search** (`/globalsearch`) | Gall and Host results filtered to species with ranges in the selected continent. | Glossary, Source, Taxonomy, and Place results stay global — they aren't geographic entities. |

### Global (not scoped)

| Page | Rationale |
|------|-----------|
| **Explore/Browse** (`/explore`) | Taxonomic view of data. Users browsing by taxonomy want the full picture. |
| **Family/Genus/Section** (`/family/:id`, `/genus/:id`, `/section/:id`) | Same — taxonomic, not geographic. |
| **Gall/Host detail** (`/gall/:id`, `/host/:id`) | Species pages show full worldwide range. |
| **Place** (`/place/:code`) | Already scoped by definition. |
| **Everything else** (articles, keys, glossary, about, etc.) | No geographic dimension. |

### Visual indicator on global pages

Global pages display a subtle "Showing all regions" indicator near the content area. This makes the scoping model explicit — the user can see their continent in the header but understands this page intentionally shows everything.

## Temporary Override

Users can clear the continent filter for a single search/ID session without changing the sticky preference. A "Search all regions" link or toggle near the filter area. Next navigation or page load restores the sticky continent.

## Query Implementation

### ID tool

Already has place filtering via `Galls.filter_galls/1` with `place_codes` parameter. Continent scoping passes the leaf descendant codes for the selected continent instead of a single place code. `Places.leaf_descendant_ids/1` handles the recursive expansion. No new query patterns needed.

### Search

`Search.global_search/1` currently has no geographic filtering. Adding continent scoping requires joining gall/host results through host_range to check if any range codes fall within the continent's descendants. This is a new join in the search queries but uses existing tables — no schema change.

## Architectural Impact on Global Expansion

**None.** The existing place hierarchy (`place` + `place_hierarchy` tables) and range tables (`host_range`, `gall_range_exclusion`) support continent-level scoping without modification. The continent selector reads from localStorage on the client, passes a continent code to the server, and the server expands it to descendant place codes using existing recursive CTE queries.

No denormalization, no new indexes, no new tables needed. The work is entirely in:
1. A header component for the continent selector (LiveView + localStorage JS hook)
2. Wiring the continent code into ID tool and Search query paths
3. The "Showing all regions" indicator on global pages
