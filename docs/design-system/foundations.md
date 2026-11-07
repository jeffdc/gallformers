# Foundations

The values everything else is built from, and the rules for using them. The source of truth for every value is `assets/css/system/tokens.css`; this document explains them.

## Principles

- **Evolve, don't replace.** Gallformers keeps its maroon, its sky-blue header, its autumn orange and League Spartan. What changes is how much room things take and how consistently they behave.
- **Information first.** Curators and naturalists come to read and compare. Spend space on content, not chrome: no bands around headings, no cards around regions, no sticky chrome beyond what navigation needs.
- **One way to do each thing.** One page header, one table, one section, one dialog, one save model. Variants are explicit attributes, not copies.
- **Two densities, one system.** Reading for the public site, Working for admin. Same tokens, same components, different sizes.
- **Structure and color carry meaning.** Every border, fill, chip and color says something true about the content.

## Color

Colors are semantic tokens. Templates use the Tailwind utilities generated from them (`text-ink`, `bg-surface-2`, `border-line-strong`); CSS uses the variables (`var(--gf-ink)`). Each token has a light and a dark value.

### Brand

| Token | Utility | Light | Dark | Use for |
|---|---|---|---|---|
| `--gf-maroon` | `text-brand` | #661419 | #e48a8f | The wordmark, active navigation, brand text, the home page's display headline and the cynipid mark. Not other page titles, not links. |
| `--gf-maroon-fill` | `bg-brand-fill` | #661419 | #8c2a31 | The fill of the one primary action on a screen. |
| `--gf-maroon-hover` | `bg-brand-hover` | #4f0f13 | #a5343c | Hover on a primary action. |
| `--gf-sky` | `bg-sky` | #c1e0f3 | #1d3445 | The site header band, the home page's identify band, and selected rows. |
| `--gf-sky-soft` | `bg-sky-soft` | #eaf4fb | #172a37 | Info surfaces (ID Notes, notices) and row hover. |
| `--gf-autumn` | `bg-autumn`, `border-autumn` | #bc6428 | #e0915a | "Needs you": marks, dots, stripes, counts' fills. |
| `--gf-autumn-ink` | `text-autumn-ink` | #a0521d | #e0915a | "Needs you" as text (counts such as Review 358). |

### Text

| Token | Utility | Light | Dark | Use for |
|---|---|---|---|---|
| `--gf-ink` | `text-ink` | #1e1b1a | #ece7e4 | Primary text and page titles. |
| `--gf-ink-2` | `text-ink-2` | #4a4442 | #c9c1bd | Secondary text: excerpts, descriptions, values in a rail. |
| `--gf-muted` | `text-muted` | #736b68 | #9d9490 | Labels, captions, counts beside headings, placeholders, "not recorded". |
| `--gf-link` | `text-link` | #1c5d8f | #86bdea | Links. An ink blue tuned to the palette. |
| `--gf-on-fill` | `text-on-fill` | #ffffff | #ffffff | Text on a filled surface (primary button). |
| `--gf-overlay` | `bg-overlay` | ink at 55% | black at 65% | The backdrop behind a dialog. |

### Surfaces and rules

| Token | Utility | Light | Dark | Use for |
|---|---|---|---|---|
| `--gf-paper` | `bg-paper` | #fbfaf9 | #141213 | The page ground. |
| `--gf-surface` | `bg-surface` | #ffffff | #1c191a | Panels, inputs, tables, dialogs. |
| `--gf-surface-2` | `bg-surface-2` | #f4f1ef | #252122 | Wells, table heads, the admin sidebar. |
| `--gf-line` | `border-line` | #e6e1de | #322d2c | Hairlines between rows and around panels. |
| `--gf-line-strong` | `border-line-strong` | #d3ccc8 | #463f3d | Control borders and the rule under a section heading. |

### State

State colors mark state and nothing else. Each has a text color and a background meant to be used together.

| State | Utilities | Light text / bg | Dark text / bg | Means |
|---|---|---|---|---|
| OK | `text-ok bg-ok-bg` | #2d7a4b / #e5f2e9 | #7fcf9c / #17301f | Complete, approved, saved. |
| Warn | `text-warn bg-warn-bg` | #8a5a00 / #fbf0d6 | #e6b85c / #33280f | In progress, holds approval, needs a look. |
| Danger | `text-danger bg-danger-bg` | #a8281e / #fbe7e4 | #f08a7f / #3a1915 | Errors, destructive actions, conflicts. |
| Info | `text-info bg-info-bg` | #1c5d8f / #eaf4fb | #86bdea / #172a37 | Neutral notices. |

### Contrast

Measured (WCAG 2.1) in both themes. Every text pairing meets AA (4.5:1) for body text.

| Pair | Light | Dark |
|---|---|---|
| ink on paper | 16.4 | 15.2 |
| ink-2 on paper | 9.2 | 10.5 |
| muted on paper / on surface-2 | 5.0 / 4.6 | 6.3 / 5.4 |
| link on paper / on sky-soft | 6.7 / 6.3 | 9.3 / 7.4 |
| autumn-ink on paper | 5.4 | 7.4 |
| on-fill on maroon-fill | 12.5 | 8.4 |
| ok / warn / danger on their backgrounds | 4.6 / 5.2 / 5.9 | 7.6 / 7.8 / 6.5 |

`--gf-autumn` itself is 4.0:1 on paper: use it for marks and fills, and `autumn-ink` for text.

### Rules

- One primary action (maroon fill) per screen region. Everything else is a secondary or ghost button.
- Links are ink blue everywhere, including in Markdown. Navigation links inherit their own color from the navigation component.
- Don't use color alone to carry meaning: a state chip has a word in it.
- The range map's fills (`--gf-map-*`) are part of the map's legend and used only by the map.

## Typography

### Typefaces

| Face | Token / utility | Role |
|---|---|---|
| League Spartan | `--font-brand`, `font-brand` | Brand, navigation, page and section headings. Not for running text, data or scientific names: it has no true italic and sets wide. |
| Source Sans 3 | `--font-sans`, `font-sans` (the default) | All text, tables, forms and labels. True italics for scientific names; tabular figures for counts and years. |
| Source Serif 4 | `--font-serif`, `font-serif` | Only for what a Source wrote: quotes and excerpts on Gall pages, "The Source wrote" in review. It separates the literature from Gallformers' own words. |

All three are self-hosted (SIL Open Font License); nothing loads from a font service.

Scientific names are always italic. Inside a League Spartan heading, italics switch to Source Sans automatically (`base.css`), so a name in a heading gets true italics.

### Scale

Sizes are semantic and depend on the density context. Use the utility named for the role, never a raw size.

| Utility | Role | Reading | Working |
|---|---|---|---|
| `text-display` | The home page's one headline, in League Spartan and the brand color | 40–52px (by width) | — |
| `text-page` | The page title (h1) | 34px | 28px |
| `text-section` | A section heading (h2) | 22px | 19px |
| `text-subsection` | A heading inside a section (h3) | 18px | 16px |
| `text-lead` | An intro paragraph | 19px | 16px |
| `text-body` | Running text | 16px | 14px |
| `text-ui` | Table cells, list rows, controls | 15px | 14px |
| `text-meta` | Secondary lines, counts, metadata | 14px | 13px |
| `text-caption` | Captions, credits | 12px | 12px |

Weights: 400 for text, 600 for labels and emphasis, 650 for headings. Headings use `text-wrap: balance`. Running text stays within `max-w-text` (44rem, about 70 characters).

**Everything is in sentence case.** No all-caps and no tracked-out letter-spacing, on labels, table heads and chips alike; the conformance check flags `uppercase` and `tracking-wide`. Two label styles cover what small caps used to:

- **A label** beside or above its value (a label/value pair, a meta line): `text-meta text-muted`, as in `fact_list`.
- **A group heading** over a run of items (a table's column heads, a menu's or a result list's groups, a Facts category): `text-meta font-semibold text-muted`.

No small label above a heading (an "eyebrow"): the heading carries its own weight. What an eyebrow would say goes in the meta line under the heading, or nowhere.

The base stylesheet sizes `h1`–`h3` from this scale, so a bare `<h2>` is already a section heading. A class on a heading overrides it.

## Spacing and density

The density context sets sizes for everything inside it. Public pages use Reading (the default). The admin shell adds `gf-density-working`, which switches to Working.

| Token | Utility | Reading | Working | Use for |
|---|---|---|---|---|
| `--gf-row-h` | `h-row`, `min-h-row` | 36px | 32px | Table and list rows |
| `--gf-ctl-h` | `h-ctl` | 36px | 32px | Inputs, selects, buttons |
| `--gf-gap-section` | `gap-section`, `mt-section` | 32px | 22px | Between sections |
| `--gf-gap-block` | `gap-block` | 16px | 12px | Between blocks inside a section |
| `--gf-pad-panel` | `p-panel` | 16px | 12px | Inside a panel |
| `--gf-page-x` | `px-page-x` | 32px | 28px | Page side gutter on wide screens |

Inside a component, use Tailwind's 4px spacing scale (`gap-2`, `px-3`) for small internal gaps. Between page parts, use the semantic tokens, so density applies.

Lay out siblings with flex or grid and `gap`, not margins on each element.

## Layout

| Token | Utility | Value | Use for |
|---|---|---|---|
| `--container-page` | `max-w-page` | 120rem (1920px) | Public page content: fluid below that width |
| `--container-text` | `max-w-text` | 44rem | Running text, articles |
| `--container-lead` | `max-w-lead` | 56rem | A page header's description (about 100 characters at lead size, so a one-sentence description stays on one line) |
| `--container-form` | `max-w-form` | 48rem | A single-column admin form |

- **Public pages** fill the screen up to `max-w-page` (1920px) with `px-page-x` gutters (16px on phones). A wide screen shows more, never wider margins: photo grids add columns (`gf-photo-grid`), card grids add a column at `2xl`. Running text stays within `max-w-text`. Detail pages use a main column and a 420px rail; the rail stacks under the title on phones, with the photo first.
- **Admin pages** fill the space beside a 212px sidebar. Edit pages use a main column and a 300px rail for facts about the record.
- **Sticky chrome budget: 100px.** The public header is 64px, with a 48px logo, and Identify as its one filled button. The admin top bar is 44px (plus a 40px step bar on review steps). The footer is never fixed.
- Long lists of short names (families, Hosts, a Source's Galls) flow into columns instead of one narrow column.
- At phone width (about 400px) every row wraps or stacks; only tables, maps and code scroll sideways, each in its own container.

## Radius and elevation

| Token | Utility | Value | Use for |
|---|---|---|---|
| `--radius-ctl` | `rounded-ctl` | 4px | Controls, chips' square corners, kbd |
| `--radius-panel` | `rounded-panel` | 8px | Panels, images, dialogs, tables |
| — | `rounded-full` | — | Chips, avatars, dots |

Nothing else rounds. Elevation is flat: panels have a 1px `border-line`, not a shadow. Only things that float above the page (menus, popovers, dialogs, toasts) use `shadow-float`.

## Icons

Phosphor icons (`ph-*`, MIT) for interface actions and Gallformers' own domain icons (`gf-*`: gall, host, taxon, source, place) via the `.icon` component. Icons sit at 1em beside text and inherit its color. An icon-only button has an accessible label. Icons never replace a word where the word is clearer.

The cynipid mark (`cynipid_mark`) is not an icon: it is Gallformers' own drawing, used as decoration, once on a page at most.

## Motion

Motion explains a change: a row expanding, a dialog opening, an item leaving after a decision. Keep it under 200ms, ease-out, and never animate content into view on load. `prefers-reduced-motion` turns it off (`base.css`).

## Dark mode

Dark mode is on for the public site (2026-11-06). Every color is a token with a dark value.

- **How it switches.** With no theme chosen, the page follows the OS setting (`prefers-color-scheme`; `<html>` has no `data-theme`). The header's theme switch (`Layouts.theme_switch`: Match my device, Light, Dark) saves a choice as `gf-theme` in the browser and sets `data-theme` on `<html>`; the root layout's `#theme-init` script applies a saved choice before the page paints. `assets/js/theme.js` holds the logic.
- **Regions.** `data-theme="dark"` or `data-theme="light"` on any element sets that region's theme (the style guide previews components both ways). The admin follows the viewer's theme like every page, with the same switch in its top bar.
- **Light-only and dark-only content.** `gf-only-light` and `gf-only-dark` show an element in one theme only (the header's color and white wordmarks).
- Never use `dark:` variants. If a color is right in light and wrong in dark, the fix is a token. A component that still uses Tailwind's raw palette is wrong in dark: move it onto tokens before a public page uses it.
- The range map keeps its light basemap and fills in both themes; its legend uses the map tokens (`bg-map-documented`, `bg-map-country`, `bg-map-excluded`, `bg-map-none`).

## Accessibility

- Every page has exactly one `h1`: the page header's title. Section headings are `h2`, nested headings `h3`.
- Text pairings meet WCAG AA (see Contrast). Don't put muted text on a tinted surface other than surface-2.
- Focus is always visible: a 2px `--gf-focus` outline, offset 2px (`base.css`). Don't remove it.
- Interactive things look interactive: links are ink blue; buttons have a border or fill.
- Controls have labels; icon-only buttons have an `aria-label`; images have alt text, or `alt=""` when decorative.
- Targets are at least 32px tall in Working density and 36px in Reading.
