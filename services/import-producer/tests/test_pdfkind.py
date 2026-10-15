from producer.pdfkind import PageStats, classify


def pages(n, *, fonts=(), fullpage=False, chars=2000):
    return [PageStats(subset_fonts=frozenset(fonts), fullpage_image=fullpage, chars=chars)] * n


def test_born_digital_with_subset_fonts_and_no_page_images():
    assert classify(pages(10, fonts={"Times-Roman", "Times-Italic"})).kind == "born_digital"


def test_born_digital_with_some_plates_is_still_born_digital():
    doc = pages(60, fonts={"Times-Roman"}) + pages(15, fonts={"Times-Roman"}, fullpage=True)
    assert classify(doc).kind == "born_digital"


def test_scan_with_ocr_text_layer_is_scanned():
    # Text extracts fine from a scan's OCR layer; that alone must not make it born-digital.
    assert classify(pages(14, fullpage=True, chars=3000)).kind == "scanned"


def test_mostly_full_page_images_with_no_subset_fonts_is_scanned():
    doc = pages(20, fullpage=True) + pages(2)
    assert classify(doc).kind == "scanned"


def test_almost_no_text_needs_ocr():
    # Images smaller than the page, no usable text layer.
    assert classify(pages(38, fonts={"Arial"}, chars=150)).kind == "image_only"


def test_reports_its_evidence():
    result = classify(pages(4, fonts={"A", "B"}) + pages(1, fullpage=True))
    assert result.pages == 5
    assert result.subset_fonts == 2
    assert result.fullpage_image_pages == 1
    assert "subset fonts" in result.reason
