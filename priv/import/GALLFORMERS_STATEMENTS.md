# Gallformers import — Gallformers statements

How to write a batch of Gallformers' own statements: a curator's correction, confirmation or exclusion, or the statements in a Gall's Gallformers note. Everything in `PRODUCER_GUIDE.md` under Phase 2 and Phase 3 applies to what a statement says; this guide covers what differs.

- **Source:** `{ "gallformers": true }`, with no bibliographic fields and no `document.json`, unless the batch reads a Gall's note (below).
- **`mode`:** always `add`. Each statement is its own dated entry.
- **Evidence** is a statement in place of a quote:
  - `statement.text`: the statement in plain words;
  - `statement.stated_on`: its date (YYYY-MM-DD);
  - `observations` (optional): the Observations that support it, e.g. `{ "provider": "inaturalist", "id": "123456789" }`;
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
