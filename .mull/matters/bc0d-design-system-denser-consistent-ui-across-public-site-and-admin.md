---
status: raw
created: 2026-11-04
updated: 2026-11-04
epic: design
relates: [f14c, 6611]
---

# Design system: denser, consistent UI across public site and admin

Jeff wants an improved (not redesigned) look across gallformers.org and the admin: less unnecessary whitespace, better information density, less awkward layout, and the new admin screens much less janky. The end product is a published design system that all future UI/UX work follows.

## Round 1 (2026-11-04): findings and direction

Artifact (private to Jeff): https://claude.ai/code/artifact/0089c292-87e3-4a67-aa5a-1fc70b8dbd97
Source: `docs/plans/design-system/` (gitignored). `python3 build.py` inlines the images into `design-direction.html`; republish that file to the same URL. `shoot.js` and `measure.js` take screenshots and measurements of the running local server through Playwright Firefox (`assets/node_modules/playwright-core`); the dev auth bypass lets them reach admin.

### Root cause found
The base `h1`–`h6` sizes, the global `a` color (Bootstrap `#0d6efd`) and every `.gf-*` class in `assets/css/app.css` sit outside Tailwind's cascade layers. Unlayered CSS beats layered CSS whatever the specificity, so Tailwind classes on those elements are ignored. Example: the admin title band `<h1 class="text-lg">` (layouts.ex ~598) renders at 40px. 87 of 126 headings and 78 links that set their own color are overridden. The fix is to move those rules into `@layer base` / `@layer components`, then review the pages that came to rely on the big sizes.

### Measured findings (1440×900)
- Sticky header 78px plus fixed footer 40px = 118px on every screen. Review steps add a 77px sticky step bar (195px, 22%). Admin content starts around 210px down: header, admin nav, title band.
- Admin sections are cards with a 69px sky-blue band holding a 28px heading. Admin Gall edit nests a card in a card.
- Table rows are 41px, 57px or 81–105px for similar lists. Some columns are empty in every row (Genus common name, synonymy Notes, Sources Kind/Updated).
- Width goes unused: Browse Galls is one narrow column; a Source's Galls fill a one-column, full-width table.
- Gall and Host pages have no `<h1>`. The title color varies by page.
- On a phone, the Gall photo comes after the traits, the map and the synonymy.
- In code: 4 card versions, 3 table routes, 4 message patterns, 4 modal variants, 6 public title patterns. 122 raw buttons. 118 color utilities. Unused width tokens and semantic text classes. No dark mode; `data-theme="light"` is hard-coded and unread.

### Proposed direction (pending Jeff's answers)
- Keep the brand: maroon, the sky header, autumn, League Spartan for brand and headings.
- Two densities from one set of tokens: Reading (public: 16px body, 36px rows) and Working (admin: 14px body, 32px rows).
- One page-header component.
- Sections are headings on a rule; cards only for separate objects.
- One table component.
- Admin form rows with labels on the left.
- One save model.
- Chips mean state.
- Sticky chrome no more than 100px; the footer is not fixed.
- Radius 4px for controls and 8px for panels; shadows only on things that float.

The mockups in the artifact cover the Gall page, admin Taxon edit (with a sidebar admin frame) and the admin Sources list.

### Open questions for Jeff
1. Source Sans 3 for text and data, with League Spartan kept for brand and headings? (Recommended: denser, with true italics for scientific names.)
2. Quoted Source text in a serif (Source Serif 4)?
3. Replace Bootstrap link blue with an ink blue from the palette? (Recommended.)
4. Unfix the footer? (Recommended.)
5. Admin navigation: a left sidebar (my lean) or a slim top bar?
6. Dark mode tokens now or later?
7. One admin save model: save as you go?

## Plan
- Round 2: put the tokens into app.css and fix the cascade layering. Build a living style guide page in the app with real components in both densities. Mock up the review flow, folding in Jeff's f14c ideas.
- Round 3: the shell (header, footer, admin layout), the Gall page, the one table component.
- Round 4: admin edit pages onto sections and form rows; the review steps.
- Publish: a design-system doc plus the style guide page; CLAUDE.md points to both.


## Decisions (Jeff, 2026-11-04)

1. Source Sans 3 for text and data; League Spartan for brand and headings. Decided.
2. Quoted Source text in Source Serif 4. Decided.
3. An ink blue for links, replacing Bootstrap blue. Decided.
4. The footer is no longer fixed. Decided.
5. Admin gets a left sidebar, plus a right rail for facts about the record (Jeff likes both in the Taxon edit mockup). Decided.
6. Dark mode is in the system now: every color is a token with light and dark values. Decided.
7. One admin save model: agreed there should be one, but which one is still open; Jeff is thinking. What bears on it:
   - Some saves write a version or an audit entry. Each save of the Gallformers note is a new dated version, and Facts are audited and replayed. Save-as-you-go would fill those histories with noise.
   - A rule that covers both: a single field saves at once, with a "Saved" note beside it. A change that writes a version, touches Facts or spans several fields collects in an "N unsaved changes · Save · Discard" bar.

## Information-rich Gall page and the map (2026-11-04)

The artifact's version 2 adds a whole-page mockup of `/gall/821` (Callirhytis quercuscornigera, agamic). The proposed page is about 1,440px long; today's is 3,262px. It shows:
- 14 Hosts as a four-column list under their own heading.
- Empty traits collapsed into one "Not recorded: …" line.
- The other generation linked beside the title.
- ID Notes pinned above the Sources; Sources run by year, one row each, and expand to the full excerpt.
- "Look further" links in place of the See Also logos.

Map: Jeff worries a small map is hard to read. He is considering a small map that opens a large map in a dialog, with full screen from there; still thinking. The mockup shows a 420px map card framed on the native range, with Enlarge opening a dialog (a "Map open" state).

Finding: the map hook frames everything it shades, introduced plantings included (`assets/js/hooks/range_map.js`: `fitToRange`, `WORLD_BOUNDS`). So a Host planted in Europe or New Zealand (Quercus rubra) pulls the map out to the whole world. Framing on the native range is what makes a small map readable, whatever size is chosen.

