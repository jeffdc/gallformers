"""Assemble stage: roll up per-stage outputs into the four contract artifacts.

Deterministic. Takes the pipeline's intermediate state (extracted records
pre-verification, verified records post-taxonomy-lookup, normalized text,
metadata, stage call records, accumulated warnings, run timing) and
produces the four JSON artifacts that go into ``bundle.tar.gz``:

- ``manifest.json`` — pipeline bookkeeping + schema versions
- ``claims.json`` — extracted records pre-verifier
- ``verified_claims.json`` — same shape, post-verifier + GBIF lookups
- ``review_artifact.json`` — consumer-facing assembled view with inline normalized text

Each builder validates by construction (Pydantic ``StrictModel``). The
pipeline calls these, writes the JSON, then ``bundle.py`` tarballs.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime

from ingest.preprocess import flat_normalized_text
from ingest.schemas import (
    SCHEMA_VERSION,
    ClaimsFile,
    DocumentMetadata,
    GallRecord,
    Manifest,
    NormalizedBlock,
    ReviewArtifact,
    ReviewSource,
    Source,
    StageRunRecord,
    VerifiedClaimsFile,
    WarningEntry,
)

# Schema versions per artifact filename. Updated alongside schema bumps.
ARTIFACT_SCHEMA_VERSIONS: dict[str, str] = {
    "manifest.json": SCHEMA_VERSION,
    "sections.json": SCHEMA_VERSION,
    "metadata.json": SCHEMA_VERSION,
    "claims.json": SCHEMA_VERSION,
    "verified_claims.json": SCHEMA_VERSION,
    "review_artifact.json": SCHEMA_VERSION,
    "raw_text.jsonl": SCHEMA_VERSION,
    "normalized_text.jsonl": SCHEMA_VERSION,
}


def build_claims_file(records: Sequence[GallRecord]) -> ClaimsFile:
    """``claims.json`` — extracted records before verifier and taxonomy_lookup."""
    return ClaimsFile(gall_records=list(records))


def build_verified_claims_file(records: Sequence[GallRecord]) -> VerifiedClaimsFile:
    """``verified_claims.json`` — records with verifier verdicts + GBIF lookups."""
    return VerifiedClaimsFile(gall_records=list(records))


def build_manifest(
    *,
    pipeline_name: str,
    pipeline_version: str,
    pipeline_config_name: str,
    seed: int,
    started_at: datetime,
    completed_at: datetime,
    source: Source,
    stages: Sequence[StageRunRecord],
    warnings: Sequence[WarningEntry] = (),
) -> Manifest:
    """``manifest.json`` — pipeline run bookkeeping.

    ``total_cost_usd`` is summed across every ``ProviderCallRecord`` in
    every stage; the manifest is the authoritative cost record for the run.
    """
    total_cost = 0.0
    for stage in stages:
        for call in stage.calls:
            total_cost += call.cost_usd
    return Manifest(
        pipeline_name=pipeline_name,
        pipeline_version=pipeline_version,
        pipeline_config_name=pipeline_config_name,
        seed=seed,
        started_at=started_at,
        completed_at=completed_at,
        source=source,
        schema_versions=dict(ARTIFACT_SCHEMA_VERSIONS),
        stages=list(stages),
        total_cost_usd=total_cost,
        warnings=list(warnings),
    )


def build_review_artifact(
    *,
    pipeline_name: str,
    pipeline_version: str,
    generated_at: datetime,
    pdf_sha256: str,
    pdf_filename: str,
    pdf_page_count: int,
    source_text_sha256: str,
    normalized_blocks: Sequence[NormalizedBlock],
    document_metadata: DocumentMetadata,
    verified_records: Sequence[GallRecord],
    warnings: Sequence[WarningEntry] = (),
) -> ReviewArtifact:
    """``review_artifact.json`` — consumer-facing view with inline normalized text.

    Evidence absolute char offsets address into ``source.normalized_text`` —
    this is what the review UI uses to render highlighted quotes in context
    without walking ``normalized_text.jsonl`` separately.
    """
    flat = flat_normalized_text(list(normalized_blocks))
    return ReviewArtifact(
        pipeline_name=pipeline_name,
        pipeline_version=pipeline_version,
        generated_at=generated_at,
        source=ReviewSource(
            pdf_sha256=pdf_sha256,
            pdf_filename=pdf_filename,
            pdf_page_count=pdf_page_count,
            source_text_sha256=source_text_sha256,
            normalized_text=flat,
        ),
        document_metadata=document_metadata,
        gall_records=list(verified_records),
        warnings=list(warnings),
    )


def assemble(
    *,
    pipeline_name: str,
    pipeline_version: str,
    pipeline_config_name: str,
    seed: int,
    started_at: datetime,
    completed_at: datetime,
    pdf_sha256: str,
    pdf_filename: str,
    pdf_page_count: int,
    source_text_sha256: str,
    normalized_blocks: Sequence[NormalizedBlock],
    document_metadata: DocumentMetadata,
    claims_records: Sequence[GallRecord],
    verified_records: Sequence[GallRecord],
    stages: Sequence[StageRunRecord],
    warnings: Sequence[WarningEntry] = (),
) -> tuple[Manifest, ClaimsFile, VerifiedClaimsFile, ReviewArtifact]:
    """One-shot wrapper. Builds all four artifacts in a consistent order."""
    source = Source(
        pdf_sha256=pdf_sha256,
        pdf_filename=pdf_filename,
        pdf_page_count=pdf_page_count,
        source_text_sha256=source_text_sha256,
    )
    manifest = build_manifest(
        pipeline_name=pipeline_name,
        pipeline_version=pipeline_version,
        pipeline_config_name=pipeline_config_name,
        seed=seed,
        started_at=started_at,
        completed_at=completed_at,
        source=source,
        stages=stages,
        warnings=warnings,
    )
    claims = build_claims_file(claims_records)
    verified = build_verified_claims_file(verified_records)
    review = build_review_artifact(
        pipeline_name=pipeline_name,
        pipeline_version=pipeline_version,
        generated_at=completed_at,
        pdf_sha256=pdf_sha256,
        pdf_filename=pdf_filename,
        pdf_page_count=pdf_page_count,
        source_text_sha256=source_text_sha256,
        normalized_blocks=normalized_blocks,
        document_metadata=document_metadata,
        verified_records=verified_records,
        warnings=warnings,
    )
    return manifest, claims, verified, review
