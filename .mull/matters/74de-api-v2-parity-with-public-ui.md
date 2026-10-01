---
status: refined
created: 2026-03-02
updated: 2026-09-13
epic: platform
---

# API v2 parity with public UI

## Audit (2026-03-02)

### High — Missing data on detail endpoints
- No taxonomy (family/genus/section) on `GET /galls/:id` or `GET /hosts/:id`
- No aliases on host responses (common names + synonymy)
- No `GET /hosts/:id/sources` endpoint

### Medium — Partial data
- No host abundance in API responses
- No inherited vs direct range distinction (API flattens to `places` + `excludedPlaces`)
- Gall sources response missing `license`/`licenselink` fields

### Low — Nice-to-haves
- No related galls, no `gallformers_code`, no source images, no genus species counts

### Behavioral inconsistencies
- `GET /galls/:id/images` returns `[]` for nonexistent gall (should 404 like host images)
- Host list items much sparser than gall list items (no abundance, aliases, etc.)

### Test gaps (fix alongside data gaps)
- 4 controllers completely untested: Source, Glossary, Place, Stats
- 3 taxonomy detail endpoints untested: families/:id, genera/:id, sections/:id
- `?simple=true` param untested on host endpoints
