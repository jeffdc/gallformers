from pathlib import Path

import pymupdf
import pytest

from ingest.extract import extract_blocks
from ingest.jsonl import read_jsonl, write_jsonl
from ingest.schemas import RawTextBlock


def _write_test_pdf(path: Path, pages: list[list[str]]) -> None:
    """Build a tiny multi-page PDF with each entry of `pages` as separate text blocks."""
    doc = pymupdf.Document()
    for page_lines in pages:
        page = doc.new_page()
        y = 72.0
        for line in page_lines:
            page.insert_text((72, y), line)
            y += 36.0  # advance the y-cursor so PyMuPDF emits separate blocks
    doc.save(str(path))
    doc.close()


class TestExtractBlocksPlainText:
    def test_plain_text_yields_one_page1_block(self, tmp_path):
        f = tmp_path / "notes.txt"
        f.write_text("Hello world\nSecond line.")
        blocks = extract_blocks(str(f))
        assert len(blocks) == 1
        assert blocks[0].block_id == "p1-b0"
        assert blocks[0].page == 1
        assert blocks[0].text == "Hello world\nSecond line."
        assert blocks[0].extractor == "plain-text"
        assert blocks[0].bbox is None

    def test_plain_text_missing_file_raises(self):
        with pytest.raises(FileNotFoundError):
            extract_blocks("/nonexistent/file.txt")


class TestExtractBlocksURL:
    def test_url_yields_one_page1_block(self, mocker):
        mocker.patch("ingest.extract.trafilatura.fetch_url", return_value="<html></html>")
        mocker.patch("ingest.extract.trafilatura.extract", return_value="Extracted web body.")
        blocks = extract_blocks("https://example.com/page")
        assert len(blocks) == 1
        assert blocks[0].block_id == "p1-b0"
        assert blocks[0].page == 1
        assert blocks[0].text == "Extracted web body."
        assert blocks[0].extractor.startswith("trafilatura-")
        assert blocks[0].quality_signals["url"] == "https://example.com/page"


class TestExtractBlocksPDF:
    def test_single_page_pdf_yields_per_block_rows(self, tmp_path):
        pdf = tmp_path / "one_page.pdf"
        _write_test_pdf(pdf, [["First paragraph text.", "Second paragraph text."]])
        blocks = extract_blocks(str(pdf))
        # Two text insertions on the same page → two text blocks.
        assert len(blocks) == 2
        assert all(b.page == 1 for b in blocks)
        assert blocks[0].block_id == "p1-b0"
        assert blocks[1].block_id == "p1-b1"
        assert blocks[0].extractor.startswith("pymupdf-")
        assert all(b.bbox is not None for b in blocks)
        # Each block's bbox should have x1 > x0 and y1 > y0.
        for b in blocks:
            assert b.bbox.x1 > b.bbox.x0
            assert b.bbox.y1 > b.bbox.y0

    def test_multi_page_pdf_resets_block_index_per_page(self, tmp_path):
        pdf = tmp_path / "two_pages.pdf"
        _write_test_pdf(pdf, [["Page one only block."], ["Page two only block."]])
        blocks = extract_blocks(str(pdf))
        # One block per page; both indices start at 0.
        assert len(blocks) == 2
        assert blocks[0].block_id == "p1-b0"
        assert blocks[0].page == 1
        assert blocks[1].block_id == "p2-b0"
        assert blocks[1].page == 2


class TestRawTextJsonlRoundTrip:
    def test_write_then_read_preserves_blocks(self, tmp_path):
        original = [
            RawTextBlock(
                block_id="p1-b0",
                page=1,
                text="block one",
                bbox=None,
                extractor="plain-text",
                quality_signals={"char_count": 9},
            ),
            RawTextBlock(
                block_id="p1-b1",
                page=1,
                text="block two",
                bbox=None,
                extractor="plain-text",
                quality_signals={"char_count": 9},
            ),
        ]
        path = tmp_path / "raw.jsonl"
        write_jsonl(original, path)
        round_tripped = read_jsonl(path, RawTextBlock)
        assert round_tripped == original

    def test_read_skips_blank_lines(self, tmp_path):
        path = tmp_path / "raw.jsonl"
        path.write_text(
            '{"block_id":"p1-b0","page":1,"text":"a","extractor":"plain-text",'
            '"quality_signals":{},"bbox":null}\n'
            "\n"
            "  \n"
            '{"block_id":"p1-b1","page":1,"text":"b","extractor":"plain-text",'
            '"quality_signals":{},"bbox":null}\n'
        )
        items = read_jsonl(path, RawTextBlock)
        assert [b.text for b in items] == ["a", "b"]
