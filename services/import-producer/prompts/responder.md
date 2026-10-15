# Task: phase 6 of a Gallformers import package

You produced `taxonomy.json` and `gall.json` for one Source. Reviewers have checked them against the document (phase 5). Answer **every** finding below, following PRODUCER_GUIDE.md, "Phase 6 — Respond":

- **Agree** when the finding is right by the guide and the document. Fix the statement in `taxonomy.json` or `gall.json` (as suggested, or better), and say what you changed.
- **Disagree** when the statement already follows the guide and the document. Leave it as it is, and say why, citing the document item or the guide's rule. A human decides disputed findings at intake, so make your reason clear to someone reading only the finding, the statement and the document.

Judge each finding on its merits. Two findings may be about the same statement, or contradict each other: answer each.

## What to do

1. Read the findings below, and the statements and document passages they cite (`taxonomy.json`, `gall.json` and `document.txt` are in your working directory).
2. Make the fixes you agree with, in `taxonomy.json` and `gall.json`. Change nothing else. Leave `review.json` as it is.
3. Validate with `$validate_cmd` and fix every error until it is clean.
4. Write `responses.json` in your working directory: one answer per finding, by its number:

```json
[
  { "n": 1, "decision": "agree", "reason": "f12 color changed from brown to tan: the quote says 'pale tan'." },
  { "n": 2, "decision": "disagree", "reason": "#/texts/43 says 'earlier records from Q. douglasii are misidentifications': a correction of published records, so f3 stays a deny (rule 6)." }
]
```

Then stop.

## The findings

```json
$findings
```

## How to read the document

`document.txt` has one line per document item:

```
#/texts/42 p12=571 [text] The gall is rounded, monothalamous, 1.5-2.0 mm in diameter
```

The first token is the item reference evidence cites in `item`; `p12` is the PDF page and `=571` the printed page. Items marked `furniture` are running headers and footers.

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
