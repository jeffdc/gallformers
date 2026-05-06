---
status: active
tags: [design]
created: 2026-05-06
updated: 2026-05-06
epic: ingestion
---

# Pipeline configuration

## Design: Named Pipeline Configurations

### Problem

Pipeline LLM settings (model, chunk size, max tokens, timeouts, concurrency) are hardcoded in `config.exs` and module-level defaults. Changing them requires editing code and restarting the server. Users need to experiment with different models and parameters per source document.

### Schema

New `pipeline_configs` table:
- `id` (integer PK)
- `name` (string, unique) — e.g., "default", "fast-deepseek", "local-lmstudio"
- `config` (jsonb) — full config blob
- `timestamps`

Config blob structure:

```json
{
  "client": {
    "api_url": "https://api.deepinfra.com/v1/openai/chat/completions",
    "receive_timeout": 120000,
    "retry_backoffs": [1000, 2000, 4000]
  },
  "llm_clean": {
    "model": "deepseek-ai/DeepSeek-V3-0324",
    "chunk_size": 6000,
    "max_tokens": 8192,
    "max_concurrency": 2,
    "task_timeout_minutes": 10
  },
  "metadata": {
    "model": "deepseek-ai/DeepSeek-V3-0324",
    "max_tokens": 1024,
    "max_input_chars": 24000
  },
  "data_extract": {
    "model": "deepseek-ai/DeepSeek-V3-0324",
    "chunk_size": 3000,
    "max_tokens": 6000,
    "max_concurrency": 2,
    "task_timeout_minutes": 10,
    "json_attempts": 3
  }
}
```

### Association

Add `pipeline_config_id` FK to `source_ingestions`. Set at submission time. Submission form gets a dropdown to pick config.

### Reading config in stages

New `IngestionPipeline.PipelineConfig` module loads the config for a given ingestion and reads nested fields with fallback to existing module defaults:

```elixir
PipelineConfig.get(source_ingestion, :llm_clean, :chunk_size, 6000)
```

Each stage's `config()` private functions change from `Application.get_env` to `PipelineConfig.get`. `LLMClient.completion/4` gets the stage model from pipeline config instead of Application env.

### Admin UI

- `/admin/pipeline-configs` — list of named configs
- `/admin/pipeline-configs/new` and `/:id/edit` — form with one card per stage section
- Current module defaults shown as placeholders

### What stays in Application config

- Storage backend (S3 vs local) — deploy-time
- API keys — env vars
- Oban queue config — structural

### Not in scope

- Multi-provider abstraction (only DeepInfra now)
- Prompt editing via UI
- Pipeline stage reordering
- Config versioning
- Per-ingestion overrides beyond config selection
