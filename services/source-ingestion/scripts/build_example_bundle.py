"""Build one example bundle.tar.gz from the Pydantic schemas.

This is the schema smoke test. Every artifact model is instantiated with
plausible data, validated on construction, serialized, then re-read and
re-validated to catch any silent round-trip bugs.

The example data is contrived but realistic — Andricus quercuscalifornicus
on Quercus agrifolia, a real California oak gall. Offsets are computed
programmatically from the concatenated normalized text so they're correct
by construction.

Run:
    cd services/source-ingestion
    uv run python scripts/build_example_bundle.py [--output PATH]

Outputs:
    {output}/manifest.json
    {output}/source.pdf            (~30-byte stub PDF)
    {output}/raw_text.jsonl
    {output}/normalized_text.jsonl
    {output}/sections.json
    {output}/metadata.json
    {output}/claims.json
    {output}/verified_claims.json
    {output}/review_artifact.json
    {output}/bundle.tar.gz
"""

from __future__ import annotations

import hashlib
import tarfile
from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path

import click
from pydantic import BaseModel

from ingest.schemas import (
    ARTIFACT_MODELS,
    SCHEMA_VERSION,
    Bbox,
    Candidate,
    CandidatesFile,
    ClaimsFile,
    ConfidenceBucket,
    Detachable,
    DocumentMetadata,
    Evidence,
    EvidenceCell,
    GallMaker,
    GallRecord,
    GallTraits,
    Host,
    Manifest,
    NormalizedBlock,
    ProviderCallRecord,
    RawTextBlock,
    ReviewArtifact,
    ReviewSource,
    ScientificNameCell,
    Section,
    SectionsFile,
    SectionType,
    Source,
    StageRunRecord,
    SupportStatus,
    Taxonomy,
    TaxonomyLookup,
    TaxonomyLookupSource,
    TaxonomyLookupStatus,
    TaxonomyMatch,
    TraitCell,
    VerifiedClaimsFile,
    WarningEntry,
    WarningSeverity,
    WarningType,
)

# ─── Example data ──────────────────────────────────────────────────────────

# A minimal PDF stub. Real bundles ship the actual source PDF.
EXAMPLE_PDF = b"%PDF-1.4\n%example-stub-not-a-real-pdf\n"

# The three normalized blocks of our example paper, in order. Joined with
# "\n\n" they form the flat normalized text that evidence offsets address.
NORMALIZED_BLOCKS_TEXT = [
    "Andricus quercuscalifornicus (Bassett, 1881) forms a large, woody, oak-apple gall on Quercus agrifolia.",
    "The gall is globular, 2-4 cm in diameter, with a bright red exterior that fades to brown at maturity.",
    "Galls are found on the leaves of Q. agrifolia in late summer (August-September).",
]
BLOCK_SEPARATOR = "\n\n"
FLAT_NORMALIZED_TEXT = BLOCK_SEPARATOR.join(NORMALIZED_BLOCKS_TEXT)

# Provenance for the run.
RUN_STARTED = datetime(2026, 5, 11, 14, 0, 0, tzinfo=UTC)
RUN_COMPLETED = datetime(2026, 5, 11, 14, 3, 27, tzinfo=UTC)
PIPELINE_NAME = "north-star-v0"
PIPELINE_VERSION = "0.1.0"
PIPELINE_CONFIG = "north-star-v0"
SEED = 42


def sha256_hex(data: bytes | str) -> str:
    """Return lowercase hex SHA-256 of the input."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


PDF_SHA = sha256_hex(EXAMPLE_PDF)
TEXT_SHA = sha256_hex(FLAT_NORMALIZED_TEXT)


# ─── Offset helpers ────────────────────────────────────────────────────────


def block_offsets() -> list[tuple[int, int]]:
    """Compute (start, end) char offsets for each normalized block in the flat text."""
    offsets: list[tuple[int, int]] = []
    cursor = 0
    for i, block in enumerate(NORMALIZED_BLOCKS_TEXT):
        start = cursor
        end = start + len(block)
        offsets.append((start, end))
        cursor = end + (len(BLOCK_SEPARATOR) if i < len(NORMALIZED_BLOCKS_TEXT) - 1 else 0)
    return offsets


def quote_evidence(block_index: int, quote: str) -> Evidence:
    """Build an Evidence pointing at `quote` within block_index.

    Looks up the absolute offset by finding `quote` in the flat text. Fails
    loudly if the quote isn't an exact substring — this is the same invariant
    the substring gate enforces in the real pipeline.
    """
    block_start, block_end = block_offsets()[block_index]
    block_text = FLAT_NORMALIZED_TEXT[block_start:block_end]
    local = block_text.find(quote)
    if local < 0:
        raise ValueError(f"Quote {quote!r} not found in block {block_index}")
    char_start = block_start + local
    char_end = char_start + len(quote)
    return Evidence(
        block_id=f"p1-b{block_index + 1}",
        page=1,
        char_start=char_start,
        char_end=char_end,
        quote=quote,
    )


# ─── Builders (one per artifact) ──────────────────────────────────────────


def build_raw_text() -> list[RawTextBlock]:
    """Raw extraction output. Includes a stripped-by-preprocess running header.

    Block p1-b0 (the header) is in raw but NOT in normalized — preprocess
    removed it. Demonstrates the raw_block_ids back-reference: normalized
    blocks track which raw blocks contributed; the header tracks back to
    nothing in normalized.
    """
    return [
        # The running header — will be stripped by preprocess.
        RawTextBlock(
            block_id="p1-b0",
            page=1,
            text="California Oak Galls",
            bbox=Bbox(x0=72.0, y0=36.0, x1=540.0, y1=52.0),
            extractor="pymupdf-1.24.0",
            quality_signals={"char_count": 20, "is_header_candidate": True},
        ),
        RawTextBlock(
            block_id="p1-b1",
            page=1,
            text=NORMALIZED_BLOCKS_TEXT[0],
            bbox=Bbox(x0=72.0, y0=72.0, x1=540.0, y1=120.0),
            extractor="pymupdf-1.24.0",
            quality_signals={"char_count": len(NORMALIZED_BLOCKS_TEXT[0])},
        ),
        RawTextBlock(
            block_id="p1-b2",
            page=1,
            text=NORMALIZED_BLOCKS_TEXT[1],
            bbox=Bbox(x0=72.0, y0=140.0, x1=540.0, y1=188.0),
            extractor="pymupdf-1.24.0",
            quality_signals={"char_count": len(NORMALIZED_BLOCKS_TEXT[1])},
        ),
        RawTextBlock(
            block_id="p1-b3",
            page=1,
            text=NORMALIZED_BLOCKS_TEXT[2],
            bbox=Bbox(x0=72.0, y0=208.0, x1=540.0, y1=240.0),
            extractor="pymupdf-1.24.0",
            quality_signals={"char_count": len(NORMALIZED_BLOCKS_TEXT[2])},
        ),
    ]


def build_normalized_text() -> list[NormalizedBlock]:
    """Normalized blocks. The header is gone; each normalized block tracks back to one raw block."""
    offsets = block_offsets()
    return [
        NormalizedBlock(
            span_id=f"S_{i + 1:04d}",
            block_id=f"p1-b{i + 1}",
            page=1,
            section_id="sec-1",
            char_start=char_start,
            char_end=char_end,
            text=text,
            raw_block_ids=[f"p1-b{i + 1}"],
        )
        for i, (text, (char_start, char_end)) in enumerate(
            zip(NORMALIZED_BLOCKS_TEXT, offsets, strict=True)
        )
    ]


def build_sections() -> SectionsFile:
    """One taxonomic-treatment section covering all three blocks."""
    return SectionsFile(
        sections=[
            Section(
                section_id="sec-1",
                type=SectionType.TAXONOMIC_TREATMENT,
                heading="Andricus quercuscalifornicus",
                heading_path=["Species Accounts", "Andricus quercuscalifornicus"],
                page_start=1,
                page_end=1,
                span_ids=["S_0001", "S_0002", "S_0003"],
                extraction_eligible=True,
            )
        ]
    )


def build_metadata() -> DocumentMetadata:
    """Bibliographic metadata. Title is grounded in block 1 (the species heading)."""
    return DocumentMetadata(
        title=EvidenceCell(
            value="California Oak Galls",
            evidence=[],  # in a real run, evidence would point at the title page
            support_status=SupportStatus.SUPPORTED,
            confidence=0.95,
        ),
        authors=[
            EvidenceCell(
                value="A. Smith",
                evidence=[],
                support_status=SupportStatus.SUPPORTED,
                confidence=0.9,
            )
        ],
        year=EvidenceCell(
            value="2003",
            evidence=[],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.99,
        ),
        doi=EvidenceCell(
            value="10.1234/cal.gall.2003",
            evidence=[],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.99,
        ),
    )


def _gall_maker_with_lookups(include_gbif: bool) -> GallMaker:
    """The gall-maker. If include_gbif, attach a GBIF taxonomy_lookup."""
    lookups: list[TaxonomyLookup] = []
    if include_gbif:
        lookups.append(
            TaxonomyLookup(
                source=TaxonomyLookupSource.GBIF,
                status=TaxonomyLookupStatus.EXACT,
                match=TaxonomyMatch(
                    scientific_name="Andricus quercuscalifornicus",
                    rank="species",
                    kingdom="Animalia",
                    family="Cynipidae",
                    order="Hymenoptera",
                    canonical_name="Andricus quercuscalifornicus",
                    source_key="1456789",
                    url="https://www.gbif.org/species/1456789",
                ),
                confidence=0.99,
                queried_at=RUN_COMPLETED,
            )
        )
    return GallMaker(
        scientific_name=ScientificNameCell(
            value="Andricus quercuscalifornicus",
            raw_value="Andricus quercuscalifornicus",
            name_as_written="Andricus quercuscalifornicus",
            evidence=[quote_evidence(0, "Andricus quercuscalifornicus")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.95,
            taxonomy_lookups=lookups,
        ),
        authority=EvidenceCell(
            value="Bassett, 1881",
            evidence=[quote_evidence(0, "(Bassett, 1881)")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        ),
        rank=EvidenceCell(
            value="species",
            evidence=[],
            support_status=SupportStatus.SUPPORTED,
            confidence=1.0,
        ),
        taxonomy=Taxonomy(
            order=ScientificNameCell(
                value="Hymenoptera",
                evidence=[],
                support_status=SupportStatus.SUPPORTED,
                confidence=0.95,
            ),
            family=ScientificNameCell(
                value="Cynipidae",
                evidence=[],
                support_status=SupportStatus.SUPPORTED,
                confidence=0.95,
            ),
        ),
    )


def _host_with_lookups(include_gbif: bool) -> Host:
    lookups: list[TaxonomyLookup] = []
    if include_gbif:
        lookups.append(
            TaxonomyLookup(
                source=TaxonomyLookupSource.GBIF,
                status=TaxonomyLookupStatus.EXACT,
                match=TaxonomyMatch(
                    scientific_name="Quercus agrifolia",
                    rank="species",
                    kingdom="Plantae",
                    family="Fagaceae",
                    order="Fagales",
                    canonical_name="Quercus agrifolia",
                    source_key="2879294",
                    url="https://www.gbif.org/species/2879294",
                ),
                confidence=0.99,
                queried_at=RUN_COMPLETED,
            )
        )
    return Host(
        scientific_name=ScientificNameCell(
            value="Quercus agrifolia",
            name_as_written="Quercus agrifolia",
            evidence=[
                quote_evidence(0, "Quercus agrifolia"),
                quote_evidence(2, "Q. agrifolia"),
            ],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.95,
            taxonomy_lookups=lookups,
        ),
    )


def _gall_traits() -> GallTraits:
    return GallTraits(
        shape=TraitCell(
            original="globular",
            suggested=["globular"],
            evidence=[quote_evidence(1, "globular")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.95,
        ),
        color=TraitCell(
            original="bright red",
            suggested=["red"],
            evidence=[quote_evidence(1, "bright red")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        ),
        season=TraitCell(
            original="late summer (August-September)",
            suggested=["Summer"],
            evidence=[quote_evidence(2, "late summer (August-September)")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        ),
        plant_part=TraitCell(
            original="leaves",
            suggested=["upper leaf"],
            evidence=[quote_evidence(2, "leaves")],
            support_status=SupportStatus.NEEDS_HUMAN_REVIEW,
            confidence=0.6,
        ),
        form=TraitCell(
            original="oak-apple gall",
            suggested=["oak apple"],
            evidence=[quote_evidence(0, "oak-apple gall")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.95,
        ),
        detachable=EvidenceCell(
            value=Detachable.DETACHABLE.value,
            evidence=[],
            support_status=SupportStatus.NEEDS_HUMAN_REVIEW,
            confidence=0.5,
        ),
    )


def build_claims() -> ClaimsFile:
    """Pre-verification: no taxonomy_lookups yet, support_status from extractor + substring gate."""
    record = GallRecord(
        record_id="R_001",
        candidate_id="C_001",
        gall_maker=_gall_maker_with_lookups(include_gbif=False),
        hosts=[_host_with_lookups(include_gbif=False)],
        gall_traits=_gall_traits(),
        description=EvidenceCell(
            value="A large, woody, oak-apple gall, globular, 2-4 cm in diameter, with a bright red exterior fading to brown.",
            evidence=[
                quote_evidence(0, "large, woody, oak-apple gall"),
                quote_evidence(
                    1,
                    "globular, 2-4 cm in diameter, with a bright red exterior that fades to brown",
                ),
            ],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.85,
        ),
        confidence_bucket=ConfidenceBucket.HIGH,
    )
    return ClaimsFile(gall_records=[record])


def build_verified_claims() -> VerifiedClaimsFile:
    """Post-verification: taxonomy_lookups populated by GBIF; verifier verdicts attached."""
    record = GallRecord(
        record_id="R_001",
        candidate_id="C_001",
        gall_maker=_gall_maker_with_lookups(include_gbif=True),
        hosts=[_host_with_lookups(include_gbif=True)],
        gall_traits=_gall_traits(),
        description=EvidenceCell(
            value="A large, woody, oak-apple gall, globular, 2-4 cm in diameter, with a bright red exterior fading to brown.",
            evidence=[
                quote_evidence(0, "large, woody, oak-apple gall"),
                quote_evidence(
                    1,
                    "globular, 2-4 cm in diameter, with a bright red exterior that fades to brown",
                ),
            ],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.85,
        ),
        confidence_bucket=ConfidenceBucket.HIGH,
        warnings=[
            WarningEntry(
                type=WarningType.TAXONOMY_FUZZY_MATCH_LOW_CONFIDENCE,
                severity=WarningSeverity.INFO,
                record_id="R_001",
                field_path="gall_traits.plant_part",
                detail={
                    "original": "leaves",
                    "suggested": ["upper leaf"],
                    "reason": "Source mentions 'leaves' without surface specification; reviewer should confirm upper vs lower.",
                },
            )
        ],
    )
    return VerifiedClaimsFile(gall_records=[record])


def build_manifest() -> Manifest:
    """Pipeline run bookkeeping. Carries schema_versions for every bundled artifact."""
    return Manifest(
        pipeline_name=PIPELINE_NAME,
        pipeline_version=PIPELINE_VERSION,
        pipeline_config_name=PIPELINE_CONFIG,
        seed=SEED,
        started_at=RUN_STARTED,
        completed_at=RUN_COMPLETED,
        source=Source(
            pdf_sha256=PDF_SHA,
            pdf_filename="example_paper.pdf",
            pdf_page_count=1,
            source_text_sha256=TEXT_SHA,
        ),
        schema_versions={
            "manifest.json": SCHEMA_VERSION,
            "sections.json": SCHEMA_VERSION,
            "metadata.json": SCHEMA_VERSION,
            "claims.json": SCHEMA_VERSION,
            "verified_claims.json": SCHEMA_VERSION,
            "review_artifact.json": SCHEMA_VERSION,
            "raw_text.jsonl": SCHEMA_VERSION,
            "normalized_text.jsonl": SCHEMA_VERSION,
        },
        stages=[
            StageRunRecord(
                name="extract",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                artifacts_written=["raw_text.jsonl"],
            ),
            StageRunRecord(
                name="preprocess",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                artifacts_written=["normalized_text.jsonl"],
                notes="Stripped 1 running-header block; rejoined 0 hyphenated words.",
            ),
            StageRunRecord(
                name="sectionize",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                artifacts_written=["sections.json"],
            ),
            StageRunRecord(
                name="metadata",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                calls=[
                    ProviderCallRecord(
                        model="deepinfra/meta-llama/Llama-3.1-8B-Instruct",
                        provider="deepinfra",
                        prompt_sha256=sha256_hex("metadata-prompt-v0"),
                        input_tokens=320,
                        output_tokens=128,
                        cost_usd=0.00018,
                        duration_ms=920,
                    )
                ],
                artifacts_written=["metadata.json"],
            ),
            StageRunRecord(
                name="find-candidates",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                calls=[
                    ProviderCallRecord(
                        model="deepinfra/meta-llama/Llama-3.1-8B-Instruct",
                        provider="deepinfra",
                        prompt_sha256=sha256_hex("find-candidates-prompt-v0"),
                        input_tokens=410,
                        output_tokens=68,
                        cost_usd=0.00012,
                        duration_ms=780,
                    )
                ]
                * 3,  # N=3 self-consistency
            ),
            StageRunRecord(
                name="extract-facts",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                calls=[
                    ProviderCallRecord(
                        model="deepinfra/Qwen/Qwen2.5-72B-Instruct",
                        provider="deepinfra",
                        prompt_sha256=sha256_hex("extract-facts-prompt-v0"),
                        input_tokens=1820,
                        output_tokens=620,
                        cost_usd=0.0091,
                        duration_ms=4200,
                    )
                ],
                artifacts_written=["candidates/C_001/facts.json"],
            ),
            StageRunRecord(
                name="verify",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                artifacts_written=["candidates/C_001/gated_facts.json"],
                notes="All evidence quotes matched at partial_ratio >= 90.",
            ),
            StageRunRecord(
                name="verify-claims",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                calls=[
                    ProviderCallRecord(
                        model="deepinfra/deepseek-ai/DeepSeek-V3",
                        provider="deepinfra",
                        prompt_sha256=sha256_hex("verify-claims-prompt-v0"),
                        input_tokens=210,
                        output_tokens=42,
                        cost_usd=0.00021,
                        duration_ms=480,
                    )
                ]
                * 12,  # one per per-field claim
            ),
            StageRunRecord(
                name="taxonomy-lookup",
                started_at=RUN_STARTED,
                completed_at=RUN_STARTED,
                status="ok",
                notes="2 GBIF lookups, both exact matches (cached: 0).",
            ),
            StageRunRecord(
                name="assemble-review",
                started_at=RUN_STARTED,
                completed_at=RUN_COMPLETED,
                status="ok",
                artifacts_written=[
                    "claims.json",
                    "verified_claims.json",
                    "review_artifact.json",
                ],
            ),
        ],
        total_cost_usd=0.01498,
        warnings=[
            WarningEntry(
                type=WarningType.SECTION_EXCLUDED,
                severity=WarningSeverity.INFO,
                detail={
                    "section_type": "references",
                    "reason": "No references section detected in example.",
                },
            )
        ],
    )


def build_review_artifact() -> ReviewArtifact:
    """The consumer-facing assembled view. Embeds normalized_text inline for UI rendering."""
    verified = build_verified_claims()
    metadata = build_metadata()
    return ReviewArtifact(
        pipeline_name=PIPELINE_NAME,
        pipeline_version=PIPELINE_VERSION,
        generated_at=RUN_COMPLETED,
        source=ReviewSource(
            pdf_sha256=PDF_SHA,
            pdf_filename="example_paper.pdf",
            pdf_page_count=1,
            source_text_sha256=TEXT_SHA,
            normalized_text=FLAT_NORMALIZED_TEXT,
        ),
        document_metadata=metadata,
        gall_records=verified.gall_records,
        warnings=verified.gall_records[0].warnings,
    )


def build_candidates() -> CandidatesFile:
    """Scratch artifact (not bundled by default) — proves the model works."""
    return CandidatesFile(
        candidates=[
            Candidate(
                candidate_id="C_001",
                gall_maker_mention="Andricus quercuscalifornicus",
                mention_span_ids=["S_0001"],
                sample_agreement=3,
            )
        ]
    )


# ─── Round-trip validation ────────────────────────────────────────────────


def round_trip[T: BaseModel](model: T) -> T:
    """Serialize to JSON, parse back into the same model class, return the parsed instance.

    Catches silent shape drift (e.g., aliases not symmetric, defaults that
    deserialize to a different value than they serialize to).
    """
    serialized = model.model_dump_json()
    parsed = type(model).model_validate_json(serialized)
    if parsed.model_dump() != model.model_dump():
        raise RuntimeError(
            f"Round-trip mismatch for {type(model).__name__}: serialized form parses back to a different object."
        )
    return parsed


# ─── Writers ───────────────────────────────────────────────────────────────


def write_json(path: Path, model: BaseModel) -> None:
    path.write_text(model.model_dump_json(indent=2) + "\n")


def write_jsonl(path: Path, rows: Iterable[BaseModel]) -> None:
    with path.open("w") as f:
        for row in rows:
            _ = f.write(row.model_dump_json() + "\n")


def write_bundle_tarball(source_dir: Path, output: Path) -> None:
    """Tar up the 9 bundle files. Per-candidate scratch is excluded by default."""
    artifacts = [
        "manifest.json",
        "source.pdf",
        "raw_text.jsonl",
        "normalized_text.jsonl",
        "sections.json",
        "metadata.json",
        "claims.json",
        "verified_claims.json",
        "review_artifact.json",
    ]
    with tarfile.open(output, "w:gz") as tar:
        for name in artifacts:
            path = source_dir / name
            if not path.exists():
                raise FileNotFoundError(f"Missing expected artifact: {path}")
            tar.add(path, arcname=name)


# ─── Main ──────────────────────────────────────────────────────────────────


@click.command()
@click.option(
    "--output",
    type=click.Path(file_okay=False, dir_okay=True, writable=True, path_type=Path),
    default=Path("/tmp/example-bundle"),
    show_default=True,
    help="Directory to write artifacts into. Will be created.",
)
def main(output: Path) -> None:
    """Build one schema-valid example bundle from the Pydantic models."""
    output.mkdir(parents=True, exist_ok=True)

    click.echo(f"Building example bundle in {output}")

    # Build every artifact. Pydantic validates on construction; any schema
    # mistake fails here.
    raw_text = build_raw_text()
    normalized_text = build_normalized_text()
    sections = build_sections()
    metadata = build_metadata()
    claims = build_claims()
    verified_claims = build_verified_claims()
    candidates = build_candidates()
    manifest = build_manifest()
    review = build_review_artifact()

    # Round-trip every top-level artifact. Catches serialization-asymmetry bugs.
    click.echo("Round-tripping artifacts...")
    for model in (sections, metadata, claims, verified_claims, candidates, manifest, review):
        round_trip(model)
    for row in raw_text + normalized_text:
        round_trip(row)
    click.echo("  ✓ all artifacts round-trip cleanly")

    # Write artifacts.
    (output / "source.pdf").write_bytes(EXAMPLE_PDF)
    write_jsonl(output / "raw_text.jsonl", raw_text)
    write_jsonl(output / "normalized_text.jsonl", normalized_text)
    write_json(output / "sections.json", sections)
    write_json(output / "metadata.json", metadata)
    write_json(output / "claims.json", claims)
    write_json(output / "verified_claims.json", verified_claims)
    write_json(output / "review_artifact.json", review)
    write_json(output / "manifest.json", manifest)

    # Also write the (not-in-bundle) candidates scratch for reference.
    scratch_dir = output / "candidates"
    scratch_dir.mkdir(exist_ok=True)
    write_json(scratch_dir / "candidates.json", candidates)

    # Tarball the bundle.
    bundle_path = output / "bundle.tar.gz"
    write_bundle_tarball(output, bundle_path)

    # Summary.
    click.echo("\nArtifacts written:")
    for path in sorted(output.glob("*")):
        if path.is_file():
            size = path.stat().st_size
            click.echo(f"  {path.name:30s} {size:>8d} bytes")

    click.echo("\nSanity checks:")
    click.echo(f"  flat normalized text length: {len(FLAT_NORMALIZED_TEXT)} chars")
    click.echo(f"  PDF SHA-256:                 {PDF_SHA}")
    click.echo(f"  normalized-text SHA-256:     {TEXT_SHA}")
    click.echo(f"  total artifact models used:  {len(ARTIFACT_MODELS)}")
    click.echo(f"\n✓ Example bundle ready at {bundle_path}")


if __name__ == "__main__":
    main()
