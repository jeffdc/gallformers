"""Tests for the block-level pre-processing pipeline and its per-block helpers."""

from ingest.preprocess import (
    BLOCK_SEPARATOR,
    flat_normalized_text,
    preprocess_blocks,
    rejoin_hyphenated,
    rejoin_lines,
    strip_bhl_boilerplate,
    strip_page_headers,
    strip_plate_pages,
    verify_block_offsets,
)
from ingest.schemas import RawTextBlock


class TestStripBHLBoilerplate:
    def test_removes_bhl_header(self):
        text = (
            "[https://www.biodiversitylibrary.org/](https://www.biodiversitylibrary.org/)\n\n"
            "# **The Philippine journal of science**\n\n"
            "Manila Bureau of Science\n"
            "[https://www.biodiversitylibrary.org/bibliography/50545](...)\n\n"
            "v.14 (1919): https://www.biodiversitylibrary.org/item/1124\n\n"
            "Page(s): Page 527, Page 528\n\n"
            "Holding Institution: Missouri Botanical Garden\n"
            "Sponsored by: Missouri Botanical Garden\n\n"
            "Generated 3 March 2026 6:28 PM\n"
            "[https://www.biodiversitylibrary.org/pdf4/...](https://...)\n\n"
            "This page intentionally left blank.\n\n"
            "A BIOLOGICAL AND SYSTEMATIC STUDY\n"
        )
        result = strip_bhl_boilerplate(text)
        assert "biodiversitylibrary.org" not in result
        assert "Holding Institution" not in result
        assert "intentionally left blank" not in result
        assert "BIOLOGICAL AND SYSTEMATIC STUDY" in result

    def test_preserves_non_bhl_text(self):
        text = "Just a normal document.\n\nWith some content."
        assert strip_bhl_boilerplate(text) == text


class TestRejoinLines:
    def test_rejoins_single_newlines(self):
        text = "This is a sentence that\ncontinues on the next line.\n\nNew paragraph here."
        result = rejoin_lines(text)
        assert "sentence that continues" in result
        assert "\n\n" in result  # paragraph break preserved

    def test_preserves_paragraph_breaks(self):
        text = "Paragraph one.\n\nParagraph two."
        result = rejoin_lines(text)
        assert result == "Paragraph one.\n\nParagraph two."

    def test_preserves_headings(self):
        text = "# INTRODUCTION\n\nSome text here."
        result = rejoin_lines(text)
        assert "# INTRODUCTION" in result

    def test_handles_blank_line_separated_ocr(self):
        """BHL-style: every line has a blank line after it."""
        text = "Galls are abnormal growths on the stems, leaves, roots, or\n\nother parts of plants, caused by the action of insects, arachnids, or\n\nfungi, by unknown agencies."
        result = rejoin_lines(text)
        # These should be joined since they're continuation lines
        assert "roots, or other parts" in result


class TestRejoinHyphenated:
    def test_rejoins_hyphenated_words(self):
        text = "This is a long ex-\nplanation of something."
        result = rejoin_hyphenated(text)
        assert "explanation" in result

    def test_rejoins_across_blank_lines(self):
        text = "a zodce-\n\ncidia may be"
        result = rejoin_hyphenated(text)
        assert "zodcecidia" in result

    def test_preserves_real_hyphens(self):
        text = "a well-known fact"
        result = rejoin_hyphenated(text)
        assert "well-known" in result


class TestStripPageHeaders:
    def test_removes_journal_page_headers(self):
        text = "end of previous text.\n\n528 Philippine Journal of Science\n1919\n\nStart of next text."
        result = strip_page_headers(text)
        assert "Philippine Journal of Science" not in result
        assert "end of previous text" in result
        assert "Start of next text" in result

    def test_removes_page_numbers(self):
        text = "some text.\n\n527\n\nmore text."
        result = strip_page_headers(text)
        assert result.strip() == "some text.\n\nmore text."


class TestStripPlatPages:
    def test_removes_plate_image_pages(self):
        text = (
            "Real content here.\n\n"
            "ILLUSTRATIONS\n\n"
            "PLATE I\n\n"
            "Description of plate one figures.\n\n"
            "PLATE I. PLANT GALLS.\n\n"
            "UICHANCO: PHILIPPINE PLANT GALLS. ] [PHILIP. JouRN. Sct., XIV, No. 5.\n\n"
            "|\n\nO\n\nHq\n\n"
            "PLATE II. PLANT GALLS.\n\n"
            "random OCR junk\n\n"
        )
        result = strip_plate_pages(text)
        assert "Real content here" in result
        assert "ILLUSTRATIONS" in result
        assert "Description of plate one figures" in result
        # Plate image pages should be gone
        assert "PLATE I. PLANT GALLS." not in result
        assert "UICHANCO: PHILIPPINE PLANT GALLS" not in result
        assert "Hq" not in result

    def test_preserves_plate_references_in_body(self):
        text = "The gall shown in Plate VI, fig. 8. Cross section."
        result = strip_plate_pages(text)
        assert "Plate VI" in result


def _raw(block_id: str, text: str, page: int = 1) -> RawTextBlock:
    return RawTextBlock(
        block_id=block_id,
        page=page,
        text=text,
        bbox=None,
        extractor="plain-text",
        quality_signals={},
    )


class TestPreprocessBlocks:
    def test_single_block_basic(self):
        blocks = preprocess_blocks([_raw("p1-b0", "Hello world.")])
        assert len(blocks) == 1
        b = blocks[0]
        assert b.span_id == "S_0001"
        assert b.block_id == "p1-b0"
        assert b.page == 1
        assert b.char_start == 0
        assert b.char_end == len("Hello world.")
        assert b.text == "Hello world."
        assert b.raw_block_ids == ["p1-b0"]
        assert b.section_id is None

    def test_two_blocks_offsets_account_for_separator(self):
        blocks = preprocess_blocks([_raw("p1-b0", "First."), _raw("p1-b1", "Second.")])
        assert len(blocks) == 2
        assert blocks[0].span_id == "S_0001"
        assert blocks[1].span_id == "S_0002"
        assert blocks[0].char_start == 0
        assert blocks[0].char_end == 6  # "First."
        # Second starts after "First." + "\n\n"
        assert blocks[1].char_start == 6 + len(BLOCK_SEPARATOR)
        assert blocks[1].char_end == blocks[1].char_start + 7  # "Second."

    def test_offsets_consistent_with_flat_text(self):
        blocks = preprocess_blocks(
            [
                _raw("p1-b0", "Alpha."),
                _raw("p2-b0", "Beta gamma.", page=2),
                _raw("p2-b1", "Delta.", page=2),
            ]
        )
        flat = flat_normalized_text(blocks)
        assert flat == "Alpha.\n\nBeta gamma.\n\nDelta."
        verify_block_offsets(blocks)  # must not raise
        for b in blocks:
            assert flat[b.char_start : b.char_end] == b.text

    def test_empty_block_after_cleanup_is_dropped(self):
        # A block consisting entirely of whitespace gets dropped.
        blocks = preprocess_blocks([_raw("p1-b0", "Real content."), _raw("p1-b1", "   \n  ")])
        assert len(blocks) == 1
        assert blocks[0].block_id == "p1-b0"

    def test_bhl_boilerplate_block_dropped(self):
        # A block that contains only BHL boilerplate becomes empty after cleanup.
        bhl_only = (
            "[https://www.biodiversitylibrary.org/](https://www.biodiversitylibrary.org/)\n\n"
            "Holding Institution: Some Library\n"
            "This page intentionally left blank."
        )
        blocks = preprocess_blocks(
            [_raw("p1-b0", bhl_only), _raw("p1-b1", "Real scientific content.")]
        )
        # BHL block becomes empty -> dropped; only the real content block remains.
        assert len(blocks) == 1
        assert blocks[0].block_id == "p1-b1"
        assert blocks[0].span_id == "S_0001"  # span_id renumbers after drops

    def test_page_number_is_preserved_per_block(self):
        blocks = preprocess_blocks(
            [
                _raw("p1-b0", "Alpha.", page=1),
                _raw("p2-b0", "Beta.", page=2),
                _raw("p5-b3", "Gamma.", page=5),
            ]
        )
        assert [b.page for b in blocks] == [1, 2, 5]

    def test_raw_block_ids_traces_back(self):
        blocks = preprocess_blocks([_raw("p1-b0", "Alpha."), _raw("p1-b1", "Beta.")])
        assert blocks[0].raw_block_ids == ["p1-b0"]
        assert blocks[1].raw_block_ids == ["p1-b1"]

    def test_empty_input_yields_empty_output(self):
        assert preprocess_blocks([]) == []


class TestVerifyBlockOffsets:
    def test_tampered_offsets_raises(self):
        original = preprocess_blocks([_raw("p1-b0", "Hello.")])
        # Corrupt by directly constructing a block with wrong offsets.
        from ingest.schemas import NormalizedBlock

        bad = NormalizedBlock(
            span_id="S_0001",
            block_id="p1-b0",
            page=1,
            char_start=0,
            char_end=4,  # would slice "Hell", not "Hello."
            text="Hello.",
            raw_block_ids=["p1-b0"],
        )
        import pytest

        with pytest.raises(ValueError, match="does not match"):
            verify_block_offsets([bad])
