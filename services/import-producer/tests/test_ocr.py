import shutil

import pymupdf
import pytest

from producer.ocr import choose, dictionary_rate, reocr

LAYER = {"nonspace": 38969, "dictionary_rate": 0.776, "suspicious_rate": 0.0067}


def test_dictionary_rate_counts_real_words():
    # "galls" is only in the word list as "gall": plurals count via the singular
    assert dictionary_rate("the galls were common on leaves") == 1.0
    # 5 words of 4+ letters, 3 real (galls, common, leaves)
    assert dictionary_rate("the galls wcre common on lcaves leaves") == pytest.approx(0.6)


def test_dictionary_rate_ignores_short_and_capitalized_words():
    # Latin names and abbreviations would otherwise count as misspellings
    assert dictionary_rate("Quercus alba Q. on oak galls") == 1.0


def test_fresh_wins_when_clearly_better():
    fresh = {"nonspace": 38681, "dictionary_rate": 0.807, "suspicious_rate": 0.0027}
    decision = choose(LAYER, fresh)
    assert decision["use"] == "fresh"


def test_tie_keeps_the_existing_layer():
    fresh = {"nonspace": 38969, "dictionary_rate": 0.781, "suspicious_rate": 0.0018}
    assert choose(LAYER, fresh)["use"] == "layer"


def test_fresh_that_loses_text_is_rejected():
    fresh = {"nonspace": 30000, "dictionary_rate": 0.9, "suspicious_rate": 0.001}
    decision = choose(LAYER, fresh)
    assert decision["use"] == "layer" and "text" in decision["reason"]


def test_no_usable_layer_uses_fresh():
    empty = {"nonspace": 0, "dictionary_rate": None, "suspicious_rate": 0.0}
    fresh = {"nonspace": 5000, "dictionary_rate": 0.7, "suspicious_rate": 0.01}
    assert choose(empty, fresh)["use"] == "fresh"


@pytest.mark.skipif(shutil.which("tesseract") is None, reason="needs tesseract")
def test_reocr_replaces_text_hidden_under_the_page_image(tmp_path):
    """Some BHL scans draw their old OCR as ordinary text covered by the page image.
    Fresh OCR must read the whole image and leave none of that old text behind."""
    words = pymupdf.open()
    words.new_page(width=400, height=200).insert_text(
        (30, 100), "Galls on the leaves of white oak", fontsize=20
    )
    image = words[0].get_pixmap(dpi=300).tobytes("png")

    scan = pymupdf.open()
    page = scan.new_page(width=400, height=200)
    page.insert_text((30, 100), "Gnlls ou tlie lcaves", fontsize=20)  # the old OCR, underneath
    page.insert_image(page.rect, stream=image)
    scan.save(tmp_path / "scan.pdf")

    text = pymupdf.open(reocr(tmp_path / "scan.pdf", tmp_path / "ocr.pdf"))[0].get_text()
    assert "leaves of white oak" in " ".join(text.split())
    assert "tlie" not in text
