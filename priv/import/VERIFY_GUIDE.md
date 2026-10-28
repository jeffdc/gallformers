# Gallformers import — verifier guide (phase 5)

How to check a package's batches against its document. You are a reviewer: you read `document.json`, `taxonomy.json` and `gall.json`, and write `review.json`. The rules the batches must follow are in `PRODUCER_GUIDE.md`; the meanings of controlled values are in `vocab/`. The batches have passed phase 4 (`validate.py`): their shape, their references, and that every quote exists in its item are already checked.

You report; you change nothing. In phase 6 the producer answers each finding, fixing the statement or explaining why it stands, and a human decides any dispute at intake. So write each finding to stand on its own: someone reading only it, the statement and the document should see the problem.

## What to check

Check every act in `taxonomy.json` and every Fact in `gall.json`, and the taxa and Galls they declare:

- **Support:** its evidence, read in the cited document item, says what the statement says. The quote exists in the item and carries the meaning claimed, in context.
- **Value:** each controlled value matches its definition (`vocab/traits.json` for Traits) and the Source's words in `as_written`.
- **Type:** the Relationship type, act kind or qualifier is the one the Source supports — the most specific the evidence allows, and no more.
- **Stance:** `deny` only where the Source corrects a published statement (`PRODUCER_GUIDE.md` rule 6); `confirm` otherwise. Other negatives belong nowhere in the batches, so their absence is correct.
- **Target:** the statement is about the right taxon, Gall and generation.
- **Generation:** a Gall carries a generation only when the Source shows a clearly different Gall for that stage of the Inducer's life cycle; repeated broods that induce the same Gall are one Gall (a `rule` finding). The value comes from the group for the Inducer's taxon in `vocab/traits.json` and matches its definition (a `wrong_value` finding). `PRODUCER_GUIDE.md`, "Generations", has the rules.
- **Rules:** the statement follows `PRODUCER_GUIDE.md` — for example, hedged statements are absent from Facts, acts are ones the Source makes or adopts, `new` and `formerly_undescribed` are claims the Source makes.

Judge each statement from the document alone.

## What to write

`review.json` beside the batches, matching `schema/review.schema.json`:

```json
{
  "format": "gallformers-review",
  "reviewed": { "taxonomy.json": "<sha256>", "gall.json": "<sha256>" },
  "reviewers": [{ "model": "<model>", "instructions_version": "<version>" }],
  "findings": [
    { "batch": "gall.json", "id": "f12", "problem": "wrong_value",
      "reason": "The quote says 'pale tan'; the Fact states color brown.", "suggestion": "color tan" }
  ]
}
```

- `reviewed`: the sha256 of each batch file you checked, as provided with the batches (or computed with a hashing tool).
- `findings`: one entry per problem, with the statement's `id` (`a…`, `f…`, `t…`, `g…`), one `problem` from the schema, a `reason` that cites the document, and an optional `suggestion`. An empty list means every statement checks out.
