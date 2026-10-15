"""Decide whether a PDF is born-digital, a scan, or images with no usable text.

Text extraction alone is not a signal: most digitized PDFs carry an OCR text
layer over page images. The signals are embedded subset fonts (authoring tools
embed them, e.g. "IPNDNG+Calibri") and pages covered by a single image.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Literal

Kind = Literal["born_digital", "scanned", "image_only"]

FULLPAGE_AREA = 0.5  # an image covering more than this share of the page
SCANNED_PAGE_SHARE = 0.5  # share of pages that must be full-page images
MIN_CHARS_PER_PAGE = 300  # below this on average, there is no usable text layer


@dataclass(frozen=True)
class PageStats:
    subset_fonts: frozenset[str]
    fullpage_image: bool
    chars: int


@dataclass(frozen=True)
class Classification:
    kind: Kind
    reason: str
    pages: int
    subset_fonts: int
    fullpage_image_pages: int
    chars_per_page: int


def classify(pages: list[PageStats]) -> Classification:
    n = len(pages)
    fonts = frozenset().union(*(p.subset_fonts for p in pages)) if pages else frozenset()
    fullpage = sum(p.fullpage_image for p in pages)
    chars_per_page = sum(p.chars for p in pages) // n if n else 0
    evidence = (
        f"{len(fonts)} subset fonts, {fullpage}/{n} full-page-image pages, "
        f"{chars_per_page} chars/page"
    )

    if chars_per_page < MIN_CHARS_PER_PAGE:
        kind: Kind = "image_only"
    elif not fonts and n and fullpage / n >= SCANNED_PAGE_SHARE:
        kind = "scanned"
    else:
        kind = "born_digital"

    return Classification(kind, evidence, n, len(fonts), fullpage, chars_per_page)


def page_stats(pdf: Path) -> list[PageStats]:
    import pymupdf

    stats = []
    with pymupdf.open(pdf) as doc:
        for page in doc:
            fonts = frozenset(
                f[3].split("+", 1)[1] for f in page.get_fonts(full=True) if "+" in f[3]
            )
            area = page.rect.width * page.rect.height
            fullpage = any(
                r.width * r.height > FULLPAGE_AREA * area
                for img in page.get_images(full=True)
                for r in page.get_image_rects(img[0])
            )
            stats.append(PageStats(fonts, fullpage, len(page.get_text())))
    return stats


def classify_pdf(pdf: Path) -> Classification:
    return classify(page_stats(pdf))
