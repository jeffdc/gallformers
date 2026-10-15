import pytest

from producer.convert import backend_for, drop_off_page, ocr_plan


@pytest.mark.parametrize(
    ("kind", "choice", "expected"),
    [
        ("born_digital", "auto", "none"),
        ("scanned", "auto", "compare"),  # fresh OCR vs the scan's own layer; the better text wins
        ("image_only", "auto", "compare"),
        ("born_digital", "force", "fresh"),
        ("scanned", "force", "fresh"),
        ("scanned", "off", "none"),
    ],
)
def test_ocr_plan(kind, choice, expected):
    assert ocr_plan(kind, choice) == expected


@pytest.mark.parametrize(
    ("kind", "expected"),
    [
        # docling-parse renders layered (MRC) scans as a smear and the layout model
        # then finds nothing (Felt 1917); pdfium renders them correctly
        ("scanned", "PyPdfiumDocumentBackend"),
        ("image_only", "PyPdfiumDocumentBackend"),
        ("born_digital", None),  # Docling's default
    ],
)
def test_backend_for(kind, expected):
    backend = backend_for(kind)
    assert (backend.__name__ if backend else None) == expected


def test_drop_off_page_removes_items_wholly_outside_their_page():
    """pdfium reports some dash glyphs on scans with a box above the page top (Gagné 2008);
    nothing printed outside the page can be content."""
    from docling_core.types.doc import BoundingBox, CoordOrigin, DocItemLabel, DoclingDocument
    from docling_core.types.doc.document import ProvenanceItem, Size

    def prov(left, top, right, bottom):  # top-left origin, page 400 x 600
        box = BoundingBox(l=left, t=top, r=right, b=bottom, coord_origin=CoordOrigin.TOPLEFT)
        return ProvenanceItem(page_no=1, bbox=box.to_bottom_left_origin(600), charspan=(0, 1))

    doc = DoclingDocument(name="scan")
    doc.add_page(page_no=1, size=Size(width=400, height=600))
    doc.add_text(label=DocItemLabel.TEXT, text="—", prov=prov(86, -5, 96, -1))
    doc.add_text(
        label=DocItemLabel.TEXT, text="Etymology. — The name", prov=prov(30, 135, 300, 150)
    )
    doc.add_text(label=DocItemLabel.TEXT, text="—", prov=prov(-30, 200, -20, 210))
    doc.add_text(label=DocItemLabel.TEXT, text="edge", prov=prov(390, 590, 410, 610))  # overlaps

    assert drop_off_page(doc) == 2
    assert [t.text for t in doc.texts] == ["Etymology. — The name", "edge"]
    assert doc.texts[1].self_ref == "#/texts/1"
