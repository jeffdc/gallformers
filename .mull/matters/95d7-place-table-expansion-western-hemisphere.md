---
status: done
created: 2026-02-18
updated: 2026-02-20
epic: geo-expansion
docs: [docs/plans/2026-02-19-range-precision-design.md]
blocks: [1db6, 554e, 67e0]
needs: [4143]
---

# Place table expansion (Western Hemisphere)

## Summary

Expand the place table from 69 entries (US + Canada) to ~530 entries covering the entire Western Hemisphere. This is the data foundation for the Western Hemisphere expansion (1db6). Sequenced AFTER maps rework (4143) — maps UX validated first, then data expanded.

## Scope

### Data migration
- Add Western Hemisphere region row
- Add 3 new continents: Central America, Caribbean, South America (North America exists)
- Add ~33 new country entries
- Add ~430 new subdivision entries (states/provinces/departments) with ISO 3166-2 codes
- Wire all hierarchy links in place_hierarchy
- Fix existing orphan: Saint Pierre & Miquelon has no parent

### Hierarchy model
```
Western Hemisphere (region)
├── North America (continent) — exists, needs parent link
│   ├── United States (country) → 52 subdivisions — exists
│   ├── Canada (country) → 13 subdivisions — exists
│   └── Mexico (country) → 32 subdivisions — NEW
├── Central America (continent) — NEW
│   ├── Belize → 6, Costa Rica → 7, El Salvador → 14
│   ├── Guatemala → 22, Honduras → 18, Nicaragua → 17, Panama → 14
├── Caribbean (continent) — NEW
│   ├── Cuba → 16, Dominican Republic → 32, Haiti → 10
│   ├── Small islands: country-level only (AG, BB, DM, GD, KN, LC, VC, JM, TT, BS)
│   └── Territories: country-level only (PR, VI, VG, KY, TC, BM, AW, CW, etc.)
├── South America (continent) — NEW
│   ├── Argentina → 24, Bolivia → 9, Brazil → 27, Chile → 16
│   ├── Colombia → 33, Ecuador → 24, Guyana → 10, Paraguay → 18
│   ├── Peru → 26, Suriname → 10, Uruguay → 19, Venezuela → 25
```

### Data source
Natural Earth 10m Admin-1 dataset. ISO 3166-2 codes nearly complete since NE v4.0. Build script fallback: COALESCE(iso_3166_2, adm1_code).

### Code changes needed
- list_places() rework — currently returns flat list of states/provinces. With 530 entries needs hierarchy-aware or parameterized queries
- ID tool place filter — flat dropdown becomes hierarchical or searchable typeahead
- Admin host range editing — map zoom should center on relevant geography, not always US
- Place admin UI — hierarchy editing (currently noted as unsupported)
- Test seeds — add representative WH places

### What does NOT change
- Range query logic in ranges.ex (joins by place_id, place-count agnostic)
- toggle/bulk place operations (work by place_id)
- Gall range computation (set logic, geography-agnostic)
- Place schema fields (name, code, type — all sufficient)
- Place type validation (continent, country, region already valid)

### Gotchas
- French overseas territories (GF, GP, MQ) appear as Admin-1 under France in NE — filter by geometry/ISO not country name
- Panama's 4 indigenous comarcas — verify presence in NE Admin-1
- Place codes shift from postal (CA, TX) to ISO 3166-2 (BR-SP, CO-ANT) — code field max:10 is sufficient
- Small Caribbean nations: subdivisions below ~5,000 km² get country-level treatment only

Select All button in host admin range map is useless (never a real use case); Deselect All does not work. Low priority, note for future cleanup.
