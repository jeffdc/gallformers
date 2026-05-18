"""Tests for the block-level pre-processing pipeline and its per-block helpers."""

from ingest.preprocess import (
    BLOCK_SEPARATOR,
    drop_repeated_blocks,
    flat_normalized_text,
    preprocess_blocks,
    rejoin_hyphenated,
    rejoin_lines,
    strip_bhl_boilerplate,
    strip_plate_pages,
    verify_block_offsets,
)
from ingest.schemas import RawTextBlock


def _block(page: int, text: str, idx: int = 0) -> RawTextBlock:
    return RawTextBlock(
        block_id=f"p{page}-b{idx}",
        page=page,
        text=text,
        extractor="test",
    )


class TestDropRepeatedBlocks:
    """Frequency- and pagination-based detector for running headers/footers."""

    def test_drops_constant_footer_on_every_page(self):
        """Path A: a cluster spanning 100% of pages with no trailing digits."""
        blocks = [_block(p, "© 2022 Magnolia Press", idx=0) for p in range(1, 11)]
        blocks.append(_block(5, "Unique body content on page 5", idx=1))
        result = drop_repeated_blocks(blocks)
        texts = [b.text for b in result]
        assert "Unique body content on page 5" in texts
        assert all("Magnolia Press" not in t for t in texts)

    def test_drops_header_where_trailing_digit_equals_page(self):
        """Path B: 10 blocks each with trailing page number matching its page."""
        blocks = [
            _block(p, f"PAIRING OF NEARCTIC OAK GALLWASP GENERATIONS · {p}", idx=0)
            for p in range(1, 11)
        ]
        blocks.append(_block(3, "Body content on page 3", idx=1))
        result = drop_repeated_blocks(blocks)
        texts = [b.text for b in result]
        assert "Body content on page 3" in texts
        assert all("PAIRING" not in t for t in texts)

    def test_drops_alternating_recto_header(self):
        """Path B with recto-only headers: digits 1, 3, 5, …, 19, all matching their page."""
        blocks = []
        for p in range(1, 21):
            if p % 2 == 1:
                blocks.append(_block(p, f"Smith and Jones · {p}", idx=0))
            blocks.append(_block(p, f"Body prose for page {p} discussing gallwasps.", idx=1))
        result = drop_repeated_blocks(blocks)
        texts = [b.text for b in result]
        assert all("Smith and Jones" not in t for t in texts)
        assert any(t == "Body prose for page 1 discussing gallwasps." for t in texts)

    def test_drops_standalone_page_numbers(self):
        """Path B with empty base: blocks containing just a digit equal to the page."""
        blocks = [
            _block(p, f"Body prose for page {p} discussing gallwasps.", idx=0) for p in range(1, 11)
        ]
        for p in [3, 5, 7, 9]:
            blocks.append(_block(p, str(p), idx=1))
        result = drop_repeated_blocks(blocks)
        texts = [b.text for b in result]
        for n in [3, 5, 7, 9]:
            assert str(n) not in texts
        # Body prose retained — its trailing token is "gallwasps.", not a digit.
        assert any(t == "Body prose for page 1 discussing gallwasps." for t in texts)

    def test_keeps_figure_captions(self):
        """Cluster of 'Figure N' blocks has trailing digit ≠ page → Path B does NOT fire."""
        blocks = [_block(p, f"Body on page {p}", idx=0) for p in range(1, 11)]
        blocks.append(_block(3, "Figure 1", idx=1))
        blocks.append(_block(5, "Figure 2", idx=1))
        blocks.append(_block(7, "Figure 3", idx=1))
        result = drop_repeated_blocks(blocks)
        texts = [b.text for b in result]
        assert "Figure 1" in texts
        assert "Figure 2" in texts
        assert "Figure 3" in texts

    def test_keeps_unique_body_content(self):
        """Blocks each with distinct non-paginated text (cluster size 1) are always kept."""
        unique_texts = [
            "Andricus quercuscalifornicus description",
            "Quercus agrifolia host plant notes",
            "Gall morphology in spring",
            "Adult emergence timing",
            "Distribution across the southwest",
            "Comparison with related taxa",
            "Type specimen deposition",
            "Acknowledgements for fieldwork",
            "References cited follow",
            "Conclusions and future work",
        ]
        blocks = [_block(p + 1, unique_texts[p], idx=0) for p in range(10)]
        result = drop_repeated_blocks(blocks)
        assert len(result) == 10

    def test_keeps_section_heading_spanning_page_break(self):
        """A heading appearing on 2 of 10 pages (20% < 40%) and with no monotonic digits is kept."""
        blocks = [_block(p, f"Body on page {p}", idx=0) for p in range(1, 11)]
        blocks.append(_block(3, "Introduction", idx=1))
        blocks.append(_block(4, "Introduction", idx=1))
        result = drop_repeated_blocks(blocks)
        intro_count = sum(1 for b in result if b.text == "Introduction")
        assert intro_count == 2

    def test_short_doc_skips_detection(self):
        """Documents below min_pages_for_detection get no detection — all blocks kept."""
        blocks = [_block(p, f"Header · {p}", idx=0) for p in range(1, 4)]
        blocks.append(_block(2, "Body content", idx=1))
        result = drop_repeated_blocks(blocks)
        assert len(result) == 4


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
