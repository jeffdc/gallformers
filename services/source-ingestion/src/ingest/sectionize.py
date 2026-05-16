"""Rule-based section detection over normalized blocks.

Detects common scientific-paper section headings (Abstract, Introduction,
Methods, Acknowledgements, References, etc.) and splits the block stream
into a sequence of typed sections. Each block gains a ``section_id``
pointing back to its section in the returned ``SectionsFile``.

Section types follow the ``SectionType`` enum. Sections marked
``extraction_eligible=False`` are excluded from downstream extraction
(references, bibliography, literature-cited, acknowledgements). When no
headings are detected the entire input becomes a single UNKNOWN section
that IS eligible — the downstream stages have their own input filters.

Output: a ``SectionsFile`` for ``sections.json`` and a new list of
``NormalizedBlock``s with ``section_id`` populated. Pydantic models are
immutable; ``model_copy(update=...)`` produces the updated blocks without
mutating the input.
"""

from __future__ import annotations

import re

from ingest.schemas import NormalizedBlock, Section, SectionsFile, SectionType

# Mapping of heading variants to the section they introduce.
# Each entry: (SectionType, eligible_for_extraction, list of heading
# strings to match). Heading matching is anchored to a complete line,
# case-insensitive, and tolerates an optional markdown ``#`` prefix.
_SECTION_PATTERNS: list[tuple[SectionType, bool, list[str]]] = [
    (SectionType.ABSTRACT, True, ["Abstract", "Summary"]),
    (SectionType.INTRODUCTION, True, ["Introduction"]),
    (
        SectionType.METHODS,
        True,
        ["Methods", "Materials and Methods", "Material and Methods", "Methodology"],
    ),
    # Results / Discussion: no schema enum yet — they fall through to
    # UNKNOWN body sections. (Could add SectionType.RESULTS / DISCUSSION
    # later if extraction needs to differentiate.)
    (SectionType.APPENDIX, False, ["Acknowledgements", "Acknowledgments"]),
    (SectionType.REFERENCES, False, ["References"]),
    (SectionType.BIBLIOGRAPHY, False, ["Bibliography"]),
    (SectionType.LITERATURE_CITED, False, ["Literature Cited", "Works Cited", "Citations"]),
]


def _build_heading_pattern() -> tuple[re.Pattern, dict[str, tuple[SectionType, bool]]]:
    """Build a combined heading regex + lookup table from _SECTION_PATTERNS."""
    alts: list[str] = []
    type_lookup: dict[str, tuple[SectionType, bool]] = {}
    for stype, eligible, variants in _SECTION_PATTERNS:
        for variant in variants:
            # Allow flexible whitespace within multi-word headings.
            alts.append(re.escape(variant).replace(r"\ ", r"\s+"))
            # Normalize to lowercase + collapsed-whitespace for lookup.
            type_lookup[re.sub(r"\s+", " ", variant.lower())] = (stype, eligible)
    pattern = re.compile(
        r"^\s*(?:#{1,4}\s*)?"
        r"(?P<heading>" + "|".join(alts) + r")\s*$",
        re.IGNORECASE,
    )
    return pattern, type_lookup


_HEADING_PATTERN, _HEADING_TYPES = _build_heading_pattern()


def _classify_heading(heading: str) -> tuple[SectionType, bool]:
    """Map a matched heading string to its (SectionType, eligible) pair."""
    key = re.sub(r"\s+", " ", heading.lower())
    return _HEADING_TYPES.get(key, (SectionType.UNKNOWN, True))


def _find_all_headings(
    blocks: list[NormalizedBlock],
) -> list[tuple[int, str, SectionType, bool]]:
    """Find every block whose first heading-matching line starts a section.

    Returns ``[(block_index, heading_text, section_type, eligible), ...]``
    sorted by block_index. At most one heading per block — only the first
    matching line in a block contributes (a block typically holds one
    paragraph, so multiple headings in one block is unusual).
    """
    found: list[tuple[int, str, SectionType, bool]] = []
    for i, block in enumerate(blocks):
        for line in block.text.split("\n"):
            match = _HEADING_PATTERN.match(line.strip())
            if match:
                heading = match.group("heading").strip()
                stype, eligible = _classify_heading(heading)
                found.append((i, heading, stype, eligible))
                break
    return found


def _make_section(
    sec_id: str,
    stype: SectionType,
    heading: str | None,
    eligible: bool,
    blocks: list[NormalizedBlock],
) -> Section:
    return Section(
        section_id=sec_id,
        type=stype,
        heading=heading,
        heading_path=[heading] if heading else [],
        page_start=min(b.page for b in blocks),
        page_end=max(b.page for b in blocks),
        span_ids=[b.span_id for b in blocks],
        extraction_eligible=eligible,
    )


def _single_unknown_section(
    blocks: list[NormalizedBlock],
) -> tuple[SectionsFile, list[NormalizedBlock]]:
    """No headings detected — emit one big UNKNOWN section."""
    section = _make_section("sec-1", SectionType.UNKNOWN, None, True, blocks)
    new_blocks = [b.model_copy(update={"section_id": "sec-1"}) for b in blocks]
    return SectionsFile(sections=[section]), new_blocks


def sectionize(blocks: list[NormalizedBlock]) -> tuple[SectionsFile, list[NormalizedBlock]]:
    """Detect sections; classify each by type and mark extraction eligibility.

    Returns:
        ``(sections_file, blocks_with_section_id)`` — the second element is a
        new list; input blocks are not mutated.
    """
    if not blocks:
        return SectionsFile(sections=[]), []

    headings = _find_all_headings(blocks)

    if not headings:
        return _single_unknown_section(blocks)

    # Pre-first-heading content. If the paper has a "real" publication
    # structure (Abstract / Introduction / Methods detected), the head
    # is the title block. Otherwise (e.g. only a References heading
    # found, like the existing fixtures), keep it as UNKNOWN for
    # backward compatibility — the metadata stage's fallback handles
    # extraction for unstructured fronts.
    has_pub_structure = any(
        stype in (SectionType.ABSTRACT, SectionType.INTRODUCTION, SectionType.METHODS)
        for _, _, stype, _ in headings
    )
    pre_heading_type = SectionType.TITLE if has_pub_structure else SectionType.UNKNOWN

    sections: list[Section] = []
    new_blocks: list[NormalizedBlock] = []
    section_counter = 1

    first_heading_idx = headings[0][0]
    if first_heading_idx > 0:
        head_blocks = blocks[:first_heading_idx]
        sec_id = f"sec-{section_counter}"
        section_counter += 1
        sections.append(_make_section(sec_id, pre_heading_type, None, True, head_blocks))
        new_blocks.extend(b.model_copy(update={"section_id": sec_id}) for b in head_blocks)

    for h_idx, (block_i, heading, stype, eligible) in enumerate(headings):
        end_i = headings[h_idx + 1][0] if h_idx + 1 < len(headings) else len(blocks)
        section_blocks = blocks[block_i:end_i]
        sec_id = f"sec-{section_counter}"
        section_counter += 1
        sections.append(_make_section(sec_id, stype, heading, eligible, section_blocks))
        new_blocks.extend(b.model_copy(update={"section_id": sec_id}) for b in section_blocks)

    return SectionsFile(sections=sections), new_blocks
