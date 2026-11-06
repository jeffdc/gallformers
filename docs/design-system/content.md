# Content

Words are part of the interface. Gallformers' readers are naturalists and curators who know galls, hosts and the literature; write for them.

## Voice

- **Plain and specific.** Say what a thing is or does, in the words a knowledgeable person would use aloud. "Leaving this open holds approval of the Source's Gall statements", not "Pending items block downstream processing".
- **The reader's words, not the system's.** Name things the way the literature and the catalog do: "the gall of *Andricus morrisoni*", "Quercus imbricaria Michx.". Never show internal refs (`t24`, `g1`), batch IDs, file names or method codes in the main view; keep them behind a "Details" disclosure for debugging.
- **Active voice; short sentences.** "Accepting adds 'imbrecaria' as a synonym."
- **No filler.** No "Welcome to", "Please note", "Simply"; no exclamation marks; no apologies in errors.

## Domain terms

**Gallformer** is the noun for the organism that induces a gall, as well as the site's name: "Gallformers on *Quercus*", "Gallformer genera". Never "gall-former" or "gall former". (The domain model's term for the role is Inducer; on screen, readers see Gallformer.)

Gallformers capitalizes its domain concepts, as the domain model does: **Gall**, **Host**, **Inducer**, **Source**, **Fact**, **Trait**, **Observation**. Lowercase when the word is used generally ("a gall on an oak leaf"), capitalized when it means the thing in Gallformers ("this Gall's Hosts"). Ranks are lowercase (family, genus, section). Generations are written as the catalog writes them: (agamic), (sexgen).

Scientific names are italic at genus rank and below, with authors, rank words and generation upright: *Quercus imbricaria* Michx.; *Callirhytis quercuscornigera* (agamic). Use `taxon_name`; don't italicize by hand.

## Labels

- **Buttons say what happens:** "Approve 9 notes", "Add synonym", "Rename", "Delete taxon". Not "Submit", "OK", "Yes".
- **Headings are nouns:** "Hosts", "Sources", "Possible range". Counts go beside them, muted, not in parentheses.
- **Field labels are short nouns;** the help text under the field explains consequences ("The old name is kept as a synonym.").
- **Links say where they go:** "View public page ↗", "Source page". An arrow ↗ marks a link that opens a new tab or another site.
- **Empty values:** say "Not recorded" for a trait no Source states; "None" only where none is a real answer; never a dash alone in a table cell.

## Numbers and dates

- Thousands separators in counts: 3,976 Galls. Tabular figures in tables and stats (automatic in `table`, and in `stat`).
- Dates: `Oct 28, 2026`. Date and time, in admin only: `Oct 28, 2026, 1:43 AM UTC`. Years alone for publications: 1959.
- Ranges with an en dash: 18–32 mm, 1862–1865.
- Units with a space: 3 mm, 1–3 cm.

## Messages

- **Errors** say what went wrong and how to fix it: "That name is already a synonym of *Quercus rubra*. Search for it instead."
- **Confirmations** name the thing and the consequence: "Delete the taxon Acanthaceae? Its 3 synonyms are deleted with it."
- **Success** is brief and past tense: "Saved", "Approved 9 notes".
- **Caveats** sit next to what they qualify, in one line: "Where the Hosts grow, not where the Gall was found."
