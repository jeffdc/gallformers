"""Tests for pipeline.py orchestration helpers.

These test the dispatch/rebuild glue that wires per-stage outputs back into
GallRecords. Most stage logic has its own test file; this one exists to
catch coupling bugs at the seams between stages — the kind that compile
fine and pass per-stage tests but blow up at runtime."""

from __future__ import annotations

import asyncio

from ingest.pipeline import _verify_records_claims
from ingest.schemas import (
    ConfidenceBucket,
    GallMaker,
    GallRecord,
    GallTraits,
    ScientificNameCell,
    SupportStatus,
)


def _empty_name_cell() -> ScientificNameCell:
    return ScientificNameCell(
        value="Andricus testus",
        evidence=[],  # no evidence → verify_cell is skipped, cell returned unchanged
        support_status=SupportStatus.SUPPORTED,
        confidence=0.9,
    )


def _record(record_id: str = "R_001") -> GallRecord:
    return GallRecord(
        record_id=record_id,
        candidate_id="C_001",
        gall_maker=GallMaker(scientific_name=_empty_name_cell()),
        generation="unspecified",
        evidence_prose=[],
        hosts=[],
        gall_traits=GallTraits(),
        location=None,
        confidence_bucket=ConfidenceBucket.HIGH,
    )


class TestVerifyRecordsRebuild:
    """The verify-claims stage dispatches per-cell verifier jobs and then
    rebuilds each GallRecord from the verified cells. Because dispatch and
    rebuild are separate code paths with shared keys, it's easy to drift —
    if a key is dispatched but not consumed (or vice versa) the rebuild
    will KeyError or strict-validate-fail at runtime. (Caught when removing
    the `description` field on 2026-05-18: the rebuild still read a
    `description` key that was no longer dispatched, crashing the run.)"""

    def test_records_rebuild_without_description_field(self):
        """Records flowing through verify-claims rebuild as valid GallRecords
        when no LLM calls happen (empty evidence on every cell)."""
        records = [_record("R_001"), _record("R_002")]
        sem = asyncio.Semaphore(1)
        out, calls, warnings = asyncio.run(
            _verify_records_claims(
                records=records,
                blocks_by_id={},
                model="any/model",
                prompt="prompt",
                prompt_sha="x" * 64,
                semaphore=sem,
            )
        )
        # No LLM calls (empty evidence skips dispatch); rebuild still produces
        # valid GallRecords.
        assert calls == []
        assert warnings == []
        assert [r.record_id for r in out] == ["R_001", "R_002"]
        # Round-trip through model_validate to confirm strict-schema compliance.
        for r in out:
            GallRecord.model_validate(r.model_dump())
