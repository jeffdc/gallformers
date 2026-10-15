# Task: phase 5 review of a Gallformers import package

Review the batches below against their document, following VERIFY_GUIDE.md exactly, and write `review.json` in your working directory. Your working directory holds `document.json`, `document.txt`, `taxonomy.json` and `gall.json`; use Grep on `document.txt` and Read on the others as you need.

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
