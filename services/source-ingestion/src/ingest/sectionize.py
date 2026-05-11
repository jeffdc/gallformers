"""Rule-based section detection over normalized blocks.

For Phase A this is intentionally minimal: detect a references-like heading
and mark that block + all subsequent blocks as a non-extraction-eligible
section (``extraction_eligible=False``). Everything before becomes a single
UNKNOWN section that *is* eligible for extraction. This catches the most
important failure mode — species names leaking out of the bibliography —
without trying to classify the body's internal structure.

Richer multi-section detection (title, abstract, methods, taxonomic
treatments, etc.) is Phase B work and will likely build on top of this
same scaffold.

Output: a ``SectionsFile`` for ``sections.json`` and a new list of
``NormalizedBlock``s with ``section_id`` populated. Pydantic models are
immutable; ``model_copy(update=...)`` produces the updated blocks without
mutating the input.
"""

from __future__ import annotations

import re

from ingest.schemas import NormalizedBlock, Section, SectionsFile, SectionType

# Match heading lines like "References", "## Bibliography", "Literature Cited".
# Anchored at start/end of a single line; case-insensitive.
_REFERENCES_HEADING = re.compile(
    r"^\s*(?:#{1,4}\s*)?"
    r"(?P<heading>"
    r"References"
    r"|Bibliography"
    r"|Literature\s+Cited"
    r"|Works\s+Cited"
    r"|Citations"
    r")\s*$",
    re.IGNORECASE,
)


def _references_type(heading: str) -> SectionType:
    """Map a matched heading to one of the three excluded section types."""
    lower = heading.lower()
    if "bibliography" in lower:
        return SectionType.BIBLIOGRAPHY
    if "literature" in lower:
        return SectionType.LITERATURE_CITED
    return SectionType.REFERENCES


def _find_references_split(
    blocks: list[NormalizedBlock],
) -> tuple[int | None, str | None, SectionType]:
    """Find the first block whose text contains a references-like heading line.

    Returns ``(block_index, heading_text, section_type)``. If no heading is
    found, returns ``(None, None, SectionType.UNKNOWN)``.
    """
    for i, block in enumerate(blocks):
        for line in block.text.split("\n"):
            match = _REFERENCES_HEADING.match(line.strip())
            if match:
                heading = match.group("heading").strip()
                return i, heading, _references_type(heading)
    return None, None, SectionType.UNKNOWN


def sectionize(blocks: list[NormalizedBlock]) -> tuple[SectionsFile, list[NormalizedBlock]]:
    """Detect sections; mark references / bibliography / literature-cited as ineligible.

    Returns:
        ``(sections_file, blocks_with_section_id)`` — the second element is a
        new list; input blocks are not mutated.
    """
    if not blocks:
        return SectionsFile(sections=[]), []

    split_index, heading, refs_type = _find_references_split(blocks)

    sections: list[Section] = []
    new_blocks: list[NormalizedBlock] = []

    if split_index is None:
        section = Section(
            section_id="sec-1",
            type=SectionType.UNKNOWN,
            heading=None,
            heading_path=[],
            page_start=min(b.page for b in blocks),
            page_end=max(b.page for b in blocks),
            span_ids=[b.span_id for b in blocks],
            extraction_eligible=True,
        )
        sections.append(section)
        new_blocks = [b.model_copy(update={"section_id": "sec-1"}) for b in blocks]
        return SectionsFile(sections=sections), new_blocks

    body = blocks[:split_index]
    refs = blocks[split_index:]

    if body:
        sections.append(
            Section(
                section_id="sec-1",
                type=SectionType.UNKNOWN,
                heading=None,
                heading_path=[],
                page_start=min(b.page for b in body),
                page_end=max(b.page for b in body),
                span_ids=[b.span_id for b in body],
                extraction_eligible=True,
            )
        )
        new_blocks.extend(b.model_copy(update={"section_id": "sec-1"}) for b in body)

    sections.append(
        Section(
            section_id="sec-2",
            type=refs_type,
            heading=heading,
            heading_path=[heading] if heading else [],
            page_start=min(b.page for b in refs),
            page_end=max(b.page for b in refs),
            span_ids=[b.span_id for b in refs],
            extraction_eligible=False,
        )
    )
    new_blocks.extend(b.model_copy(update={"section_id": "sec-2"}) for b in refs)

    return SectionsFile(sections=sections), new_blocks
