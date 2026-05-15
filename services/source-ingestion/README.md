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

You should see a list of subcommands (`run`, `extract`, `metadata`, etc.).

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

The default pipeline is **`north-star-v0`** — tuned for born-digital PDFs.

Pick a paper you have rights to (a PDF you authored, a preprint, an open-access article, etc.) and save it somewhere on your machine. The repo intentionally does **not** ship sample PDFs — most published papers are under copyright and can't be redistributed.

Then run:

```bash
uv run ingest run \
  -p pipelines/north-star-v0.yaml \
  --config providers.yaml \
  --source-id mypaper \
  -i /path/to/your/paper.pdf
```

(On Windows PowerShell, replace the trailing backslashes with backticks `` ` `` or put the whole command on one line.)

Arguments:

- `-p` — which pipeline YAML to run. Use `pipelines/north-star-v0.yaml` unless told otherwise.
- `--config` — path to your provider config. Always `providers.yaml`.
- `--source-id` — a short label you choose. It becomes the output directory name. Use lowercase, no spaces (e.g., `smith-2024`, `mypaper`).
- `-i` — path to the PDF.

### What you'll see

Output is currently sparse — you'll see one line like `Running pipeline 'north-star-v0' for source mypaper` and then silence while it works. A typical paper takes **2–5 minutes** end-to-end.

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
  normalized_text.jsonl  ← after deterministic cleanup
  sections.json          ← rule-based section detection (abstract, methods, etc.)
  metadata.json          ← title, authors, year, DOI
  candidates.json        ← gall records the model thought it found
  claims.json            ← per-record field extractions (raw)
  verified_claims.json   ← same, after a second model double-checks each claim
```

The two files most useful for a human reviewer:

1. **`review_artifact.json`** — the rolled-up, structured result. It contains:
   - `document_metadata` — title, authors, year, DOI, etc.
   - `gall_records` — one entry per gall the model identified. Each has `gall_maker`, `hosts`, `gall_traits`, `description`, `location`, a `confidence_bucket`, and `warnings`. Every field carries `evidence` pointers (block id, page, character offsets, the literal quoted text) back into the source so you can verify any claim.
   - `warnings` — issues the pipeline noticed (e.g., a quoted phrase didn't match the source text closely enough).

2. **`bundle.tar.gz`** — everything above, packaged. This is the file the gallformers server will eventually ingest. Keep it; it's the canonical artifact.

To peek at the review JSON quickly:

```bash
uv run python -m json.tool output/mypaper/review_artifact.json | less
```

---

## 8. Re-running and caching

If you run the same pipeline against the same paper a second time, the tool **resumes from cache** — it won't re-call the LLMs for work whose inputs and prompts haven't changed. This is intentional: it means you can stop and restart, or re-run after a config tweak, without paying twice.

- **To re-run a single stage cleanly:** delete the corresponding file in `output/<source-id>/` (e.g., delete `metadata.json` to force a metadata re-extraction).
- **To start completely fresh:** delete the whole `output/<source-id>/` directory.

Caches live alongside the outputs (`*.cache.json`, `*.stage-cache.json`) and are invalidated automatically if the prompt text or model changes between runs.

---

## Known limitations

The pipeline is in alpha. Things that **don't work yet**:

1. **Scanned / image-only PDFs are not supported.** The pipeline reads the PDF's text layer directly. If your paper is a scan with no real text (you can't select text in a PDF reader), the output will be empty or garbage. A separate OCR pipeline exists but is out of scope for this alpha.

2. **No URL or HTML input.** Only local PDF files for now. (The `extract` subcommand supports URLs in isolation, but it isn't wired into the full `north-star-v0` pipeline.)

3. **No batch mode.** One paper per `ingest run` invocation. To process many papers, run the command repeatedly with different `--source-id` and `-i` values.

4. **Taxonomy enrichment is limited.** The pipeline attempts a GBIF lookup for each extracted scientific name, but results vary: names that the model couldn't validate against the source text are left unresolved, and WCVP plant-name resolution is server-side (not in this pipeline). Expect to see `taxonomy_lookups: []` for many records.

5. **Bundles don't auto-ingest into gallformers.org yet.** The tool produces `bundle.tar.gz` locally; server-side ingestion of bundles is a separate workstream. For the alpha, share the bundle file directly.

6. **No figure or table extraction.** Text only. Plates, photographs, and structured tables in the PDF are ignored.

7. **Output is text-light while running.** The CLI prints one line at the start and nothing until it's done. If you want a sign of life, watch `output/<source-id>/` for new files appearing.

If something else looks broken, send the `output/<source-id>/manifest.json` along with the paper — it records every stage, model, and timing.

---

## Developer reference

The sections below are aimed at developers extending the pipeline. Alpha testers can skip these.

### CLI

Today the CLI exposes a single subcommand:

```
ingest run --pipeline <yaml> --source-id <id> --input <pdf> [--config <yaml>] [--output <dir>]
```

Everything else is driven by the pipeline YAML — individual stages aren't exposed as top-level commands.

### Pipeline stages

The stages a pipeline YAML can reference:

| Stage | LLM? | Description |
|-------|------|-------------|
| `extract` | No | Text extraction via pymupdf (PDF) or trafilatura (URL) |
| `preprocess` | No | Deterministic cleanup heuristics |
| `sectionize` | No | Rule-based section detection |
| `metadata` | Yes | Title, authors, year, DOI |
| `find-candidates` | Yes | N=3 self-consistency over candidate gall records |
| `evidence-pack` | No | Deterministic per-candidate span gathering |
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
  schema_version: 1.0.0
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

See `pipelines/north-star-v0.yaml` for the canonical production config and `pipelines/north-star-v0-stub.yaml` for a stub (no LLM cost) variant useful for plumbing tests.

### Provider configuration

`providers.example.yaml` lists every provider. Each provider has:

- `base_url` — OpenAI-compatible API endpoint
- `env_key` — environment variable name for the API key
- `no_system_role` — set `true` for models that don't support the system role (folds system prompt into user message)
- `models` — list of available model names

Reference a model from a pipeline as `provider/model` (e.g., `deepinfra/deepseek-ai/DeepSeek-V3`).

### Preprocessing heuristics

`preprocess` applies deterministic cleanup tailored for typical journal PDFs:

1. BHL boilerplate removal — strips Biodiversity Heritage Library cover-page metadata
2. Plate page removal — drops OCR junk from scanned photograph pages
3. Page header stripping — removes running headers, journal names, page numbers
4. Hyphenation rejoining — fixes words split across line breaks
5. Line rejoining — merges broken lines back into paragraphs

### Output structure

The pipeline runner writes all artifacts flat under `output/<source_id>/`. See [section 7](#7-find-your-results) above for the full layout.

### Resumability and caching

Caching is **prompt-SHA aware**: if a stage's input bytes, prompt text, model spec, and configuration hash all match what's in the cache, the LLM call is skipped. Otherwise the cache entry is invalidated and the stage re-runs. Cache files live alongside the artifacts (`*.cache.json`, `*.stage-cache.json`).

### Development

```bash
uv sync
make ci          # lint + format-check + typecheck + test + schemas-check
make test        # tests only
make lint-fix    # auto-fix lint
```

The full check list mirrors what CI runs.
