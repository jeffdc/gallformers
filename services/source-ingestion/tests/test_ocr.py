from pathlib import Path

import pymupdf
import pytest

from ingest.ocr import avg_chars_per_page, maybe_ocr, should_ocr
from ingest.schemas import RawTextBlock


def _block(page: int, text: str, idx: int = 0) -> RawTextBlock:
    return RawTextBlock(
        block_id=f"p{page}-b{idx}",
        page=page,
        text=text,
        bbox=None,
        extractor="pymupdf-test",
        quality_signals={"char_count": len(text)},
    )


def _write_image_only_pdf(path: Path, pages: int = 2) -> None:
    """Build a PDF with rendered images but no text layer — simulates a scan."""
    doc = pymupdf.Document()
    for _ in range(pages):
        page = doc.new_page()
        # Draw a few rectangles so the page isn't blank, but insert NO text.
        page.draw_rect((72, 72, 200, 120), color=(0, 0, 0), fill=(0.9, 0.9, 0.9))
    doc.save(str(path))
    doc.close()


def _write_text_pdf(path: Path, page_text: str) -> None:
    """Build a 1-page PDF with embedded text. Stands in for an OCR'd PDF in tests."""
    doc = pymupdf.Document()
    page = doc.new_page()
    page.insert_text((72, 72), page_text)
    doc.save(str(path))
    doc.close()


class TestAvgCharsPerPage:
    def test_empty_blocks_returns_zero(self):
        assert avg_chars_per_page([]) == 0.0

    def test_single_page_single_block(self):
        blocks = [_block(1, "a" * 80)]
        assert avg_chars_per_page(blocks) == 80.0

    def test_averages_across_distinct_pages(self):
        # 2 pages: page 1 has 100 chars, page 2 has 60 chars. Avg = 80.
        blocks = [_block(1, "a" * 100), _block(2, "b" * 60)]
        assert avg_chars_per_page(blocks) == 80.0

    def test_sums_multiple_blocks_on_same_page(self):
        # 1 page, 2 blocks of 30 + 70 = 100 chars total on 1 page.
        blocks = [_block(1, "a" * 30, idx=0), _block(1, "b" * 70, idx=1)]
        assert avg_chars_per_page(blocks) == 100.0


class TestShouldOcr:
    def test_never_returns_false(self):
        blocks = [_block(1, "a" * 5)]  # density 5, well below default 100
        decision, _reason = should_ocr(blocks, enabled="never")
        assert decision is False

    def test_always_returns_true(self):
        blocks = [_block(1, "a" * 5000)]  # density 5000, way above threshold
        decision, _reason = should_ocr(blocks, enabled="always")
        assert decision is True

    def test_auto_triggers_when_density_below_threshold(self):
        # 2 pages, 60 chars each → density 60 < default 100
        blocks = [_block(1, "a" * 60), _block(2, "b" * 60)]
        decision, reason = should_ocr(blocks, enabled="auto")
        assert decision is True
        assert "60" in reason  # the density appears in the reason

    def test_auto_does_not_trigger_at_or_above_threshold(self):
        # 1 page, 100 chars → density 100, NOT below threshold 100
        blocks = [_block(1, "a" * 100)]
        decision, _reason = should_ocr(blocks, enabled="auto", min_chars_per_page=100.0)
        assert decision is False

    def test_auto_threshold_is_configurable(self):
        # 1 page, 200 chars. Default would NOT trigger (200 >= 100).
        # With threshold raised to 500, should trigger.
        blocks = [_block(1, "a" * 200)]
        decision, _ = should_ocr(blocks, enabled="auto", min_chars_per_page=500.0)
        assert decision is True

    def test_invalid_enabled_value_raises(self):
        with pytest.raises(ValueError, match="enabled"):
            should_ocr([_block(1, "x")], enabled="sometimes")


class TestMaybeOcr:
    def test_non_pdf_input_passthrough(self, tmp_path):
        text_file = tmp_path / "notes.txt"
        text_file.write_text("hello")
        blocks = [_block(1, "anything")]
        new_blocks, result = maybe_ocr(str(text_file), blocks, tmp_path)
        assert new_blocks == blocks
        assert result.triggered is False
        assert result.reason == "not-pdf"
        assert result.ocr_pdf_path is None

    def test_high_density_pdf_passthrough(self, tmp_path):
        pdf = tmp_path / "born_digital.pdf"
        _write_text_pdf(pdf, "A" * 500)
        # Block-level density 500 chars / 1 page = 500. Well above default 100.
        blocks = [_block(1, "A" * 500)]
        new_blocks, result = maybe_ocr(str(pdf), blocks, tmp_path)
        assert new_blocks == blocks
        assert result.triggered is False
        assert "500" in result.reason

    def test_low_density_triggers_ocr_and_replaces_blocks(self, tmp_path, mocker):
        pdf = tmp_path / "scan.pdf"
        _write_image_only_pdf(pdf)

        def fake_run(input_path, output_path, **kwargs):
            # Stand in for ocrmypdf: write a text-bearing PDF to output_path.
            _write_text_pdf(output_path, "OCR-recovered content goes here.")

        run_mock = mocker.patch("ingest.ocr._run_ocrmypdf", side_effect=fake_run)
        mocker.patch("ingest.ocr._ocrmypdf_version", return_value="ocrmypdf-test-0.0.0")

        # Density 1, well below the default 100 threshold.
        blocks = [_block(1, "x")]
        new_blocks, result = maybe_ocr(str(pdf), blocks, tmp_path)

        assert run_mock.call_count == 1
        assert result.triggered is True
        assert result.ocr_pdf_path == tmp_path / "source.ocr.pdf"
        assert result.ocrmypdf_version == "ocrmypdf-test-0.0.0"
        # Block list should reflect the OCR'd PDF's content, not the input.
        assert any("OCR-recovered content" in b.text for b in new_blocks)
        assert new_blocks != blocks

    def test_cache_hit_avoids_running_ocrmypdf_again(self, tmp_path, mocker):
        pdf = tmp_path / "scan.pdf"
        _write_image_only_pdf(pdf)

        def fake_run(input_path, output_path, **kwargs):
            _write_text_pdf(output_path, "cached OCR output")

        run_mock = mocker.patch("ingest.ocr._run_ocrmypdf", side_effect=fake_run)
        mocker.patch("ingest.ocr._ocrmypdf_version", return_value="0.0.0")

        blocks = [_block(1, "x")]
        # First run — should invoke the binary.
        maybe_ocr(str(pdf), blocks, tmp_path)
        assert run_mock.call_count == 1
        # Second run — same PDF, same config — should be a cache hit.
        _, result2 = maybe_ocr(str(pdf), blocks, tmp_path)
        assert run_mock.call_count == 1
        assert result2.triggered is True
        assert "cache" in result2.reason.lower()

    def test_never_disabled_on_low_density_pdf_passthrough(self, tmp_path, mocker):
        pdf = tmp_path / "scan.pdf"
        _write_image_only_pdf(pdf)
        run_mock = mocker.patch("ingest.ocr._run_ocrmypdf")

        blocks = [_block(1, "x")]  # density 1
        new_blocks, result = maybe_ocr(str(pdf), blocks, tmp_path, enabled="never")

        assert run_mock.call_count == 0
        assert result.triggered is False
        assert new_blocks == blocks


class TestPipelineWiring:
    def test_ocr_is_a_valid_pipeline_step(self):
        from ingest.pipeline import VALID_STEPS

        assert "ocr" in VALID_STEPS
