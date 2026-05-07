---
status: planned
tags: [design]
created: 2026-05-07
updated: 2026-05-07
epic: admin
---

# Named pipeline configs with DB-backed default

## Design

Replace the implicit "module defaults" fallback with a required DB-backed default pipeline config.

### Schema change
Add `is_default :boolean, default: false` to `pipeline_configs`. Partial unique index: `CREATE UNIQUE INDEX ... ON pipeline_configs (is_default) WHERE is_default = true` — enforces at most one default at the DB level.

### Migration
- Add `is_default` column
- Seed one record: name "DeepInfra Qwen 72B", `is_default: true`, full config map:
  - client: api_url deepinfra, receive_timeout 300_000, retry_backoffs [1000, 2000, 4000]
  - llm_clean: model Qwen/Qwen2.5-72B-Instruct, chunk_size 6000, max_tokens 4096, max_concurrency 2, task_timeout_minutes 10
  - metadata: model Qwen/Qwen2.5-72B-Instruct, max_tokens 1024, max_input_chars 24_000
  - data_extract: model Qwen/Qwen2.5-72B-Instruct, chunk_size 3000, max_tokens 8192, max_concurrency 2, task_timeout_minutes 10, json_attempts 3

### Context (PipelineConfigs)
- `get_default/0` — returns the default config or nil
- `set_default/1` — transaction: unset old default, set new one
- Delete guard: cannot delete config where `is_default: true`

### PipelineConfigReader
- When `pipeline_config_id` is nil, load the default config instead of returning nil
- Key behavioral change: every ingestion gets a real config

### UI — Ingestion review
- Dropdown pre-selects the default config
- Remove "Default (module defaults)" option — always a DB-backed default

### UI — Pipeline config admin
- Show which config is the default
- Allow changing the default

### Stage @default_* attrs
- Keep as ultimate fallbacks for missing keys within a config map
- Should never fire for the seeded record (all keys present)
