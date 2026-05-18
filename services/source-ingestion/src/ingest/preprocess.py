"""Deterministic block-level text pre-processing.

Operates on ``RawTextBlock`` instances from extraction and produces
``NormalizedBlock`` instances suitable for ``normalized_text.jsonl``. The
five-step cleanup (BHL boilerplate strip, plate-page strip, page-header
strip, hyphen rejoin, line rejoin) runs per-block. Blocks that become
empty after cleanup are dropped; remaining blocks get sequential span IDs
and absolute character offsets into the flat normalized text — the
canonical substrate evidence offsets address.
"""

from __future__ import annotations

import re

from ingest.schemas import NormalizedBlock, RawTextBlock


def strip_bhl_boilerplate(text: str) -> str:
    """Remove BHL cover page boilerplate from the start of the document.

    Detects BHL documents by the biodiversitylibrary.org URL and strips
    everything up to and including "This page intentionally left blank."
    """
    # Check if this looks like a BHL document
    if "biodiversitylibrary.org" not in text[:500]:
        return text

    # Find the end of BHL boilerplate. Common markers:
    # - "This page intentionally left blank."
    # - "Generated <date>" line
    markers = [
        "This page intentionally left blank.",
        "This page intentionally left blank",
    ]

    cut_point = 0
    for marker in markers:
        idx = text.find(marker)
        if idx >= 0:
            # Cut after the marker and any following whitespace
            cut_point = idx + len(marker)
            break

    if cut_point == 0:
        # No blank page marker — try cutting after "Generated ... PM/AM" line
        gen_match = re.search(r"Generated .+(?:PM|AM)\b.*?\n", text)
        if gen_match:
            cut_point = gen_match.end()

    if cut_point == 0:
        return text

    return text[cut_point:].lstrip("\n")


def rejoin_lines(text: str) -> str:
    """Rejoin lines that were broken by OCR/PDF extraction.

    BHL PDFs often produce one of two patterns:
    1. Single newlines mid-sentence: "word\\nword"
    2. Blank-line-separated lines that are actually one paragraph:
       "sentence start,\\n\\ncontinuation"

    Preserves real paragraph breaks and headings.
    """
    # Split into blocks separated by 2+ blank lines
    blocks = re.split(r"\n{2,}", text)

    merged: list[str] = []
    i = 0
    while i < len(blocks):
        block = blocks[i].strip()
        if not block:
            i += 1
            continue

        # If this block looks like a heading or special line, keep it separate
        if _is_heading_or_special(block):
            merged.append(block)
            i += 1
            continue

        # Collect continuation blocks — lines that look like mid-sentence
        # continuations of the previous block
        parts = [block]
        while i + 1 < len(blocks):
            next_block = blocks[i + 1].strip()
            if not next_block:
                i += 1
                continue
            if _is_continuation(parts[-1], next_block):
                parts.append(next_block)
                i += 1
            else:
                break

        # Join the parts with spaces (they were mid-sentence breaks)
        joined = " ".join(parts)
        # Also rejoin any single newlines within each block
        joined = re.sub(r"(?<!\n)\n(?!\n)", " ", joined)
        merged.append(joined)
        i += 1

    return "\n\n".join(merged)


def _is_heading_or_special(line: str) -> bool:
    """Check if a line is a heading, all-caps title, or special marker."""
    stripped = line.strip()
    if stripped.startswith("#"):
        return True
    # All-caps short lines are likely headings
    if stripped.isupper() and len(stripped) < 100:
        return True
    # Lines that are just numbers (page numbers that weren't caught)
    return stripped.isdigit()


def _is_continuation(prev: str, current: str) -> bool:
    """Heuristic: does `current` look like a continuation of `prev`?

    A line is a continuation if the previous line doesn't end with sentence-
    ending punctuation and the current line starts with a lowercase letter
    or common continuation patterns.
    """
    prev_stripped = prev.rstrip()
    current_stripped = current.lstrip()

    if not prev_stripped or not current_stripped:
        return False

    # Previous line ends mid-sentence
    prev_ends_mid = prev_stripped[-1] not in '.!?:;"'

    # Current line starts lowercase or with common continuation chars
    # Continuation punctuation includes em-dash and en-dash, which
    # commonly appear at the start of OCR'd continuation lines.
    current_continues = (
        current_stripped[0].islower() or current_stripped[0] in ",(;—–-"  # noqa: RUF001
    )

    # Previous ends with comma, semicolon, or conjunction words
    prev_ends_soft = prev_stripped[-1] in ",;:" or prev_stripped.endswith(
        (" or", " and", " the", " of", " a", " an", " in", " to", " by")
    )

    return (prev_ends_mid and current_continues) or prev_ends_soft


def rejoin_hyphenated(text: str) -> str:
    """Rejoin words that were hyphenated across line breaks.

    Handles both "ex-\\nplanation" and "ex-\\n\\nplanation" patterns.
    Only rejoins when the second part starts with a lowercase letter
    (to preserve real hyphenated compounds like "well-known").
    """
    # Hyphen at end of line followed by newline(s) and lowercase continuation
    text = re.sub(r"(\w)-\s*\n+\s*([a-z])", r"\1\2", text)
    return text


# ─── Repeated-block detector ──────────────────────────────────────────────
#
# Detects running headers, footers, and standalone page-number blocks by
# their cross-page repetition signal. Replaces the prior per-journal regex
# approach (Philippines / "AUTHOR: TITLE" patterns) which only ever matched
# the first test paper and didn't generalize.

_PAGE_FRACTION_THRESHOLD = 0.4
_MIN_PAGES_FOR_DETECTION = 5
_MIN_PAGINATED_MEMBERS = 3

_TRAILING_DIGITS_RE = re.compile(r"(\d+)\s*$")
_WHITESPACE_RUN_RE = re.compile(r"\s+")


def _split_base_and_digit(text: str) -> tuple[str, int | None]:
    """Return (normalized-base-without-trailing-digits, trailing-digit-or-None).

    Normalization: lowercase, collapse internal whitespace. Trailing digits
    are stripped so paginated headers (`"... · 11"`, `"... · 13"`) cluster on
    the same base.
    """
    normalized = _WHITESPACE_RUN_RE.sub(" ", text.lower().strip())
    match = _TRAILING_DIGITS_RE.search(normalized)
    if not match:
        return normalized, None
    base = normalized[: match.start()].rstrip()
    return base, int(match.group(1))


def drop_repeated_blocks(
    raw_blocks: list[RawTextBlock],
    *,
    page_fraction_threshold: float = _PAGE_FRACTION_THRESHOLD,
    min_pages_for_detection: int = _MIN_PAGES_FOR_DETECTION,
    min_paginated_members: int = _MIN_PAGINATED_MEMBERS,
) -> list[RawTextBlock]:
    """Drop running headers, footers, and page-number blocks via repetition signal.

    Two detection paths fire independently per cluster (group of blocks sharing
    the same normalized base text, after stripping trailing digits):

    - **Frequency** — cluster spans ≥ ``page_fraction_threshold`` of the
      document's pages. Catches headers without page numbers.
    - **Paginated** — cluster has ≥ ``min_paginated_members`` blocks whose
      trailing digit equals the block's own page number. Catches alternating
      recto/verso headers (each side forms its own cluster) and standalone
      page-number markers.

    Documents below ``min_pages_for_detection`` pages skip detection — the
    signal is too noisy for short docs.
    """
    if not raw_blocks:
        return raw_blocks

    page_count = max(b.page for b in raw_blocks)
    if page_count < min_pages_for_detection:
        return raw_blocks

    groups: dict[str, list[tuple[RawTextBlock, int | None]]] = {}
    for block in raw_blocks:
        base, digit = _split_base_and_digit(block.text)
        groups.setdefault(base, []).append((block, digit))

    dropped_block_ids: set[str] = set()
    for members in groups.values():
        distinct_pages = {b.page for b, _ in members}
        drop = len(distinct_pages) / page_count >= page_fraction_threshold
        if not drop:
            paginated = sum(1 for b, d in members if d is not None and d == b.page)
            drop = paginated >= min_paginated_members
        if drop:
            for b, _ in members:
                dropped_block_ids.add(b.block_id)

    return [b for b in raw_blocks if b.block_id not in dropped_block_ids]


def strip_plate_pages(text: str) -> str:
    """Remove plate image pages (OCR junk from scanned photographs).

    Keeps plate caption/description sections (e.g., under "ILLUSTRATIONS")
    but removes the actual plate image pages which produce only OCR garbage.

    Plate image pages are identified by lines like:
    - "PLATE I. PLANT GALLS."
    - "AUTHOR: TITLE. ] [JOURNAL..."
    followed by OCR noise (single characters, pipes, short nonsense).
    """
    lines = text.split("\n")
    result: list[str] = []
    in_plate_image = False

    for line in lines:
        stripped = line.strip()

        # Detect start of a plate image page
        if re.match(r"^PLATE\s+[IVXLCDM]+\.\s+", stripped):
            in_plate_image = True
            continue

        # Running headers on plate pages
        if in_plate_image and re.match(r"^[A-Z]+:\s+[A-Z\s]+\.", stripped):
            continue

        # OCR junk lines: very short, single characters, pipes, etc.
        if in_plate_image and (len(stripped) <= 3 or re.match(r"^[|OoIl\s\W]+$", stripped)):
            continue

        # If we're in a plate image section and hit a real content line,
        # check if it's another plate or if we've exited the plates
        if in_plate_image:
            # Another plate reference in captions (PLATE I\n\nDescription)
            # is fine — these are in the ILLUSTRATIONS section before the
            # image pages
            if re.match(r"^PLATE\s+[IVXLCDM]+$", stripped):
                in_plate_image = False
                result.append(line)
                continue
            # Real content — we've exited the plate image pages
            if len(stripped) > 20:
                in_plate_image = False
                result.append(line)
                continue
            # Skip short ambiguous lines while in plate mode
            continue

        result.append(line)

    return "\n".join(result)


# Separator placed between normalized blocks in the flat text substrate.
# Evidence absolute char offsets address into the flat text composed with this.
BLOCK_SEPARATOR = "\n\n"


def preprocess_blocks(raw_blocks: list[RawTextBlock]) -> list[NormalizedBlock]:
    """Apply deterministic cleanup to raw blocks, producing normalized blocks.

    For each raw block, runs the same five-step text cleanup that
    ``preprocess`` runs on a single joined string — applied per-block.
    Blocks that become empty after cleanup are dropped. Each kept raw
    block maps 1:1 to a normalized block in Phase A; the schema's
    ``raw_block_ids`` list shape leaves room for future many-to-one
    merging without changing the contract.

    Output blocks carry sequential ``S_NNNN`` span IDs and absolute
    ``char_start``/``char_end`` offsets into the flat normalized text
    (the concatenation of all kept blocks separated by ``BLOCK_SEPARATOR``).
    Evidence offsets in claims address into that flat text.
    """
    # Drop running headers/footers/page-number blocks by cross-page repetition
    # before per-block cleanup, so downstream stages don't see them as content.
    filtered_blocks = drop_repeated_blocks(raw_blocks)

    cleaned: list[tuple[RawTextBlock, str]] = []
    for raw in filtered_blocks:
        text = raw.text
        text = strip_bhl_boilerplate(text)
        text = strip_plate_pages(text)
        text = rejoin_hyphenated(text)
        text = rejoin_lines(text)
        text = text.strip()
        if text:
            cleaned.append((raw, text))

    normalized: list[NormalizedBlock] = []
    cursor = 0
    sep_len = len(BLOCK_SEPARATOR)
    last_idx = len(cleaned) - 1
    for idx, (raw, text) in enumerate(cleaned):
        char_start = cursor
        char_end = cursor + len(text)
        normalized.append(
            NormalizedBlock(
                span_id=f"S_{idx + 1:04d}",
                block_id=raw.block_id,
                page=raw.page,
                section_id=None,
                char_start=char_start,
                char_end=char_end,
                text=text,
                raw_block_ids=[raw.block_id],
            )
        )
        # Advance cursor past this block; add separator length except after
        # the last block (no trailing separator in flat normalized text).
        cursor = char_end + (sep_len if idx < last_idx else 0)
    return normalized


def flat_normalized_text(blocks: list[NormalizedBlock]) -> str:
    """The canonical text substrate. Evidence absolute char offsets address into this."""
    return BLOCK_SEPARATOR.join(b.text for b in blocks)


def verify_block_offsets(blocks: list[NormalizedBlock]) -> None:
    """Sanity check: each block's [char_start:char_end] equals its text in the flat text.

    Raises ValueError on mismatch. Cheap to run; useful in tests and as a
    pre-bundle invariant in the assemble stage.
    """
    flat = flat_normalized_text(blocks)
    for b in blocks:
        if flat[b.char_start : b.char_end] != b.text:
            raise ValueError(
                f"Block {b.block_id} (span {b.span_id}) text does not match its "
                f"char_start/char_end offsets in the flat normalized text"
            )
