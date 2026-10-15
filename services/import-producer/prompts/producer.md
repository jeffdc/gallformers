# Task: phase $phase of a Gallformers import package

You are producing **$batch_file** for one Source: $phase_task

The Gallformers import contract is below: the producer guide, the JSON schemas, the vocabularies and the examples. **Follow PRODUCER_GUIDE.md exactly.** Where the guide and your own judgement differ, the guide wins. State only what this Source states.

## What to do

1. Read the document (below, and as `document.txt` in your working directory; `document.json` is the same document in full).
2. Write `$batch_file` in your working directory.
3. Validate it with `$validate_cmd` (the contract's validator: the schemas, plus every quote found in its item, refs, qualifiers, one Inducer per Gall), and fix every error until it is clean. Warnings are worth a look but don't block.
4. To map a place name to a code, run `$lookup_cmd "<place name>"`. The full places list is too long to include here.
5. When it is clean, write `notes-phase$phase.md` (see "Notes" below) and stop.

You may build a large batch in steps: write a first part, then Edit to add more. Use Grep on `document.txt` to find passages.

## Values you must use exactly

These are fixed by the run, not by you:

```json
$envelope
```

Fill in the rest of `source` (kind, title, authors, authored, citation, identifiers, license) from the document itself. $source_hint

## How to read the document

`document.txt` has one line per document item:

```
#/texts/42 p12=571 [text] The gall is rounded, monothalamous, 1.5-2.0 mm in diameter
#/texts/43 p13 [text] …
#/tables/0 p5=~564 [table]
    Gargaphia solani | AL AZ AR | Henry and Froeschner (1988)
```

- The first token is the item's reference: use it as `evidence.item`.
- `p12` is the PDF page index.
- `=571` is the **printed page**, read from the running heads: use it as `evidence.page`. `=~564` is inferred from neighbouring pages; use it too. When a line has no `=`, leave `page` out.
- Items marked `furniture` are running headers and footers; cite body items as evidence.
- Table rows are indented under their table, with cells joined by ` | `. Quote a row the same way, with the table's reference as the item.
- `quote` must be copied verbatim from that one item, including the Source's spelling mistakes and OCR errors. Whitespace differences are fine. A word broken across a line ("caro- linense") may be quoted either way.
- A paragraph may contain text from several species or, in scans, damaged passages. Quote only the part that supports the Fact.

## Notes

`notes-phase$phase.md` is for the people reviewing this run. Keep it short:

- **Summary:** what you produced (counts), and anything you deliberately left out and why.
- **Judgement calls:** places where you were unsure how to apply the guide, and what you chose.
- **Contract questions:** anything in the guide, schemas or vocabularies that seemed wrong, unclear, contradictory, or unable to express what the Source says. Be specific: quote the rule and the passage. This is the most useful part of the notes.
- **Document problems:** text that was garbled, missing, or out of order in `document.txt` and affected the batch.

$phase_rules

---

# The contract

$contract

---

# The document

$document
