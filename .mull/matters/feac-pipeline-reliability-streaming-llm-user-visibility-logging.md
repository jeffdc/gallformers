---
status: done
tags: [design]
created: 2026-05-07
updated: 2026-05-07
epic: admin
---

# Pipeline reliability: streaming LLM, user visibility, logging

## Design

Three-pronged fix for pipeline reliability, user visibility, and engineering observability.

### 1. Streaming LLM Client

Replace synchronous Req.post in LLMClient with SSE streaming via Req's `into:` callback.

- Send `stream: true` and `stream_options: %{continuous_usage_stats: true}` in request body
- Parse SSE `data:` lines, accumulate content tokens, track running token count
- On each SSE event: update running metrics (tokens so far, elapsed, tokens/sec)
- On stream complete: return `{:ok, content, usage}` (same interface) with new fields: tokens_per_sec, estimated_cost, truncated (finish_reason == "length")
- **Stall timeout** replaces monolithic receive_timeout: if no SSE event for N seconds (configurable, default 60s), kill request. As long as tokens flow, it runs indefinitely.
- SSE parsing is ~30 lines on top of Req's `into:` callback — no new dependencies
- Targets OpenAI-compatible SSE contract (works with DeepInfra and OpenRouter)

### 2. Chunk-level Progress Broadcasting

Stages running LLM requests (llm_clean, metadata, data_extract) broadcast chunk-level progress via existing PubSub:

- New message: `{:chunk_progress, stage, %{chunk: N, total_chunks: M, tokens: T, tokens_per_sec: R}}`
- Sent after each chunk's LLM call completes (not per-SSE-event)
- On truncation: `{:chunk_warning, stage, %{message: "...", chunk: N}}`
- Existing broadcast_progress/3 (percent-based) still works for overall stage progress

### 3. User-Facing Activity Line

Compact live-updating line below progress bar on Show page:

- While processing: "Chunk 3/12 — 847 tokens, 142 tok/sec"
- On truncation: "Chunk 3 output truncated (8192 tokens) — retrying with split" (amber)
- On completion: "12 chunks processed — 4,230 tokens extracted, avg 156 tok/sec"
- On failure: actionable message ("Chunk 3 timed out after 60s stall — source may be too info-dense for current chunk size") instead of bare "timeout"
- Implemented via new PubSub messages updating a Show LiveView assign — just a `<p>` tag with conditional styling

### 4. Logging Cleanup

**Dev logger metadata** — add to allowlist in config/dev.exs:
- :reason, :attempt, :max_attempts (failure diagnostics)
- :tokens_per_sec, :estimated_cost, :truncated, :finish_reason (streaming metrics)
- :chunk, :total_chunks (chunk context)

**Heartbeat filter** — Custom telemetry handler on [:gallformers, :repo, :query] that drops parameterless SELECT 1 queries. ~5 lines, wired in Application.start/2.

**LLM log lines** become richer (stage, chunk N/M, model, input/output chars, tokens/sec, cost, truncated, elapsed_ms). Failure lines always include reason, attempt, max_attempts.

### 5. Provider Flexibility

Streaming targets OpenAI-compatible SSE contract. OpenRouter uses same format. Pipeline config client.api_url already supports provider switching. estimated_cost is DeepInfra-specific; handled gracefully when absent (nil).

### Context

Ingestion 8 failed all 3 Oban attempts: timeouts on attempts 1 and 3, CaseClauseError on attempt 2 (invalid_contract from since-removed vocab validation). Root cause: monolithic HTTP timeout too low for info-dense documents, no way to distinguish stall from slow-but-working, and no diagnostics surfaced to user or logs.

## Implementation Plan

**Goal:** Replace synchronous LLM requests with SSE streaming to eliminate timeouts, surface real-time chunk progress to users, and make logs actionable for debugging.

**Architecture:** New SSE parser module handles stream parsing as pure functions. LLMClient switches its internal HTTP call to streaming while keeping the same external interface. Stages pass chunk index context through to the broadcaster. Show LiveView handles new PubSub messages for a live activity line.

**Tech Stack:** Req `into:` callback for SSE transport, existing PubSub/Broadcaster for progress, Phoenix LiveView for UI updates. No new dependencies.

### Task 1: Logging Cleanup

Quick win — immediately improves debugging before any streaming work.

**Files:**
- Modify: `config/dev.exs` (add metadata keys to logger allowlist)
- Create: `lib/gallformers/repo/telemetry_filter.ex` (heartbeat filter)
- Modify: `lib/gallformers/application.ex` (attach telemetry handler)
- Test: `test/gallformers/repo/telemetry_filter_test.exs`

**Behavior:**
Add `:reason`, `:attempt`, `:max_attempts`, `:tokens_per_sec`, `:estimated_cost`, `:truncated`, `:finish_reason`, `:chunk`, `:total_chunks` to the dev logger metadata allowlist in `config/dev.exs`.

Create `Gallformers.Repo.TelemetryFilter` that attaches to `[:gallformers, :repo, :query]` telemetry events. On each event, check if the query is a parameterless `SELECT 1` (DBConnection heartbeat). If so, set the log level to `false` to suppress it. Otherwise pass through.

Wire the telemetry handler in `Application.start/2` after the supervisor starts, using `:telemetry.attach/4`.

**Testing:**
- Telemetry handler suppresses SELECT 1 with empty params
- Telemetry handler passes through normal queries (SELECT with params, INSERT, etc.)
- Telemetry handler passes through SELECT 1 that has params (defensive)

**Notes:**
Ecto's telemetry metadata includes `:query` (the SQL string) and `:params` (the parameter list). The heartbeat is `"SELECT 1"` with `params: []` and `source: nil`. Match on all three to be precise.

### Task 2: SSE Parser Module

Foundation for streaming. Pure functions, no side effects, easy to test thoroughly.

**Files:**
- Create: `lib/gallformers/ingestion_pipeline/sse_parser.ex`
- Test: `test/gallformers/ingestion_pipeline/sse_parser_test.exs`

**Behavior:**
Module `Gallformers.IngestionPipeline.SSEParser` provides:

`new/0` — returns an initial accumulator state:
```elixir
%{
  buffer: "",           # partial line buffer for TCP frame boundaries
  content: [],          # iolist of content deltas (reversed, joined at end)
  usage: nil,           # latest usage map from continuous_usage_stats
  finish_reason: nil,   # "stop", "length", etc.
  done: false           # true after [DONE] sentinel
}
```

`feed/2` — takes state and a raw binary chunk from Req's `into:` callback. Prepends `buffer` to the chunk, splits on `\n`, keeps incomplete last line as new buffer. For each complete line:
- Skip empty lines and lines starting with `:` (SSE comments)
- Strip `data: ` prefix
- If remaining text is `[DONE]`, set `done: true`
- Otherwise JSON-decode the data object, extract `choices[0].delta.content` and append to content iolist. Extract `usage` if present. Extract `finish_reason` from `choices[0]` if non-null.

Returns `{events_count, updated_state}` where `events_count` is the number of content deltas processed in this feed (used for stall detection — 0 events means no new content).

`finish/1` — takes final state, returns:
```elixir
{:ok, content_string, %{
  prompt_tokens: integer,
  completion_tokens: integer,
  estimated_cost: float | nil,
  finish_reason: String.t(),
  truncated: boolean
}}
```
Joins the content iolist, extracts usage fields. `truncated` is `finish_reason == "length"`. `estimated_cost` is nil if not present (non-DeepInfra providers).

Returns `{:error, :incomplete_stream}` if `done` is false and content is empty.

**Testing:**
- Parse a single complete SSE event with content delta
- Parse multiple events in one chunk (TCP coalescing)
- Parse event split across two chunks (TCP fragmentation)
- Handle `[DONE]` sentinel
- Extract usage from final chunk (DeepInfra default: include_usage true)
- Extract usage from intermediate chunks (continuous_usage_stats)
- Handle `finish_reason: "length"` → truncated: true
- Handle `finish_reason: "stop"` → truncated: false
- Handle missing `estimated_cost` gracefully (nil)
- Handle SSE comment lines (`:` prefix) — skip them
- Handle empty content delta (some providers send empty deltas)
- `finish/1` on empty/incomplete stream returns error

**Notes:**
Use real SSE payloads from DeepInfra docs as test fixtures. The content iolist approach avoids string concatenation on every token — only join once at the end.

### Task 3: Streaming LLMClient

Replace synchronous HTTP with streaming. External interface stays the same.

**Files:**
- Modify: `lib/gallformers/ingestion_pipeline/llm_client.ex`
- Modify: `test/gallformers/ingestion_pipeline/llm_client_test.exs`

**Behavior:**

**Request body changes:**
`request_body/4` adds `"stream" => true` and `"stream_options" => %{"include_usage" => true, "continuous_usage_stats" => true}`.

**New `default_request` using streaming:**
Replace the current `Req.post` call with `Req.post(into: callback)` where the callback:
1. Creates an SSEParser state
2. On each `{:data, chunk}`: feed it to `SSEParser.feed/2`, reset a stall timer
3. On stream end: call `SSEParser.finish/1`

Stall timeout: Use `Process.send_after/3` to schedule a `:stall_timeout` message. After each successful `feed` that produces events, cancel the old timer and start a new one. If the timer fires (no events for N seconds), abort the request.

The default stall timeout is 60 seconds, configurable via `stall_timeout` in pipeline config's client section (replaces `receive_timeout` conceptually).

**Enriched usage map:**
`completion/4` now returns usage with additional fields:
```elixir
%{
  prompt_tokens: integer,
  completion_tokens: integer,
  tokens_per_sec: float,
  estimated_cost: float | nil,
  finish_reason: String.t(),
  truncated: boolean
}
```
`tokens_per_sec` is calculated as `completion_tokens / (elapsed_ms / 1000)`.

**Enriched logging:**
`log_result/5` adds `:tokens_per_sec`, `:estimated_cost`, `:truncated`, `:finish_reason` to metadata.

**Retry behavior:**
Server errors (5xx) and stall timeouts still retry with backoffs, same as today. The retry logic in `do_completion` doesn't change — it just calls the new streaming `default_request` instead of the old synchronous one.

**Backward compat for tests:**
The existing `request_fun` injection still works — tests inject a function returning `{:ok, %{status: 200, body: %{...}}}` which bypasses `default_request` entirely. When `request_fun` is set, the old synchronous path runs. Only `default_request` (production path) uses streaming.

**Testing:**
- Existing tests continue to pass unchanged (they use request_fun injection)
- New test: `stall_timeout` fires when no events arrive (use a request_fun that sleeps)
- New test: usage map includes `tokens_per_sec`, `truncated`, `finish_reason`
- New test: `estimated_cost` is nil when not in response (OpenRouter compat)
- New test: request body includes `stream: true` and `stream_options`

**Notes:**
The `into:` callback in Req receives `{:data, binary}` chunks. The callback must return `{:cont, {req, resp}}` to continue or `{:halt, {req, resp}}` to abort. For stall timeout, use `:halt` to abort.

Req streaming with `into:` — the response body is whatever the callback accumulates, not the raw body. We'll accumulate into the SSEParser state and extract the result after the request completes.

### Task 4: Broadcaster Chunk Messages

**Files:**
- Modify: `lib/gallformers/ingestion_pipeline/broadcaster.ex`
- Modify: `test/gallformers/ingestion_pipeline/broadcaster_test.exs`

**Behavior:**
Add two new broadcast functions:

`broadcast_chunk_progress/4` — broadcasts `{:chunk_progress, stage, progress_map}` where progress_map is `%{chunk: integer, total_chunks: integer, tokens: integer, tokens_per_sec: float}`.

`broadcast_chunk_warning/3` — broadcasts `{:chunk_warning, stage, warning_map}` where warning_map is `%{message: String.t(), chunk: integer}`.

**Testing:**
- Subscribe to topic, call broadcast_chunk_progress, assert message received with correct shape
- Subscribe to topic, call broadcast_chunk_warning, assert message received with correct shape

### Task 5: Stage Modules — Chunk Progress and Timeout Changes

**Files:**
- Modify: `lib/gallformers/ingestion_pipeline/stages/llm_clean.ex`
- Modify: `lib/gallformers/ingestion_pipeline/stages/metadata.ex`
- Modify: `lib/gallformers/ingestion_pipeline/stages/data_extract.ex`
- Modify: `lib/gallformers/ingestion_pipeline/stages/llm_support.ex` (reduce_async_result)
- Modify tests in `test/gallformers/ingestion_pipeline/stages/` as needed

**Behavior:**

**Task.async_stream timeout → :infinity:**
All three stage modules change `timeout: task_timeout(ingestion)` to `timeout: :infinity` in their `Task.async_stream` calls. The stall timeout in LLMClient is now the safety valve. Remove `task_timeout/1` and the `@default_task_timeout` constants from llm_clean and data_extract (and the `task_timeout_minutes` pipeline config key — dead config).

**Chunk context threading:**
`extract_chunks` and `clean_chunks` currently map over chunks without index. Change to `Enum.with_index(chunks, 1)` and pass `{chunk, chunk_index}` tuples through async_stream. After each chunk's LLM call completes, broadcast chunk progress.

For llm_clean and data_extract (multi-chunk stages):
```elixir
# After successful LLM call for a chunk:
Broadcaster.broadcast_chunk_progress(ingestion.id, :data_extract, %{
  chunk: chunk_index,
  total_chunks: total_chunks,
  tokens: usage.completion_tokens,
  tokens_per_sec: usage.tokens_per_sec
})
```

For data_extract truncation detection:
```elixir
# When truncation detected (usage.truncated == true):
Broadcaster.broadcast_chunk_warning(ingestion.id, :data_extract, %{
  message: "Output truncated at #{usage.completion_tokens} tokens — retrying with split",
  chunk: chunk_index
})
```

**metadata stage** is single-chunk (no chunking), so it broadcasts one progress event with chunk: 1, total_chunks: 1.

**reduce_async_result in LLMSupport:**
No changes needed — it already handles `{:ok, result}` and `{:exit, reason}`. The chunk_index doesn't affect the reducer since broadcasting happens inside the chunk function before returning.

**Testing:**
- Verify Task.async_stream no longer has a finite timeout
- Verify broadcast messages are sent with correct chunk/total_chunks after LLM calls (in stage tests that mock the LLM client)

**Notes:**
The `total_chunks` count is known before async_stream starts — pass it through as a closure variable. The chunk_index is from `Enum.with_index`.

### Task 6: Show Page — Activity Line

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/show.ex`

**Behavior:**

New assigns: `:activity_text` (string, default nil), `:activity_style` (atom, :normal | :warning | :success, default :normal).

Handle new PubSub messages:

`handle_info({:chunk_progress, stage, progress}, socket)` — update `:activity_text` to "Chunk #{progress.chunk}/#{progress.total_chunks} — #{progress.tokens} tokens, #{round(progress.tokens_per_sec)} tok/sec". Set `:activity_style` to `:normal`.

`handle_info({:chunk_warning, stage, warning}, socket)` — update `:activity_text` to warning.message. Set `:activity_style` to `:warning`.

On `{:stage_complete, _stage}` (existing handler): update `:activity_text` to nil (clear it — the progress bar already shows stage completion).

On `{:error, stage, reason}` (existing handler): set `:activity_text` to an actionable description of the failure. For `:timeout` → "Processing stalled — source may be too information-dense for current chunk size". For `{:invalid_contract, messages}` → "Validation error: #{Enum.join(messages, "; ")}". For other reasons → inspect(reason). Set `:activity_style` to `:warning`.

**Render:**
Below the `<.pipeline_progress>` component, add:
```heex
<p :if={@activity_text} class={[
  "text-xs mt-2 font-mono",
  activity_text_class(@activity_style)
]}>
  {@activity_text}
</p>
```

`activity_text_class(:normal)` → "text-gray-500"
`activity_text_class(:warning)` → "text-amber-600"
`activity_text_class(:success)` → "text-green-600"

**Testing:**
This is UI behavior — verify by running the dev server and submitting an ingestion. The progress line should update in real-time as chunks complete.

**Notes:**
The existing `handle_info({:progress, _stage, _percent}, socket)` that currently does nothing (`{:noreply, socket}`) stays as-is for now. The new chunk_progress messages are a different shape and carry richer data.
