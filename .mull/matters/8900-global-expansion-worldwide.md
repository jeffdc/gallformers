---
status: active
created: 2026-02-23
updated: 2026-02-25
epic: geo-expansion
docs: ['']
relates: [1db6, b99b]
needs: [b99b]
---

# Global expansion (worldwide)

Expand from Western Hemisphere to worldwide coverage. Infrastructure-first — ship global map/places/continent selector, data populates organically. Target: Romania conference summer 2026.

## Guiding Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Rollout model | Infrastructure-first, data-organic | Data will always be patchy outside NA. Ship the global map and let it fill in. |
| Territory classification | Pure geography, not politics | Réunion → Africa, not France. Ecology, not sovereignty. |
| Disputed territories | Follow Natural Earth defaults | Apply logic when edge cases arise. |
| Subdivision scope | Curated by ecological relevance | Most countries of meaningful size get subdivisions. |
| User region preference | localStorage, sticky continent selector | No accounts needed. Persists across sessions. |
| Host plant data | WCVP (already global) | Pipeline from WH expansion works as-is. |

## Work Streams

### Stream 0: Maps & Range Cleanup (b99b) — COMPLETE
Fixed bugs (list_places vs list_all_places, split_by_precision missing place_id, exclusion subtraction, ExclusionDrillDown semantics). Code quality improvements and test coverage added.

### Stream 1: Place Data Expansion — COMPLETE
8 continents, 249 countries, 4290 subdivisions in DB. Global PMTiles (4880 features, 370MB). All tests passing. Supersedes Western Hemisphere expansion (1db6).

### Stream 2: Continent Scoping UI
Sticky localStorage-backed continent selector in main header. Scopes ID tool and Search only. Browse/Explore and individual species pages stay global. No schema changes needed — purely query/UI layering.

**Scoped pages:** ID tool (gall results filtered by continent, place typeahead limited), Search (gall/host results filtered, glossary/source/taxonomy stay global).

**Global pages:** Explore/Browse, Family/Genus/Section, Gall/Host detail, Place, articles, keys, glossary.

**Implementation:** Header component with globe icon + continent name. JS hook for localStorage. Wire continent code into ID tool and Search query paths. "Showing all regions" indicator on global pages. Temporary override available without changing sticky preference.

### Stream 3: Data Sourcing
WCVP reconciliation for global hosts. Pipeline extends naturally from WH work.

### Stream 4: Branding/Messaging Updates

## Dependencies

- Stream 0 (b99b) → Stream 1 → Stream 2 (tiles) → Stream 3 (map JS)
- Stream 4 (continent selector) can parallel Streams 1-3

## Not In Scope

User accounts, UI localization, bulk data import, Eastern Hemisphere host data sourcing (WCVP already global).

## Open Questions

- Continent grouping for selector: 8 continents as-is or grouped (e.g., "Americas")?
- First-visit experience: modal, interstitial, or inline in ID tool?
- Map default view: user's continent or whole world when no range data?

## Territory Reference

Detailed Natural Earth investigation for 60+ overseas territories documented in docs/investigations/20260223-territory-boundary-extraction.md. Covers extraction methods, tricky mappings (BES→NLY, SJM→NSV), and multi-feature territories.
