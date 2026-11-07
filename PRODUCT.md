# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **People identifying a gall.** Naturalists, from casual to burgeoning scientist to cecidologist, who have found a gall and want to know what it is and what induces it. They arrive with a Host, a plant part, a few visible Traits, a place and a season. This is the public site's main job.
- **Curators (admins).** Volunteer site administrators who catalog galls from the literature: reviewing imported Source statements, editing Galls, Hosts, Sources and taxonomy. Fewer people, heavier and more repetitive use; revision papers arrive in bursts of many merges and splits.
- **Researchers.** Scientists who cite Gallformers or pull its data through the public API and the daily database snapshot.

When needs conflict, public views win over admin views. Consistency between the two still matters a lot, because more of the admin is moving into the main (public) pages instead of living in a separate back office.

## Product Purpose

Gallformers (gallformers.org) is a website and database that helps people **identify** galls and **catalog** gall-inducing organisms. It aims to Source every Fact it states about a Gall. Success: a person with an unknown gall gets to the right Gall (or the lowest Taxon they can) and the literature behind it, and a curator can keep the catalog current with the literature quickly and safely.

## Positioning

What a neighboring site (iNaturalist, BugGuide, a regional gall guide) could not truthfully claim, all three together:

- **Breadth of catalog.** About 3,670 gallformer species across 86 families and 376 genera, including about 1,455 undescribed taxa, from every kingdom that induces galls (as of Feb 2026). Expanding from North America to the whole Western Hemisphere.
- **Sourced Facts.** Every Fact is attributed to at least one Source. The most recently authored Source wins; withdrawn and superseded Facts stay visible as history; retracted Sources are marked. Taxonomy follows the literature, with Gallformers as the authority only in rare exceptions.
- **Gall-first identification.** Identify from the gall itself (Host, plant part, Traits, place, season) instead of from the adult organism, plus dichotomous keys.

## Operating Context

- Public: Gall, Host, genus, section, Place and Source pages; browse pages; the ID tool; dichotomous keys; glossary; search; articles; public analytics.
- Admin: review queue for imported Source statements, the Gall page editor, taxonomy admin (rename, synonymize, merge, split), Source editor. Admin capabilities are increasingly surfaced on the public pages themselves.
- Data flows in from the literature (papers, books, BHL), POWO for Host taxonomy and ranges, and iNaturalist for Observations and photos. Data flows out through the public API, a daily PostgreSQL snapshot, and citations.
- The domain language (Gall, Host, Inducer, Source, Fact, Trait, Observation, Generation) is defined in `docs/domain/domain-model.md`; on-screen wording follows `docs/design-system/content.md`.

## Capabilities and Constraints

- **The design system is the visual authority.** `docs/design-system/` (start at its README) owns every visual and component decision: semantic tokens in `assets/css/system/tokens.css`, the component catalog in `components.md` (components in `lib/gallformers_web/components/`), page patterns, content rules, and the living style guide at `/dev/design-system`. It has two densities (Reading for public, Working for admin), and `test/gallformers_web/design_system/conformance_test.exs` fails on off-system styling. All UI work uses its components and tokens; a new component, pattern or token needs Jeff's approval first. Don't treat a missing DESIGN.md as a missing design system.
- Existing Phoenix LiveView codebase.
- "Gallformer" is the on-screen noun for the inducing organism. Domain concepts are capitalized when they mean the thing in Gallformers. Scientific names are italic at genus and below, with authors and generation upright.
- Image licenses and Source attributions must always be shown. Nothing is presented without credit.
- Roadmap, not yet built: Western Hemisphere expansion, iNaturalist integration (photos, observed range), DNA barcodes, gall associates (Parasitoids, Inquilines and the wider Gall Community), a mobile-first offline ID tool, GBIF/DarwinCore/Wikidata/DOIs, open contribution pathways. Field use on phones is not yet a binding design constraint.

## Brand Commitments

- Name: Gallformers. Logo (an oak gall wasp with a spherical oak gall and a white oak leaf) in color, black and white at `priv/static/branding/Wide Logo Versions/`; League Spartan in `priv/static/branding/Font/`. (`priv/static/images/logo.svg` is Phoenix's default, not the brand.) Stipple-style cynipid drawings at `priv/static/images/cynipid.svg`, `cynipid_L.svg`, `cynipid_R.svg`. Original content released under CC-BY 4.0; open source on GitHub (jeffdc/gallformers).
- Voice: written for naturalists and curators who know galls, Hosts and the literature. Plain, specific, active, no filler, no exclamation marks. The About page keeps a dry, warm amateur's humor ("touched, if not bitten, by the gall bug"); the catalog itself stays factual.
- Non-commercial tone: a grant- and Patreon-funded volunteer project. No marketing gloss, no upsell patterns, no dark patterns.
- Visual identity is recorded in the design system (`docs/design-system/foundations.md`), not here.

## Evidence on Hand

- Catalog figures from the Feb 2026 roadmap (`docs/presentations/2026-02-roadmap-v3.md`): launched May 2021 with about 100 species; about 3,670 species, 1,455 undescribed taxa, 6,500+ images by Feb 2026.
- Support: National Science Foundation Grant No. 2418250; Patreon supporters; a named list of volunteer administrators (rendered on the About page).
- Licensed photos contributed by individuals, each with a documented license; Source citations throughout the catalog.
- Public API with interactive docs; daily database snapshot download; public analytics page.
- No testimonials, user counts, press or partner logos are recorded. Don't invent any.

## Product Principles

1. **Public first, one system.** Public views take priority, but public and admin pages share the same components and behavior, so an admin control on a public page feels native.
2. **Every claim has a Source.** Show where a Fact comes from and when it changed. Attribution and licensing are part of the content, not fine print.
3. **Start from the gall in hand.** Identification works from what a person can see and knows about the find (Host, plant part, Traits, place, season), and an answer at genus or family still counts.
4. **The literature's words.** Name things the way gall researchers and the catalog do, not the way the software does.
5. **Quiet, credible, non-commercial.** A reference people cite. Information first; nothing that sells.

## Accessibility & Inclusion

WCAG 2.2 AA is the required standard for public and admin pages, in light and dark themes.
