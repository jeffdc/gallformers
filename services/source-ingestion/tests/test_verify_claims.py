"""Tests for the verify-claims stage."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest

from ingest.schemas import (
    Evidence,
    EvidenceCell,
    NormalizedBlock,
    SupportStatus,
    TraitCell,
)
from ingest.verify_claims import (
    _claim_string,
    _LLMVerdict,
    _quoted_text,
    verify_cell,
)


def _block(block_id: str, text: str) -> NormalizedBlock:
    return NormalizedBlock(
        span_id=block_id,
        block_id=block_id,
        page=1,
        char_start=0,
        char_end=len(text),
        text=text,
        raw_block_ids=[block_id],
    )


def _ev(block_id: str = "p1-b0") -> Evidence:
    return Evidence(block_id=block_id, page=1, char_start=0, char_end=1, quote="q")


def _install_mock_verifier(mocker, support_status: str, reason: str = "ok"):
    verdict = _LLMVerdict(support_status=support_status, reason=reason)
    completion = MagicMock()
    completion.usage = MagicMock()
    completion.usage.prompt_tokens = 50
    completion.usage.completion_tokens = 10
    mock_client = MagicMock()
    mock_client.create_with_completion = AsyncMock(return_value=(verdict, completion))
    mocker.patch("ingest.verify_claims.make_instructor_client", return_value=mock_client)
    mocker.patch("ingest.verify_claims._safe_completion_cost", return_value=0.0)
    return mock_client


# ─── Pure helpers ─────────────────────────────────────────────────────────


class TestClaimString:
    def test_evidence_cell_returns_value(self):
        cell = EvidenceCell(
            value="Quercus alba",
            evidence=[_ev()],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        assert _claim_string(cell) == "Quercus alba"

    def test_trait_cell_joins_suggested(self):
        cell = TraitCell(
            original="reddish",
            suggested=["red", "pink"],
            evidence=[_ev()],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        assert _claim_string(cell) == "red, pink"

    def test_empty_value_returns_empty(self):
        cell = EvidenceCell(
            value=None,
            evidence=[_ev()],
            support_status=SupportStatus.ABSTAINED,
            confidence=0.0,
        )
        assert _claim_string(cell) == ""


class TestQuotedText:
    def test_joins_block_texts_for_multi_evidence(self):
        blocks = {
            "p1-b0": _block("p1-b0", "First block."),
            "p2-b0": _block("p2-b0", "Second block."),
        }
        cell = EvidenceCell(
            value="x",
            evidence=[_ev("p1-b0"), _ev("p2-b0")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        assert _quoted_text(cell, blocks) == "First block.\n\nSecond block."

    def test_missing_block_id_silently_skipped(self):
        blocks = {"p1-b0": _block("p1-b0", "First block.")}
        cell = EvidenceCell(
            value="x",
            evidence=[_ev("p1-b0"), _ev("missing-block")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        assert _quoted_text(cell, blocks) == "First block."


# ─── verify_cell integration ──────────────────────────────────────────────


class TestVerifyCell:
    async def test_supported_verdict_sets_support_status(self, mocker):
        _install_mock_verifier(mocker, "supported")
        blocks = {"p1-b0": _block("p1-b0", "context text")}
        cell = EvidenceCell(
            value="Quercus alba",
            evidence=[_ev("p1-b0")],
            support_status=SupportStatus.NEEDS_HUMAN_REVIEW,  # different starting status
            confidence=0.8,
        )
        new_cell, record = await verify_cell(
            cell,
            "hosts[0].scientific_name",
            blocks,
            model="deepinfra/deepseek-v3",
            prompt="verify prompt",
            prompt_sha256="a" * 64,
        )
        assert new_cell.support_status == SupportStatus.SUPPORTED
        assert new_cell.value == "Quercus alba"  # unchanged
        assert record.status == "ok"
        assert record.input_tokens == 50
        assert record.provider == "deepinfra"

    @pytest.mark.parametrize(
        "verdict,expected_status",
        [
            ("contradicted", SupportStatus.CONTRADICTED),
            ("not_enough_evidence", SupportStatus.NOT_ENOUGH_EVIDENCE),
            ("needs_human_review", SupportStatus.NEEDS_HUMAN_REVIEW),
        ],
    )
    async def test_other_verdicts_map_to_support_status(self, mocker, verdict, expected_status):
        _install_mock_verifier(mocker, verdict)
        blocks = {"p1-b0": _block("p1-b0", "context")}
        cell = EvidenceCell(
            value="X",
            evidence=[_ev("p1-b0")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        new_cell, _ = await verify_cell(
            cell,
            "x.y",
            blocks,
            model="m",
            prompt="p",
            prompt_sha256="b" * 64,
        )
        assert new_cell.support_status == expected_status

    async def test_no_evidence_skips_llm_call(self, mocker):
        # If a cell has no evidence (e.g. extractor abstained), we don't
        # call the verifier — return unchanged with a zero-cost record.
        make_client = mocker.patch("ingest.verify_claims.make_instructor_client")
        cell = EvidenceCell(
            value=None,
            evidence=[],
            support_status=SupportStatus.ABSTAINED,
            confidence=0.0,
        )
        new_cell, record = await verify_cell(
            cell,
            "x.y",
            {},
            model="m",
            prompt="p",
            prompt_sha256="c" * 64,
        )
        make_client.assert_not_called()
        assert new_cell is cell  # truly unchanged
        assert record.input_tokens == 0
        assert record.output_tokens == 0

    async def test_trait_cell_verifies_against_joined_suggested(self, mocker):
        client = _install_mock_verifier(mocker, "supported")
        blocks = {"p1-b0": _block("p1-b0", "the gall is red and round")}
        cell = TraitCell(
            original="red",
            suggested=["red"],
            evidence=[_ev("p1-b0")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        await verify_cell(
            cell,
            "gall_traits.color",
            blocks,
            model="m",
            prompt="p",
            prompt_sha256="d" * 64,
        )
        # The verifier was called with messages that include the joined
        # suggested list as the claim.
        call_kwargs = client.create_with_completion.call_args.kwargs
        messages = call_kwargs["messages"]
        user_msg = next(m for m in messages if m["role"] == "user")
        assert "## Claim\n\nred\n" in user_msg["content"]
        assert "## Quoted span text\n\nthe gall is red and round\n" in user_msg["content"]

    async def test_instructor_failure_returns_cell_unchanged_with_error_record(self, mocker):
        """If the verifier LLM call fails (Instructor RetryError, timeout, etc.),
        the cell is returned with its pre-verifier support_status intact and
        the call record carries status='error' for the manifest."""
        mock_client = MagicMock()
        mock_client.create_with_completion = AsyncMock(
            side_effect=RuntimeError("verifier model returned malformed output")
        )
        mocker.patch("ingest.verify_claims.make_instructor_client", return_value=mock_client)
        mocker.patch("ingest.verify_claims._safe_completion_cost", return_value=0.0)
        blocks = {"p1-b0": _block("p1-b0", "context")}
        cell = EvidenceCell(
            value="Quercus alba",
            evidence=[_ev("p1-b0")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )

        new_cell, record = await verify_cell(
            cell,
            "hosts[0].scientific_name",
            blocks,
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="e" * 64,
        )

        # Cell is unchanged — falls back to extractor's status.
        assert new_cell is cell
        assert new_cell.support_status == SupportStatus.SUPPORTED
        # The call record signals the failure to the pipeline runner.
        assert record.status == "error"
        assert record.error_detail is not None
        assert "RuntimeError" in record.error_detail
