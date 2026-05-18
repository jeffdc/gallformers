"""Optional OCR stage for scanned PDFs.

Sits between ``extract`` and ``preprocess``. Decides whether the document
needs OCR based on text density of the first-pass pymupdf extraction; if
so, runs ``ocrmypdf`` on the whole document and replaces the block list
with text extracted from the OCR'd PDF.

Vision-LLM OCR (e.g. olmOCR via DeepInfra) is intentionally not used here
— see matter 4fef for the design rationale.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from ingest.extract import _extract_pdf_blocks
from ingest.schemas import RawTextBlock


@dataclass
class OcrResult:
    """What the OCR stage decided and did. Consumed by the pipeline runner
    to build a ``StageRunRecord`` for the manifest."""

    triggered: bool
    reason: str
    ocr_pdf_path: Path | None
    ocrmypdf_version: str | None


def should_ocr(
    blocks: list[RawTextBlock],
    *,
    enabled: str = "auto",
    min_chars_per_page: float = 100.0,
) -> tuple[bool, str]:
    """Decide whether to run OCR on this document.

    Returns ``(decision, reason)``. The reason is human-readable and shows
    up in the manifest's ``StageRunRecord.notes`` so an audit reader can
    see why OCR did or didn't run on any given paper.
    """
    if enabled == "never":
        return False, "disabled"
    if enabled == "always":
        return True, "always"
    if enabled != "auto":
        raise ValueError(f"Invalid enabled value: {enabled!r}; expected one of auto|always|never")
    density = avg_chars_per_page(blocks)
    if density < min_chars_per_page:
        return True, f"auto: {density:.1f} chars/page < {min_chars_per_page:.1f}"
    return False, f"auto: {density:.1f} chars/page >= {min_chars_per_page:.1f}"


def avg_chars_per_page(blocks: list[RawTextBlock]) -> float:
    """Average character count per page across all blocks.

    Used by the auto-detect trigger to decide whether a document looks like
    a scan. Empty input returns 0.0 (which will trigger OCR under any
    positive threshold).
    """
    if not blocks:
        return 0.0
    pages = {b.page for b in blocks}
    total_chars = sum(len(b.text) for b in blocks)
    return total_chars / len(pages)


def maybe_ocr(
    input_path: str,
    raw_blocks: list[RawTextBlock],
    output_dir: Path,
    *,
    enabled: str = "auto",
    min_chars_per_page: float = 100.0,
    language: str = "eng",
    force_ocr: bool = False,
) -> tuple[list[RawTextBlock], OcrResult]:
    """Optionally OCR the input PDF and replace the block list.

    Non-PDF inputs are always passed through unchanged. For PDFs, the
    decision is delegated to ``should_ocr``. When OCR fires, the output
    PDF is cached at ``<output_dir>/source.ocr.pdf`` keyed on the input
    PDF's SHA-256 + ocrmypdf config; repeat runs reuse the cached PDF.
    """
    no_op = OcrResult(triggered=False, reason="not-pdf", ocr_pdf_path=None, ocrmypdf_version=None)

    if not input_path.lower().endswith(".pdf"):
        return raw_blocks, no_op

    decision, reason = should_ocr(
        raw_blocks, enabled=enabled, min_chars_per_page=min_chars_per_page
    )
    if not decision:
        return raw_blocks, OcrResult(
            triggered=False, reason=reason, ocr_pdf_path=None, ocrmypdf_version=None
        )

    input_pdf = Path(input_path)
    ocr_pdf = output_dir / "source.ocr.pdf"
    cache_key = {
        "pdf_sha256": _sha256_file(input_pdf),
        "ocrmypdf_version": _ocrmypdf_version(),
        "language": language,
        "force_ocr": force_ocr,
    }

    if _is_cache_valid(ocr_pdf, cache_key):
        new_blocks = _extract_pdf_blocks(str(ocr_pdf))
        return new_blocks, OcrResult(
            triggered=True,
            reason=f"{reason}; cache hit",
            ocr_pdf_path=ocr_pdf,
            ocrmypdf_version=cache_key["ocrmypdf_version"],
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    _run_ocrmypdf(input_pdf, ocr_pdf, language=language, force_ocr=force_ocr)
    _write_cache_sidecar(ocr_pdf, cache_key)
    new_blocks = _extract_pdf_blocks(str(ocr_pdf))
    return new_blocks, OcrResult(
        triggered=True,
        reason=reason,
        ocr_pdf_path=ocr_pdf,
        ocrmypdf_version=cache_key["ocrmypdf_version"],
    )


# ─── Internals ────────────────────────────────────────────────────────────


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _cache_sidecar_path(artifact: Path) -> Path:
    return artifact.with_suffix(artifact.suffix + ".cache.json")


def _is_cache_valid(artifact: Path, current_key: dict) -> bool:
    sidecar = _cache_sidecar_path(artifact)
    if not artifact.exists() or not sidecar.exists():
        return False
    try:
        prior = json.loads(sidecar.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    return all(prior.get(k) == v for k, v in current_key.items())


def _write_cache_sidecar(artifact: Path, key: dict) -> None:
    _cache_sidecar_path(artifact).write_text(json.dumps(key, indent=2, sort_keys=True))


def _ocrmypdf_version() -> str:
    """Look up the installed ocrmypdf version. Raises if the binary isn't installed."""
    binary = shutil.which("ocrmypdf")
    if binary is None:
        raise RuntimeError(
            "ocrmypdf binary not found on PATH. Install via 'brew install ocrmypdf'."
        )
    result = subprocess.run([binary, "--version"], capture_output=True, text=True, check=True)
    return f"ocrmypdf-{result.stdout.strip()}"


def _run_ocrmypdf(input_pdf: Path, output_pdf: Path, *, language: str, force_ocr: bool) -> None:
    """Invoke ocrmypdf on the input PDF, writing a text-layered copy to output_pdf.

    ``force_ocr=True`` re-OCRs even pages that already have a text layer;
    leave it ``False`` to let ocrmypdf skip pages that already have text.
    """
    cmd = [
        "ocrmypdf",
        "--language",
        language,
    ]
    if force_ocr:
        cmd.append("--force-ocr")
    else:
        cmd.append("--skip-text")
    cmd.extend([str(input_pdf), str(output_pdf)])
    # No --quiet: ocrmypdf's per-page progress streams to stderr so users
    # see something happening during the slow OCR pass.
    subprocess.run(cmd, check=True)
