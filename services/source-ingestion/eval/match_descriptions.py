"""Eval-set label generator.

For each (PDF, source_id) in the mapping, pull every (species, description)
row from gallformers_dev where the description is non-trivial, and
substring-match each description block against the PDF text.

Reports per-source coverage tiers:
  Tier A — >=95% of blocks (by char weight) match
  Tier B — 70-95% match
  Tier C — <70% match (likely a format the matcher doesn't handle)

Outputs:
  - eval/output/labels/<source_id>.json   per-source labels
  - eval/output/coverage_report.md        markdown summary
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

import psycopg
from rapidfuzz import fuzz

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))
from pdf_source_map import PDF_DIR, PDF_SOURCE_MAP

from ingest.extract import extract_blocks
from ingest.ocr import maybe_ocr
from ingest.preprocess import (
    rejoin_hyphenated,
    rejoin_lines,
    strip_bhl_boilerplate,
    strip_page_headers,
    strip_plate_pages,
)

EVAL_DIR = Path(__file__).parent
OUT_DIR = EVAL_DIR / "output"
LABELS_DIR = OUT_DIR / "labels"
LABELS_DIR.mkdir(parents=True, exist_ok=True)

# Coverage thresholds for tier classification (per (species,source) entry).
TIER_A_MIN = 0.95
TIER_B_MIN = 0.70

# Block-level match confidence thresholds.
EXACT_MIN = 1.00  # block found as exact substring after normalization
FUZZY_MIN = 90.0  # rapidfuzz partial_ratio threshold for fuzzy match


# ── Normalization ────────────────────────────────────────────────────


_WS_RE = re.compile(r"\s+")
_PUNCT_RE = re.compile(r"[‐-―]")  # unicode hyphens/dashes -> regular
_HYPHEN_LINEBREAK_RE = re.compile(r"(\w)-\s*\n+\s*([a-z])")


def normalize(text: str) -> str:
    """Whitespace + unicode normalization for substring matching.

    - Rejoin line-break-hyphenated words ("devel-\\noping" -> "developing").
    - NFKD decomposition (handles ligatures like "ﬁ" -> "fi").
    - Strip combining marks (accents): "Volcán" -> "Volcan".
    - Normalize unicode dashes and smart quotes.
    - Collapse all whitespace runs to single space.
    """
    text = _HYPHEN_LINEBREAK_RE.sub(r"\1\2", text)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = _PUNCT_RE.sub("-", text)
    text = text.replace("'", "'").replace(""", '"').replace(""", '"')
    text = _WS_RE.sub(" ", text)
    return text.strip()


_CURATOR_BRACKET_RE = re.compile(r"^\s*\[.*\]\s*$", re.DOTALL)
_INLINE_BRACKET_RE = re.compile(r"\[[^\[\]]*\]")


def strip_inline_brackets(text: str) -> str:
    """Remove inline curator annotations like '[Acer saccharum]' or
    '[sic--mistaken in later literature]' from a block. The bracketed
    spans are not in the source PDF — they're curator interjections —
    so leaving them in breaks substring matching.

    Repeats until stable to handle blocks with many bracketed bits.
    """
    prev = None
    while prev != text:
        prev = text
        text = _INLINE_BRACKET_RE.sub("", text)
    return text


def split_description_blocks(description: str) -> list[str]:
    """Split a curator description into substring-matchable blocks.

    Splits on blank lines, drops blocks that are wholly enclosed in
    [...] (curator annotations like '[Photo captions]' or
    '[Undescribed species tentatively assigned to ...]').

    Returns the original-text blocks (un-normalized) so callers can
    record provenance; normalize at match time.
    """
    raw_blocks = re.split(r"\n\s*\n+", description.strip())
    out = []
    for blk in raw_blocks:
        blk = blk.strip()
        if not blk:
            continue
        if _CURATOR_BRACKET_RE.match(blk):
            continue
        out.append(blk)
    return out


# ── Matching ─────────────────────────────────────────────────────────


@dataclass
class BlockMatch:
    block_text: str
    block_chars: int
    match_kind: str  # "exact" | "fuzzy" | "miss"
    score: float
    match_index: int  # char offset into PDF text, or -1 for fuzzy/miss


def match_block(block: str, pdf_text_norm: str) -> BlockMatch:
    block_for_match = strip_inline_brackets(block)
    block_norm = normalize(block_for_match)
    if not block_norm:
        # Block was entirely curator annotation — count as matched
        # (no source content to verify against).
        return BlockMatch(block, 0, "exact", 100.0, -1)

    # Exact whole-block substring match wins
    idx = pdf_text_norm.find(block_norm)
    if idx >= 0:
        return BlockMatch(block, len(block_norm), "exact", 100.0, idx)

    # Line-level fallback for multi-line blocks (Felt key-style: each
    # line is verbatim from a different part of the source, scattered).
    # Each line >= 20 chars must substring-match. Aggregate matched chars.
    lines = [ln.strip() for ln in block_for_match.splitlines() if ln.strip()]
    if len(lines) > 1:
        matched_chars = 0
        total_chars = 0
        for ln in lines:
            ln_norm = normalize(ln)
            if not ln_norm:
                continue
            total_chars += len(ln_norm)
            if len(ln_norm) >= 20 and ln_norm in pdf_text_norm:
                matched_chars += len(ln_norm)
            elif len(ln_norm) < 20:
                # Short lines (host names, fragments): match but don't
                # claim credit either way to avoid trivial false positives.
                total_chars -= len(ln_norm)
        if total_chars > 0:
            line_coverage = matched_chars / total_chars
            if line_coverage >= 0.70:
                return BlockMatch(block, len(block_norm), "fuzzy", line_coverage * 100, -1)

    # Whole-block fuzzy fallback
    score = fuzz.partial_ratio(block_norm, pdf_text_norm)
    if score >= FUZZY_MIN:
        return BlockMatch(block, len(block_norm), "fuzzy", score, -1)
    return BlockMatch(block, len(block_norm), "miss", score, -1)


@dataclass
class DescriptionResult:
    species_id: int
    species_name: str
    description_len: int
    blocks: list[BlockMatch] = field(default_factory=list)

    @property
    def coverage(self) -> float:
        total = sum(b.block_chars for b in self.blocks)
        if total == 0:
            return 0.0
        matched = sum(b.block_chars for b in self.blocks if b.match_kind in ("exact", "fuzzy"))
        return matched / total

    @property
    def tier(self) -> str:
        c = self.coverage
        if c >= TIER_A_MIN:
            return "A"
        if c >= TIER_B_MIN:
            return "B"
        return "C"


@dataclass
class SourceResult:
    source_id: int
    label: str
    pdf_path: Path
    species: list[DescriptionResult] = field(default_factory=list)
    pdf_chars: int = 0
    error: str | None = None

    @property
    def tier_counts(self) -> dict[str, int]:
        out = {"A": 0, "B": 0, "C": 0}
        for s in self.species:
            out[s.tier] += 1
        return out

    @property
    def avg_coverage(self) -> float:
        if not self.species:
            return 0.0
        return sum(s.coverage for s in self.species) / len(self.species)


# ── DB + PDF I/O ─────────────────────────────────────────────────────


def fetch_species_descriptions(source_id: int) -> list[tuple[int, str, str]]:
    """Return (species_id, species_name, description) for non-trivial descriptions."""
    with psycopg.connect("dbname=gallformers_dev") as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT ss.species_id, sp.name, ss.description
            FROM species_source ss
            JOIN species sp ON sp.id = ss.species_id
            WHERE ss.source_id = %s
              AND length(ss.description) >= 200
            ORDER BY ss.species_id
            """,
            (source_id,),
        )
        return list(cur.fetchall())


OCR_CACHE_DIR = OUT_DIR / "ocr_cache"
OCR_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def extract_pdf_text(pdf_path: Path) -> str:
    """Extract PDF text and apply the same preprocess heuristics the
    real ingestion pipeline uses, so the eval measures what the pipeline
    will actually see.

    Routes through ``maybe_ocr`` so image-only/low-density PDFs get OCR'd
    before extraction — matching the pipeline's behavior. OCR output is
    cached under ``eval/output/ocr_cache/<pdf-stem>/`` so re-runs are fast.
    """
    raw_blocks = extract_blocks(str(pdf_path))
    cache_subdir = OCR_CACHE_DIR / pdf_path.stem
    cache_subdir.mkdir(parents=True, exist_ok=True)
    raw_blocks, _ = maybe_ocr(str(pdf_path), raw_blocks, cache_subdir)
    text = "\n".join(b.text for b in raw_blocks)
    text = strip_bhl_boilerplate(text)
    text = strip_plate_pages(text)
    text = strip_page_headers(text)
    text = rejoin_hyphenated(text)
    text = rejoin_lines(text)
    return normalize(text)


# ── Orchestration ────────────────────────────────────────────────────


def process_source(pdf_filename: str, source_id: int, label: str) -> SourceResult:
    pdf_path = PDF_DIR / pdf_filename
    result = SourceResult(source_id=source_id, label=label, pdf_path=pdf_path)
    if not pdf_path.exists():
        result.error = f"PDF not found at {pdf_path}"
        return result

    try:
        pdf_text_norm = extract_pdf_text(pdf_path)
        result.pdf_chars = len(pdf_text_norm)
    except Exception as exc:  # noqa: BLE001
        result.error = f"PDF extraction failed: {exc}"
        return result

    rows = fetch_species_descriptions(source_id)
    for species_id, species_name, description in rows:
        dr = DescriptionResult(
            species_id=species_id,
            species_name=species_name,
            description_len=len(description),
        )
        for block in split_description_blocks(description):
            dr.blocks.append(match_block(block, pdf_text_norm))
        result.species.append(dr)
    return result


def write_labels_json(result: SourceResult) -> None:
    out = {
        "source_id": result.source_id,
        "label": result.label,
        "pdf_filename": result.pdf_path.name,
        "pdf_chars": result.pdf_chars,
        "species_count": len(result.species),
        "tier_counts": result.tier_counts,
        "avg_coverage": round(result.avg_coverage, 4),
        "species": [
            {
                "species_id": s.species_id,
                "species_name": s.species_name,
                "description_len": s.description_len,
                "coverage": round(s.coverage, 4),
                "tier": s.tier,
                "blocks": [
                    {
                        "match_kind": b.match_kind,
                        "score": round(b.score, 1),
                        "block_chars": b.block_chars,
                        "block_text": b.block_text,
                    }
                    for b in s.blocks
                ],
            }
            for s in result.species
        ],
    }
    path = LABELS_DIR / f"{result.source_id}.json"
    path.write_text(json.dumps(out, indent=2, ensure_ascii=False))


def write_report(results: list[SourceResult]) -> None:
    lines = ["# Eval-set match coverage report", ""]
    lines.append("Per-source tier distribution and average coverage. "
                 "Tier A = >=95% of description blocks (by char weight) matched into source PDF, "
                 "B = 70-95%, C = <70%.")
    lines.append("")
    lines.append("| Source | n | Tier A | Tier B | Tier C | Avg cov | Notes |")
    lines.append("|---|---:|---:|---:|---:|---:|---|")
    total_a = total_b = total_c = 0
    for r in sorted(results, key=lambda x: -len(x.species)):
        if r.error:
            lines.append(f"| {r.label} | — | — | — | — | — | ⚠ {r.error} |")
            continue
        tc = r.tier_counts
        total_a += tc["A"]
        total_b += tc["B"]
        total_c += tc["C"]
        lines.append(
            f"| {r.label} | {len(r.species)} | {tc['A']} | {tc['B']} | {tc['C']} | "
            f"{r.avg_coverage*100:.1f}% | |"
        )
    grand = total_a + total_b + total_c
    lines.append("")
    lines.append(f"**Totals: {grand} labeled (species, source) pairs**")
    lines.append(f"- Tier A: {total_a} ({total_a/grand*100:.1f}%)")
    lines.append(f"- Tier B: {total_b} ({total_b/grand*100:.1f}%)")
    lines.append(f"- Tier C: {total_c} ({total_c/grand*100:.1f}%)")

    (OUT_DIR / "coverage_report.md").write_text("\n".join(lines))


def main() -> None:
    results = []
    for pdf_filename, source_id, label in PDF_SOURCE_MAP:
        print(f"Processing source {source_id}: {label} ...", flush=True)
        r = process_source(pdf_filename, source_id, label)
        if r.error:
            print(f"  ERROR: {r.error}", flush=True)
        else:
            tc = r.tier_counts
            print(f"  {len(r.species)} species | A={tc['A']} B={tc['B']} C={tc['C']} "
                  f"| avg cov {r.avg_coverage*100:.1f}%", flush=True)
            write_labels_json(r)
        results.append(r)

    write_report(results)
    print(f"\nReport written to {OUT_DIR / 'coverage_report.md'}")
    print(f"Labels written to {LABELS_DIR}/")


if __name__ == "__main__":
    main()
