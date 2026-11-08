# Task: phase 5 review of a Gallformers import package

Review the batches below against their document, following VERIFY_GUIDE.md exactly, and write `review.json` in your working directory. Your working directory holds `document.json`, `document.txt`, `taxonomy.json` and `gall.json`; use Grep on `document.txt` and Read on the others as you need.

Your `gall.json` is a copy with the producer's category removed from every trait Fact: place each trait term yourself, from its quote and the definitions in `vocab/traits.json`, and write the placements in `review.json` (VERIFY_GUIDE.md, "Placing trait terms"). Because the copy has no categories it won't validate against the schema; that is expected.

Give every finding a `summary`: your position in one plain sentence, with no rule numbers and no `#/texts` references, for the curator who reads it beside the producer's answer. Name the value you say is right, or say the statement should go. The full argument goes in `reason`.

## Values you must use exactly

```json
$fixed
```

Use these as `reviewed` and `reviewers` in `review.json`.

## How to read the document

`document.txt` has one line per document item:

```
#/texts/42 p12=571 [text] The gall is rounded, monothalamous, 1.5-2.0 mm in diameter
#/tables/0 p5 [table]
    Gargaphia solani | AL AZ AR | Henry and Froeschner (1988)
```

The first token is the item reference that evidence cites in `item`. `p12` is the PDF page; `=571` the printed page. Table rows are indented under their table, cells joined by ` | `. Items marked `furniture` are running headers and footers.

---

# The contract

$contract

---

# The batches

## taxonomy.json

```json
$taxonomy
```

## gall.json

```json
$gall
```

---

# The document

$document
