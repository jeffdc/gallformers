"""Block-level text extraction from PDFs, URLs, and plain text files.

Produces ``RawTextBlock`` instances suitable for ``raw_text.jsonl``. Each PDF
text block on each page becomes one row, preserving page number, bounding
box, and per-block text. URLs and plain text files produce a single
synthesized block on page 1.

Block IDs follow ``p{page}-b{idx}`` with ``page`` 1-indexed and ``idx``
0-indexed within each page; the index resets at the start of each page so
IDs are stable across re-runs of the same input.
"""

from __future__ import annotations

from pathlib import Path

import pymupdf
import trafilatura

from ingest.schemas import Bbox, RawTextBlock


def extract_blocks(input_path: str) -> list[RawTextBlock]:
    """Extract source content as a list of ``RawTextBlock`` rows.

    Detection rules:
    - Paths ending in ``.pdf`` are treated as PDF files.
    - Paths starting with ``http://`` or ``https://`` are treated as URLs.
    - Everything else is read as a plain text file.

    Raises:
        FileNotFoundError: If a plain text file does not exist.
        RuntimeError: If URL fetch or extraction fails.
    """
    if input_path.lower().endswith(".pdf"):
        return _extract_pdf_blocks(input_path)
    elif input_path.startswith("http://") or input_path.startswith("https://"):
        return _extract_url_blocks(input_path)
    else:
        return _extract_plain_text_blocks(input_path)


def _extract_pdf_blocks(path: str) -> list[RawTextBlock]:
    """Use PyMuPDF block-level extraction to produce per-page blocks.

    Skips image blocks (``block_type != 0``) and empty blocks.
    """
    extractor = f"pymupdf-{pymupdf.__version__}"
    blocks: list[RawTextBlock] = []
    with pymupdf.open(path) as doc:
        for page_idx, page in enumerate(doc.pages()):
            page_num = page_idx + 1
            block_idx = 0
            for raw in page.get_text("blocks"):
                # Tuple shape: (x0, y0, x1, y1, text, block_no, block_type)
                x0, y0, x1, y1, text, _block_no, block_type = raw
                if block_type != 0:
                    continue
                text = text.strip()
                if not text:
                    continue
                blocks.append(
                    RawTextBlock(
                        block_id=f"p{page_num}-b{block_idx}",
                        page=page_num,
                        text=text,
                        bbox=Bbox(x0=x0, y0=y0, x1=x1, y1=y1),
                        extractor=extractor,
                        quality_signals={"char_count": len(text)},
                    )
                )
                block_idx += 1
    return blocks


def _extract_url_blocks(url: str) -> list[RawTextBlock]:
    """Synthesize a single page-1 block from URL extraction (no page structure)."""
    downloaded = trafilatura.fetch_url(url)
    if downloaded is None:
        raise RuntimeError(f"Failed to fetch URL: {url}")
    text = trafilatura.extract(downloaded, output_format="markdown")
    if text is None:
        raise RuntimeError(f"Failed to extract content from URL: {url}")

    return [
        RawTextBlock(
            block_id="p1-b0",
            page=1,
            text=text,
            bbox=None,
            extractor=f"trafilatura-{trafilatura.__version__}",
            quality_signals={"char_count": len(text), "source": "url", "url": url},
        )
    ]


def _extract_plain_text_blocks(path: str) -> list[RawTextBlock]:
    """Synthesize a single page-1 block from a plain text file (no page structure)."""
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")
    text = p.read_text()
    return [
        RawTextBlock(
            block_id="p1-b0",
            page=1,
            text=text,
            bbox=None,
            extractor="plain-text",
            quality_signals={"char_count": len(text), "source": "plain"},
        )
    ]
