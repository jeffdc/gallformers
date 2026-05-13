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
        assert sections_file.sections[0].type == SectionType.REFERENCES
        assert sections_file.sections[0].extraction_eligible is False
        sec_id = sections_file.sections[0].section_id
        assert all(b.section_id == sec_id for b in blocks)


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


class TestStructuredPaper:
    """A paper with Abstract, Introduction, Methods, References gets fully classified."""

    def test_full_section_split(self):
        inputs = [
            _block("S_0001", "Title block.", page=1),
            _block("S_0002", "Author block.", page=1, char_start=20),
            _block("S_0003", "Abstract\nThe study examines...", page=1, char_start=40),
            _block("S_0004", "Introduction\nGalls have been studied...", page=2, char_start=80),
            _block("S_0005", "More intro content.", page=2, char_start=120),
            _block("S_0006", "Methods\nWe surveyed...", page=3, char_start=140),
            _block("S_0007", "Acknowledgements\nThanks to...", page=4, char_start=180),
            _block("S_0008", "References\nSmith 1881.", page=5, char_start=220),
        ]
        sections_file, blocks = sectionize(inputs)

        # 6 sections: title (pre-Abstract), abstract, intro, methods, ack, refs
        assert len(sections_file.sections) == 6
        types = [s.type for s in sections_file.sections]
        assert types == [
            SectionType.TITLE,
            SectionType.ABSTRACT,
            SectionType.INTRODUCTION,
            SectionType.METHODS,
            SectionType.APPENDIX,  # acknowledgements
            SectionType.REFERENCES,
        ]
        eligible = [s.extraction_eligible for s in sections_file.sections]
        # title/abstract/intro/methods eligible; ack/refs not
        assert eligible == [True, True, True, True, False, False]

    def test_methods_variants_recognized(self):
        for variant in ["Methods", "Materials and Methods", "Material and Methods"]:
            inputs = [
                _block("S_0001", "Abstract\nbody", page=1),
                _block("S_0002", f"{variant}\nWe studied...", page=2, char_start=20),
            ]
            sections_file, _ = sectionize(inputs)
            assert SectionType.METHODS in [s.type for s in sections_file.sections], (
                f"Failed to detect {variant!r} as Methods"
            )

    def test_acknowledgements_variants_recognized(self):
        for variant in ["Acknowledgements", "Acknowledgments"]:
            inputs = [
                _block("S_0001", "Body content.", page=1),
                _block("S_0002", f"{variant}\nThanks.", page=2, char_start=20),
            ]
            sections_file, _ = sectionize(inputs)
            ack = next((s for s in sections_file.sections if s.type == SectionType.APPENDIX), None)
            assert ack is not None, f"Failed to detect {variant!r} as APPENDIX"
            assert ack.extraction_eligible is False

    def test_references_only_keeps_pre_section_as_unknown(self):
        # When ONLY a References heading is present (no Abstract/Intro/Methods),
        # the pre-References content stays UNKNOWN — not retyped as TITLE — so
        # the legacy "body + refs" two-section behavior is preserved.
        inputs = [
            _block("S_0001", "Body content.", page=1),
            _block("S_0002", "References\nSmith 1881.", page=2, char_start=20),
        ]
        sections_file, _ = sectionize(inputs)
        assert len(sections_file.sections) == 2
        assert sections_file.sections[0].type == SectionType.UNKNOWN
        assert sections_file.sections[1].type == SectionType.REFERENCES

    def test_abstract_promotes_pre_section_to_title(self):
        inputs = [
            _block("S_0001", "Paper Title", page=1),
            _block("S_0002", "Authors A and B", page=1, char_start=20),
            _block("S_0003", "Abstract\nThe study...", page=1, char_start=40),
        ]
        sections_file, _ = sectionize(inputs)
        assert sections_file.sections[0].type == SectionType.TITLE
        assert sections_file.sections[0].span_ids == ["S_0001", "S_0002"]
        assert sections_file.sections[1].type == SectionType.ABSTRACT
