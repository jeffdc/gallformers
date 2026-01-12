# Tasks: Adopt Phoenix + LiveView Architecture

## Decisions
- **Framework**: Phoenix + LiveView (replacing SvelteKit + Go)
- **Database**: Ecto with ecto_sqlite3
- **Interactivity**: LiveView for all dynamic features
- **Client-side**: JS hooks only for maps and complex uploads
- **Styling**: Tailwind CSS (ported from SvelteKit)
- **Auth**: Auth0 via ueberauth

## 0. Code Migration ✅

- [x] 0.1 Move existing `v2/` directory to `v2_old/`
- [x] 0.2 Create new `v2/` directory for Phoenix project
- [x] 0.3 Update root `CLAUDE.md` to reflect:
  - New v2 is Phoenix + LiveView + Ecto
  - v2_old contains the Go + SvelteKit implementation
  - v2_old serves as reference for porting and will be removed after migration

**Note**: We do NOT need separate documentation of routes and API endpoints (previous 0.2/0.3). The code in `v2_old/` IS the documentation - use it as reference when porting.

## 1. Foundation Setup ✅

### 1.1 Phoenix Project Bootstrap ✅
- [x] 1.1.1 Create new Phoenix project with `mix phx.new gallformers --database sqlite3`
- [x] 1.1.2 Configure ecto_sqlite3 to use existing database path
- [x] 1.1.3 Verify `mix phx.server` starts successfully
- [x] 1.1.4 Configure `.formatter.exs` for consistent code style

### 1.2 CI Pipeline ✅
- [x] 1.2.1 Add `mix format --check-formatted` to CI
- [x] 1.2.2 Add `mix test` to CI
- [x] 1.2.3 Add `mix credo` for code quality
- [x] 1.2.4 Add `mix dialyzer` for type checking

### 1.3 Documentation ✅
- [x] 1.3.1 Create `v2/CLAUDE.md` with:
  - Scope and isolation rules (stay in v2/)
  - Development commands (mix phx.server, etc.)
  - Reference to v2_old for porting guidance
  - Tailwind styling patterns (copy from current v2/CLAUDE.md)
  - LiveView patterns as they emerge

### 1.4 Tailwind Configuration ✅
- [x] 1.4.1 Copy custom colors from `v2_old/web/src/app.css` to Tailwind config
- [x] 1.4.2 Add `gf-maroon`, `gf-sky-blue`, `gf-autumn`, `cadet-blue`, `canary` colors
- [x] 1.4.3 Configure League Spartan font
- [x] 1.4.4 Port any custom utility classes from SvelteKit

### 1.5 Base Layout ✅
- [x] 1.5.1 Create `root.html.heex` with HTML skeleton, meta tags
- [x] 1.5.2 Create `app.html.heex` with site structure
- [x] 1.5.3 Create header component matching SvelteKit design
- [x] 1.5.4 Create footer component matching SvelteKit design
- [x] 1.5.5 Create navigation component

### 1.6 Static Assets ✅
- [x] 1.6.1 Copy favicon, apple-touch-icon from `v2_old/web/static/`
- [x] 1.6.2 Copy brand images (cynipid_R.svg, etc.)
- [x] 1.6.3 Configure static file serving with cache headers

## 2. First Deployment ✅

### 2.1 Fly.io Configuration ✅
- [x] 2.1.1 Create `fly.toml` for Phoenix app
- [x] 2.1.2 Configure SQLite volume mount
- [x] 2.1.3 Set environment variables (SECRET_KEY_BASE, DATABASE_PATH, LITESTREAM_*)
- [x] 2.1.4 Create release configuration in `mix.exs`
- [x] 2.1.5 Create `Dockerfile` for Phoenix release (with Litestream)
- [x] 2.1.6 Configure health check endpoint

### 2.2 Initial Deploy ✅
- [x] 2.2.1 Test Docker build locally
- [x] 2.2.2 Deploy to Fly.io (fixed Ecto migration skip, litestream permissions, SSL redirect)
- [x] 2.2.3 Verify site loads at https://gallformers.fly.dev/
- [ ] 2.2.4 Set up deployment pipeline for continuous deploys (deferred)

## 3. Home Page (Tracer Bullet)

Goal: Get the core site working with a real page. Once home page works, we have confidence.

### 3.1 Minimal Ecto Schemas ✅
- [x] 3.1.1 Create `Species` schema (just fields needed for home page)
- [x] 3.1.2 Create `Image` schema with S3 URL handling
- [x] 3.1.3 Create `Gallformers.Species` context with `random_gall/0` function

### 3.2 Home Page LiveView
- [x] 3.2.1 Create `HomeLive` - home page with random gall feature
- [x] 3.2.2 Verify visual parity with `v2_old/web/src/routes/+page.svelte`
- [ ] 3.2.3 Deploy and verify in production

**Milestone: Site is live with working home page**

## 4. Complete Ecto Schemas ✅

### 4.1 Core Schemas ✅
- [x] 4.1.1 Complete `Species` schema with all fields
- [x] 4.1.2 Create `Gall` schema with all fields and associations
- [x] 4.1.3 Create `Host` schema with all fields
- [x] 4.1.4 Create `Taxonomy` schema with parent relationship
- [x] 4.1.5 Create `Source` schema
- [x] 4.1.6 Create `Glossary` schema

### 4.2 Join Tables ✅
- [x] 4.2.1 Map `specieshosts` join table
- [x] 4.2.2 Map `gallhost` join table
- [x] 4.2.3 Map filter field join tables (colors, shapes, textures, etc.)
- [x] 4.2.4 Map `speciesplace` for range data

### 4.3 Filter Fields ✅
- [x] 4.3.1 Create schemas for filter field tables (color, shape, texture, etc.)
- [x] 4.3.2 Create associations from Gall to filter fields

### 4.4 Contexts ✅
- [x] 4.4.1 Create `Gallformers.Species` context with CRUD functions
- [x] 4.4.2 Create `Gallformers.Hosts` context
- [x] 4.4.3 Create `Gallformers.Taxonomy` context
- [x] 4.4.4 Create `Gallformers.Glossary` context
- [x] 4.4.5 Create `Gallformers.Sources` context
- [x] 4.4.6 Create `Gallformers.Search` context
- [x] 4.4.7 Create `Gallformers.IDTool` context with filtering logic

## 5. Shared Components ✅

### 5.1 UI Components ✅
- [x] 5.1.1 Create `card` component matching SvelteKit style
- [x] 5.1.2 Create `loading_spinner` component
- [x] 5.1.3 Create `error_message` component
- [x] 5.1.4 Create `pagination` component
- [x] 5.1.5 Create `alert` component (success, error, info)
- [x] 5.1.6 Create `info_tip` tooltip component

### 5.2 Form Components ✅
- [x] 5.2.1 Create `input` component with error display
- [x] 5.2.2 Create `textarea` component
- [x] 5.2.3 Create `select` component
- [x] 5.2.4 Create `checkbox` component
- [x] 5.2.5 Create `button` component with variants

### 5.3 Data Display Components ✅
- [x] 5.3.1 Create `image_gallery` component with lazy loading
- [x] 5.3.2 Create `species_card` component
- [x] 5.3.3 Create `host_list` component
- [x] 5.3.4 Create `source_citation` component
- [x] 5.3.5 Create `taxonomy_breadcrumb` component
- [x] 5.3.6 Create `data_completeness_indicator` component
- [x] 5.3.7 Create `edit_button` component (for admin links)

## 6. Public Pages (LiveViews)

Build one page at a time, deploy after each, verify visual parity.

### 6.1 Content Pages
- [x] 6.1.1 Create `AboutLive` - about page
- [x] 6.1.2 Create `FilterGuideLive` - filter guide page
- [x] 6.1.3 Create `ResourcesLive` - resources page
- [x] 6.1.4 Create `GlossaryLive` - glossary with sorting
- [x] 6.1.5 Create `RefIndexLive` - reference article index

### 6.2 Entity Pages
- [x] 6.2.1 Create `GallLive` - gall/species detail page
- [x] 6.2.2 Create `HostLive` - host detail page
- [x] 6.2.3 Create `FamilyLive` - family listing page
- [x] 6.2.4 Create `GenusLive` - genus listing page
- [x] 6.2.5 Create `SourceLive` - source detail page
- [x] 6.2.6 Create `SectionLive` - section listing page
- [x] 6.2.7 Create `PlaceLive` - place detail page

### 6.3 Error Pages
- [x] 6.3.1 Create custom 404 page matching site design
- [x] 6.3.2 Create custom 500 page matching site design
- [x] 6.3.3 Configure error view in endpoint

## 7. Search (LiveView) ✅

- [x] 7.1 Create `SearchLive` with search input
- [x] 7.2 Implement `handle_event("search", ...)` with debounce
- [x] 7.3 Display results grouped by type (galls, hosts, sources)
- [x] 7.4 Add keyboard navigation for results
- [x] 7.5 Implement URL sync with `push_patch`

## 8. ID Tool (LiveView)

- [x] 8.1 Create `IDLive` with filter form
- [x] 8.2 Implement `handle_params` for URL-based filter state
- [x] 8.3 Implement filter change handlers with `push_patch`
- [x] 8.4 Create results grid component
- [x] 8.5 Implement host picker (LiveView typeahead)
- [x] 8.6 Implement genus picker (LiveView typeahead)
- [x] 8.7 Port all filter options (color, shape, texture, location, etc.)
- [x] 8.8 Test back/forward navigation preserves filters

## 9. Explore Page (LiveView) ✅

- [x] 9.1 Create `ExploreLive` with browse options
- [x] 9.2 Implement browse-by-family
- [x] 9.3 Implement browse-by-host
- [x] 9.4 Tree expand/collapse handles large datasets (no pagination needed)

## 10. Range Map (JS Hook)

- [x] 10.1 Create `RangeMap` hook in `assets/js/hooks/range_map.js`
- [x] 10.2 Configure D3.js (used instead of MapLibre to match v2_old implementation)
- [x] 10.3 Implement `mounted()` to initialize map with data
- [x] 10.4 Implement `updated()` to handle data changes
- [x] 10.5 Style map to match current design
- [x] 10.6 Create HEEx component `range_map` with hook binding
- [x] 10.7 Test with real range data

## 11. Admin Pages (LiveView)

### 11.1 Admin Foundation ✅
- [x] 11.1.1 Configure Auth0 with ueberauth_auth0
- [x] 11.1.2 Create `Gallformers.Accounts` context
- [x] 11.1.3 Create admin authentication plugs
- [x] 11.1.4 Create admin layout with navigation
- [x] 11.1.5 Create `AdminDashboardLive`

### 11.2 Species Admin
- [ ] 11.2.1 Create `Admin.SpeciesLive.Index` with listing and search
- [ ] 11.2.2 Create `Admin.SpeciesLive.Form` for create/edit
- [ ] 11.2.3 Implement changeset validation with error display
- [ ] 11.2.4 Create alias/synonym editor (LiveView list management)
- [ ] 11.2.5 Create host association editor
- [ ] 11.2.6 Add PubSub broadcast on save

### 11.3 Host Admin
- [ ] 11.3.1 Create `Admin.HostLive.Index`
- [ ] 11.3.2 Create `Admin.HostLive.Form`
- [ ] 11.3.3 Add PubSub broadcast on save

### 11.4 Taxonomy Admin
- [ ] 11.4.1 Create `Admin.TaxonomyLive.Index`
- [ ] 11.4.2 Create `Admin.TaxonomyLive.Form`
- [ ] 11.4.3 Handle parent taxonomy selection

### 11.5 Other Admin Pages
- [ ] 11.5.1 Create source admin pages
- [ ] 11.5.2 Create glossary admin pages
- [ ] 11.5.3 Create place admin pages

### 11.6 Image Management
- [ ] 11.6.1 Create `ImageUpload` hook for drag-drop upload
- [ ] 11.6.2 Implement S3 upload flow (presigned URLs)
- [ ] 11.6.3 Create image reordering with LiveView
- [ ] 11.6.4 Implement image deletion with confirmation

## 12. Real-time Updates (PubSub)

- [ ] 12.1 Configure PubSub in application supervision tree
- [ ] 12.2 Create broadcast helpers in contexts
- [ ] 12.3 Subscribe to entity updates in public LiveViews
- [ ] 12.4 Handle `:entity_updated` messages to refresh assigns
- [ ] 12.5 Test admin edit → public page auto-update

## 13. Public API

### 13.1 API Foundation
- [ ] 13.1.1 Create API router scope with JSON pipeline
- [ ] 13.1.2 Configure CORS for API routes
- [ ] 13.1.3 Create API error view (JSON format per v2_old pattern)

### 13.2 Public Read Endpoints
Port endpoints matching v2_old patterns (see `v2_old/api/internal/handlers/`):

- [ ] 13.2.1 GET /api/v2/species (list with pagination)
- [ ] 13.2.2 GET /api/v2/species/:id
- [ ] 13.2.3 GET /api/v2/galls (list with filtering)
- [ ] 13.2.4 GET /api/v2/galls/:id
- [ ] 13.2.5 GET /api/v2/galls/random (home page feature)
- [ ] 13.2.6 GET /api/v2/galls/id (ID tool filtering)
- [ ] 13.2.7 GET /api/v2/galls/:id/images
- [ ] 13.2.8 GET /api/v2/galls/:id/related
- [ ] 13.2.9 GET /api/v2/hosts (list with pagination)
- [ ] 13.2.10 GET /api/v2/hosts/:id
- [ ] 13.2.11 GET /api/v2/taxonomy
- [ ] 13.2.12 GET /api/v2/sources (list with pagination)
- [ ] 13.2.13 GET /api/v2/sources/:id
- [ ] 13.2.14 GET /api/v2/sources/by-title/:title
- [ ] 13.2.15 GET /api/v2/glossary
- [ ] 13.2.16 GET /api/v2/glossary/:id
- [ ] 13.2.17 GET /api/v2/glossary/by-word/:word
- [ ] 13.2.18 GET /api/v2/places
- [ ] 13.2.19 GET /api/v2/places/:id
- [ ] 13.2.20 GET /api/v2/places/by-name/:name
- [ ] 13.2.21 GET /api/v2/filter-fields (list types)
- [ ] 13.2.22 GET /api/v2/filter-fields/:type
- [ ] 13.2.23 GET /api/v2/filter-fields/:type/:id
- [ ] 13.2.24 GET /api/v2/speciessources
- [ ] 13.2.25 GET /api/v2/gallhosts
- [ ] 13.2.26 GET /api/v2/search
- [ ] 13.2.27 GET /api/v2/explore
- [ ] 13.2.28 GET /api/v2/stats

### 13.3 API Documentation
- [ ] 13.3.1 Add open_api_spex dependency
- [ ] 13.3.2 Define OpenAPI schemas for all response types
- [ ] 13.3.3 Add OpenAPI operation specs to controllers
- [ ] 13.3.4 Serve Swagger UI at /api/docs (with testable endpoints)
- [ ] 13.3.5 Serve openapi.json at /api/docs/openapi.json

### 13.4 Rate Limiting
- [ ] 13.4.1 Add rate limiting library (Hammer or ExRated)
- [ ] 13.4.2 Configure limits: 100 req/min for public reads
- [ ] 13.4.3 Return 429 with Retry-After header when exceeded

## 14. SEO

- [ ] 14.1 Create `meta_tags` component for title, description, canonical
- [ ] 14.2 Create `og_tags` component for Open Graph
- [ ] 14.3 Add meta tags to all public pages
- [ ] 14.4 Create `/sitemap.xml` route with all public URLs
- [ ] 14.5 Create `/robots.txt` (allow public, disallow admin)
- [ ] 14.6 Add JSON-LD structured data to species pages

## 15. Markdown & Glossary

- [x] 15.1 Add earmark or mdex dependency
- [x] 15.2 Create `Gallformers.Markdown` module
- [x] 15.3 Implement glossary term auto-linking
- [x] 15.4 Cache compiled markdown in ETS or process state
- [x] 15.5 Test markdown rendering in source descriptions

## 16. Testing

### 16.1 Unit Tests
- [ ] 16.1.1 Test Ecto schemas and changesets
- [ ] 16.1.2 Test context functions
- [ ] 16.1.3 Test markdown processing
- [ ] 16.1.4 Test glossary linking

### 16.2 LiveView Tests
- [ ] 16.2.1 Test public page LiveViews render correctly
- [ ] 16.2.2 Test search LiveView events
- [ ] 16.2.3 Test ID tool filter events
- [ ] 16.2.4 Test admin form submission

### 16.3 Integration Tests
- [ ] 16.3.1 Test full page load flows
- [ ] 16.3.2 Test authentication flow
- [ ] 16.3.3 Test PubSub broadcast → LiveView update

### 16.4 API Tests
- [ ] 16.4.1 Test API endpoints return correct JSON
- [ ] 16.4.2 Test API error responses
- [ ] 16.4.3 Test CORS headers

## 17. Visual Parity Verification

- [ ] 17.1 Compare home page side-by-side with v2_old
- [ ] 17.2 Compare gall/species pages side-by-side
- [ ] 17.3 Compare host pages side-by-side
- [ ] 17.4 Compare family/genus pages side-by-side
- [ ] 17.5 Compare search results side-by-side
- [ ] 17.6 Compare ID tool side-by-side
- [ ] 17.7 Compare admin pages side-by-side
- [ ] 17.8 Test responsive layout at mobile/tablet/desktop breakpoints
- [ ] 17.9 Sign-off: all pages achieve visual parity

## 18. Cleanup (only after 17.9 complete)

- [ ] 18.1 Remove `v2_old/` directory
- [ ] 18.2 Update `v2/CLAUDE.md` - remove references to v2_old
- [ ] 18.3 Update root `CLAUDE.md` - remove v2_old section
- [ ] 18.4 Archive `adopt-templ-htmx` proposal
- [ ] 18.5 Archive `convert-v2-to-spa` proposal

## 19. Documentation Updates

- [ ] 19.1 Document LiveView patterns in CLAUDE.md
- [ ] 19.2 Document component library
- [ ] 19.3 Document PubSub patterns for real-time
- [ ] 19.4 Document deployment process
- [ ] 19.5 Document local development setup

## Dependencies

```
Phase 0 (Migration) - no dependencies
Phase 1 (Foundation + CI) - depends on Phase 0
Phase 2 (First Deploy) - depends on Phase 1
Phase 3 (Home Page) - depends on Phases 1, 2
Phase 4 (Schemas) - depends on Phase 3
Phase 5 (Components) - depends on Phase 1
Phase 6 (Public Pages) - depends on Phases 4, 5
Phase 7-9 (Search, ID Tool, Explore) - depends on Phase 6
Phase 10 (Range Map) - can parallel with Phases 6-9
Phase 11 (Admin) - depends on Phase 6
Phase 12 (PubSub) - depends on Phase 11
Phase 13 (API) - depends on Phase 4
Phase 14 (SEO) - depends on Phase 6
Phase 15 (Markdown) - can parallel with Phase 6
Phase 16 (Testing) - parallel with all phases
Phase 17 (Visual Parity) - depends on all UI phases
Phase 18 (Cleanup) - depends on Phase 17
```

## Parallelizable Work

After Phase 2 (first deploy):
- Ecto schemas (Phase 4)
- Shared components (Phase 5)
- Markdown processing (Phase 15)
- Range map hook (Phase 10)

After Phase 6 public pages:
- Search LiveView (Phase 7)
- ID Tool LiveView (Phase 8)
- Admin pages (Phase 11)
- API endpoints (Phase 13)
- SEO (Phase 14)

## Key Principles

1. **Deploy early, deploy often** - Get something running in prod ASAP
2. **One page at a time** - Build, deploy, verify visual parity, then move on
3. **v2_old is the spec** - Reference the existing code, don't create separate docs
4. **CI from day one** - Catch issues early
5. **Home page first** - Proves the architecture works end-to-end

## Future Enhancements (Post-Launch)

- [ ] 20.1 Add LiveView streams for large lists (performance)
- [ ] 20.2 Add offline indicator (detect WebSocket disconnect)
- [ ] 20.3 Add caching layer (ETS) for frequently accessed data
- [ ] 20.4 Add metrics/telemetry for performance monitoring

### 20.5 Admin Write API Endpoints (authenticated)
- [ ] 20.5.1 POST/PUT/DELETE /api/v2/galls
- [ ] 20.5.2 POST/PUT/DELETE /api/v2/hosts
- [ ] 20.5.3 POST/PUT/DELETE /api/v2/sources
- [ ] 20.5.4 POST/PUT/DELETE /api/v2/glossary
- [ ] 20.5.5 POST/PUT/DELETE /api/v2/places
- [ ] 20.5.6 POST/PUT/DELETE /api/v2/filter-fields
- [ ] 20.5.7 POST/DELETE /api/v2/speciessources
- [ ] 20.5.8 POST/DELETE /api/v2/gallhosts

### 20.6 Auth API Endpoints
- [ ] 20.6.1 GET /api/v2/auth/login
- [ ] 20.6.2 GET /api/v2/auth/callback
- [ ] 20.6.3 POST /api/v2/auth/refresh
- [ ] 20.6.4 POST /api/v2/auth/logout
