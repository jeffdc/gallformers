"""OCR for scans, outside Docling.

Docling's own tesseract step runs orientation detection on every page and
rotates on any non-zero answer, with no confidence threshold; on 19th-century
typefaces that flips about a fifth of the (upright) pages. So OCR happens here,
with OCRmyPDF and no page rotation, and Docling reads the result with its OCR off.

For a scan that already carries a text layer (e.g. from BHL), fresh OCR is kept
only when it measures clearly better: neither always wins (1862 Source: fresh
better; 1896 Source: a tie).
"""

import re
import shutil
import subprocess
from functools import cache
from pathlib import Path

from producer.quality import nonspace, suspicious_rate

WORD_LIST = Path("/usr/share/dict/words")
TOKEN = re.compile(r"[A-Za-z]+")
MIN_GAIN = 0.01  # fresh OCR must beat the layer by this much (dictionary rate)
MIN_KEPT = 0.95  # and keep at least this share of the layer's non-space characters


@cache
def words() -> frozenset[str]:
    if not WORD_LIST.exists():
        return frozenset()
    return frozenset(w.strip().lower() for w in WORD_LIST.read_text().splitlines())


def dictionary_rate(text: str) -> float | None:
    """Share of lower-case words of 4+ letters found in the word list (singular forms count).

    Lower-case only, so Latin names and abbreviations don't count against a text.
    None when no word list is available or the text has no such words.
    """
    vocabulary = words()
    candidates = [w for w in TOKEN.findall(text) if len(w) >= 4 and w.islower()]
    if not vocabulary or not candidates:
        return None
    hits = sum(w in vocabulary or (w.endswith("s") and w[:-1] in vocabulary) for w in candidates)
    return round(hits / len(candidates), 3)


def measure(pdf: Path) -> dict:
    import pymupdf

    with pymupdf.open(pdf) as doc:
        text = "\n".join(page.get_text() for page in doc)
    return {
        "nonspace": nonspace(text),
        "dictionary_rate": dictionary_rate(text),
        "suspicious_rate": round(suspicious_rate(text), 4),
    }


def choose(layer: dict, fresh: dict) -> dict:
    """Which text to keep: the scan's existing layer or fresh OCR."""
    if not layer["nonspace"] or layer["dictionary_rate"] is None:
        return {"use": "fresh", "reason": "the PDF has no usable text layer"}
    if fresh["nonspace"] < MIN_KEPT * layer["nonspace"]:
        return {"use": "layer", "reason": "fresh OCR recovers less text than the existing layer"}
    if (
        fresh["dictionary_rate"] is not None
        and fresh["dictionary_rate"] >= layer["dictionary_rate"] + MIN_GAIN
    ):
        return {"use": "fresh", "reason": "fresh OCR reads clearly better"}
    return {"use": "layer", "reason": "fresh OCR is not clearly better"}


def reocr(pdf: Path, out: Path) -> Path:
    """Rasterize each page and OCR all of it with tesseract. Pages are never rotated.

    Not --redo-ocr: it keeps any text it thinks is visible and blanks those words
    out of the image before OCR. Some BHL scans draw their old OCR as ordinary text
    under the page image, so redo kept the old text and read only letter fragments.
    """
    if shutil.which("tesseract") is None:
        raise RuntimeError("tesseract is not installed")
    subprocess.run(
        [
            "ocrmypdf",
            "--force-ocr",  # page images are re-rendered; any old text layer is dropped
            "--output-type", "pdf",  # minimal changes, no Ghostscript
            "--optimize", "0",
            "-l", "eng",
            "--quiet",
            str(pdf),
            str(out),
        ],
        check=True,
        capture_output=True,
        text=True,
    )  # fmt: skip
    return out
