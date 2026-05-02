"""Tests for LLM cleanup and metadata extraction."""

import json
import time
from unittest.mock import Mock

import pytest
from openai import APIError

from ingest.llm import (
    CleanupResult,
    DataExtractResult,
    MetadataResult,
    TokenUsage,
    _chunk_text,
    clean_text,
    extract_data,
    extract_metadata,
)
from ingest.prompts import (
    CLEANUP_SYSTEM_PROMPT,
    DATA_EXTRACT_SYSTEM_PROMPT,
    METADATA_SYSTEM_PROMPT,
)
from ingest.providers import ProviderConfig


@pytest.fixture()
def provider():
    """Return a test provider config."""
    return ProviderConfig(
        base_url="https://api.test.com/v1",
        api_key="test-key-123",
        model="test-model",
    )


@pytest.fixture()
def mock_openai(mocker):
    """Mock the OpenAI client and return helper to configure responses."""
    mock_cls = mocker.patch("ingest.llm.OpenAI")
    mock_client = mock_cls.return_value

    def configure(content="response text", prompt_tokens=100, completion_tokens=50):
        mock_response = Mock()
        mock_response.choices = [Mock(message=Mock(content=content))]
        mock_response.usage = Mock(
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
        )
        mock_client.chat.completions.create.return_value = mock_response
        return mock_client

    return configure


class TestPrompts:
    def test_cleanup_system_prompt_well_formed(self):
        prompt = CLEANUP_SYSTEM_PROMPT.lower()
        assert "ocr" in prompt
        assert "preserve" in prompt
        assert "markdown" in prompt
        assert "latin" in prompt or "italic" in prompt

    def test_metadata_system_prompt_well_formed(self):
        prompt = METADATA_SYSTEM_PROMPT.lower()
        assert "title" in prompt
        assert "author" in prompt
        assert "year" in prompt
        assert "doi" in prompt
        assert "json" in prompt

    def test_data_extract_system_prompt_well_formed(self):
        prompt = DATA_EXTRACT_SYSTEM_PROMPT.lower()
        # Must mention JSON output
        assert "json" in prompt
        # Must contain all trait vocabulary categories
        for category in [
            "shape",
            "color",
            "texture",
            "walls",
            "cells",
            "alignment",
            "plant_part",
            "form",
            "season",
            "detachable",
        ]:
            assert category in prompt, f"Missing vocabulary category: {category}"
        # Must contain specific vocabulary values
        assert "globular" in prompt  # shape
        assert "monothalamous" in prompt  # cells
        assert "erineum" in prompt  # texture
        assert "witches broom" in prompt  # form
        # Must mention gall and host species
        assert "gall" in prompt
        assert "host" in prompt
        # Must mention confidence
        assert "confidence" in prompt


class TestCleanText:
    def test_calls_api_with_correct_params(self, provider, mock_openai):
        client = mock_openai(content="cleaned")

        clean_text("raw text", provider)

        client.chat.completions.create.assert_called_once()
        call_kwargs = client.chat.completions.create.call_args[1]
        assert call_kwargs["model"] == "test-model"
        messages = call_kwargs["messages"]
        assert messages[0]["role"] == "system"
        assert messages[0]["content"] == CLEANUP_SYSTEM_PROMPT
        assert messages[1]["role"] == "user"
        assert messages[1]["content"] == "raw text"

    def test_captures_usage(self, provider, mock_openai):
        mock_openai(content="cleaned", prompt_tokens=200, completion_tokens=75)

        result = clean_text("raw text", provider)

        assert isinstance(result.usage, TokenUsage)
        assert result.usage.prompt_tokens == 200
        assert result.usage.completion_tokens == 75

    def test_returns_content(self, provider, mock_openai):
        mock_openai(content="This is the cleaned text.")

        result = clean_text("messy text", provider)

        assert isinstance(result, CleanupResult)
        assert result.text == "This is the cleaned text."


class TestExtractMetadata:
    def test_parses_json(self, provider, mock_openai):
        json_response = (
            '{"title": "Gall Wasps", "authors": ["Smith", "Jones"], '
            '"year": 2020, "doi": "10.1234/test"}'
        )
        mock_openai(content=json_response)

        result = extract_metadata("some text", provider)

        assert isinstance(result, MetadataResult)
        assert result.title == "Gall Wasps"
        assert result.authors == ["Smith", "Jones"]
        assert result.year == 2020
        assert result.doi == "10.1234/test"

    def test_strips_markdown_fences(self, provider, mock_openai):
        fenced = '```json\n{"title": "Fenced", "authors": ["A"], "year": 2020, "doi": null}\n```'
        mock_openai(content=fenced)

        result = extract_metadata("some text", provider)

        assert result.title == "Fenced"
        assert result.year == 2020

    def test_strips_markdown_fences_with_preamble(self, provider, mock_openai):
        response = 'Here is the JSON:\n\n```json\n{"title": "Test", "authors": [], "year": null, "doi": null}\n```'
        mock_openai(content=response)

        result = extract_metadata("some text", provider)

        assert result.title == "Test"

    def test_truncated_json(self, provider, mock_openai):
        truncated = '```json\n{"title": "Truncated", "authors": ["A"'
        mock_openai(content=truncated)

        result = extract_metadata("some text", provider)

        assert result.title == "Truncated"

    def test_handles_partial_json(self, provider, mock_openai):
        json_response = '{"title": "Partial Paper"}'
        mock_openai(content=json_response)

        result = extract_metadata("some text", provider)

        assert result.title == "Partial Paper"
        assert result.authors == []
        assert result.year is None
        assert result.doi is None


class TestChunking:
    def test_short_text_single_chunk(self):
        chunks = _chunk_text("Short text.", max_tokens=1000)
        assert len(chunks) == 1
        assert chunks[0] == "Short text."

    def test_splits_on_paragraph_boundaries(self):
        # Each paragraph ~25 chars = ~6 tokens. With max_tokens=10, we should get multiple chunks.
        text = "Paragraph one here.\n\nParagraph two here.\n\nParagraph three."
        chunks = _chunk_text(text, max_tokens=10)
        assert len(chunks) > 1
        # Rejoining should recover the original
        assert "\n\n".join(chunks) == text

    def test_clean_text_chunks_large_input(self, provider, mock_openai):
        """Large text should be split and each chunk cleaned separately."""
        client = mock_openai(content="cleaned chunk")

        # Create text that will need chunking (> 100 tokens at 4 chars/token = 400+ chars)
        paragraphs = [f"Paragraph {i} with some content here." for i in range(20)]
        big_text = "\n\n".join(paragraphs)

        result = clean_text(big_text, provider, chunk_max_tokens=100)

        # Should have made multiple LLM calls
        assert client.chat.completions.create.call_count > 1
        # Usage should be summed across chunks
        assert result.usage.prompt_tokens > 100

    def test_clean_text_single_chunk_still_works(self, provider, mock_openai):
        """Small text should work as before — single LLM call."""
        client = mock_openai(content="cleaned")

        result = clean_text("small text", provider, chunk_max_tokens=10000)

        client.chat.completions.create.assert_called_once()
        assert result.text == "cleaned"


class TestExtractData:
    """Tests for extract_data() — structured gall record extraction."""

    def test_parses_json_array(self, provider, mock_openai):
        """extract_data returns records from a JSON array response."""
        json_response = json.dumps(
            [
                {
                    "gall_species": {
                        "name": "Andricus quercuscalifornicus",
                        "authority": "Bassett",
                        "family": "Cynipidae",
                        "order": "Hymenoptera",
                    },
                    "host_species": {
                        "name": "Quercus lobata",
                        "authority": "Née",
                        "family": "Fagaceae",
                    },
                    "traits": {
                        "shape": {"original": "globular", "suggested": ["globular"]},
                        "color": {"original": "tan", "suggested": ["tan"]},
                        "texture": {"original": None, "suggested": []},
                        "walls": {"original": None, "suggested": []},
                        "cells": {
                            "original": "monothalamous",
                            "suggested": ["monothalamous"],
                        },
                        "alignment": {"original": None, "suggested": []},
                        "plant_part": {"original": "twig", "suggested": ["stem"]},
                        "form": {"original": None, "suggested": []},
                        "season": {"original": None, "suggested": []},
                        "detachable": "unknown",
                    },
                    "description": "A large globular gall on twigs.",
                    "location": "California",
                    "confidence": 0.9,
                }
            ]
        )
        mock_openai(content=json_response)

        result = extract_data("scholarly text about galls", provider)

        assert isinstance(result, DataExtractResult)
        assert len(result.records) == 1
        assert (
            result.records[0]["gall_species"]["name"] == "Andricus quercuscalifornicus"
        )
        assert result.records[0]["confidence"] == 0.9

    def test_returns_usage(self, provider, mock_openai):
        """extract_data captures token usage."""
        mock_openai(content="[]", prompt_tokens=500, completion_tokens=200)

        result = extract_data("some text", provider)

        assert isinstance(result.usage, TokenUsage)
        assert result.usage.prompt_tokens == 500
        assert result.usage.completion_tokens == 200

    def test_handles_fenced_json_array(self, provider, mock_openai):
        """extract_data handles JSON arrays wrapped in markdown fences."""
        fenced = (
            '```json\n[{"gall_species": {"name": "Test gall"}, "confidence": 0.5}]\n```'
        )
        mock_openai(content=fenced)

        result = extract_data("some text", provider)

        assert len(result.records) == 1
        assert result.records[0]["gall_species"]["name"] == "Test gall"

    def test_chunking_merges_arrays(self, provider, mock_openai):
        """Large text is chunked and JSON arrays from each chunk are merged."""
        client = mock_openai(
            content='[{"gall_species": {"name": "Gall A"}, "confidence": 0.8}]'
        )

        # Create text large enough to require chunking
        paragraphs = [
            f"Paragraph {i} with enough content to exceed the chunk limit easily."
            for i in range(30)
        ]
        big_text = "\n\n".join(paragraphs)

        result = extract_data(big_text, provider, chunk_max_tokens=100)

        # Multiple LLM calls should have been made
        assert client.chat.completions.create.call_count > 1
        # Records from all chunks should be merged
        assert len(result.records) == client.chat.completions.create.call_count
        # Usage should be summed
        assert result.usage.prompt_tokens > 100

    def test_empty_array(self, provider, mock_openai):
        """extract_data handles an empty array (no records found)."""
        mock_openai(content="[]")

        result = extract_data("text with no gall data", provider)

        assert result.records == []

    def test_calls_api_with_correct_prompt(self, provider, mock_openai):
        """extract_data merges system prompt into user message for better extraction."""
        client = mock_openai(content="[]")

        extract_data("some text", provider)

        call_kwargs = client.chat.completions.create.call_args[1]
        messages = call_kwargs["messages"]
        # data-extract always merges the prompt into the user message
        assert messages[0]["role"] == "user"
        assert DATA_EXTRACT_SYSTEM_PROMPT in messages[0]["content"]
        assert "some text" in messages[0]["content"]


class TestParallelProcessing:
    """Tests for parallel chunk processing."""

    def test_clean_text_chunks_run_in_parallel(self, provider, mocker):
        """Multiple chunks should be processed concurrently, not sequentially."""
        mock_cls = mocker.patch("ingest.llm.OpenAI")
        mock_client = mock_cls.return_value

        def slow_create(**kwargs):
            time.sleep(0.3)
            response = Mock()
            response.choices = [Mock(message=Mock(content="cleaned"))]
            response.usage = Mock(prompt_tokens=100, completion_tokens=50)
            return response

        mock_client.chat.completions.create.side_effect = slow_create

        # Create text that splits into 3+ chunks
        paragraphs = [
            f"Paragraph {i} with enough content to exceed limit." for i in range(20)
        ]
        big_text = "\n\n".join(paragraphs)

        start = time.monotonic()
        clean_text(big_text, provider, chunk_max_tokens=100)
        elapsed = time.monotonic() - start

        call_count = mock_client.chat.completions.create.call_count
        assert call_count >= 3

        # Sequential would take call_count * 0.3s = 0.9s+
        # Parallel should take ~0.3s (one batch). Allow some overhead.
        assert elapsed < call_count * 0.3, (
            f"Took {elapsed:.2f}s for {call_count} calls — appears sequential"
        )

    def test_extract_data_chunks_run_in_parallel(self, provider, mocker):
        """extract_data should process chunks concurrently."""
        mock_cls = mocker.patch("ingest.llm.OpenAI")
        mock_client = mock_cls.return_value

        def slow_create(**kwargs):
            time.sleep(0.3)
            response = Mock()
            response.choices = [Mock(message=Mock(content='[{"gall": "test"}]'))]
            response.usage = Mock(prompt_tokens=100, completion_tokens=50)
            return response

        mock_client.chat.completions.create.side_effect = slow_create

        paragraphs = [
            f"Paragraph {i} with enough content to exceed limit." for i in range(20)
        ]
        big_text = "\n\n".join(paragraphs)

        start = time.monotonic()
        result = extract_data(big_text, provider, chunk_max_tokens=100)
        elapsed = time.monotonic() - start

        call_count = mock_client.chat.completions.create.call_count
        assert call_count >= 3
        assert elapsed < call_count * 0.3, (
            f"Took {elapsed:.2f}s for {call_count} calls — appears sequential"
        )
        # Records from all chunks should be merged
        assert len(result.records) == call_count

    def test_clean_text_parallel_preserves_order(self, provider, mocker):
        """Parallel processing must preserve chunk order in output."""
        mock_cls = mocker.patch("ingest.llm.OpenAI")
        mock_client = mock_cls.return_value

        call_counter = {"n": 0}

        def ordered_create(**kwargs):
            call_counter["n"] += 1
            n = call_counter["n"]
            response = Mock()
            response.choices = [Mock(message=Mock(content=f"cleaned-{n}"))]
            response.usage = Mock(prompt_tokens=10, completion_tokens=5)
            return response

        mock_client.chat.completions.create.side_effect = ordered_create

        paragraphs = [
            f"Paragraph {i} with enough content to exceed limit." for i in range(20)
        ]
        big_text = "\n\n".join(paragraphs)

        result = clean_text(big_text, provider, chunk_max_tokens=100)

        # Output should contain cleaned parts in order
        parts = result.text.split("\n\n")
        for i, part in enumerate(parts, 1):
            assert part == f"cleaned-{i}", f"Chunk {i} out of order: got {part}"


class TestErrorHandling:
    def test_api_error_raises_clear_message(self, provider, mocker):
        mock_cls = mocker.patch("ingest.llm.OpenAI")
        mock_client = mock_cls.return_value
        mock_client.chat.completions.create.side_effect = APIError(
            message="rate limit exceeded",
            request=Mock(),
            body=None,
        )

        with pytest.raises(RuntimeError, match="LLM API call failed"):
            clean_text("text", provider)
