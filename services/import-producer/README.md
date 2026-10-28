# Import producer

A reference producer for the Gallformers import contract (`priv/import/`): turns a Source (a PDF or a saved web page) into a package that passes `validate.py --review`. Phase 1 is local and free; phases 2, 3, 5 and 6 run headless Claude Code on a Claude subscription.

It is a proof of concept used for the pipeline trial (mull matter `8546`): five Sources, about 1% wrong in 177 human-checked statements, $3–10 and 5–25 minutes per Source.

## Setup

- [uv](https://docs.astral.sh/uv/) (installs Python 3.13 and the dependencies on first run).
- Tesseract and Ghostscript, for OCR of scans: `brew install tesseract ghostscript`. English only is enough to start.
- [Claude Code](https://docs.claude.com/en/docs/claude-code), logged in with a Claude subscription. The producer removes `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` from the child process so runs bill the subscription, not an API key.
- Optional: a local `gallformers_dev` Postgres database, for the dry run (`scripts/dryrun.py`).

Check the headless setup once (one short Opus turn): it shows which account is billed and that the tool lockdown works.

```
uv run python scripts/smoke.py output/<any-package-dir>
```

Docling downloads its layout models on the first `convert` (about a minute).

## Running a Source

Put the file in `sources/` (gitignored), named `<gallformers source id>-<short name>.pdf`. Then, from this directory:

```
uv run produce convert sources/98-ashmead-1896.pdf -o output/98-ashmead-1896      # phase 1 (free)
uv run produce phase --phase 2 output/98-ashmead-1896                            # taxonomy batch
uv run produce phase --phase 3 output/98-ashmead-1896                            # gall batch
uv run produce phase --phase 4 output/98-ashmead-1896                            # validate (free)
uv run produce phase --phase 5 output/98-ashmead-1896                            # review: Opus, then Sonnet
uv run produce phase --phase 6 output/98-ashmead-1896                            # respond (only if phase 5 had findings)
uv run ../../priv/import/validate.py --review output/98-ashmead-1896              # ready?
```

For a web page: `uv run produce convert-url <url or saved .html> -o output/<name>`. Supply the page's URL and access date yourself (the producer can't know them; see "Known limits").

`--dry-run` on any `phase` writes the prompt and shows the command without running Claude. `--effort` (default `high`) and, for phase 5, `--model` (repeatable) change the run. Phases 5 and 6 refuse to run while phase 4 fails.

**Cost and time** (API-equivalent, billed to the subscription), from the trial: phase 2 about $0.50–1.20; phase 3 $1–5 (scales with the Source: a 53-page field guide was $4.73); phase 5 about $0.75–2.60 for both reviewers; phase 6 about $0.50–1.70. A web page cost $2.72 in total; papers and guides $7.70–10.

## What's in a package directory

| File | From |
|---|---|
| `document.json`, `document.txt`, `convert.json` | phase 1: the DoclingDocument, a one-line-per-item rendering the agents read, and the conversion record (which text was used, quality measures) |
| `taxonomy.json`, `gall.json` | phases 2–3 |
| `notes-phase2.md`, `notes-phase3.md` | the producer's summary, judgement calls and contract questions: worth reading |
| `review.json`, `review.<model>.json` | phase 5 (merged, and each reviewer's own), then phase 6's responses |
| `phase<N>.prompt.md`, `phase<N>.stream.jsonl`, `run.json` | each run's prompt, transcript, and cost/turn/time record |
| `ocr.pdf` | scans only: the fresh OCR (kept when it read better) |

`document.txt` lines look like `#/texts/42 p12=571 [text] The gall is rounded…`: the item reference, the PDF page, the printed page (read from running heads; `=~571` when inferred), and the item's label. Items marked `furniture` are running heads and footers.

## How phase 1 handles PDFs

- **Born-digital** PDFs (embedded fonts) keep their text; Docling's default reader.
- **Scans**: OCRmyPDF re-OCRs every page with Tesseract (no page rotation: Docling's own OCR flips upright 19th-century pages it misjudges). Both texts are measured and the fresh one is kept only if it reads clearly better (more dictionary words, without losing text). Docling then reads the chosen PDF with its OCR off, through pdfium (Docling's default reader garbles layered scan pages).
- Items outside the page area (phantom glyphs) are dropped.
- `convert.json` records which text was used and why; `quality` gives coverage, OCR-noise and per-page measures to sanity-check a conversion.

## The agents

- Prompts: `prompts/producer.md` (phases 2–3), `prompts/verifier.md` (phase 5), `prompts/responder.md` (phase 6). The contract files are inlined into each prompt from `priv/import/`.
- Model: Opus 5.5 produces and responds; Opus and Sonnet review.
- Tools: phases 2, 3 and 6 work in the package directory with Read, Write, Edit, Grep and two allowed commands (the validator and `lookup-place`); the reviewer works in a scratch copy holding only the document and the batches, with no shell. Claude Code's `--safe-mode` keeps user settings, hooks, skills and memory out of the runs. Read-only shell commands can still slip through Claude Code's auto-approval; full lockdown would mean replacing Bash with an MCP tool.

## Scripts

- `scripts/dryrun.py <package> <source id>`: approximates Gallformers' importer against `gallformers_dev`: resolves names and Galls (including old "C. q. X" names and undescribed-gall candidates) and compares with the entries already linked to the Source. Writes `dryrun.json`.
- `scripts/seed_errors.py`: plants known errors in a copy of a package, to test phase 5.
- `scripts/smoke.py`: the setup check above.

## Golden regression set

`golden/` holds Jeff's verdicts from the trial's five human check pages: 177 statements (173 right, 2 wrong, 2 unsure) and 18 name matches, one file per Source (`<source id>-<short name>.json`). Each item keeps the verdict, the note and the whole statement as it was checked, with local ids replaced by what they stand for (the Gall by its Inducer, Host, generation and name as written; taxa by their names; quotes and pages), so a new run can be scored without the trial packages. Two verdicts carry a revision from the trial log: Ashmead f141 was recounted right, and 1862 f162 is wrong only in its second citation (fixed when that quote goes and the Fact stays).

Run it after any change to the guide, the prompts, the vocabulary or the model, and before the backscan. Re-running the five Sources costs money (phases 2–6 each); scoring is free and makes no API calls.

```
uv run python scripts/dryrun.py output/<run> <source id>   # optional: name matches (local database)
uv run produce golden score output/<run>                   # Source id from the dir name, or --source <id>
```

The scorer matches each golden item in the run by meaning, never by local id (`g3`, `f41` are renumbered every run). Galls are paired by their identifying fields, then by the name as written; statements by a natural key per kind (a Relationship by its subject and object, a Trait by Gall and trait and value, a range adjustment by Gall and place, a description by Gall and word overlap, a taxonomic act by its names). Each item is `present`, `changed` (same key, different value or stance, both shown) or `missing`. The report lists possible regressions (right, now changed or missing), wrong statements still present and those fixed, and the unsure ones for a person to look at. It prints and writes `golden-score.json` in the run dir (`--out` elsewhere). Name matches are scored only when the run has a `dryrun.json`.

The checked packages predate the 2026-10-17 and 2026-10-26 contract decisions. An old `include` range adjustment is scored as an `occurrence` Fact at the same place; the season, detachable and generation changes keep their fields' shapes, so a value they change shows as `changed` (or, for a generation, as a change in the Gall mapping) for a person to judge.

`uv run produce golden export --verdicts <dir>` rebuilds the files from the local trial packages and the check pages' exported verdicts (`<dir>/<name>/checks/<doc id>.json`); revisions live in `src/producer/golden.py`.

## Known limits

- **Web pages:** the producer can't know a page's URL or access date; pass them in (not yet automated). Docling's HTML conversion fragments text at every italic name and may duplicate the page inside a layout table; quotes still verify.
- **Photos aren't read:** the batches say what the text says, even where a photo shows otherwise.
- **Long Sources** (a 147-page catalogue, a 352-page key) are untested; a gall batch could exceed one response.
- **Complex tables** convert poorly.

## Development

```
uv run pytest           # tests
uv run ruff check       # lint
uv run ruff format      # format
```
