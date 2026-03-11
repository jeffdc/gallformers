---
status: done
created: 2026-03-11
updated: 2026-03-11
epic: platform
relates: [be9d, 7157]
---

# Unified text search — shared TextMatch module and consistent styling

## Problem

Three different text search approaches coexist with inconsistent behavior:

1. **FTS5 word-prefix** (Species, Search context) — `term*` syntax, BM25 ranking, requires manual sync (13+ `update_species_fts` calls). Covers species names + aliases only.
2. **Multi-term LIKE** (`Plants.search_hosts`) — splits on whitespace, `%term%` per word, all terms must match. Works but is one-off implementation.
3. **Single-string LIKE** (host range filter, images, taxonomy, places) — `%whole query%`, no splitting. "q alba" does NOT match "Quercus alba".

Additionally, client-side filtering in `multi_select_typeahead` uses `String.contains?` with no word splitting.

The host range admin page also has a styling mismatch: the search input is a raw `<input>` with ad-hoc Tailwind, while filter dropdowns use the `.input` component with `gf-select` styling.

## Design

### 1. Shared `Gallformers.Search.TextMatch` module

A composable Ecto query builder for consistent multi-term text matching:

- `match_terms(query, search_string, fields)` — splits search string on whitespace, builds LIKE clauses where ALL terms must match across ANY of the specified fields
- `match_terms_client(search_string, text)` — same logic for client-side (Enum.filter) use
- Handles: empty queries, single terms, case normalization, nil/empty fields
- Testable in isolation with unit tests

**Pattern:** Each term becomes `%term%` (case-insensitive substring). All terms must match. A term can match in any of the specified fields. This is the `Plants.search_hosts` pattern, extracted and generalized.

**FTS5 stays** for ranked global search where BM25 relevance matters. `TextMatch` replaces all other LIKE callsites.

### 2. Compact search input styling

The existing `.gf-search-input` class is designed for the hero global search bar (1.125rem font, 0.75rem padding). Admin toolbar search needs a compact variant that matches `.gf-select` sizing.

Add a `.gf-search-input-sm` class (or use a `size` attr on `.search_input` component) with:
- Same font size as `.gf-select` (1rem)
- Same vertical padding (0.5rem)
- Matching border radius and focus states
- Left padding for the magnifying glass icon

Update `.search_input` component to accept a `size` attr (`:default` | `:sm`), defaulting to `:default` for backward compatibility.

### 3. Migration callsites

| Callsite | Current | After |
|----------|---------|-------|
| `Plants.list_hosts_for_range_review` (host range admin) | Single-string LIKE | `TextMatch.match_terms` |
| `Plants.search_hosts` | Custom multi-term LIKE | `TextMatch.match_terms` (extract existing logic) |
| `Plants.search_hosts_for_section` | Single-string LIKE | `TextMatch.match_terms` |
| `Images.search_species` | Single-string LIKE | `TextMatch.match_terms` |
| `Images LiveView` source search | Client-side `String.contains?` | `TextMatch.match_terms_client` |
| `Taxonomy.Search.search_families` | Prefix LIKE | Keep (prefix-only is intentional for taxonomy) |
| `Taxonomy.Search.search_genera_and_sections` | Mixed prefix + substring | Keep (intentional) |
| `Places.search_places` | Single-string LIKE | `TextMatch.match_terms` |
| `Search.search_glossary` | Single-string LIKE | `TextMatch.match_terms` |
| `Search.search_sources` | Single-string LIKE | `TextMatch.match_terms` |
| `Search.search_places` | Single-string LIKE | `TextMatch.match_terms` |
| `multi_select_typeahead` component | Client-side `String.contains?` | `TextMatch.match_terms_client` |

**Not migrated:** FTS5-backed searches (global search, species typeaheads) — ranking matters there. Taxonomy prefix searches — prefix-only is intentional behavior.

### 4. Host range page toolbar

Replace the raw `<input>` with `.search_input` using the new `:sm` size. All toolbar elements (filters + search) will share consistent `.gf-select` / `.gf-search-input-sm` sizing.
