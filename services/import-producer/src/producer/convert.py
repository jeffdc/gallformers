"""Phase 1: convert a PDF into a DoclingDocument (document.json).

OCR happens before Docling (producer.ocr), never inside it: Docling's own
tesseract step rotates pages on low-confidence orientation guesses. For scans,
fresh OCR is compared with the scan's existing text layer and the better text
is kept; Docling then reads the chosen PDF with its OCR off.
"""

import json
import time
from dataclasses import asdict
from pathlib import Path
from typing import Literal

from producer.document import load, render
from producer.ocr import choose, measure, reocr
from producer.pdfkind import Classification, classify_pdf
from producer.quality import report, text_layer_chars

OcrChoice = Literal["auto", "force", "off"]
OcrPlan = Literal["none", "compare", "fresh"]


def ocr_plan(kind: str, choice: OcrChoice) -> OcrPlan:
    """auto: born-digital PDFs keep their text; scans and image-only PDFs compare fresh OCR
    with their own text layer. force: always fresh OCR. off: never OCR."""
    if choice == "force":
        return "fresh"
    if choice == "off" or kind == "born_digital":
        return "none"
    return "compare"


def backend_for(kind: str):
    """Scans read through pdfium: Docling's default renderer smears layered (MRC) scan
    pages, so its layout model finds no regions and every line becomes its own item.
    Born-digital PDFs keep Docling's default backend. None means the default."""
    if kind == "born_digital":
        return None
    from docling.backend.pypdfium2_backend import PyPdfiumDocumentBackend

    return PyPdfiumDocumentBackend


def build_converter(kind: str):
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions
    from docling.document_converter import DocumentConverter, PdfFormatOption

    options = PdfPipelineOptions(do_ocr=False, do_table_structure=True)
    backend = backend_for(kind)
    pdf_format = (
        PdfFormatOption(pipeline_options=options, backend=backend)
        if backend
        else PdfFormatOption(pipeline_options=options)
    )
    return DocumentConverter(format_options={InputFormat.PDF: pdf_format})


def drop_off_page(doc) -> int:
    """Delete text items whose every box lies wholly outside its page; return how many.

    pdfium reports some glyphs on scans with a box above the page (lone "—" items in
    Gagné 2008, duplicates of dashes already in their paragraphs). Nothing printed
    outside the page can be content.
    """

    def outside(prov) -> bool:
        size = doc.pages[prov.page_no].size
        box = prov.bbox.to_top_left_origin(size.height)
        return box.b <= 0 or box.t >= size.height or box.r <= 0 or box.l >= size.width

    phantoms = [t for t in doc.texts if t.prov and all(outside(p) for p in t.prov)]
    if phantoms:
        doc.delete_items(node_items=phantoms)
    return len(phantoms)


def prepare_text(pdf: Path, out_dir: Path, plan: OcrPlan) -> tuple[Path, dict]:
    """The PDF whose text layer Docling should read, and the record of how it was chosen."""
    if plan == "none":
        return pdf, {"plan": plan}
    started = time.monotonic()
    fresh_pdf = reocr(pdf, out_dir / "ocr.pdf")
    layer, fresh = measure(pdf), measure(fresh_pdf)
    if plan == "fresh":
        decision = {"use": "fresh", "reason": "--ocr force"}
    else:
        decision = choose(layer, fresh)
    record = {
        "plan": plan,
        "layer": layer,
        "fresh": fresh,
        **decision,
        "seconds": round(time.monotonic() - started, 1),
    }
    return (fresh_pdf if decision["use"] == "fresh" else pdf), record


def convert(pdf: Path, out_dir: Path, ocr: OcrChoice = "auto") -> dict:
    """Write out_dir/document.json, document.txt and convert.json; return the phase 1 record."""
    out_dir.mkdir(parents=True, exist_ok=True)
    kind: Classification = classify_pdf(pdf)
    source, ocr_record = prepare_text(pdf, out_dir, ocr_plan(kind.kind, ocr))

    started = time.monotonic()
    result = build_converter(kind.kind).convert(source)
    seconds = round(time.monotonic() - started, 1)
    dropped = drop_off_page(result.document)

    document = out_dir / "document.json"
    result.document.save_as_json(document, ensure_ascii=False)
    doc = load(document)
    (out_dir / "document.txt").write_text(render(doc), encoding="utf-8")

    record = {
        "pdf": str(pdf),
        "classification": asdict(kind),
        "ocr": ocr_record,
        "backend": type(result.input._backend).__name__,
        "status": str(result.status),
        "seconds": seconds,
        "dropped_off_page_items": dropped,
        "quality": report(doc, text_layer_chars(source)),
    }
    (out_dir / "convert.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    return record


def convert_url(url: str, out_dir: Path) -> dict:
    """Phase 1 for a web page: Docling reads the HTML directly (no OCR, no PDF checks)."""
    from docling.document_converter import DocumentConverter

    out_dir.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    result = DocumentConverter().convert(url)
    seconds = round(time.monotonic() - started, 1)

    document = out_dir / "document.json"
    result.document.save_as_json(document, ensure_ascii=False)
    doc = load(document)
    (out_dir / "document.txt").write_text(render(doc), encoding="utf-8")

    record = {"url": url, "status": str(result.status), "seconds": seconds, "quality": report(doc)}
    (out_dir / "convert.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    return record
