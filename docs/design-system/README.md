# Gallformers design system

The design system is how Gallformers looks and behaves: one set of tokens (color, type, space), one set of components built from them, and a few page patterns built from those. Every page, public and admin, is built from it. Anyone writing UI, person or agent, starts here.

## The documents

| Document | What it holds |
|---|---|
| [foundations.md](foundations.md) | Principles, color, typography, spacing and density, layout, radius and elevation, icons, motion, dark mode, accessibility. The tokens and the rules for using them. |
| [components.md](components.md) | The component catalog: each component's job, when to use it and when not, its attributes and slots, and what it replaces. |
| [patterns.md](patterns.md) | Page templates (detail, collection, admin dashboard, admin list, admin edit, review step) and interaction patterns (saving, empty states, confirmations, loading). |
| [content.md](content.md) | Words on screen: voice, the domain's terms, labels, numbers and dates. |
| [mockups.md](mockups.md) | How to make a mockup in the system's own language. |

The living reference is the style guide page at `/dev/design-system` (development only; `dev/gallformers_web/dev/design_system_live.ex`). It renders every token and every built component in light and dark, with its code. When a component is built, it gets an entry there.

## Five rules

1. **Use a component before writing markup.** Look in [components.md](components.md). If a component almost fits, extend it. If none fits, propose one (below); don't hand-roll a card, table, header or button.
2. **Style with tokens, never raw values.** Colors are semantic (`text-ink`, `bg-surface`, `border-line`, `text-ok`), sizes are semantic (`text-section`, `text-meta`), and radius, shadow and widths come from tokens. No Tailwind palette colors (`text-gray-500`), no default type scale (`text-sm`), no hex values, no `dark:` variants, no arbitrary values (`top-[78px]`).
3. **Density comes from context, not from each element.** Public pages read at the Reading density; the admin shell sets the Working density. Components size themselves from it. Don't shrink one table by hand.
4. **Structure means something.** A card is a separate object, not a page region; a section is a heading on a rule. Color marks state or action, never decoration. A chip has a fixed meaning.
5. **Write in the curator's words.** Name things the way gallformers' users and the literature do. See [content.md](content.md).

## Where things live

| What | Where |
|---|---|
| Tokens (raw values, light and dark, densities, Tailwind mapping) | `assets/css/system/tokens.css` |
| Typefaces | `assets/css/system/fonts.css`, files in `priv/static/fonts/` |
| Element defaults (`@layer base`) | `assets/css/system/base.css` |
| Component styles (`@layer components`) | `assets/css/system/components.css` |
| Components (HEEx function components) | `lib/gallformers_web/components/` (see the catalog for each one's module) |
| Conformance check | `GallformersWeb.DesignSystem.Conformance`, its test, and the baseline `test/support/design_system_baseline.json` |

All stylesheet rules live in a cascade layer (`base` or `components`), so a utility class on an element always wins over them. Keep it that way: an unlayered rule silently overrides every template.

## Replacing a component

Nothing is replaced on its look alone. Before a component replaces another (or a page moves onto the system):

1. Read its entry in [components.md](components.md) and the code: every call site, and the events, URL parameters, hooks and tests each relies on.
2. The replacement keeps every behavior it finds there. Typeaheads in particular keep their exact mechanics: their look may change, their behavior may not.
3. A behavior change (even a fix) needs approval; record it, with who approved it and when, in the component's entry in [components.md](components.md).
4. Prefer changing markup around unchanged logic: a page's events, URL parameters and handlers stay as they are, and only its template moves onto the components.

## Adding to the system

1. Check the catalog and the style guide. Most needs are a variant of something that exists.
2. If something new is needed, write its entry in [components.md](components.md) (job, when to use, attributes, what it replaces) and get approval before building it. New UI patterns need explicit approval.
3. Build it with a component test, give it a style guide entry, and use tokens only.
4. A new token goes in `tokens.css` with light and dark values and a line in [foundations.md](foundations.md).

## The conformance ratchet

`test/gallformers_web/design_system/conformance_test.exs` scans templates and stylesheets for off-system styling and compares each file with a baseline. It fails when:

- a file has more off-system styling than its baseline, or a new file has any. The failure lists each line and the system's replacement. Fix the code; don't raise the baseline.
- a file has less than its baseline. Lock the improvement in with `mix gallformers.design_system.baseline`.

The baseline holds the migration backlog. It only goes down.

## Status

The system is in place on every page, public and admin.

- Foundations: tokens (light and dark, two densities), typefaces, cascade layering, the conformance check.
- The catalog was approved on 2026-11-04; each entry's status is in [components.md](components.md). Still Approved, not built: `range_map` (rework), `pagination` (restyle), `typeahead` (consolidate), `save_bar`, `toast` (restyle), `skeleton` and `spinner`, and `button`'s `link` extension.
- The conformance baseline holds four files: the root layout, the conformance check itself, the admin profile page and the read-only-mode plug.
