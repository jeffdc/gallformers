"""Tests for the rule-based sectionizer."""

from __future__ import annotations

from ingest.schemas import NormalizedBlock, SectionType
from ingest.sectionize import sectionize


def _block(span_id: str, text: str, page: int = 1, char_start: int = 0) -> NormalizedBlock:
    return NormalizedBlock(
        span_id=span_id,
        block_id=span_id,
        page=page,
        char_start=char_start,
        char_end=char_start + len(text),
        text=text,
        raw_block_ids=[span_id],
    )


class TestEmptyInput:
    def test_empty_blocks_yields_no_sections(self):
        sections_file, blocks = sectionize([])
        assert sections_file.sections == []
        assert blocks == []


class TestNoReferencesHeading:
    def test_all_blocks_become_one_unknown_section(self):
        inputs = [
            _block("S_0001", "Some body text.", page=1, char_start=0),
            _block("S_0002", "More body text.", page=2, char_start=20),
        ]
        sections_file, blocks = sectionize(inputs)

        assert len(sections_file.sections) == 1
        sec = sections_file.sections[0]
        assert sec.section_id == "sec-1"
        assert sec.type == SectionType.UNKNOWN
        assert sec.extraction_eligible is True
        assert sec.span_ids == ["S_0001", "S_0002"]
        assert sec.page_start == 1
        assert sec.page_end == 2

        assert all(b.section_id == "sec-1" for b in blocks)


class TestReferencesSplit:
    def test_references_heading_splits_into_body_and_refs(self):
        inputs = [
            _block("S_0001", "Body content.", page=1, char_start=0),
            _block("S_0002", "References\nSmith 1881. A paper.", page=2, char_start=20),
            _block("S_0003", "Jones 1900. Another paper.", page=2, char_start=60),
        ]
        sections_file, blocks = sectionize(inputs)

        assert len(sections_file.sections) == 2

        body = sections_file.sections[0]
        assert body.section_id == "sec-1"
        assert body.type == SectionType.UNKNOWN
        assert body.extraction_eligible is True
        assert body.span_ids == ["S_0001"]

        refs = sections_file.sections[1]
        assert refs.section_id == "sec-2"
        assert refs.type == SectionType.REFERENCES
        assert refs.extraction_eligible is False
        assert refs.span_ids == ["S_0002", "S_0003"]
        assert refs.heading == "References"
        assert refs.heading_path == ["References"]

        # Each block now has its section_id
        section_ids = [b.section_id for b in blocks]
        assert section_ids == ["sec-1", "sec-2", "sec-2"]

    def test_no_body_blocks_when_refs_heading_is_first(self):
        # First block is the references heading itself.
        inputs = [
            _block("S_0001", "References\nFirst entry.", page=1, char_start=0),
            _block("S_0002", "Second entry.", page=1, char_start=30),
        ]
        sections_file, blocks = sectionize(inputs)

        # Only the references section exists; no body section is emitted.
        assert len(sections_file.sections) == 1
        assert sections_file.sections[0].section_id == "sec-2"
        assert sections_file.sections[0].extraction_eligible is False
        assert all(b.section_id == "sec-2" for b in blocks)


class TestReferencesTypeDetection:
    def test_bibliography_heading_typed_as_bibliography(self):
        inputs = [
            _block("S_0001", "Body.", page=1, char_start=0),
            _block("S_0002", "Bibliography\nSomeone 1900.", page=2, char_start=10),
        ]
        sections_file, _ = sectionize(inputs)
        refs = sections_file.sections[-1]
        assert refs.type == SectionType.BIBLIOGRAPHY

    def test_literature_cited_heading_typed_as_literature_cited(self):
        inputs = [
            _block("S_0001", "Body.", page=1, char_start=0),
            _block("S_0002", "Literature Cited\nFoo 1881.", page=2, char_start=10),
        ]
        sections_file, _ = sectionize(inputs)
        refs = sections_file.sections[-1]
        assert refs.type == SectionType.LITERATURE_CITED

    def test_markdown_heading_prefix_is_tolerated(self):
        inputs = [
            _block("S_0001", "Body.", page=1, char_start=0),
            _block("S_0002", "## References\nFoo 1881.", page=2, char_start=10),
        ]
        sections_file, _ = sectionize(inputs)
        refs = sections_file.sections[-1]
        assert refs.type == SectionType.REFERENCES
        # The captured heading is just the word, not the # prefix.
        assert refs.heading == "References"

    def test_case_insensitive_matching(self):
        inputs = [
            _block("S_0001", "Body.", page=1, char_start=0),
            _block("S_0002", "REFERENCES\nFoo 1881.", page=2, char_start=10),
        ]
        sections_file, _ = sectionize(inputs)
        assert sections_file.sections[-1].type == SectionType.REFERENCES


class TestInputNotMutated:
    def test_input_blocks_unchanged(self):
        # section_id starts as None; sectionize must not mutate the input.
        inputs = [_block("S_0001", "Body.", page=1, char_start=0)]
        before_id = inputs[0].section_id  # None
        sectionize(inputs)
        assert inputs[0].section_id == before_id  # still None
