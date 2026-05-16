"""Async pipeline runner for the north-star ingestion pipeline.

Loads a YAML config, dispatches each stage in order, and writes artifacts
to a per-source working directory. Per-candidate stages (``extract-facts``,
``verify-claims`` per cell) fan out via ``asyncio.gather`` with a per-stage
``asyncio.Semaphore`` from the stage's ``max_workers``. The final stages
assemble all four contract artifacts and tarball the bundle.

Resumability is intentionally minimal in Phase A — if an intermediate
artifact exists on disk the stage skips and reuses it. Richer cache
invalidation (prompt-SHA aware) is Phase B work.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import yaml

from ingest.assemble import assemble
from ingest.bundle import write_bundle
from ingest.evidence_pack import build_evidence_pack
from ingest.extract import extract_blocks
from ingest.extract_facts import extract_facts
from ingest.find_candidates import find_candidates
from ingest.jsonl import write_jsonl
from ingest.metadata import extract_document_metadata
from ingest.preprocess import flat_normalized_text, preprocess_blocks
from ingest.schemas import (
    Candidate,
    CandidatesFile,
    DocumentMetadata,
    GallRecord,
    NormalizedBlock,
    ProviderCallRecord,
    SectionType,
    StageRunRecord,
    WarningEntry,
    WarningSeverity,
    WarningType,
)
from ingest.sectionize import sectionize
from ingest.taxonomy_lookup import enrich_cells_concurrently
from ingest.verify import _index_blocks, gate_cell
from ingest.verify_claims import verify_cell

VALID_STEPS = frozenset(
    {
        "extract",
        "preprocess",
        "sectionize",
        "metadata",
        "find-candidates",
        "evidence-pack",
        "extract-facts",
        "verify",
        "verify-claims",
        "taxonomy-lookup",
        "assemble-review",
        "bundle",
    }
)


# ─── YAML loading + validation ────────────────────────────────────────────


def load_pipeline(config_path: str) -> dict:
    """Load and validate a pipeline YAML config."""
    path = Path(config_path)
    if not path.exists():
        raise FileNotFoundError(f"Pipeline config not found: {config_path}")

    with path.open() as f:
        raw = yaml.safe_load(f)

    if not isinstance(raw, dict) or "pipeline" not in raw:
        raise ValueError(f"Pipeline config must contain a top-level 'pipeline' key: {config_path}")
    pipeline = raw["pipeline"]
    for required in ("name", "stages"):
        if required not in pipeline:
            raise ValueError(f"Pipeline config missing '{required}': {config_path}")
    if not pipeline["stages"]:
        raise ValueError(f"Pipeline config has empty 'stages' list: {config_path}")

    for stage in pipeline["stages"]:
        step = stage.get("step")
        if step is None:
            raise ValueError(f"Stage missing 'step' key: {stage}")
        if step not in VALID_STEPS:
            raise ValueError(f"Unknown step type {step!r}. Valid steps: {sorted(VALID_STEPS)}")

    return pipeline


# ─── Helpers ──────────────────────────────────────────────────────────────


def _stages_by_step(pipeline: dict) -> dict[str, dict]:
    """Map step name to its config dict. Last definition wins on duplicates."""
    return {s["step"]: s for s in pipeline["stages"]}


def _project_root() -> Path:
    """Repo path that hosts ``prompts/`` and ``schemas/`` relative to this module."""
    return Path(__file__).resolve().parents[2]


def _load_prompt(rel_path: str) -> tuple[str, str]:
    """Load a prompt file and compute its SHA-256."""
    path = _project_root() / rel_path
    if not path.exists():
        raise FileNotFoundError(f"Prompt file not found: {path}")
    content = path.read_text()
    return content, hashlib.sha256(content.encode("utf-8")).hexdigest()


def _now() -> datetime:
    return datetime.now(UTC)


def _pdf_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _text_sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _eligible_blocks(
    blocks: list[NormalizedBlock], sections_with_eligibility: dict[str, bool]
) -> list[NormalizedBlock]:
    """Filter blocks to those whose section is extraction-eligible."""
    return [b for b in blocks if sections_with_eligibility.get(b.section_id or "", True)]


def _blocks_in_section_types(
    blocks: list[NormalizedBlock],
    sections_by_id: dict[str, Any],
    section_types: list[str],
) -> list[NormalizedBlock]:
    """Filter blocks whose section type matches one of the given names."""
    wanted = set(section_types)
    return [
        b
        for b in blocks
        if b.section_id
        and sections_by_id.get(b.section_id)
        and sections_by_id[b.section_id].type.value in wanted
    ]


def _cache_sidecar_path(artifact_path: Path) -> Path:
    """Sidecar path holding the cache key for an artifact (``foo.json.cache.json``)."""
    return artifact_path.with_suffix(artifact_path.suffix + ".cache.json")


def _is_cache_valid(artifact_path: Path, current_key: dict) -> bool:
    """True iff both the artifact and its cache sidecar exist and the sidecar's
    stored key matches ``current_key``.

    Used by LLM stages to decide whether the prior run's output can be reused
    without re-issuing the LLM call. The cache key typically captures the
    prompt SHA, the model, and any content-hash of the stage's actual input
    so upstream changes invalidate downstream caches automatically.
    """
    sidecar = _cache_sidecar_path(artifact_path)
    if not artifact_path.exists() or not sidecar.exists():
        return False
    try:
        prior = json.loads(sidecar.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    return all(prior.get(k) == v for k, v in current_key.items())


def _write_cache_sidecar(artifact_path: Path, key: dict) -> None:
    """Persist a cache key next to its artifact for use on the next run."""
    _cache_sidecar_path(artifact_path).write_text(json.dumps(key, indent=2, sort_keys=True))


def _sha_str(s: str) -> str:
    """Short SHA-256 of a string. Used in cache keys for content-stability."""
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def _warning_for_error_call(
    call: ProviderCallRecord,
    *,
    stage: str,
    record_id: str | None = None,
    field_path: str | None = None,
    detail: dict | None = None,
) -> WarningEntry | None:
    """Synthesize a manifest WarningEntry from an error-status ProviderCallRecord.

    Returns ``None`` for successful calls. Used by the pipeline runner to flow
    Instructor-failure information from individual LLM calls into the manifest's
    top-level warnings list. The stage, record_id, and field_path arguments
    carry scope information the call record itself doesn't track.
    """
    if call.status != "error":
        return None
    d = dict(detail or {})
    d["stage"] = stage
    if call.error_detail:
        d["error_detail"] = call.error_detail
    return WarningEntry(
        type=WarningType.LLM_OUTPUT_INVALID,
        severity=WarningSeverity.WARNING,
        record_id=record_id,
        field_path=field_path,
        detail=d,
    )


# ─── Main runner ──────────────────────────────────────────────────────────


async def run_pipeline(
    pipeline: dict,
    source_id: str | int,
    input_path: str | None,
    provider_config: dict,
    output_dir: str = "./output",
) -> Path:
    """Execute a pipeline end-to-end. Returns the path to the produced bundle.

    Args:
        pipeline: parsed YAML config from ``load_pipeline``.
        source_id: per-paper identifier; defines the working subdirectory.
        input_path: PDF/URL/text file to ingest. Required for the ``extract`` stage.
        provider_config: parsed providers config (unused directly at this layer —
            LiteLLM resolves models from the model strings in the pipeline YAML).
        output_dir: base directory for per-source working dirs.

    Returns:
        Path to the produced ``bundle.tar.gz``.

    Raises:
        NotImplementedError: if the pipeline uses a stage type that exists in
            ``VALID_STEPS`` but isn't wired into this runner yet (e.g., ``ocr``).
        FileNotFoundError: missing input file, missing prompt file, or missing
            artifact at the bundle stage with ``verify_complete=True``.
    """
    started_at = _now()
    src_dir = Path(output_dir) / str(source_id)
    src_dir.mkdir(parents=True, exist_ok=True)
    candidates_dir = src_dir / "candidates"
    candidates_dir.mkdir(exist_ok=True)

    stages_cfg = _stages_by_step(pipeline)
    defaults = pipeline.get("defaults", {})
    default_total_timeout = float(defaults.get("total_timeout_s", 300.0))
    stage_records: list[StageRunRecord] = []
    warnings: list[WarningEntry] = []

    # ── extract ──────────────────────────────────────────────────────────
    if "extract" not in stages_cfg:
        raise ValueError("Pipeline must include an 'extract' stage")
    if input_path is None:
        raise ValueError("input_path is required for the 'extract' stage")
    t = _now()
    raw_blocks = extract_blocks(input_path)
    write_jsonl(raw_blocks, src_dir / "raw_text.jsonl")
    pdf_sha = (
        _pdf_sha(Path(input_path))
        if Path(input_path).suffix.lower() == ".pdf"
        else _text_sha(input_path)
    )
    stage_records.append(
        StageRunRecord(
            name="extract",
            started_at=t,
            completed_at=_now(),
            artifacts_written=["raw_text.jsonl"],
        )
    )

    # ── preprocess ───────────────────────────────────────────────────────
    t = _now()
    normalized_blocks = preprocess_blocks(raw_blocks)
    stage_records.append(
        StageRunRecord(
            name="preprocess",
            started_at=t,
            completed_at=_now(),
            artifacts_written=[],
        )
    )

    # ── sectionize ───────────────────────────────────────────────────────
    # normalized_text.jsonl is written here (not after preprocess) so each
    # row carries the section_id that sectionize assigns; otherwise every
    # on-disk row would be section_id=null even though in-memory blocks
    # are correct.
    t = _now()
    sections_file, normalized_blocks = sectionize(normalized_blocks)
    write_jsonl(normalized_blocks, src_dir / "normalized_text.jsonl")
    (src_dir / "sections.json").write_text(sections_file.model_dump_json(indent=2))
    sections_by_id = {s.section_id: s for s in sections_file.sections}
    eligibility = {s.section_id: s.extraction_eligible for s in sections_file.sections}
    stage_records.append(
        StageRunRecord(
            name="sectionize",
            started_at=t,
            completed_at=_now(),
            artifacts_written=["normalized_text.jsonl", "sections.json"],
        )
    )

    # ── metadata ─────────────────────────────────────────────────────────
    document_metadata: DocumentMetadata
    if "metadata" in stages_cfg:
        cfg = stages_cfg["metadata"]
        prompt_content, prompt_sha = _load_prompt(cfg["prompt"])
        section_types = cfg.get("input_section_types") or [
            SectionType.TITLE.value,
            SectionType.ABSTRACT.value,
            SectionType.INTRODUCTION.value,
        ]
        meta_input_blocks = _blocks_in_section_types(
            normalized_blocks, sections_by_id, section_types
        )
        # Phase A: when sectionizer hasn't typed sections (everything UNKNOWN),
        # fall back to the first ~20 blocks so the stage still gets input.
        # 20 (vs 5) covers journal-banner-heavy front matter on monograph
        # publishers like Zootaxa: page 1 typically has DOI/ISSN/copyright
        # in blocks 0-7 with title and authors only appearing around blocks
        # 8-12. Cost is negligible — metadata is one call per paper and
        # 20 blocks of front matter is ~3-5K tokens.
        if not meta_input_blocks:
            meta_input_blocks = normalized_blocks[:20]

        meta_path = src_dir / "metadata.json"
        meta_input_sha = _sha_str("\n".join(f"{b.span_id}:{b.text}" for b in meta_input_blocks))
        meta_cache_key = {
            "stage": "metadata",
            "prompt_sha256": prompt_sha,
            "model": cfg["model"],
            "input_sha": meta_input_sha,
        }

        t = _now()
        if _is_cache_valid(meta_path, meta_cache_key):
            document_metadata = DocumentMetadata.model_validate_json(meta_path.read_text())
            stage_records.append(
                StageRunRecord(
                    name="metadata",
                    started_at=t,
                    completed_at=_now(),
                    calls=[],
                    artifacts_written=["metadata.json"],
                    notes="cached",
                )
            )
        else:
            document_metadata, call = await extract_document_metadata(
                meta_input_blocks,
                model=cfg["model"],
                prompt=prompt_content,
                prompt_sha256=prompt_sha,
                total_timeout=float(cfg.get("total_timeout_s", default_total_timeout)),
            )
            meta_path.write_text(document_metadata.model_dump_json(indent=2))
            _write_cache_sidecar(meta_path, meta_cache_key)
            w = _warning_for_error_call(call, stage="metadata")
            if w:
                warnings.append(w)
            stage_records.append(
                StageRunRecord(
                    name="metadata",
                    started_at=t,
                    completed_at=_now(),
                    calls=[call],
                    artifacts_written=["metadata.json"],
                )
            )
    else:
        document_metadata = DocumentMetadata(
            title=__import__("ingest.metadata", fromlist=["_abstaining_title"])._abstaining_title()
        )
        (src_dir / "metadata.json").write_text(document_metadata.model_dump_json(indent=2))

    # ── find-candidates ──────────────────────────────────────────────────
    cfg = stages_cfg["find-candidates"]
    prompt_content, prompt_sha = _load_prompt(cfg["prompt"])
    eligible = _eligible_blocks(normalized_blocks, eligibility)

    candidates_path = src_dir / "candidates.json"
    eligible_sha = _sha_str("\n".join(f"{b.span_id}:{b.text}" for b in eligible))
    fc_cache_key = {
        "stage": "find-candidates",
        "prompt_sha256": prompt_sha,
        "model": cfg["model"],
        "n_samples": cfg.get("n_samples", 3),
        "agreement_threshold": cfg.get("agreement_threshold", 2),
        "eligible_sha": eligible_sha,
    }

    t = _now()
    if _is_cache_valid(candidates_path, fc_cache_key):
        candidates_file = CandidatesFile.model_validate_json(candidates_path.read_text())
        stage_records.append(
            StageRunRecord(
                name="find-candidates",
                started_at=t,
                completed_at=_now(),
                calls=[],
                notes="cached",
            )
        )
    else:
        candidates_file, sample_records = await find_candidates(
            blocks=eligible,
            model=cfg["model"],
            prompt=prompt_content,
            prompt_sha256=prompt_sha,
            n_samples=cfg.get("n_samples", 3),
            agreement_threshold=cfg.get("agreement_threshold", 2),
        )
        candidates_path.write_text(candidates_file.model_dump_json(indent=2))
        _write_cache_sidecar(candidates_path, fc_cache_key)
        for i, sample_call in enumerate(sample_records):
            w = _warning_for_error_call(
                sample_call, stage="find-candidates", detail={"sample_idx": i}
            )
            if w:
                warnings.append(w)
        stage_records.append(
            StageRunRecord(
                name="find-candidates",
                started_at=t,
                completed_at=_now(),
                calls=sample_records,
            )
        )

    # ── evidence-pack + extract-facts (per candidate) ────────────────────
    pack_cfg = stages_cfg.get("evidence-pack", {})
    context_window = pack_cfg.get("context_window", 2)
    facts_cfg = stages_cfg["extract-facts"]
    facts_prompt, facts_prompt_sha = _load_prompt(facts_cfg["prompt"])
    facts_workers = facts_cfg.get("max_workers", 4)
    facts_semaphore = asyncio.Semaphore(facts_workers)
    # Optional controlled-vocab JSON (per-trait `suggested[]` allowed values).
    # Path is relative to the project root, same convention as `prompt:`.
    facts_vocab: dict | None = None
    facts_vocab_sha: str | None = None
    if facts_cfg.get("vocab"):
        vocab_path = _project_root() / facts_cfg["vocab"]
        if not vocab_path.exists():
            raise FileNotFoundError(f"Vocab file not found: {vocab_path}")
        vocab_text = vocab_path.read_text()
        facts_vocab = json.loads(vocab_text)
        facts_vocab_sha = _sha_str(vocab_text)

    async def _process_candidate(c: Candidate) -> tuple[GallRecord, ProviderCallRecord | None]:
        candidate_dir = candidates_dir / c.candidate_id
        candidate_dir.mkdir(exist_ok=True)
        pack_text, meta = build_evidence_pack(c, normalized_blocks, context_window=context_window)
        (candidate_dir / "evidence_pack.txt").write_text(pack_text)
        (candidate_dir / "evidence_pack.meta.json").write_text(json.dumps(meta, indent=2))
        facts_path = candidate_dir / "facts.json"
        cand_cache_key = {
            "stage": "extract-facts",
            "prompt_sha256": facts_prompt_sha,
            "model": facts_cfg["model"],
            "vocab_sha": facts_vocab_sha,
            "candidate_id": c.candidate_id,
            "evidence_pack_sha": _sha_str(pack_text),
        }
        if _is_cache_valid(facts_path, cand_cache_key):
            record = GallRecord.model_validate_json(facts_path.read_text())
            return record, None
        async with facts_semaphore:
            record, call = await extract_facts(
                candidate=c,
                evidence_pack_text=pack_text,
                allowed_span_ids=meta["allowed_span_ids"],
                model=facts_cfg["model"],
                prompt=facts_prompt,
                prompt_sha256=facts_prompt_sha,
                total_timeout=float(facts_cfg.get("total_timeout_s", default_total_timeout)),
                vocab=facts_vocab,
            )
        facts_path.write_text(record.model_dump_json(indent=2))
        _write_cache_sidecar(facts_path, cand_cache_key)
        return record, call

    t = _now()
    facts_results = await asyncio.gather(
        *[_process_candidate(c) for c in candidates_file.candidates]
    )
    claims_records = [r for r, _ in facts_results]
    # Cache hits return None for the call; filter them out of the manifest.
    facts_calls = [c for _, c in facts_results if c is not None]
    for record, call in facts_results:
        if call is None:
            continue
        w = _warning_for_error_call(call, stage="extract-facts", record_id=record.record_id)
        if w:
            warnings.append(w)
    stage_records.append(
        StageRunRecord(
            name="evidence-pack",
            started_at=t,
            completed_at=_now(),
            artifacts_written=[
                f"candidates/{c.candidate_id}/evidence_pack.txt" for c in candidates_file.candidates
            ],
        )
    )
    stage_records.append(
        StageRunRecord(
            name="extract-facts",
            started_at=t,
            completed_at=_now(),
            calls=facts_calls,
            artifacts_written=[
                f"candidates/{c.candidate_id}/facts.json" for c in candidates_file.candidates
            ],
        )
    )

    # ── verify (substring gate) ──────────────────────────────────────────
    t = _now()
    blocks_by_id = _index_blocks(normalized_blocks)
    gated_records: list[GallRecord] = []
    for record in claims_records:
        gated, record_warnings = _gate_record(record, blocks_by_id)
        gated_records.append(gated)
        warnings.extend(record_warnings)
        (candidates_dir / record.candidate_id / "gated_facts.json").write_text(
            gated.model_dump_json(indent=2)
        )
    stage_records.append(StageRunRecord(name="verify", started_at=t, completed_at=_now()))

    # ── verify-claims (per cell, LLM verifier) ───────────────────────────
    vc_cfg = stages_cfg["verify-claims"]
    vc_prompt, vc_sha = _load_prompt(vc_cfg["prompt"])
    vc_workers = vc_cfg.get("max_workers", 8)
    vc_total_timeout = float(vc_cfg.get("total_timeout_s", default_total_timeout))
    vc_semaphore = asyncio.Semaphore(vc_workers)

    # Cache key spans the full input set: prompt, model, and a hash of all
    # gated records (the verifier's input). If any record's pre-verifier
    # state changes, the SHA changes and the cache invalidates wholesale.
    # Cache is keyed at the stage level (one sidecar) but checks per-record
    # artifacts existence — so it's robust to partial output deletion.
    vc_input_sha = _sha_str("\n".join(r.model_dump_json() for r in gated_records))
    vc_cache_key = {
        "stage": "verify-claims",
        "prompt_sha256": vc_sha,
        "model": vc_cfg["model"],
        "input_sha": vc_input_sha,
    }
    # No single artifact for verify-claims (output is per-record). Use a
    # standalone sidecar file at the source-dir level.
    vc_sidecar = src_dir / "verify-claims.stage-cache.json"
    vc_per_record_paths = [
        candidates_dir / r.candidate_id / "verified_facts.json" for r in gated_records
    ]
    vc_cache_hit = False
    if vc_sidecar.exists() and all(p.exists() for p in vc_per_record_paths):
        try:
            prior = json.loads(vc_sidecar.read_text())
            vc_cache_hit = all(prior.get(k) == v for k, v in vc_cache_key.items())
        except (OSError, json.JSONDecodeError):
            vc_cache_hit = False

    t = _now()
    if vc_cache_hit:
        verified_records = [
            GallRecord.model_validate_json(p.read_text()) for p in vc_per_record_paths
        ]
        stage_records.append(
            StageRunRecord(
                name="verify-claims",
                started_at=t,
                completed_at=_now(),
                calls=[],
                notes="cached",
            )
        )
    else:
        verified_records, vc_calls, vc_warnings = await _verify_records_claims(
            gated_records,
            blocks_by_id,
            vc_cfg["model"],
            vc_prompt,
            vc_sha,
            vc_semaphore,
            total_timeout=vc_total_timeout,
        )
        warnings.extend(vc_warnings)
        for r in verified_records:
            (candidates_dir / r.candidate_id / "verified_facts.json").write_text(
                r.model_dump_json(indent=2)
            )
        vc_sidecar.write_text(json.dumps(vc_cache_key, indent=2, sort_keys=True))
        stage_records.append(
            StageRunRecord(
                name="verify-claims",
                started_at=t,
                completed_at=_now(),
                calls=vc_calls,
            )
        )

    # ── taxonomy-lookup ──────────────────────────────────────────────────
    tax_cfg = stages_cfg.get("taxonomy-lookup", {})
    cache_dir = Path(tax_cfg.get("cache_dir", str(src_dir / "cache" / "gbif")))
    t = _now()
    verified_records = await _enrich_records_with_taxonomy(
        verified_records,
        cache_dir=cache_dir,
        max_workers=tax_cfg.get("max_workers", 8),
    )
    stage_records.append(StageRunRecord(name="taxonomy-lookup", started_at=t, completed_at=_now()))

    # ── assemble-review ──────────────────────────────────────────────────
    completed_at = _now()
    flat_text = flat_normalized_text(normalized_blocks)
    pdf_filename = Path(input_path).name if Path(input_path).is_file() else str(source_id)
    pdf_page_count = max((b.page for b in raw_blocks), default=1)

    manifest, claims, verified, review = assemble(
        pipeline_name=pipeline["name"],
        pipeline_version=str(pipeline.get("version", "0.1.0")),
        pipeline_config_name=pipeline["name"],
        seed=int(pipeline.get("seed", 42)),
        started_at=started_at,
        completed_at=completed_at,
        pdf_sha256=pdf_sha,
        pdf_filename=pdf_filename,
        pdf_page_count=pdf_page_count,
        source_text_sha256=_text_sha(flat_text),
        normalized_blocks=normalized_blocks,
        document_metadata=document_metadata,
        claims_records=claims_records,
        verified_records=verified_records,
        stages=stage_records,
        warnings=warnings,
    )
    (src_dir / "claims.json").write_text(claims.model_dump_json(indent=2))
    (src_dir / "verified_claims.json").write_text(verified.model_dump_json(indent=2))
    (src_dir / "review_artifact.json").write_text(review.model_dump_json(indent=2))
    (src_dir / "manifest.json").write_text(manifest.model_dump_json(indent=2))

    # Ensure source.pdf is bundleable (the bundle stage requires it).
    bundle_pdf = src_dir / "source.pdf"
    if not bundle_pdf.exists():
        if Path(input_path).is_file() and Path(input_path).suffix.lower() == ".pdf":
            bundle_pdf.write_bytes(Path(input_path).read_bytes())
        else:
            bundle_pdf.write_bytes(b"%PDF-1.4\n%not-a-pdf-stub\n")

    # ── bundle ───────────────────────────────────────────────────────────
    bundle_cfg = stages_cfg.get("bundle", {})
    bundle_path = src_dir / bundle_cfg.get("output", "bundle.tar.gz")
    write_bundle(
        src_dir,
        bundle_path,
        include_candidates=bool(bundle_cfg.get("include_candidates", False)),
        verify_complete=bool(bundle_cfg.get("verify_complete", True)),
    )
    return bundle_path


# ─── Helpers: record-level verify + taxonomy walking ──────────────────────


def _gate_record(record: GallRecord, blocks_by_id: dict) -> tuple[GallRecord, list[WarningEntry]]:
    """Walk every cell in a record, run the substring gate, accumulate warnings."""
    warnings: list[WarningEntry] = []
    field_path_base = f"records[{record.record_id}]"

    def _gate(cell, path: str):
        if cell is None or not cell.evidence:
            return cell, []
        return gate_cell(cell, blocks_by_id, field_path=path, record_id=record.record_id)

    gm = record.gall_maker
    new_scientific_name, w1 = _gate(
        gm.scientific_name, f"{field_path_base}.gall_maker.scientific_name"
    )
    warnings.extend(w1)
    new_authority, w2 = _gate(gm.authority, f"{field_path_base}.gall_maker.authority")
    warnings.extend(w2)
    new_rank, w3 = _gate(gm.rank, f"{field_path_base}.gall_maker.rank")
    warnings.extend(w3)
    new_gm = gm.model_copy(
        update={
            "scientific_name": new_scientific_name,
            "authority": new_authority,
            "rank": new_rank,
        }
    )

    new_hosts = []
    for i, h in enumerate(record.hosts):
        h_name, w = _gate(h.scientific_name, f"{field_path_base}.hosts[{i}].scientific_name")
        warnings.extend(w)
        new_hosts.append(h.model_copy(update={"scientific_name": h_name}))

    new_traits_update = {}
    for field_name in (
        "color",
        "shape",
        "texture",
        "walls",
        "cells",
        "alignment",
        "plant_part",
        "form",
        "season",
    ):
        cell = getattr(record.gall_traits, field_name)
        new_cell, w = _gate(cell, f"{field_path_base}.gall_traits.{field_name}")
        if cell is not None:
            new_traits_update[field_name] = new_cell
        warnings.extend(w)
    if record.gall_traits.detachable is not None:
        new_det, w = _gate(
            record.gall_traits.detachable, f"{field_path_base}.gall_traits.detachable"
        )
        new_traits_update["detachable"] = new_det
        warnings.extend(w)
    new_traits = record.gall_traits.model_copy(update=new_traits_update)

    new_desc, w = _gate(record.description, f"{field_path_base}.description")
    warnings.extend(w)
    new_loc, w = _gate(record.location, f"{field_path_base}.location")
    warnings.extend(w)

    return (
        record.model_copy(
            update={
                "gall_maker": new_gm,
                "hosts": new_hosts,
                "gall_traits": new_traits,
                "description": new_desc,
                "location": new_loc,
                "warnings": record.warnings + warnings,
            }
        ),
        warnings,
    )


_TRAIT_FIELDS: tuple[str, ...] = (
    "color",
    "shape",
    "texture",
    "walls",
    "cells",
    "alignment",
    "plant_part",
    "form",
    "season",
)


async def _verify_records_claims(
    records: list[GallRecord],
    blocks_by_id: dict,
    model: str,
    prompt: str,
    prompt_sha: str,
    semaphore: asyncio.Semaphore,
    *,
    total_timeout: float = 300.0,
) -> tuple[list[GallRecord], list[ProviderCallRecord], list[WarningEntry]]:
    """Run verify_cell on every cell across all records, in parallel.

    Concurrency model: every verifiable cell across every record is
    submitted to a single ``asyncio.gather``. The shared semaphore caps
    in-flight LLM calls at ``max_workers`` (configured per-stage in the
    pipeline YAML); the rest queue. Per-record assembly happens after
    all calls complete.

    Returns ``(verified_records, calls, warnings)``. Warnings are
    synthesized for any cell whose verifier call failed (status='error');
    the cell falls back to its pre-verifier support_status.
    """

    async def _verify(cell, path, record_summary):
        if cell is None or not cell.evidence:
            return cell, None
        async with semaphore:
            updated, call = await verify_cell(
                cell,
                path,
                blocks_by_id,
                model=model,
                prompt=prompt,
                prompt_sha256=prompt_sha,
                total_timeout=total_timeout,
                record_summary=record_summary,
            )
        return updated, call

    # Build a flat list of verification jobs across all records. Each job
    # carries the (record_idx, location_key, field_path, cell, record_summary)
    # tuple so results can be re-assembled into per-record GallRecord copies
    # after the global gather completes. record_summary gives the verifier
    # the candidate species context — without it, host/trait claims can't
    # be attributed to a specific species.
    jobs: list[tuple[int, str, str, Any, str]] = []
    for r_idx, record in enumerate(records):
        path_base = f"records[{record.record_id}]"
        gm = record.gall_maker
        species_name = gm.scientific_name.value or "(unidentified)"
        record_summary = f"candidate species: {species_name}"
        jobs.append(
            (
                r_idx,
                "gm_sci",
                f"{path_base}.gall_maker.scientific_name",
                gm.scientific_name,
                record_summary,
            )
        )
        jobs.append(
            (r_idx, "gm_auth", f"{path_base}.gall_maker.authority", gm.authority, record_summary)
        )
        jobs.append((r_idx, "gm_rank", f"{path_base}.gall_maker.rank", gm.rank, record_summary))
        for h_idx, h in enumerate(record.hosts):
            jobs.append(
                (
                    r_idx,
                    f"host_{h_idx}",
                    f"{path_base}.hosts[{h_idx}].scientific_name",
                    h.scientific_name,
                    record_summary,
                )
            )
        for fname in _TRAIT_FIELDS:
            jobs.append(
                (
                    r_idx,
                    f"trait_{fname}",
                    f"{path_base}.gall_traits.{fname}",
                    getattr(record.gall_traits, fname),
                    record_summary,
                )
            )
        if record.gall_traits.detachable is not None:
            jobs.append(
                (
                    r_idx,
                    "trait_detachable",
                    f"{path_base}.gall_traits.detachable",
                    record.gall_traits.detachable,
                    record_summary,
                )
            )
        jobs.append(
            (r_idx, "description", f"{path_base}.description", record.description, record_summary)
        )
        jobs.append((r_idx, "location", f"{path_base}.location", record.location, record_summary))

    # Run the whole batch concurrently. Semaphore enforces the in-flight
    # cap; everything else queues.
    results = await asyncio.gather(
        *[_verify(cell, path, summary) for _, _, path, cell, summary in jobs]
    )

    # Track calls + warnings in job order (preserves the per-record
    # ordering callers/manifest readers expect).
    all_calls: list[ProviderCallRecord] = []
    all_warnings: list[WarningEntry] = []
    for (r_idx, _, path, _, _), (_, call) in zip(jobs, results, strict=True):
        if call is None:
            continue
        all_calls.append(call)
        w = _warning_for_error_call(
            call,
            stage="verify-claims",
            record_id=records[r_idx].record_id,
            field_path=path,
        )
        if w:
            all_warnings.append(w)

    # Build (record_idx, location_key) -> updated_cell map.
    by_loc: dict[tuple[int, str], Any] = {
        (r_idx, key): updated
        for (r_idx, key, _, _, _), (updated, _) in zip(jobs, results, strict=True)
    }

    # Re-assemble each record from the verified cells.
    out_records: list[GallRecord] = []
    for r_idx, record in enumerate(records):
        new_gm = record.gall_maker.model_copy(
            update={
                "scientific_name": by_loc[(r_idx, "gm_sci")],
                "authority": by_loc[(r_idx, "gm_auth")],
                "rank": by_loc[(r_idx, "gm_rank")],
            }
        )
        new_hosts = [
            h.model_copy(update={"scientific_name": by_loc[(r_idx, f"host_{h_idx}")]})
            for h_idx, h in enumerate(record.hosts)
        ]
        traits_update: dict[str, Any] = {}
        for fname in _TRAIT_FIELDS:
            if getattr(record.gall_traits, fname) is not None:
                traits_update[fname] = by_loc[(r_idx, f"trait_{fname}")]
        if record.gall_traits.detachable is not None:
            traits_update["detachable"] = by_loc[(r_idx, "trait_detachable")]
        new_traits = record.gall_traits.model_copy(update=traits_update)

        out_records.append(
            record.model_copy(
                update={
                    "gall_maker": new_gm,
                    "hosts": new_hosts,
                    "gall_traits": new_traits,
                    "description": by_loc[(r_idx, "description")],
                    "location": by_loc[(r_idx, "location")],
                }
            )
        )

    return out_records, all_calls, all_warnings


async def _enrich_records_with_taxonomy(
    records: list[GallRecord],
    cache_dir: Path,
    max_workers: int = 8,
) -> list[GallRecord]:
    """Append GBIF TaxonomyLookup to every scientific-name cell in every record."""
    cells_with_kingdoms: list[tuple] = []
    locations: list[tuple] = []  # (record_idx, "gall_maker" | (("host", host_idx)))

    for r_idx, record in enumerate(records):
        cells_with_kingdoms.append((record.gall_maker.scientific_name, "Animalia"))
        locations.append((r_idx, "gall_maker"))
        for h_idx, host in enumerate(record.hosts):
            cells_with_kingdoms.append((host.scientific_name, "Plantae"))
            locations.append((r_idx, ("host", h_idx)))

    if not cells_with_kingdoms:
        return records

    enriched_cells = await enrich_cells_concurrently(
        cells_with_kingdoms,
        cache_dir=cache_dir,
        max_workers=max_workers,
    )

    out_records = [r.model_copy() for r in records]
    for cell, loc in zip(enriched_cells, locations, strict=True):
        r_idx, where = loc
        record = out_records[r_idx]
        if where == "gall_maker":
            new_gm = record.gall_maker.model_copy(update={"scientific_name": cell})
            out_records[r_idx] = record.model_copy(update={"gall_maker": new_gm})
        else:
            _, h_idx = where
            new_hosts = list(record.hosts)
            new_hosts[h_idx] = new_hosts[h_idx].model_copy(update={"scientific_name": cell})
            out_records[r_idx] = record.model_copy(update={"hosts": new_hosts})

    return out_records
