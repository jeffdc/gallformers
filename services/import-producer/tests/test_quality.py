import pymupdf

from producer.quality import nonspace, report, suspicious_rate, text_layer_chars


def test_suspicious_rate_flags_ocr_damage():
    assert suspicious_rate("Galls on Quercus lobata leaves.") == 0
    assert suspicious_rate("Galls on Q.1obata l0wer leaves") == 0.4


def test_nonspace_ignores_whitespace():
    assert nonspace("Galls  of\n\n Asphondylia ") == len("GallsofAsphondylia")


def test_report_counts_labels_and_layers(doc):
    doc["pages"] = {str(n): {} for n in range(1, 10)}
    result = report(doc, text_layer_chars=400)
    assert result["labels"]["page_header (furniture)"] == 1
    assert result["labels"]["list_item"] == 2
    assert result["tables"] == 1
    assert 1 in result["pages_under_100_body_chars"]
    assert result["coverage_vs_text_layer"] == round(result["body_chars_nonspace"] / 400, 3)


def test_coverage_is_not_fooled_by_padded_whitespace(doc, tmp_path):
    """A BHL-style text layer padded with whitespace must not look like lost text."""
    body = "".join(t["text"] for t in doc["texts"] if t["content_layer"] == "body")
    body += "".join(c["text"] for row in doc["tables"][0]["data"]["grid"] for c in row)
    pdf = pymupdf.open()
    page = pdf.new_page()
    padded = "   \n  ".join(body.split()) + "\n\n\n"
    box = pymupdf.Rect(20, 20, page.rect.width - 20, page.rect.height - 20)
    assert page.insert_textbox(box, padded, fontsize=6) >= 0
    path = tmp_path / "padded.pdf"
    pdf.save(path)
    layer = text_layer_chars(path)
    assert layer == nonspace(body)
    assert report(doc, text_layer_chars=layer)["coverage_vs_text_layer"] >= 0.95
