# Gallformers import — verifier guide (phase 5)

How to check a package's batches against its document. You are a reviewer: you read `document.json`, `taxonomy.json` and `gall.json`, and write `review.json`. The rules the batches must follow are in `PRODUCER_GUIDE.md`; the meanings of controlled values are in `vocab/`. The batches have passed phase 4 (`validate.py`): their shape, their references, and that every quote exists in its item are already checked.

The `gall.json` you read is a copy with the producer's `category` and `depends_on_gall` removed from every trait Fact. You place each trait term yourself ("Placing trait terms"), so that Gallformers can tell whether two readers place a new term alike.

You report; you change nothing. In phase 6 the producer answers each finding, fixing the statement or explaining why it stands, and a human decides any dispute at intake. So write each finding to stand on its own: someone reading only it, the statement and the document should see the problem.

## What to check

Check every act in `taxonomy.json` and every Fact in `gall.json`, and the taxa and Galls they declare:

- **Support:** its evidence, read in the cited document item, says what the statement says. The quote exists in the item and carries the meaning claimed, in context. A quote that is only a name, or a fragment that doesn't state the Fact, is an `unsupported` finding, even when the sentence around it would support the statement.
- **Value:** each controlled value (a generation, a plant part in `identified_by`, a place, a qualifier) matches its definition (`vocab/traits.json` for generations and plant parts) and the Source's words in `as_written`.
- **Term:** a trait Fact's `term` is the Source's own word or short phrase for one value of that Trait of that Gall, verbatim: the words that are the term, not the sentence and not a clause. A term for another Trait, words that describe something else ("sometimes three or four together, pressing each other into irregular shapes" as a shape; "each with a single insect" as cells, where nothing says how many chambers the Gall has), or words the Source doesn't use for it, is a `wrong_value` finding. A comparison the Source makes for the Trait ("the color of a large dried pea") is a term (`PRODUCER_GUIDE.md`, "Traits").
- **Type:** the Relationship type, act kind or qualifier is the one the Source supports — the most specific the evidence allows, and no more.
- **Stance:** `deny` only where the Source corrects a published statement (`PRODUCER_GUIDE.md` rule 6); `confirm` otherwise. Other negatives belong nowhere in the batches, so their absence is correct.
- **Target:** the statement is about the right taxon, Gall and generation.
- **Generation:** a Gall carries a generation only when the Source shows a clearly different Gall for that stage of the Inducer's life cycle; repeated broods that induce the same Gall are one Gall (a `rule` finding). The value comes from the group for the Inducer's taxon in `vocab/traits.json` and matches its definition (a `wrong_value` finding). `PRODUCER_GUIDE.md`, "Generations", has the rules.
- **Rules:** the statement follows `PRODUCER_GUIDE.md` — for example, hedged statements are absent from Facts, acts are ones the Source makes or adopts, `new` and `formerly_undescribed` are claims the Source makes.
- **New taxa:** every taxon the Source calls new ("new species", "n. sp.", *sp. nov.*) carries `new` in `taxonomy.json`, beside its name act; one without it there is a `rule` finding on the taxon (`t…`). The taxa `gall.json` declares are only references for its Facts and carry no `new`, so a new taxon there without it is correct, not a finding.
- **Hosts by common name:** a Host declared with `common_name: true` is right when the Source names that plant only by a common name ("the black oak", or a bare "an unknown oak") and never pairs that name with a scientific name (`PRODUCER_GUIDE.md` rule 3). Don't report it for lacking a scientific name or a rank, and don't suggest a species or the genus in its place. Report it only where the Source does pair that same common name with a scientific name (a pairing of "red oak" doesn't cover a bare "oak"), or where a genus Host stands in for a plant the Source names by a common name.

Judge each statement from the document alone.

## Placing trait terms

Place every trait Fact's term, as the producer did but without knowing what it suggested: from the term, its quote and the Gall's whole description, choose the value of the Fact's Trait whose definition in `vocab/traits.json` fits.

- `category`: `{ "value": … }`, or `null` when no value's definition fits. Never force a fit: a near miss is `null`.
- `depends_on_gall: true` when the term means different values for different Galls and this Gall's description decides it ("swelling": `abrupt swelling`, `tapered swelling` or `stem club`). The category is the one this Gall's description supports, or `null` when nothing in it tells them apart.
- `reason`: a short reason, when the category is `null` or depends on the Gall.

A term `traits.json` lists as `placed` (`mappings`) takes its category. An `ambiguous` term, listed with its `candidates`, is placed from this Gall's description, with `depends_on_gall: true`.

- **A term that names several values** is several trait Facts with the same Gall, Trait and term ("green-yellow": green and yellow; "protruding from both sides" of a leaf: upper leaf and lower leaf). Place them together, each in one of the values the term names. A term that names several values but has a Fact for only one of them is a `rule` finding on that Fact.
- **A term naming alternatives names each of them** ("green or yellowish": green and yellow; "single-chambered or have many chambers": monothalamous and polythalamous): several values of a Trait mean the Gall can be any of them. Place its Facts as for any term that names several values. A place on the leaf is the exception: "on either side of the leaf" and "on the upper or lower surface" are `leaf`.
- **Never guess a value the Source doesn't name.** A term that leaves the value open ("of various colours", "variable in shape") or that the Source says is unknown is `null`, with `depends_on_gall: true` when its value varies from Gall to Gall.
- A `plant_part` is the most precise location the Source supports; `leaf` when it supports no more precise place on the leaf. Never `leaf` beside a leaf value from the same words: every leaf value is on the leaf.
- Place a term in a value only when its definition fits clearly: where the producer suggested nothing, two reviewers agreeing place a new term for every Source.

A placement is not a finding: write one for every trait Fact, whether or not you also report a finding on it.

## What to write

`review.json` beside the batches, matching `schema/review.schema.json`:

```json
{
  "format": "gallformers-review",
  "reviewed": { "taxonomy.json": "<sha256>", "gall.json": "<sha256>" },
  "reviewers": [{ "model": "<model>", "instructions_version": "<version>" }],
  "findings": [
    { "batch": "gall.json", "id": "f12", "problem": "wrong_value",
      "reason": "The quote says 'pale tan when mature'; the term is 'mature'.",
      "summary": "The term should be the colour, pale tan, not 'mature'.", "suggestion": "term 'pale tan'" }
  ],
  "placements": [
    { "id": "f12", "category": { "value": "tan" } },
    { "id": "f14", "category": null, "depends_on_gall": true,
      "reason": "'swelling' with no shape given: abrupt swelling, tapered swelling or stem club" }
  ]
}
```

- `reviewed`: the sha256 of each batch file you checked, as provided with the batches (or computed with a hashing tool).
- `findings`: one entry per problem, with the statement's `id` (`a…`, `f…`, `t…`, `g…`), one `problem` from the schema, a `reason` that cites the document, a `summary`, and an optional `suggestion`. An empty list means every statement checks out.
- `summary`: your position in one plain sentence, for the curator who weighs it against the producer's answer: no rule numbers and no `#/texts` references. Name the value you say is right, or say the statement should go ("'Fleshy' describes the tissue inside, not the surface, so it isn't a texture term"). The full argument stays in `reason`.
- `placements`: one entry per trait Fact, by its `id` ("Placing trait terms").
