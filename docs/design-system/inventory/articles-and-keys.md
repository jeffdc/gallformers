# Inventory: the Articles and Keys pages

The behavior contract for the Articles list (`/articles`, `ArticlesController`), an article (`/articles/:slug`, `ArticleController`), the Keys list (`/keys`, `KeysLive`) and a key (`/keys/:slug`, `KeyLive`, with `KeyComponents` and the `ScrollToCouplet` hook), taken from the code on 2026-11-05 (design-system branch). A redesign may change how they look. It must keep every behavior listed here unless a change is explicitly approved and recorded below.

## Behaviors

- **Articles list.** Published articles only, newest first; `?tag=` filters by tag, with the tags (published only) and their counts offered as filters. Each article: title linked, author, date (`published_at`, else `inserted_at`), tags, a preview (the description, else the first 200 characters of the content with Markdown stripped). Admins get an edit link per article. An empty filter says so and links back to all.
- **An article.** A missing slug is a 404; an unpublished article is a 404 except to admins, who see it marked as a draft with `noindex`. Title, author, date, "Updated" when changed later, tags linking to the filtered list, the content as Markdown (glossary terms linked, `Gallformers.Markdown`), up to five related articles (shared tags). Page title, description (the article's, else 160 characters of its content), canonical URL and Article JSON-LD. Admins get an edit link.
- **Keys list.** Every key, by title: title linked, subtitle, description (cut to 200 characters), authors.
- **A key.** Every couplet shown at once; couplet 1 active. Choosing a lead (`select_lead`) adds a step and goes to its couplet (scrolling to it, clear of the sticky header and path bar measured through `data-sticky-chrome`) or ends at its taxon. Choosing again at a visited couplet is not offered; a step in the path goes back to its couplet (`jump_to`, dropping it and what follows); Back undoes the last step; Start over clears the path. `?path=1:0,2:3` (couplet:lead index) replays a path on load and scrolls to where it stops. At a result, Copy path copies the title, the link, each step's lead text and the result with its Gall links (`copy_to_clipboard`, the hook fills in the origin) and flashes. A result links its Gall (`/gall/:id`); one that covers several Galls links each. Destinations carry a group label and a context (family) when the key gives them. Leads may have notes and images (uploaded content images, or legacy files under `keys/<slug>/`). PDF downloads, text-only and, when the key has images, with images. Citation linked when it has a URL.

## Findings

- **The typography plugin styled every Markdown block** (`prose`, `prose-sm`…`prose-xl`): articles, Privacy, the Gall page's ID Notes and source reader, the admin article preview. Its colors came from tokens in `legacy.css`; its code colors were palette hex.
- **Articles use `#` headings inside the content**, so rendered articles carried a second `h1`.
- **A missing key rendered "Key Not Found" with status 200.**
- **Leads were clickable `div`s:** no keyboard access.
- **A result covering several Galls showed bare ids** ("[4011] [3989]").
- **Copy path copied a block of text only;** there was no way to copy just the link. Steps in the text were numbered by couplet only ("9."), so a reader couldn't tell which lead was chosen.
- **Glossary links** were styled in `legacy.css` with palette hex (slate, a yellow hover).

## Approved changes

- **Articles and keys on the design system** (Jeff approved the mockups, 2026-11-05).
  - `prose` (built) styles all running text: articles at 18px, ID Notes and the source reader in serif (A−/A+ step 14, 16, 18, 20px), Privacy, the admin preview. Markdown headings start at section level. The typography plugin and the legacy `.prose` rules are gone.
  - Glossary links keep the text's color with a dotted underline. Superseded (Jeff, 2026-11-08, matter `87a1` question 13): the dotted underline is `fact_ref`'s alone, so glossary terms are plain links to their entry, the first sentence of the definition in a `tooltip`.
  - Articles list: first built as a reading list; Jeff found it stark, and approved a livelier mockup (2026-11-05): topics as `chip_nav` chips; on the unfiltered list the newest article featured (`article_card featured`, "Newest"); the rest as `article_card`s in a grid (3, 2 or 1 across), each tinted by its first topic with a large tilted icon (`ArticlesHTML` maps topics to tone and icon); admin pencils on the cards; a "More to read" row of `link_tile`s (Identification keys with the count, Glossary, Filter guide). The Keys list keeps the reading-list layout for now.
  - An article: `page_header` (Articles crumb; By, Published, Updated, Topics; Edit for admins), a "Draft" warning notice, the text in `prose` (`max-w-text`), Related articles in the rail. A contents list was considered and dropped.
  - Keys list: the articles' list layout, with each key's scope and couplet count (`Keys.list_keys/0` gives `couplet_count`).
  - A key: `page_header` (Keys crumb; Covers, By, Couplets, Source; PDF buttons). Couplets as a printed key sets them (`key_couplet`): leads lettered a, b, c…, each with where it goes at the right; a choosable lead is a button. The path (`key_path`) is a panel beside the key on wide screens (each step with its lead's text) and a bar under the header on narrow ones; it is always shown, saying where to start before the first choice. Results covering several Galls name each Gall (`Catalog.list_galls_by_id/1`). A missing key is a 404.
  - Copy is two actions: **Copy link** (the `?path=` link, any time there is a path) and **Copy as text** (as before, at a result). Steps in the text read as the page names them ("9b. …"). The flash says "Copied".
