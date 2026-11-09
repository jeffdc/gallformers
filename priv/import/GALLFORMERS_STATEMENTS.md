# Gallformers import — Gallformers statements

How to write a batch of Gallformers' own statements: a curator's correction, confirmation or exclusion, or the statements in a Gall's Gallformers note. Everything in `PRODUCER_GUIDE.md` under Phase 2 and Phase 3 applies to what a statement says; this guide covers what differs.

- **Source:** `{ "gallformers": true }`, with no bibliographic fields and no `document.json`, unless the batch reads a Gall's note (below).
- **`mode`:** always `add`. Each statement is its own dated entry.
- **Evidence** is a statement in place of a quote:
  - `statement.text`: the statement in plain words;
  - `statement.stated_on`: its date (YYYY-MM-DD);
  - `observations` (optional): the Observations that support it, e.g. `{ "provider": "inaturalist", "id": "123456789" }`; an iNaturalist observation may add its `quality_grade` when the statement was made (`research`, `needs_id`, `casual`) and a `thumbnail_url`, shown with the statement;
  - `cites` (optional): the Source the curator follows for it ("per Weld 1959"): `as_written`, the Source as the curator names it, and `source_id`, Gallformers' ID for it when known. The statement stays Gallformers' own, dated as made; the Source is recorded on it, and when that Source is brought in, its own statement joins the same Fact.
- **Observations** appear only as cited evidence.
- **A Trait** is stated as in Phase 3, "Traits": the statement's own word for it as the `term` (often the category itself), with the category.
- **A Host Gallformers added "tentatively"** from an Observation is a Fact like any other, not a hedged statement (`PRODUCER_GUIDE.md` rule 7): state it as `host_of`, with that Observation as its evidence.
- Run `validate.py` on the batch file.

Example: `examples/gallformers-statement/gall.json` (a range exclusion, a Host verified from Observations, and a recorded occurrence).

## Reading a Gall's note

Each Gall can have a Gallformers note ("Notes on ID and Taxonomy"), Gallformers' own document for that Gall. A batch that reads one quotes it, like any Source document.

- **Source:** `{ "gallformers": true, "note": { "gallformers_gall_id": …, "stated_on": … }, "document": { "file": "document.json", "sha256": … } }`, given to you; don't change it. Every statement takes the note's `stated_on`.
- **The document** is the note: one text item, `#/texts/0`, the note's text as written (Markdown, links included).
- **Evidence** quotes `#/texts/0`, verbatim, including any link text in its brackets ("Observed in Maryland in [September]"). Never a `statement`.
- **Observations:** a link to an Observation becomes one on the evidence: `inaturalist.org/observations/<id>` is `inaturalist`, `bugguide.net/node/view/<id>` is `bugguide`.
- **The note's Gall** is declared with its `gallformers_gall_id` and the identifying fields you are given for it (its Inducer, generation, Host).

What the note states as Facts:

- **Hosts** it adds, including "tentatively" from Observations (above): `host_of`, with the Observations.
- **Where and when the Gall was seen** ("Observed in Illinois in July"): an `occurrence` Fact per place, with `when_as_written`. When it was seen is not its `season`: state `season` only where the note says when the Gall forms or grows.
- **Traits** it states for the Gall: the note's term and a suggested category, as in Phase 3, "Traits".
- **A description**, when the note describes the Gall (most often an undescribed Gall's): a `description` Fact of the note's descriptive sentences.
- **Facts about another Gall** the note states in so many words, on that Gall (Phase 3, "Galls").

What isn't a Fact: leave it out, as a paper's background is left out. It stays in the note, which the Gall page shows whole.

- How to identify the Gall and tell it from similar ones; comparisons with other Galls.
- Summaries of the literature and of the state of knowledge, open questions, hypotheses.
- Pointers to people, websites and other resources.

What goes to `unmapped` (slot `other`), with a `note` saying which and the `topic` of what it is about (`PRODUCER_GUIDE.md` rule 5):

- **A statement credited to a published work** ("As Felt said, …", "according to Russo"): `from <the work>`. It is that work's statement, checked against that Source.
- **A ruling between Sources** ("Our current interpretation follows Gagne"): `ruling`. Rulings are looked at one by one.
- **A personal communication** ("James Nicholls (personal communication)"): `personal communication`.
- **A placeholder** ("Artemisia campestris is used as a placeholder"): `placeholder`. It is not a Fact.
- **A hedge** (`PRODUCER_GUIDE.md` rule 7), except a tentative Host from Observations.

Example: `examples/gallformers-note/` (a Host added from an Observation and a recorded occurrence; the note's identification tip is left out).

## Fixing a reading of a Source

When Gallformers read a Source it holds wrongly (took it to say a Host it doesn't, or the wrong Trait value), a curator fixes the reading under that Source's authority, not as a Gallformers statement. The batch is the Source's statements read again; Gallformers takes no position in it. Gallformers builds these from the Fact inspector ("Fix our reading…").

- **Source:** `{ "reading_of": { "gallformers_source_id": …, "why": …, "accept": true } }`: the Source read again, by Gallformers' ID, optionally the curator's reason in their words, and, in a taxonomy batch only, `accept` when the curator accepts the taxonomic statements the fix states ("Accept it now"; without it they await a curator in the taxonomy queue). No bibliographic fields and no `document.json`: the Source and its document are held already.
- **Gall or taxonomy:** a gall batch fixes Facts; a taxonomy batch fixes acts (a placement, a synonymy) the same way.
- **`mode`:** always `add`.
- **A Fact (or act) the Source doesn't say** is the misread statement, marked `"unstated": true`: the Source's statement of it is taken away. Other Sources' statements of it stay.
- **What the Source does say** in its place, if anything, is a Fact (or act) with `"replaces": "<the unstated Fact's id>"`, stated as the Source states it: its date is the Source's, its words as written and its quotes carried from the misread statement.
- **Evidence** is the Source's quotes, each naming the stored document's item by `gallformers_document_item_id` in place of `item`; `whole_item` takes it too. Never a `statement`. A Source Gallformers holds no quotes of (the legacy data) is fixed with `"evidence": []`: the statement as Gallformers holds it.
- **The Gall** is declared with its `gallformers_gall_id`, and taxa with their `gallformers_taxon_id`.

Example: `examples/reading-fix/gall.json` (a Host read as Q. alba that the Source gives as Q. bicolor).
