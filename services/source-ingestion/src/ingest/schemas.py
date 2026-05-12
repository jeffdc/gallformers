"""Source-of-truth Pydantic models for the ingestion-pipeline artifact bundle.

Every artifact in `bundle.tar.gz` is defined here. JSON Schema 2020-12 files
for server-side consumption are generated from these models via a separate
build script (`scripts/generate_schemas.py`, TBD).

Conventions:
- All `.json` artifacts have a top-level wrapper model with a pinned
  `schema_version` field (Literal type — bumping it is a deliberate break).
- JSONL artifacts (raw_text.jsonl, normalized_text.jsonl) use a per-row item
  model; their schema versions are tracked in `Manifest.schema_versions`.
- All models extend `StrictModel` which forbids extra fields. The pipeline
  fails loudly on schema violation; the server does the same on import.
- Evidence cells, trait cells, and scientific-name cells share `EvidenceCell`
  as a base; trait cells substitute `original/suggested[]` for `value`.

For Phase A (plumbing) all stages produce valid instances of these models
even when the LLM output is a stub. Phase B (prompt iteration) improves the
content without changing the shape.
"""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

SCHEMA_VERSION: Literal["1.0.0"] = "1.0.0"


# ─── Enums ─────────────────────────────────────────────────────────────────


class SupportStatus(StrEnum):
    """Verifier/gate verdict on a single field's evidence.

    `supported` and `contradicted` are verifier verdicts.
    `evidence_substring_mismatch` is the substring gate's verdict (value nulled).
    `abstained` is the extractor declining to fill the field.
    """

    SUPPORTED = "supported"
    CONTRADICTED = "contradicted"
    NOT_ENOUGH_EVIDENCE = "not_enough_evidence"
    NEEDS_HUMAN_REVIEW = "needs_human_review"
    EVIDENCE_SUBSTRING_MISMATCH = "evidence_substring_mismatch"
    ABSTAINED = "abstained"


class WarningType(StrEnum):
    """Closed enum of warning types. UI rendering depends on this set."""

    EVIDENCE_SUBSTRING_MISMATCH = "evidence_substring_mismatch"
    VERIFIER_CONTRADICTED = "verifier_contradicted"
    SCHEMA_REPAIR_APPLIED = "schema_repair_applied"
    LLM_OUTPUT_INVALID = "llm_output_invalid"
    IDLE_TIMEOUT_RETRY = "idle_timeout_retry"
    USAGE_ESTIMATED = "usage_estimated"
    SECTION_EXCLUDED = "section_excluded"
    VOCAB_NO_MATCH = "vocab_no_match"
    TAXONOMY_NO_MATCH = "taxonomy_no_match"
    TAXONOMY_FUZZY_MATCH_LOW_CONFIDENCE = "taxonomy_fuzzy_match_low_confidence"
    TAXONOMY_API_ERROR = "taxonomy_api_error"
    TAXONOMY_SOURCE_DISAGREEMENT = "taxonomy_source_disagreement"


class WarningSeverity(StrEnum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"


class TaxonomyLookupSource(StrEnum):
    """The pipeline produces GBIF entries only. The server appends WCVP for plants."""

    GBIF = "GBIF"
    WCVP = "WCVP"
    COL = "COL"
    EOL = "EOL"
    ITIS = "ITIS"


class TaxonomyLookupStatus(StrEnum):
    EXACT = "exact"
    FUZZY = "fuzzy"
    SYNONYM = "synonym"
    NO_MATCH = "no_match"
    API_ERROR = "api_error"


class SectionType(StrEnum):
    """Logical sections detected by the rule-based sectionizer."""

    TITLE = "title"
    ABSTRACT = "abstract"
    INTRODUCTION = "introduction"
    METHODS = "methods"
    TAXONOMIC_TREATMENT = "taxonomic_treatment"
    DESCRIPTION = "description"
    HOST_LIST = "host_list"
    KEY = "key"
    TABLE = "table"
    CAPTION = "caption"
    REFERENCES = "references"
    BIBLIOGRAPHY = "bibliography"
    LITERATURE_CITED = "literature_cited"
    APPENDIX = "appendix"
    UNKNOWN = "unknown"


class ConfidenceBucket(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class Detachable(StrEnum):
    """How a gall relates to host tissue. Distinct from trait vocab."""

    UNKNOWN = "unknown"
    INTEGRAL = "integral"
    DETACHABLE = "detachable"
    BOTH = "both"


# ─── Base model ────────────────────────────────────────────────────────────


class StrictModel(BaseModel):
    """All artifact models inherit from this. Unknown fields are rejected."""

    model_config = ConfigDict(extra="forbid")


# ─── Evidence ──────────────────────────────────────────────────────────────


class Evidence(StrictModel):
    """A single citation pointing at the canonical normalized text.

    Both block-relative addressing (`block_id`) and absolute offsets are
    carried (per amendment 1 of the artifact contract). UI uses
    `char_start`/`char_end` to render highlights; audit tools use `block_id`
    to trace back to `normalized_text.jsonl`.
    """

    block_id: str = Field(description="ID of the source block in normalized_text.jsonl")
    page: int = Field(ge=1, description="1-indexed page number")
    char_start: int = Field(ge=0, description="Absolute char offset in the flat normalized text")
    char_end: int = Field(ge=0, description="Absolute char offset (exclusive)")
    quote: str = Field(
        description="Exact substring at [char_start:char_end] of the flat normalized text"
    )

    @model_validator(mode="after")
    def _check_range(self) -> Evidence:
        if self.char_end <= self.char_start:
            raise ValueError(f"char_end ({self.char_end}) must be > char_start ({self.char_start})")
        return self


# ─── Taxonomy ──────────────────────────────────────────────────────────────


class TaxonomyMatch(StrictModel):
    """A single source's matched record. Fields beyond `scientific_name` are best-effort."""

    scientific_name: str
    rank: str | None = None
    kingdom: str | None = None
    phylum: str | None = None
    class_name: str | None = Field(
        default=None, description="Taxonomic class (avoiding Python `class` keyword)"
    )
    order: str | None = None
    family: str | None = None
    genus: str | None = None
    canonical_name: str | None = None
    accepted_name: str | None = Field(default=None, description="Populated when status == synonym")
    source_key: str | None = Field(
        default=None, description="Provider-native ID, e.g. GBIF usageKey"
    )
    url: str | None = None


class TaxonomyLookup(StrictModel):
    """One source's lookup result. Stored as a list per name field."""

    source: TaxonomyLookupSource
    status: TaxonomyLookupStatus
    match: TaxonomyMatch | None = Field(
        default=None, description="Populated when status is exact/fuzzy/synonym; null otherwise"
    )
    confidence: float | None = Field(
        default=None, ge=0, le=1, description="Provider-reported match confidence"
    )
    queried_at: datetime


# ─── Evidence cells (the repeating unit) ──────────────────────────────────


class EvidenceCell(StrictModel):
    """Every fact field has this shape: value + evidence + verifier verdict."""

    value: str | None = Field(
        description="Extracted value; null when abstained or substring-gate-rejected"
    )
    raw_value: str | None = Field(
        default=None, description="Source phrase before normalization, when different from value"
    )
    evidence: list[Evidence] = Field(default_factory=list)
    support_status: SupportStatus
    confidence: float = Field(ge=0, le=1)


class ScientificNameCell(EvidenceCell):
    """Evidence cell for taxonomic names. Carries `name_as_written` and `taxonomy_lookups`.

    The pipeline appends one GBIF entry to `taxonomy_lookups`. The server appends
    a WCVP entry for plant names during bundle import.
    """

    name_as_written: str | None = Field(
        default=None,
        description="Exact source-text form, preserved verbatim. Includes OCR damage and historical spellings.",
    )
    taxonomy_lookups: list[TaxonomyLookup] = Field(default_factory=list)


class TraitCell(StrictModel):
    """Trait fields use original-source-phrase + controlled-vocab-suggestions shape.

    `suggested` items map to entries in `gallformers-vocab.json`. Pipeline does not
    enforce the vocab at this layer — Instructor uses a per-call dynamic schema
    constraining `suggested` to allowed values during extraction.
    """

    original: str | None = Field(
        description="Exact source phrase, e.g. 'bright red'. Null if trait unmentioned."
    )
    suggested: list[str] = Field(
        default_factory=list, description="Controlled-vocab mappings; may be empty"
    )
    evidence: list[Evidence] = Field(default_factory=list)
    support_status: SupportStatus
    confidence: float = Field(ge=0, le=1)


# ─── Warnings ──────────────────────────────────────────────────────────────


class WarningEntry(StrictModel):
    """One warning. Type-specific detail goes in `detail` as a free-form dict."""

    type: WarningType
    severity: WarningSeverity = WarningSeverity.WARNING
    record_id: str | None = Field(
        default=None, description="Gall-record ID when warning is record-scoped"
    )
    field_path: str | None = Field(
        default=None,
        description="Dotted path to the offending field, e.g. 'gall_traits.color'",
    )
    detail: dict[str, Any] = Field(
        default_factory=dict, description="Type-specific structured info"
    )


# ─── Raw text and normalized text (JSONL rows) ────────────────────────────


class Bbox(StrictModel):
    """Bounding box in PDF page coordinates (top-left origin)."""

    x0: float
    y0: float
    x1: float
    y1: float


class RawTextBlock(StrictModel):
    """One row of `raw_text.jsonl` — a block extracted from a PDF page.

    Audit-only artifact. Not addressable by evidence offsets; the normalized
    blocks are the canonical substrate.
    """

    block_id: str = Field(description="Unique block ID, e.g. 'p12-b04'")
    page: int = Field(ge=1)
    text: str
    bbox: Bbox | None = None
    extractor: str = Field(description="e.g. 'pymupdf-1.24.0' or 'olmocr-2-7B-1025'")
    quality_signals: dict[str, Any] = Field(
        default_factory=dict,
        description="Extractor-specific signals: confidence, char count, weird-char ratio, etc.",
    )


class NormalizedBlock(StrictModel):
    """One row of `normalized_text.jsonl` — a cleaned block. Used as a span by extraction.

    `char_start`/`char_end` are the block's range in the flat normalized text
    (the concatenation of all normalized blocks separated by '\\n\\n'). Evidence
    in claims/verified_claims addresses *into* the flat text using these
    absolute offsets, which are stable across re-runs given the same input.
    """

    span_id: str = Field(description="e.g. 'S_0001', zero-padded for sortability")
    block_id: str = Field(description="Block identifier; what Evidence.block_id references")
    page: int = Field(ge=1)
    section_id: str | None = Field(default=None, description="ID into sections.json")
    char_start: int = Field(ge=0, description="Block start offset in the flat normalized text")
    char_end: int = Field(
        ge=0, description="Block end offset (exclusive) in the flat normalized text"
    )
    text: str
    raw_block_ids: list[str] = Field(
        description="Source blocks in raw_text.jsonl that contributed to this block"
    )

    @model_validator(mode="after")
    def _check_range(self) -> NormalizedBlock:
        if self.char_end <= self.char_start:
            raise ValueError(f"char_end ({self.char_end}) must be > char_start ({self.char_start})")
        return self


# ─── Sections ──────────────────────────────────────────────────────────────


class Section(StrictModel):
    section_id: str
    type: SectionType
    heading: str | None = Field(default=None, description="Detected heading text, if any")
    heading_path: list[str] = Field(
        default_factory=list,
        description="Ancestral headings, e.g. ['Taxonomic Treatments', 'Andricus quercuscalifornicus']",
    )
    page_start: int = Field(ge=1)
    page_end: int = Field(ge=1)
    span_ids: list[str] = Field(
        description="Span IDs in normalized_text.jsonl belonging to this section"
    )
    extraction_eligible: bool = Field(
        description="False for references/bibliography/literature_cited; suppresses extraction"
    )

    @model_validator(mode="after")
    def _check_pages(self) -> Section:
        if self.page_end < self.page_start:
            raise ValueError(
                f"page_end ({self.page_end}) must be >= page_start ({self.page_start})"
            )
        return self


class SectionsFile(StrictModel):
    """`sections.json` — top-level container for the document's sections."""

    schema_version: Literal["1.0.0"] = "1.0.0"
    sections: list[Section]


# ─── Manifest ──────────────────────────────────────────────────────────────


class ProviderCallRecord(StrictModel):
    """One LLM call's bookkeeping. Many of these aggregate into a stage record."""

    model: str = Field(
        description="LiteLLM model string, e.g. 'deepinfra/Qwen/Qwen2.5-72B-Instruct'"
    )
    provider: str = Field(description="Provider name extracted from model string, e.g. 'deepinfra'")
    prompt_sha256: str = Field(min_length=64, max_length=64)
    input_tokens: int = Field(ge=0)
    output_tokens: int = Field(ge=0)
    cost_usd: float = Field(ge=0, description="From LiteLLM completion_cost()")
    duration_ms: int = Field(ge=0)
    idle_timeouts_hit: int = Field(default=0, ge=0)
    total_timeout_hit: bool = False
    usage_estimated: bool = Field(
        default=False, description="True if LiteLLM didn't return usage and we estimated"
    )
    status: Literal["ok", "error"] = "ok"
    error_detail: str | None = Field(
        default=None,
        description=(
            "Exception class and message when the call failed (e.g. Instructor "
            "exhausted retries on schema validation). Only set when status='error'."
        ),
    )


class StageRunRecord(StrictModel):
    """One stage's execution bookkeeping."""

    name: str = Field(description="Stage name, e.g. 'extract-facts'")
    started_at: datetime
    completed_at: datetime
    status: Literal["ok", "error", "skipped"] = "ok"
    calls: list[ProviderCallRecord] = Field(
        default_factory=list, description="LLM calls made by this stage"
    )
    artifacts_written: list[str] = Field(
        default_factory=list, description="Artifact filenames produced"
    )
    notes: str | None = None

    @model_validator(mode="after")
    def _check_times(self) -> StageRunRecord:
        if self.completed_at < self.started_at:
            raise ValueError("completed_at must be >= started_at")
        return self


class Source(StrictModel):
    """Source-document identity. Appears in `Manifest`. The PDF bytes ship in the bundle."""

    pdf_sha256: str = Field(
        min_length=64, max_length=64, description="SHA-256 of source.pdf, lowercase hex"
    )
    pdf_filename: str
    pdf_page_count: int = Field(ge=1)
    source_text_sha256: str = Field(
        min_length=64, max_length=64, description="SHA-256 of the flat normalized text"
    )


class Manifest(StrictModel):
    """`manifest.json` — pipeline run metadata. The authoritative bookkeeper.

    Records schema versions for every artifact in the bundle (especially JSONL
    artifacts that don't carry schema_version themselves).
    """

    schema_version: Literal["1.0.0"] = "1.0.0"
    pipeline_name: str
    pipeline_version: str
    pipeline_config_name: str
    seed: int
    started_at: datetime
    completed_at: datetime
    source: Source
    schema_versions: dict[str, str] = Field(
        description="Map of artifact filename → schema version. Covers JSONL artifacts."
    )
    stages: list[StageRunRecord]
    total_cost_usd: float = Field(ge=0)
    warnings: list[WarningEntry] = Field(default_factory=list)

    @model_validator(mode="after")
    def _check_times(self) -> Manifest:
        if self.completed_at < self.started_at:
            raise ValueError("completed_at must be >= started_at")
        return self


# ─── Document metadata ─────────────────────────────────────────────────────


class DocumentMetadata(StrictModel):
    """`metadata.json` — bibliographic metadata, evidence-bound."""

    schema_version: Literal["1.0.0"] = "1.0.0"
    title: EvidenceCell
    authors: list[EvidenceCell] = Field(default_factory=list)
    year: EvidenceCell | None = None
    journal: EvidenceCell | None = None
    volume: EvidenceCell | None = None
    issue: EvidenceCell | None = None
    pages: EvidenceCell | None = None
    doi: EvidenceCell | None = None
    language: EvidenceCell | None = None


# ─── Gall records ──────────────────────────────────────────────────────────


class Taxonomy(StrictModel):
    """Higher-classification ranks for a taxon. All optional; populated per source.

    `class` is renamed to `class_name` to avoid the Python keyword. Server-side
    consumers normalize this back to `class` on read if needed.
    """

    kingdom: ScientificNameCell | None = None
    phylum: ScientificNameCell | None = None
    class_name: ScientificNameCell | None = None
    order: ScientificNameCell | None = None
    suborder: ScientificNameCell | None = None
    family: ScientificNameCell | None = None
    subfamily: ScientificNameCell | None = None
    tribe: ScientificNameCell | None = None
    genus: ScientificNameCell | None = None
    subgenus: ScientificNameCell | None = None


class GallMaker(StrictModel):
    """The organism that induces the gall. May be unknown (`scientific_name.value` null)."""

    scientific_name: ScientificNameCell
    authority: EvidenceCell | None = None
    rank: EvidenceCell | None = Field(
        default=None, description="Taxonomic rank of scientific_name, e.g. 'species'"
    )
    taxonomy: Taxonomy = Field(default_factory=Taxonomy)
    aliases: list[ScientificNameCell] = Field(default_factory=list)
    common_names: list[EvidenceCell] = Field(default_factory=list)


class Host(StrictModel):
    """A host species the gall-maker uses. One record per (gall, host) pair."""

    scientific_name: ScientificNameCell
    authority: EvidenceCell | None = None
    rank: EvidenceCell | None = None


class GallTraits(StrictModel):
    """Trait fields. `suggested` values come from gallformers-vocab.json.

    Adult-insect traits (antennae, wings, mesosoma, body color, etc.) are
    explicitly disallowed by the extraction prompt — they belong on the
    gall-maker, not the gall.
    """

    color: TraitCell | None = None
    shape: TraitCell | None = None
    texture: TraitCell | None = None
    walls: TraitCell | None = None
    cells: TraitCell | None = None
    alignment: TraitCell | None = None
    plant_part: TraitCell | None = None
    form: TraitCell | None = None
    season: TraitCell | None = None
    detachable: EvidenceCell | None = Field(
        default=None,
        description="One of: unknown, integral, detachable, both (see Detachable enum)",
    )


class GallRecord(StrictModel):
    """One gall-host association. The atomic unit of extraction."""

    record_id: str = Field(description="Stable record ID, e.g. 'R_001'")
    candidate_id: str = Field(description="Pipeline-internal candidate ID, e.g. 'C_001'")
    gall_maker: GallMaker
    hosts: list[Host] = Field(default_factory=list)
    gall_traits: GallTraits = Field(default_factory=GallTraits)
    description: EvidenceCell | None = Field(
        default=None, description="Morphological description text from the source"
    )
    location: EvidenceCell | None = Field(
        default=None, description="Collection locality if mentioned"
    )
    confidence_bucket: ConfidenceBucket = ConfidenceBucket.MEDIUM
    warnings: list[WarningEntry] = Field(default_factory=list)


# ─── Claims / verified claims ──────────────────────────────────────────────


class ClaimsFile(StrictModel):
    """`claims.json` — extracted records before verifier and taxonomy_lookup ran.

    Same shape as VerifiedClaimsFile; `support_status` reflects only the
    extractor's self-report and the substring gate's verdict at this point.
    """

    schema_version: Literal["1.0.0"] = "1.0.0"
    gall_records: list[GallRecord]


class VerifiedClaimsFile(StrictModel):
    """`verified_claims.json` — claims with verifier verdicts and GBIF lookups populated."""

    schema_version: Literal["1.0.0"] = "1.0.0"
    gall_records: list[GallRecord]


# ─── Candidates (scratch — find-candidates output) ────────────────────────


class Candidate(StrictModel):
    """One gall-maker mention. Per-candidate scratch only; not in the bundle by default."""

    candidate_id: str = Field(description="e.g. 'C_001'")
    gall_maker_mention: str = Field(description="Name as it appears in the source")
    mention_span_ids: list[str] = Field(description="Spans where this candidate is mentioned")
    sample_agreement: int = Field(
        ge=1, description="How many of N self-consistency samples produced this candidate"
    )


class CandidatesFile(StrictModel):
    """`candidates.json` — find-candidates output (scratch, not in bundle)."""

    schema_version: Literal["1.0.0"] = "1.0.0"
    candidates: list[Candidate]


# ─── Review artifact (top-level consumer view) ────────────────────────────


class ReviewSource(StrictModel):
    """Source info for the review artifact. Carries `normalized_text` inline for UI rendering."""

    pdf_sha256: str = Field(min_length=64, max_length=64)
    pdf_filename: str
    pdf_page_count: int = Field(ge=1)
    source_text_sha256: str = Field(min_length=64, max_length=64)
    normalized_text: str = Field(
        description="Flat normalized text; evidence char offsets address into this string"
    )


class ReviewArtifact(StrictModel):
    """`review_artifact.json` — consumer-facing assembled view.

    What the review UI primarily reads. Combines metadata + gall_records +
    enough source context (normalized_text) to render evidence highlights
    without needing to walk other artifacts.
    """

    schema_version: Literal["1.0.0"] = "1.0.0"
    pipeline_name: str
    pipeline_version: str
    generated_at: datetime
    source: ReviewSource
    document_metadata: DocumentMetadata
    gall_records: list[GallRecord]
    warnings: list[WarningEntry] = Field(default_factory=list)


# ─── Public list of artifact models (for the schema generator) ────────────


ARTIFACT_MODELS: dict[str, type[BaseModel]] = {
    "manifest.json": Manifest,
    "sections.json": SectionsFile,
    "metadata.json": DocumentMetadata,
    "claims.json": ClaimsFile,
    "verified_claims.json": VerifiedClaimsFile,
    "review_artifact.json": ReviewArtifact,
    # JSONL artifacts: schema generator emits the item model.
    "raw_text.jsonl": RawTextBlock,
    "normalized_text.jsonl": NormalizedBlock,
    # Scratch artifacts (not bundled by default):
    "candidates.json": CandidatesFile,
}
