# Source Ingestion Pipeline

A command-line tool that turns a research paper (PDF) into a structured "review bundle" for gallformers.org. The pipeline extracts the text, identifies sections, finds candidate gall records, extracts facts about each one (host plants, traits, scientific names, etc.), and packages everything — along with evidence pointers back into the source text — into a single `bundle.tar.gz`.

This README covers everything you need to install the tool, configure it, and run it against a paper. A developer reference section at the end documents the CLI subcommands and pipeline-config format.

---

## What you'll need

- A computer running macOS or Windows (Linux works too — install steps are the same as macOS).
- About 15 minutes for first-time setup.
- A DeepInfra account with a funded balance (covered below). $5 is plenty for many papers.
- A born-digital PDF of a paper. ("Born-digital" means the PDF has a real text layer — most modern journal PDFs do. Scanned/image-only PDFs are not supported yet; see [Known limitations](#known-limitations).)

You do **not** need to install Python yourself. The tool [uv](https://docs.astral.sh/uv/) (installed below) takes care of that.

---

## 1. Install the prerequisites

You need three things: **Git**, **uv**, and a local copy of the repository.

### macOS

Open Terminal.

```bash
# Git — usually already installed. If not, this prompts you to install it.
git --version

# uv — installs to ~/.local/bin
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After installing `uv`, close and reopen Terminal (or run `source ~/.zshrc`) so the new `uv` command is on your `PATH`.

### Windows

Open **PowerShell** (not the old Command Prompt).

```powershell
# Git — install via winget if not already present.
winget install --id Git.Git -e

# uv
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

After installing, close and reopen PowerShell so the new commands are on your `PATH`.

### Verify

On either platform:

```bash
git --version
uv --version
```

Both should print a version number.

---

## 2. Clone the repository

Pick a directory where you keep code (e.g., `~/dev` on macOS, `C:\dev` on Windows). Then:

```bash
git clone https://github.com/jeffdc/gallformers.git
cd gallformers/services/source-ingestion
```

All remaining commands assume your shell is in `services/source-ingestion/`.

---

## 3. Install Python dependencies

```bash
uv sync
```

The first run downloads Python 3.12 (if you don't already have it) and installs ~40 packages. Takes a minute or two. Subsequent runs are instant.

To confirm:

```bash
uv run ingest --help
```

You should see the `run` subcommand (currently the only one).

---

## 4. Get a DeepInfra API key

The pipeline uses several LLMs hosted by [DeepInfra](https://deepinfra.com/). You'll need an account with a funded balance.

1. Sign up at <https://deepinfra.com/>.
2. Add funds to your account. **$5 is plenty** — a typical paper costs well under $1 in API calls, and re-running the same paper is free thanks to caching.
3. Go to **Dashboard → API Keys** and create a new key. It will start with `sk-`.
4. Copy the key.

### Set the key as an environment variable

You set it once per shell session — or persistently so it's always available.

**macOS / Linux (zsh or bash):**

```bash
# For this session only:
export DEEPINFRA_API_KEY="sk-your-key-here"

# To set it permanently, add the same line to ~/.zshrc (or ~/.bashrc):
echo 'export DEEPINFRA_API_KEY="sk-your-key-here"' >> ~/.zshrc
```

After editing `~/.zshrc`, close and reopen Terminal.

**Windows (PowerShell):**

```powershell
# For this session only:
$env:DEEPINFRA_API_KEY = "sk-your-key-here"

# To set it permanently (new shells will see it; existing shells won't):
[System.Environment]::SetEnvironmentVariable('DEEPINFRA_API_KEY', 'sk-your-key-here', 'User')
```

After running the persistent command, close and reopen PowerShell.

### Verify (without printing the key)

```bash
# macOS / Linux
test -n "$DEEPINFRA_API_KEY" && echo "key is set" || echo "key is NOT set"
```

```powershell
# Windows
if ($env:DEEPINFRA_API_KEY) { "key is set" } else { "key is NOT set" }
```

---

## 5. Configure the provider file

Copy the example config to the active config name:

```bash
cp providers.example.yaml providers.yaml
```

(On Windows PowerShell: `Copy-Item providers.example.yaml providers.yaml`.)

You do **not** need to edit `providers.yaml` for the standard pipeline — DeepInfra is already configured there. The file simply tells the tool which models live where; your `DEEPINFRA_API_KEY` env var supplies the credential.

---

## 6. Run the pipeline against a PDF

The production pipeline is **`default.yaml`** — handles both born-digital and scanned PDFs (OCR is auto-detected per-page).

Pick a paper you have rights to (a PDF you authored, a preprint, an open-access article, etc.) and save it somewhere on your machine. The repo intentionally does **not** ship sample PDFs — most published papers are under copyright and can't be redistributed.

Then run:

```bash
uv run ingest run -s mypaper -i /path/to/your/paper.pdf
```

That's it — every other flag has a sensible default. The full form is:

```bash
uv run ingest run \
  -s mypaper \
  -i /path/to/your/paper.pdf \
  [-p pipelines/default.yaml] \
  [-c providers.yaml] \
  [-o ./output]
```

(On Windows PowerShell, replace the trailing backslashes with backticks `` ` `` or put the whole command on one line.)

Arguments:

- `-s`, `--source-id` (**required**) — a short label you choose. It becomes the output directory name. Use lowercase, no spaces (e.g., `smith-2024`, `mypaper`).
- `-i`, `--input` — path to the PDF.
- `-p`, `--pipeline` — which pipeline YAML to run. Defaults to `pipelines/default.yaml`.
- `-c`, `--config` — provider config. Defaults to `providers.yaml`.
- `-o`, `--output` — parent output directory. Defaults to `./output`. The run lands at `<output>/<source-id>/`.

### What you'll see

The pipeline streams progress per stage as it runs — start/complete markers for `extract`, `ocr`, `block-triage`, `preprocess`, `sectionize`, `metadata`, `find-candidates`, `evidence-pack`, `extract-facts`, `verify`, `verify-claims`, `taxonomy-lookup`, `assemble-review`, and `bundle`, each with timing and a quick result summary (block counts, candidate counts, LLM call counts). A typical paper takes **3–7 minutes** end-to-end; papers that trigger OCR or have many candidates take longer (10–20 min for large reference works).

A full copy of the run output is also tee'd to `output/<source-id>/run.log` so you can review what happened after the fact.

The most-watched stages by wall time are `extract-facts` (one LLM call per candidate) and `verify-claims` (one per claim, ~15 per candidate). Both run with `max_workers: 50` against DeepInfra's 200/model/user concurrency cap, so they parallelize well — but on a paper with 100+ candidates, expect a noticeable verify-claims phase.

While it runs, you can watch new files appear in `output/<source-id>/`.

---

## 7. Find your results

When the pipeline finishes, look in `output/<source-id>/`:

```
output/mypaper/
  bundle.tar.gz          ← the full review bundle (send this in for review)
  review_artifact.json   ← human-readable summary of what was extracted
  manifest.json          ← provenance: every stage, model, prompt SHA, timing
  source.pdf             ← the input PDF (so the bundle is self-contained)
  raw_text.jsonl         ← text extracted from the PDF, page+block addressed
  block_triage.json      ← LLM triage decisions (which raw blocks were content vs noise)
  normalized_text.jsonl  ← after deterministic cleanup of the kept blocks
  sections.json          ← rule-based section detection (abstract, methods, etc.)
  metadata.json          ← title, authors, year, DOI
  candidates.json        ← gall records the model thought it found
  claims.json            ← per-record field extractions (raw)
  verified_claims.json   ← same, after a second model double-checks each claim
  run.log                ← full stdout/stderr capture of the pipeline run
```

The two files most useful for a human reviewer:

1. **`review_artifact.json`** — the rolled-up, structured result. It contains:
   - `document_metadata` — title, authors, year, DOI, etc.
   - `gall_records` — one entry per gall the model identified. Each has `gall_maker`, `generation` (`sexgen` / `agamic` / `unspecified` — Cynipid wasps and other species with alternating generations get a record per generation), `evidence_prose` (the verbatim per-paragraph source text the LLM saw, the primary review surface), `hosts`, `gall_traits`, `description`, `location`, a `confidence_bucket`, and `warnings`. Structured fields carry `evidence` pointers (block id, page, character offsets, literal quoted text) back into the source so you can verify any claim.
   - `warnings` — issues the pipeline noticed (e.g., a quoted phrase didn't match the source text closely enough).

2. **`bundle.tar.gz`** — everything above, packaged. This is the file the gallformers server will ingest. Keep it; it's the canonical artifact.

To peek at the review JSON quickly:

```bash
uv run python -m json.tool output/mypaper/review_artifact.json | less
```

---

## 8. Re-running and caching

If you run the same pipeline against the same paper a second time, the tool **resumes from cache** — it won't re-call the LLMs for work whose inputs and prompts haven't changed. This is intentional: it means you can stop and restart, or re-run after a config tweak, without paying twice.

- **To re-run a single stage cleanly:** delete the corresponding file in `output/<source-id>/` (e.g., delete `metadata.json` to force a metadata re-extraction).
- **To start completely fresh:** delete the whole `output/<source-id>/` directory.

Caches live alongside the outputs (`*.cache.json`, `*.stage-cache.json`) and are invalidated automatically when **any** of these change between runs: prompt text (`prompt_sha256`), model name, stage config (`n_samples`, `batch_size`, etc.), upstream content hash, bundle `SCHEMA_VERSION`, or the stage's own `STAGE_VERSION` constant.

---

## Known limitations

The pipeline is in alpha. Things that **don't work yet**:

1. **Scanned PDFs go through OCR automatically.** The default pipeline's `ocr` stage runs in `enabled: auto` mode — pages whose text density is below 100 chars/page get an ocrmypdf text layer added before the rest of the pipeline runs. To force OCR on every page set `enabled: always`; to disable, `enabled: never`.

2. **No URL or HTML input.** Only local PDF files for now. (The `extract` subcommand supports URLs in isolation, but it isn't wired into the full `default` pipeline.)

3. **No batch mode.** One paper per `ingest run` invocation. To process many papers, run the command repeatedly with different `--source-id` and `-i` values.

4. **Taxonomy enrichment is limited.** The pipeline attempts a GBIF lookup for each extracted scientific name, but results vary: names that the model couldn't validate against the source text are left unresolved, and WCVP plant-name resolution is server-side (not in this pipeline). Expect to see `taxonomy_lookups: []` for many records.

5. **Bundles don't auto-ingest into gallformers.org yet.** The tool produces `bundle.tar.gz` locally; server-side ingestion of bundles is a separate workstream. For the alpha, share the bundle file directly.

6. **No figure or table extraction.** Text only. Plates, photographs, and structured tables in the PDF are ignored.

7. **Block-triage adds latency.** The new LLM-based noise filter classifies every extracted block (in batches) before downstream stages run. It eliminates running headers, footers, table-of-contents lines, copyright boilerplate, and similar layout noise that would otherwise pollute the curator-facing prose. Adds ~1–2 min on a typical paper; well worth it on documents with heavy layout chrome.

If something else looks broken, send the `output/<source-id>/manifest.json` along with the paper — it records every stage, model, and timing.

---

## Developer reference

The sections below are aimed at developers extending the pipeline. Alpha testers can skip these.

### CLI

Today the CLI exposes a single subcommand:

```
ingest run -s <id> -i <pdf> [-p <yaml>] [-c <yaml>] [-o <dir>]
```

Flags:

| Flag | Long | Required | Default |
|------|------|---------:|---------|
| `-s` | `--source-id` | yes | — |
| `-i` | `--input` | (optional when resuming from cache) | — |
| `-p` | `--pipeline` | no | `pipelines/default.yaml` |
| `-c` | `--config` | no | `providers.yaml` |
| `-o` | `--output` | no | `./output` |

All paths are resolved relative to the CWD (run the CLI from inside `services/source-ingestion/`). The run lands at `<output>/<source-id>/`, and stdout + stderr are tee'd to `<output>/<source-id>/run.log`.

Everything else is driven by the pipeline YAML — individual stages aren't exposed as top-level commands.

### Pipeline stages

The stages a pipeline YAML can reference:

| Stage | LLM? | Description |
|-------|------|-------------|
| `extract` | No | Text extraction via pymupdf (PDF) or trafilatura (URL) |
| `ocr` | No | Conditional OCR via ocrmypdf for pages below text-density threshold |
| `block-triage` | Yes | N-sample LLM filter classifying raw blocks as content vs noise |
| `preprocess` | No | Deterministic cleanup heuristics on the kept blocks |
| `sectionize` | No | Rule-based section detection |
| `metadata` | Yes | Title, authors, year, DOI |
| `find-candidates` | Yes | N=3 self-consistency over candidate gall records; species-level dedup with per-generation emission |
| `evidence-pack` | No | Deterministic per-candidate span gathering; includes sibling-generation candidates' first mention |
| `extract-facts` | Yes | Per-candidate structured field extraction (dynamic-schema) |
| `verify` | No | Substring gate (RapidFuzz partial-ratio) |
| `verify-claims` | Yes | Per-field verification using a different model family |
| `taxonomy-lookup` | No (GBIF API) | Best-effort canonical-name resolution |
| `assemble-review` | No | Roll-up + schema validation |
| `bundle` | No | Tar.gz packaging |

### Pipeline config format

A pipeline YAML declares an ordered list of stages plus shared defaults:

```yaml
pipeline:
  name: my-pipeline
  schema_version: 1.4.0
  seed: 42

  defaults:
    idle_timeout_s: 60
    total_timeout_s: 600
    retry_on_idle: 1
    max_workers: 4
    structured_output: true

  stages:
    - step: extract
      extractor: pymupdf
    - step: preprocess
    - step: sectionize
      excluded_section_types: [references, bibliography]
    - step: metadata
      model: deepinfra/meta-llama/Meta-Llama-3.1-8B-Instruct
      prompt: prompts/metadata.md
    # ... etc
```

See `pipelines/default.yaml` for the canonical production config. Per-stage settings can be overridden by copying the file and editing inline; the runner respects a per-stage `skip: true` flag for bypassing optional stages without commenting out their block.

### Provider configuration

`providers.example.yaml` lists every provider. Each provider has:

- `base_url` — OpenAI-compatible API endpoint
- `env_key` — environment variable name for the API key
- `no_system_role` — set `true` for models that don't support the system role (folds system prompt into user message)
- `models` — list of available model names

Reference a model from a pipeline as `provider/model` (e.g., `deepinfra/deepseek-ai/DeepSeek-V3`).

### Preprocessing heuristics

`preprocess` applies deterministic cleanup tailored for typical journal PDFs (running headers, footers, TOC entries, and similar layout noise are now handled upstream by the LLM-based `block-triage` stage instead):

1. **BHL boilerplate removal** — strips Biodiversity Heritage Library cover-page metadata.
2. **Plate page removal** — drops OCR junk from scanned photograph pages.
3. **Repeated-block detector** (`drop_repeated_blocks`) — frequency-based + monotonic-page-number signal catches anything block-triage missed (defense-in-depth, deterministic, no LLM).
4. **Hyphenation rejoining** — fixes words split across line breaks.
5. **Line rejoining** — merges broken lines back into paragraphs.

### Output structure

The pipeline runner writes all artifacts flat under `output/<source_id>/`. See [section 7](#7-find-your-results) above for the full layout.

### Resumability and caching

Each stage's cache key includes: bundle `SCHEMA_VERSION` (the per-artifact Pydantic version), the stage's own `STAGE_VERSION` constant (bumped by engineers when stage code changes alter outputs — see `CLAUDE.md` for the discipline), `prompt_sha256` of the prompt file, model spec, stage-specific config (`n_samples`, `batch_size`, `agreement_threshold`, …), and a content hash of the stage's upstream input. Any change to any of those invalidates the cache. Sidecars live alongside the artifacts (`*.cache.json`, `*.stage-cache.json`).

### Development

```bash
uv sync
make ci          # lint + format-check + typecheck + test + schemas-check
make test        # tests only
make lint-fix    # auto-fix lint
```

The full check list mirrors what CI runs.
