"""Tests for the metadata extraction stage."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

from ingest.metadata import extract_document_metadata
from ingest.schemas import (
    DocumentMetadata,
    Evidence,
    EvidenceCell,
    NormalizedBlock,
    SupportStatus,
)


def _block(span_id: str, text: str) -> NormalizedBlock:
    return NormalizedBlock(
        span_id=span_id,
        block_id=span_id,
        page=1,
        char_start=0,
        char_end=len(text),
        text=text,
        raw_block_ids=[span_id],
    )


def _ev(block_id: str) -> Evidence:
    return Evidence(block_id=block_id, page=1, char_start=0, char_end=1, quote="q")


def _cell(value: str, evidence_block_id: str = "S_0001") -> EvidenceCell:
    return EvidenceCell(
        value=value,
        evidence=[_ev(evidence_block_id)],
        support_status=SupportStatus.SUPPORTED,
        confidence=0.9,
    )


def _mock_completion(prompt_tokens: int = 80, completion_tokens: int = 30):
    completion = MagicMock()
    completion.usage = MagicMock()
    completion.usage.prompt_tokens = prompt_tokens
    completion.usage.completion_tokens = completion_tokens
    return completion


def _install_mock_client(mocker, metadata: DocumentMetadata, completion=None):
    if completion is None:
        completion = _mock_completion()
    mock_client = MagicMock()
    mock_client.create_with_completion = AsyncMock(return_value=(metadata, completion))
    mocker.patch("ingest.metadata.make_instructor_client", return_value=mock_client)
    mocker.patch("ingest.metadata._safe_completion_cost", return_value=0.01)
    return mock_client


class TestExtractDocumentMetadata:
    async def test_happy_path_returns_metadata_and_record(self, mocker):
        blocks = [_block("S_0001", "Paper Title"), _block("S_0002", "Smith A. 2003")]
        metadata = DocumentMetadata(
            title=_cell("Paper Title"),
            authors=[_cell("A. Smith", evidence_block_id="S_0002")],
            year=_cell("2003", evidence_block_id="S_0002"),
        )
        _install_mock_client(mocker, metadata)

        result, record = await extract_document_metadata(
            blocks,
            model="deepinfra/test",
            prompt="metadata prompt",
            prompt_sha256="a" * 64,
        )

        assert result.title.value == "Paper Title"
        assert result.authors[0].value == "A. Smith"
        assert record.input_tokens == 80
        assert record.provider == "deepinfra"
        assert record.status == "ok"

    async def test_empty_input_abstains_without_calling_llm(self, mocker):
        make_client = mocker.patch("ingest.metadata.make_instructor_client")
        result, record = await extract_document_metadata(
            blocks=[],
            model="m",
            prompt="p",
            prompt_sha256="b" * 64,
        )
        make_client.assert_not_called()
        assert result.title.value is None
        assert result.title.support_status == SupportStatus.ABSTAINED
        assert record.input_tokens == 0
        assert record.status == "ok"

    async def test_evidence_outside_allowed_span_ids_is_scrubbed(self, mocker):
        blocks = [_block("S_0001", "Paper Title here")]
        # LLM returned title with evidence citing a span NOT in the allowed set.
        metadata = DocumentMetadata(
            title=_cell("Paper Title", evidence_block_id="S_BOGUS"),
        )
        _install_mock_client(mocker, metadata)

        result, _ = await extract_document_metadata(
            blocks,
            model="m",
            prompt="p",
            prompt_sha256="c" * 64,
        )

        # Title's evidence cited S_BOGUS which isn't in {S_0001}; cell got nulled.
        assert result.title.value is None
        assert result.title.support_status == SupportStatus.ABSTAINED
        assert result.title.evidence == []

    async def test_message_includes_allowed_span_ids_and_chunked_input(self, mocker):
        blocks = [_block("S_0001", "first span text"), _block("S_0002", "second span text")]
        metadata = DocumentMetadata(title=_cell("X"))
        client = _install_mock_client(mocker, metadata)

        await extract_document_metadata(
            blocks,
            model="m",
            prompt="metadata system prompt",
            prompt_sha256="d" * 64,
        )

        call_kwargs = client.create_with_completion.call_args.kwargs
        messages = call_kwargs["messages"]
        user_msg = next(m for m in messages if m["role"] == "user")
        assert "S_0001, S_0002" in user_msg["content"]
        assert "[S_0001] first span text" in user_msg["content"]
        assert "[S_0002] second span text" in user_msg["content"]

    async def test_instructor_failure_returns_abstaining_metadata_and_error_record(self, mocker):
        """When Instructor exhausts retries, return an abstaining DocumentMetadata
        with an error-status ProviderCallRecord rather than raising."""
        blocks = [_block("S_0001", "doc title")]
        mock_client = MagicMock()
        mock_client.create_with_completion = AsyncMock(
            side_effect=RuntimeError("instructor gave up after retries")
        )
        mocker.patch("ingest.metadata.make_instructor_client", return_value=mock_client)
        mocker.patch("ingest.metadata._safe_completion_cost", return_value=0.0)

        result, record = await extract_document_metadata(
            blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="e" * 64,
        )

        assert result.title.value is None
        assert result.title.support_status == SupportStatus.ABSTAINED
        assert record.status == "error"
        assert record.error_detail is not None
        assert "RuntimeError" in record.error_detail
        assert "instructor gave up" in record.error_detail
