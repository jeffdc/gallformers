"""LLM-based text cleanup and metadata extraction."""

from __future__ import annotations

import json
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field

from openai import APIError, OpenAI

from ingest.prompts import (
    CLEANUP_SYSTEM_PROMPT,
    DATA_EXTRACT_SYSTEM_PROMPT,
    METADATA_SYSTEM_PROMPT,
)
from ingest.providers import ProviderConfig


@dataclass(frozen=True)
class TokenUsage:
    """Token usage from a single LLM call."""

    prompt_tokens: int
    completion_tokens: int


@dataclass(frozen=True)
class CleanupResult:
    """Result of cleaning text via LLM."""

    text: str
    usage: TokenUsage


@dataclass(frozen=True)
class DataExtractResult:
    """Result of structured data extraction from scholarly text."""

    records: list[dict] = field(default_factory=list)
    usage: TokenUsage = field(default_factory=lambda: TokenUsage(0, 0))


@dataclass(frozen=True)
class MetadataResult:
    """Extracted bibliographic metadata."""

    title: str | None = None
    authors: list[str] = field(default_factory=list)
    year: int | None = None
    doi: str | None = None
    usage: TokenUsage = field(default_factory=lambda: TokenUsage(0, 0))


def _call_llm(
    system_prompt: str,
    user_text: str,
    provider: ProviderConfig,
    max_tokens: int = 8192,
    merge_prompt: bool = False,
) -> tuple[str, TokenUsage]:
    """Send a chat completion request and return (content, usage).

    Args:
        system_prompt: System prompt for the LLM.
        user_text: User content to process.
        provider: LLM provider configuration.
        max_tokens: Maximum completion tokens. Prevents providers from
            allocating the full context window, which causes slow generation.
        merge_prompt: If True, merge system prompt into the user message
            regardless of provider setting. Useful for complex structured
            prompts that models follow better as user content.

    Raises:
        RuntimeError: If the API call fails.
    """
    client = OpenAI(base_url=provider.base_url, api_key=provider.api_key)

    if provider.no_system_role or merge_prompt:
        messages: list[dict[str, str]] = [
            {"role": "user", "content": f"{system_prompt}\n\n---\n\n{user_text}"},
        ]
    else:
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_text},
        ]

    try:
        response = client.chat.completions.create(
            model=provider.model,
            messages=messages,  # type: ignore[arg-type]
            max_tokens=max_tokens,
        )
    except APIError as exc:
        raise RuntimeError(f"LLM API call failed: {exc}") from exc

    content = response.choices[0].message.content
    if content is None:
        raise RuntimeError("LLM returned empty response")
    usage = TokenUsage(
        prompt_tokens=response.usage.prompt_tokens,  # type: ignore[union-attr]
        completion_tokens=response.usage.completion_tokens,  # type: ignore[union-attr]
    )
    return content, usage


def _estimate_tokens(text: str) -> int:
    """Rough token estimate: ~4 characters per token."""
    return len(text) // 4


def _chunk_text(text: str, max_tokens: int) -> list[str]:
    """Split text into chunks that fit within max_tokens.

    Splits on paragraph boundaries (double newlines). If a single paragraph
    exceeds max_tokens, it goes into its own chunk.
    """
    paragraphs = text.split("\n\n")
    chunks: list[str] = []
    current: list[str] = []
    current_tokens = 0

    for para in paragraphs:
        para_tokens = _estimate_tokens(para)
        if current and current_tokens + para_tokens > max_tokens:
            chunks.append("\n\n".join(current))
            current = [para]
            current_tokens = para_tokens
        else:
            current.append(para)
            current_tokens += para_tokens

    if current:
        chunks.append("\n\n".join(current))

    return chunks


# Default max tokens for user content per chunk. Leaves room for system prompt
# and completion within a typical context window.
DEFAULT_CHUNK_MAX_TOKENS = 6000

# Smaller chunks for data extraction — each record produces ~400 tokens of JSON
# output, so smaller input chunks keep the output within limits and help the
# model find all associations.
EXTRACT_CHUNK_MAX_TOKENS = 3000


def clean_text(
    text: str,
    provider: ProviderConfig,
    chunk_max_tokens: int = DEFAULT_CHUNK_MAX_TOKENS,
    cache_dir: str | None = None,
) -> CleanupResult:
    """Clean and format extracted text using an LLM.

    If the text exceeds chunk_max_tokens, it is split into chunks on paragraph
    boundaries. Each chunk is cleaned separately and the results are joined.

    When cache_dir is provided, each cleaned chunk is saved to
    ``{cache_dir}/chunk_{i}.md`` and loaded on subsequent runs instead of
    re-calling the LLM.

    Args:
        text: Raw extracted text to clean.
        provider: LLM provider configuration.
        chunk_max_tokens: Max estimated tokens per chunk.
        cache_dir: Optional directory for caching cleaned chunks.

    Returns:
        CleanupResult with cleaned text and token usage.

    Raises:
        RuntimeError: If the API call fails.
    """
    from pathlib import Path

    import click

    chunks = _chunk_text(text, chunk_max_tokens)
    results: list[str | None] = [None] * len(chunks)
    total_prompt = 0
    total_completion = 0

    if cache_dir:
        Path(cache_dir).mkdir(parents=True, exist_ok=True)

    # Separate cached vs uncached chunks
    uncached: list[tuple[int, str]] = []  # (index, chunk_text)
    for i, chunk in enumerate(chunks):
        chunk_cache = Path(cache_dir) / f"chunk_{i + 1}.md" if cache_dir else None
        if chunk_cache and chunk_cache.exists():
            click.echo(f"  Loading cached chunk {i + 1}/{len(chunks)}")
            results[i] = chunk_cache.read_text()
        else:
            uncached.append((i, chunk))

    # Process uncached chunks in parallel
    if uncached:
        if len(chunks) > 1:
            click.echo(f"  Cleaning {len(uncached)} chunks in parallel...")

        def _process_chunk(idx_chunk: tuple[int, str]) -> tuple[int, str, TokenUsage]:
            idx, chunk = idx_chunk
            content, usage = _call_llm(
                CLEANUP_SYSTEM_PROMPT, chunk, provider, max_tokens=chunk_max_tokens
            )
            return idx, content, usage

        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {executor.submit(_process_chunk, item): item for item in uncached}
            for future in as_completed(futures):
                idx, content, usage = future.result()
                results[idx] = content
                total_prompt += usage.prompt_tokens
                total_completion += usage.completion_tokens
                if len(chunks) > 1:
                    click.echo(f"  Chunk {idx + 1}/{len(chunks)} done.")
                chunk_cache = (
                    Path(cache_dir) / f"chunk_{idx + 1}.md" if cache_dir else None
                )
                if chunk_cache:
                    chunk_cache.write_text(content)

    return CleanupResult(
        text="\n\n".join(results),  # type: ignore[arg-type]
        usage=TokenUsage(
            prompt_tokens=total_prompt, completion_tokens=total_completion
        ),
    )


def extract_metadata(text: str, provider: ProviderConfig) -> MetadataResult:
    """Extract bibliographic metadata from document text using an LLM.

    Sends the text with METADATA_SYSTEM_PROMPT and parses the JSON response.

    Args:
        text: Document text to extract metadata from.
        provider: LLM provider configuration.

    Returns:
        MetadataResult with extracted fields and token usage.

    Raises:
        RuntimeError: If the API call fails or JSON parsing fails.
    """
    # Metadata is in the first few pages — truncate to save tokens.
    max_chars = DEFAULT_CHUNK_MAX_TOKENS * 4
    truncated = text[:max_chars] if len(text) > max_chars else text
    content, usage = _call_llm(
        METADATA_SYSTEM_PROMPT, truncated, provider, max_tokens=1024
    )

    data = _extract_json(content)

    return MetadataResult(
        title=data.get("title"),
        authors=data.get("authors", []),
        year=data.get("year"),
        doi=data.get("doi"),
        usage=usage,
    )


def extract_data(
    text: str,
    provider: ProviderConfig,
    chunk_max_tokens: int = EXTRACT_CHUNK_MAX_TOKENS,
    cache_dir: str | None = None,
) -> DataExtractResult:
    """Extract structured gall records from scholarly text using an LLM.

    If the text exceeds chunk_max_tokens, it is split into chunks on paragraph
    boundaries. Each chunk is processed separately and the resulting JSON arrays
    are merged.

    Args:
        text: Cleaned scholarly text to extract data from.
        provider: LLM provider configuration.
        chunk_max_tokens: Max estimated tokens per chunk.
        cache_dir: Optional directory for caching per-chunk results.

    Returns:
        DataExtractResult with merged records list and summed token usage.

    Raises:
        RuntimeError: If the API call fails or JSON parsing fails.
    """
    from pathlib import Path

    import click

    chunks = _chunk_text(text, chunk_max_tokens)
    chunk_records: list[list[dict] | None] = [None] * len(chunks)
    total_prompt = 0
    total_completion = 0

    if cache_dir:
        Path(cache_dir).mkdir(parents=True, exist_ok=True)

    # Separate cached vs uncached chunks
    uncached: list[tuple[int, str]] = []
    for i, chunk in enumerate(chunks):
        chunk_cache = Path(cache_dir) / f"chunk_{i + 1}.json" if cache_dir else None
        if chunk_cache and chunk_cache.exists():
            click.echo(f"  Loading cached chunk {i + 1}/{len(chunks)}")
            chunk_records[i] = json.loads(chunk_cache.read_text())
        else:
            uncached.append((i, chunk))

    # Process uncached chunks in parallel
    if uncached:
        if len(chunks) > 1:
            click.echo(f"  Extracting {len(uncached)} chunks in parallel...")

        def _process_chunk(
            idx_chunk: tuple[int, str],
        ) -> tuple[int, list[dict], TokenUsage]:
            idx, chunk = idx_chunk
            content, usage = _call_llm(
                DATA_EXTRACT_SYSTEM_PROMPT,
                chunk,
                provider,
                max_tokens=chunk_max_tokens * 2,
                merge_prompt=True,
            )
            records = _extract_json_array(content)
            return idx, records, usage

        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {executor.submit(_process_chunk, item): item for item in uncached}
            for future in as_completed(futures):
                item = futures[future]
                try:
                    idx, records, usage = future.result()
                except RuntimeError as e:
                    idx = item[0]
                    click.echo(f"  Chunk {idx + 1}/{len(chunks)} failed: {e}", err=True)
                    chunk_records[idx] = []
                    continue
                chunk_records[idx] = records
                total_prompt += usage.prompt_tokens
                total_completion += usage.completion_tokens
                if len(chunks) > 1:
                    click.echo(
                        f"  Chunk {idx + 1}/{len(chunks)} done ({len(records)} records)."
                    )
                chunk_cache = (
                    Path(cache_dir) / f"chunk_{idx + 1}.json" if cache_dir else None
                )
                if chunk_cache:
                    chunk_cache.write_text(json.dumps(records, indent=2))

    # Merge records in order
    all_records: list[dict] = []
    for records in chunk_records:
        if records:
            all_records.extend(records)

    return DataExtractResult(
        records=all_records,
        usage=TokenUsage(
            prompt_tokens=total_prompt, completion_tokens=total_completion
        ),
    )


def _extract_json_array(content: str) -> list[dict]:
    """Best-effort JSON array extraction from LLM output.

    Handles: raw JSON arrays, markdown-fenced JSON, preamble text before JSON,
    and truncated JSON (returns all complete objects found).
    """
    # Try fenced JSON first
    fence_match = re.search(r"```(?:json)?\s*\n(.*?)(?:\n?```|$)", content, re.DOTALL)
    candidate = fence_match.group(1).strip() if fence_match else content.strip()

    # If no fence, find the first '['
    if not candidate.startswith("["):
        bracket_pos = candidate.find("[")
        if bracket_pos >= 0:
            candidate = candidate[bracket_pos:]

    try:
        result = json.loads(candidate)
        if isinstance(result, list):
            return result
        return [result]
    except json.JSONDecodeError:
        pass

    # Truncated JSON — find the last complete object by searching backwards
    # for "},\n" or "}\n]" patterns, then close the array.
    last_complete = _find_last_complete_object(candidate)
    if last_complete:
        try:
            result = json.loads(last_complete)
            if isinstance(result, list):
                return result
            return [result]
        except json.JSONDecodeError:
            pass

    raise RuntimeError(
        f"Could not extract JSON array from LLM response.\n"
        f"Response was: {content[:500]}"
    )


def _find_last_complete_object(candidate: str) -> str | None:
    """Find the last complete top-level object in a truncated JSON array.

    Searches backwards for closing braces that end a complete top-level object,
    then closes the array.
    """
    # Track brace/bracket depth to find where top-level objects end
    depth = 0
    in_string = False
    escape = False
    last_obj_end = -1

    for i, ch in enumerate(candidate):
        if escape:
            escape = False
            continue
        if ch == "\\" and in_string:
            escape = True
            continue
        if ch == '"' and not escape:
            in_string = not in_string
            continue
        if in_string:
            continue

        if ch == "[" or ch == "{":
            depth += 1
        elif ch == "]" or ch == "}":
            depth -= 1
            # depth==1 means we just closed a top-level object inside the array
            if depth == 1 and ch == "}":
                last_obj_end = i

    if last_obj_end > 0:
        return candidate[: last_obj_end + 1] + "\n]"
    return None


def _extract_json(content: str) -> dict:
    """Best-effort JSON extraction from LLM output.

    Handles: raw JSON, markdown-fenced JSON, preamble text before JSON,
    and truncated JSON (returns whatever fields were complete).
    """
    # Try fenced JSON first
    fence_match = re.search(r"```(?:json)?\s*\n(.*?)(?:\n?```|$)", content, re.DOTALL)
    candidate = fence_match.group(1).strip() if fence_match else content.strip()

    # If no fence, find the first '{'
    if not candidate.startswith("{"):
        brace_pos = candidate.find("{")
        if brace_pos >= 0:
            candidate = candidate[brace_pos:]

    # Try parsing as-is
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        pass

    # Truncated JSON — try progressively closing open structures
    closers = ['"}', '"}]', '"]}', '"]}}', "}", "]}", "]}"]
    for suffix in closers:
        try:
            return json.loads(candidate + suffix)
        except json.JSONDecodeError:
            continue

    raise RuntimeError(
        f"Could not extract JSON from LLM response.\nResponse was: {content[:500]}"
    )
