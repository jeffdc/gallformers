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

### Format

Uses `###` markdown headings for section labels. Species name as `##` heading with taxonomic status (sp. nov., syn. nov., etc.) when applicable. Latin names italicized.

### Sections (in order, all optional)

1. **Name** (`##` heading) — Species name as used by the source, with taxonomic status. E.g., `## *Pseudoneuroterus saltabundus* Sottile & Cerasa sp. nov.`
2. **Synonyms** — The author's synonym list, as given.
3. **Gall** — Gall morphology, measurements, appearance. Verbatim from source — no wasp/adult insect anatomy.
4. **Host** — Host plant listing. Modern name corrections in `[brackets]` when the source uses an outdated name.
5. **Range** — Geographic distribution.
6. **Phenology** — Timing, emergence, seasonality.
7. **Comments** — Ecology, taxonomic notes, similar galls. Editorial commentary in `[square brackets]`.

### Key principles

- **Direct quotation.** Text outside `[square brackets]` is verbatim from the source. The LLM selects and structures relevant passages but does not paraphrase, summarize, or rephrase. This is attributed to the source author, not the editor.
- **`[Square brackets]` are editor-only.** Only the human editor adds bracketed commentary — corrections to outdated host names, cross-references to other GF entries, taxonomic context the source doesn't provide. The LLM should not generate editorial commentary; it lacks the domain context to do so meaningfully.
- **No insect morphology.** Adult wasp anatomy (antenna segments, mesoscutum sculpture, etc.) is stripped. Only gall descriptions are included.
- **Sparse entries are fine.** A species mentioned only in a table might have just Host, Range, and Phenology. The template compresses naturally.
- **Table extraction.** When a source includes a summary table of species with host/range/phenology data, the LLM extracts each species into its own entry. This is one of the highest-value uses of the tool.

### Worked example

Source: Sottile S., Nicholls J.A., Tang C-T., Stone G.N. & Cerasa G. 2026. Description of *Pseudoneuroterus saltabundus* new species (Hymenoptera: Cynipidae: Cynipini) with jumping galls from Italy and revised keys to Western Palaearctic Cynipini genera lacking transscutal articulation. European Journal of Taxonomy 1039: 219–250. https://doi.org/10.5852/ejt.2026.1039.3193

This paper describes one new species and provides a table summarizing biology, distribution, host plants, and emergence times for all five *Pseudoneuroterus* species. The LLM extracts entries for each.

---

#### Full entry (new species, rich data)

## *Pseudoneuroterus saltabundus* Sottile & Cerasa sp. nov.

### Gall
The gall typically develops on the lower surface of *Q. cerris* leaves along the secondary veins, although in rare cases it has been observed on the upper surface as well; in the presence of 4–6 closely spaced galls, complete deformation and bending of the leaf lamina may occur. At the point of insertion, an invagination of the leaf blade is observed, while no conspicuous structures are present at the corresponding point on the upper surface, but rather a translucent 'spot'. At the insertion point, a thin membranous lamina expands in a fan-like manner and envelops the gall like a small shell; it is covered with star-shaped hairs similar to those on the leaf. This laminar structure is present only on one side of the gall and may perform a protective function in the early stages of gall development. In the mature gall, the lamina remains vestigial, reaching up to ¼, rarely ⅓ of its height. In rare cases, the lamina develops into a ribbon-like structure that encircles the gall. The lamina remains attached to the leaf after the main gall detaches, providing a remnant of the gall's presence.

The main gall has a sub-globular ellipsoid shape, with a glabrous surface, traversed by very slight reliefs resembling venations (venulations). The thin (< 0.1 mm), leathery walls enclose a large larval chamber, excavated by the larva during the trophic phase. Typical dimensions are: longest side: 1.6–1.8 mm, shortest side: 1.3–1.5 mm, height: 1.4–1.6 mm. On the underside of the gall, the shape protrudes towards the point of insertion on the leaf blade; however, it is sessile with no peduncle present. The colour is whitish to pale green during development, and becomes light brown upon maturation.

### Host
*Quercus cerris* (Quercus section Cerris), the only known host species to date.

### Range
Northern Italy (Lombardy and Emilia-Romagna), peninsular Italy (Tuscany, Umbria, and Lazio) and Hungary.

### Phenology
Galls develop rapidly in late spring, between the end of May and mid-June, and generally complete development within approximately 7 to 10 days. Mature galls abscise from the leaf and remain in the moist litter during the following months. Agamic females emerge during the second half of January and early February of the following year.

### Comments
Only the asexual generation is known.

Rapid development and immediate abscission from the host leaf are likely advantageous traits favouring escape from parasitoid attack. Gall abscission is a process enhanced by the fully fed, mature larva, which is capable of performing rapid body extensions that facilitate detachment. The larva is positioned in a U-shaped posture within the gall chamber and, when externally stimulated, it abruptly extends its body, producing a rapid snapping motion. These contractions strike the internal walls of the gall, generating a distinct and audible "tick" sound perceptible to the human ear. The kinetic energy generated by these repeated strikes not only facilitates gall abscission, but also enables the remarkable jumping ability of the fallen galls, often exceeding distances of over 60 mm. The galls retain this jumping ability until September.

**Similar galls.** The asexual generation galls of *P. saltabundus* sp. nov. are similar in shape and size to the asexual generation galls of *Neuroterus anthracinus*, but while the galls of the latter exhibit two symmetrical lamellar valves at the base and possess a smooth and glossy surface with coloured maculae, the galls of the new species present only a single lateral lamella, and the surface is traversed by very slight elevations resembling venation and is matte. Moreover, the agamic generation of *N. anthracinus* develops in the late summer–autumn on section Quercus oaks, whereas those of *P. saltabundus* develop in late spring (late May–mid-June) on section Cerris oaks.

Asexual galls of *P. saltabundus* sp. nov. could be confused with those of its congener *P. saliens*. Galls of that species have a fusiform shape with a longer attachment base, larger dimensions, a smooth, almost shiny surface or with very fine parallel dorso-ventral striations, and develop along young stems or the leaf midrib. In contrast, *P. saltabundus* galls are rounder not fusiform, have a matte surface with characteristic venulation and typically develop on secondary veins. Additionally, *P. saliens* galls develop in autumn rather than spring. Both galls exhibit the ability to jump, although this behaviour is less pronounced in *P. saliens*.

---

#### Table-derived entry (sparse, from Table 1)

## *Pseudoneuroterus mazandarani* Melika & Stone, 2010

### Host
*Q. castaneifolia*

### Range
Iran, Mazandaran Province.

### Phenology
June (asexual generation).

---

## Open questions

- Which models balance quality, cost, and speed for this domain? Needs empirical testing.
- What's the right UX for the format button? Inline preview? Side-by-side diff? Replace-in-place with undo?
- What daily rate limit per user is reasonable? Depends on typical source entry patterns.
- When do later layers get proposed? After layer 1 is proven and community feedback is in.
