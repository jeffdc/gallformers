"""Tests for assemble.py (artifact roll-up) and bundle.py (tarball writer)."""

from __future__ import annotations

import tarfile
from datetime import UTC, datetime
from pathlib import Path

import pytest

from ingest.assemble import (
    ARTIFACT_SCHEMA_VERSIONS,
    assemble,
    build_claims_file,
    build_manifest,
    build_review_artifact,
    build_verified_claims_file,
)
from ingest.bundle import REQUIRED_ARTIFACTS, write_bundle
from ingest.schemas import (
    DocumentMetadata,
    Evidence,
    EvidenceCell,
    GallMaker,
    GallRecord,
    NormalizedBlock,
    ProviderCallRecord,
    ScientificNameCell,
    Source,
    StageRunRecord,
    SupportStatus,
)


def _ts(seconds: int = 0) -> datetime:
    return datetime(2026, 5, 11, 14, 0, seconds, tzinfo=UTC)


def _name_cell(value: str) -> ScientificNameCell:
    return ScientificNameCell(
        value=value,
        evidence=[Evidence(block_id="p1-b0", page=1, char_start=0, char_end=1, quote="q")],
        support_status=SupportStatus.SUPPORTED,
        confidence=0.9,
    )


def _record(record_id: str = "R_001") -> GallRecord:
    return GallRecord(
        record_id=record_id,
        candidate_id=record_id.replace("R_", "C_"),
        gall_maker=GallMaker(scientific_name=_name_cell("Andricus quercuscalifornicus")),
    )


def _block(text: str, char_start: int = 0, span_id: str = "S_0001") -> NormalizedBlock:
    return NormalizedBlock(
        span_id=span_id,
        block_id="p1-b0",
        page=1,
        char_start=char_start,
        char_end=char_start + len(text),
        text=text,
        raw_block_ids=["p1-b0"],
    )


def _metadata() -> DocumentMetadata:
    return DocumentMetadata(
        title=EvidenceCell(
            value="Test Paper",
            evidence=[],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        ),
    )


def _source() -> Source:
    return Source(
        pdf_sha256="a" * 64,
        pdf_filename="test.pdf",
        pdf_page_count=1,
        source_text_sha256="b" * 64,
    )


# ─── assemble.py ──────────────────────────────────────────────────────────


class TestBuildClaimsAndVerified:
    def test_claims_and_verified_carry_records(self):
        records = [_record("R_001"), _record("R_002")]
        claims = build_claims_file(records)
        verified = build_verified_claims_file(records)
        assert len(claims.gall_records) == 2
        assert len(verified.gall_records) == 2
        assert claims.schema_version == "1.0.0"


class TestBuildManifest:
    def test_total_cost_sums_across_stages(self):
        stages = [
            StageRunRecord(
                name="extract",
                started_at=_ts(),
                completed_at=_ts(1),
                calls=[],
            ),
            StageRunRecord(
                name="find-candidates",
                started_at=_ts(1),
                completed_at=_ts(3),
                calls=[
                    ProviderCallRecord(
                        model="m",
                        provider="p",
                        prompt_sha256="a" * 64,
                        input_tokens=10,
                        output_tokens=5,
                        cost_usd=0.01,
                        duration_ms=100,
                    ),
                    ProviderCallRecord(
                        model="m",
                        provider="p",
                        prompt_sha256="a" * 64,
                        input_tokens=10,
                        output_tokens=5,
                        cost_usd=0.02,
                        duration_ms=100,
                    ),
                ],
            ),
        ]
        manifest = build_manifest(
            pipeline_name="north-star-v0",
            pipeline_version="0.1.0",
            pipeline_config_name="north-star-v0",
            seed=42,
            started_at=_ts(),
            completed_at=_ts(10),
            source=_source(),
            stages=stages,
        )
        assert manifest.total_cost_usd == pytest.approx(0.03)
        assert manifest.schema_versions == ARTIFACT_SCHEMA_VERSIONS


class TestBuildReviewArtifact:
    def test_inlines_flat_normalized_text(self):
        blocks = [
            _block("First block.", char_start=0, span_id="S_0001"),
            _block("Second block.", char_start=14, span_id="S_0002"),
        ]
        review = build_review_artifact(
            pipeline_name="north-star-v0",
            pipeline_version="0.1.0",
            generated_at=_ts(10),
            pdf_sha256="a" * 64,
            pdf_filename="test.pdf",
            pdf_page_count=1,
            source_text_sha256="b" * 64,
            normalized_blocks=blocks,
            document_metadata=_metadata(),
            verified_records=[_record()],
        )
        # Flat text is BLOCK1 + "\n\n" + BLOCK2
        assert review.source.normalized_text == "First block.\n\nSecond block."
        assert len(review.gall_records) == 1


class TestAssembleOneShot:
    def test_assemble_returns_all_four_artifacts(self):
        manifest, claims, verified, review = assemble(
            pipeline_name="north-star-v0",
            pipeline_version="0.1.0",
            pipeline_config_name="north-star-v0",
            seed=42,
            started_at=_ts(),
            completed_at=_ts(10),
            pdf_sha256="a" * 64,
            pdf_filename="test.pdf",
            pdf_page_count=1,
            source_text_sha256="b" * 64,
            normalized_blocks=[_block("a", char_start=0)],
            document_metadata=_metadata(),
            claims_records=[_record()],
            verified_records=[_record()],
            stages=[],
        )
        assert manifest.pipeline_name == "north-star-v0"
        assert len(claims.gall_records) == 1
        assert len(verified.gall_records) == 1
        assert review.source.pdf_sha256 == "a" * 64


# ─── bundle.py ────────────────────────────────────────────────────────────


def _seed_artifacts(directory: Path, artifacts: list[str]) -> None:
    """Write minimal placeholder files for each named artifact."""
    for name in artifacts:
        (directory / name).write_text("{}" if name.endswith(".json") else "")


class TestWriteBundle:
    def test_bundle_contains_all_required_artifacts(self, tmp_path):
        src = tmp_path / "out"
        src.mkdir()
        _seed_artifacts(src, REQUIRED_ARTIFACTS)
        out = tmp_path / "bundle.tar.gz"

        write_bundle(src, out)
        with tarfile.open(out) as tar:
            names = sorted(tar.getnames())
        assert names == sorted(REQUIRED_ARTIFACTS)

    def test_verify_complete_raises_when_artifact_missing(self, tmp_path):
        src = tmp_path / "out"
        src.mkdir()
        # Only seed some of the required artifacts.
        _seed_artifacts(src, REQUIRED_ARTIFACTS[:3])

        with pytest.raises(FileNotFoundError, match="missing"):
            write_bundle(src, tmp_path / "bundle.tar.gz", verify_complete=True)

    def test_include_candidates_adds_candidates_subtree(self, tmp_path):
        src = tmp_path / "out"
        src.mkdir()
        _seed_artifacts(src, REQUIRED_ARTIFACTS)
        # Seed a per-candidate scratch directory.
        (src / "candidates" / "C_001").mkdir(parents=True)
        (src / "candidates" / "C_001" / "facts.json").write_text('{"x": 1}')

        out = tmp_path / "bundle.tar.gz"
        write_bundle(src, out, include_candidates=True)
        with tarfile.open(out) as tar:
            names = tar.getnames()
        assert "candidates" in names
        assert "candidates/C_001/facts.json" in names

    def test_default_bundle_excludes_candidates(self, tmp_path):
        src = tmp_path / "out"
        src.mkdir()
        _seed_artifacts(src, REQUIRED_ARTIFACTS)
        (src / "candidates" / "C_001").mkdir(parents=True)
        (src / "candidates" / "C_001" / "facts.json").write_text("{}")

        write_bundle(src, tmp_path / "bundle.tar.gz")
        with tarfile.open(tmp_path / "bundle.tar.gz") as tar:
            names = tar.getnames()
        assert not any(n.startswith("candidates") for n in names)


# ─── round-trip via the assemble outputs ──────────────────────────────────


class TestAssembleRoundTrip:
    def test_artifacts_serialize_and_parse_back_to_equal_objects(self):
        manifest, claims, verified, review = assemble(
            pipeline_name="north-star-v0",
            pipeline_version="0.1.0",
            pipeline_config_name="north-star-v0",
            seed=42,
            started_at=_ts(),
            completed_at=_ts(10),
            pdf_sha256="a" * 64,
            pdf_filename="test.pdf",
            pdf_page_count=1,
            source_text_sha256="b" * 64,
            normalized_blocks=[_block("a", char_start=0)],
            document_metadata=_metadata(),
            claims_records=[_record()],
            verified_records=[_record()],
            stages=[],
        )
        for obj in (manifest, claims, verified, review):
            serialized = obj.model_dump_json()
            roundtripped = type(obj).model_validate_json(serialized)
            assert roundtripped.model_dump() == obj.model_dump()
