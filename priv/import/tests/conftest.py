"""Fixtures for the validator tests.

Run: uv run --with pytest --with "jsonschema>=4.18" --with "referencing>=0.30" pytest priv/import/tests
"""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path

import pytest

CONTRACT = Path(__file__).resolve().parents[1]
EXAMPLES = CONTRACT / "examples"


def _load_validate():
    spec = importlib.util.spec_from_file_location("validate", CONTRACT / "validate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validate = _load_validate()


@pytest.fixture(scope="session")
def schema_errors():
    registry, schemas = validate.load_registry()
    return lambda batch: validate.schema_errors(batch, registry, schemas)


def example(name: str, batch: str = "gall.json") -> dict:
    return json.loads((EXAMPLES / name / batch).read_text(encoding="utf-8"))


@pytest.fixture
def paper():
    """A fresh copy of the simple-paper gall batch, safe to mutate."""
    return copy.deepcopy(example("simple-paper"))


@pytest.fixture
def revision():
    return copy.deepcopy(example("revision", "taxonomy.json"))


def _prov(page):
    return [{"page_no": page, "bbox": {}, "charspan": [0, 0]}]


def _text(i, text, label="text", layer="body", page=1):
    return {
        "self_ref": f"#/texts/{i}",
        "label": label,
        "content_layer": layer,
        "text": text,
        "prov": _prov(page),
        "children": [],
    }


def _cell(text, row, col, col_end=None):
    return {
        "text": text,
        "start_row_offset_idx": row,
        "end_row_offset_idx": row + 1,
        "start_col_offset_idx": col,
        "end_col_offset_idx": col_end if col_end is not None else col + 1,
    }


@pytest.fixture
def document():
    """A small DoclingDocument with the shapes Docling produces (texts, a table, a picture)."""
    texts = [
        _text(0, "58 Journal of Examples", "page_header", "furniture"),
        _text(1, "The large stem galls produced by the agamic generation of Andricus quercuscalifornicus are glob-\nular and pale tan when mature."),
        _text(2, "Common on Q. lobata throughout the hills; earlier records from Q. douglasii are misidentifications."),
        _text(3, "Torymus developed as an external parasitoid of the gall wasp larva."),
        _text(4, "Figure 1. A gall."),
    ]
    header = [_cell("Species", 0, 0), _cell("Count", 0, 1), _cell("Note", 0, 2)]
    row = [_cell("Torymus sp.", 1, 0), _cell("14", 1, 1), _cell("reared", 1, 2)]
    spanning = _cell("Parasitoids", 2, 0, col_end=3)
    return {
        "schema_name": "DoclingDocument",
        "body": {"self_ref": "#/body", "children": [{"$ref": f"#/texts/{i}"} for i in range(4)]
                 + [{"$ref": "#/tables/0"}, {"$ref": "#/pictures/0"}]},
        "furniture": {"self_ref": "#/furniture", "children": []},
        "groups": [],
        "texts": texts,
        "tables": [{
            "self_ref": "#/tables/0", "label": "table", "content_layer": "body", "prov": _prov(2),
            "children": [], "data": {"grid": [header, row, [spanning, spanning, spanning]]},
        }],
        "pictures": [{
            "self_ref": "#/pictures/0", "label": "picture", "content_layer": "body", "prov": _prov(2),
            "children": [{"$ref": "#/texts/4"}], "captions": [{"$ref": "#/texts/4"}],
        }],
    }


@pytest.fixture
def batch():
    """A gall batch whose evidence points into the `document` fixture."""
    return {
        "format": "gallformers-import", "format_version": 3, "vocabulary_version": "2026-10-07",
        "batch_type": "gall", "mode": "replace", "batch_id": "00000000-test-0001",
        "produced_at": "2026-10-08T00:00:00Z", "producer": {"name": "test", "version": "0"},
        "source": {
            "kind": "publication", "title": "T", "authors": ["A"],
            "authored": {"date": "2024", "as_written": "2024"}, "citation": "A. 2024. T.",
            "license": {"value": "CC-BY", "as_written": "CC BY 4.0"},
            "document": {"file": "document.json", "sha256": "0" * 64},
        },
        "taxa": [
            {"ref": "t1", "name_as_written": "Andricus quercuscalifornicus", "rank": "species"},
            {"ref": "t2", "name_as_written": "Q. lobata", "rank": "species"},
            {"ref": "t3", "name_as_written": "Torymus", "rank": "genus"},
        ],
        "galls": [{"ref": "g1", "name_as_written": "the large stem galls",
                   "identified_by": {"inducer": "t1", "generation": {"value": "agamic", "as_written": "agamic generation"}}}],
        "facts": [
            {"id": "f1", "stance": "confirm", "kind": "relationship", "type": "inducer_of", "subject": "t1", "object": "g1",
             "evidence": [{"item": "#/texts/1", "quote": "produced by the agamic generation of Andricus quercuscalifornicus"}]},
            {"id": "f2", "stance": "confirm", "kind": "relationship", "type": "host_of", "subject": "t2", "object": "g1",
             "evidence": [{"item": "#/texts/2", "quote": "Common on Q. lobata throughout the hills"}]},
            {"id": "f3", "stance": "confirm", "kind": "relationship", "type": "parasitoid_in", "subject": "t3", "object": "g1",
             "evidence": [{"item": "#/tables/0", "quote": "Torymus sp. | 14 | reared"}]},
            {"id": "f4", "stance": "confirm", "kind": "qualifier", "of": "f3", "qualifier": "parasitism_mode",
             "value": {"value": "ecto", "as_written": "external parasitoid"},
             "evidence": [{"item": "#/texts/3", "whole_item": True}]},
        ],
    }


@pytest.fixture
def taxonomy(batch):
    """A taxonomy batch (same Source as `batch`) whose evidence points into the `document` fixture."""
    tb = {k: copy.deepcopy(v) for k, v in batch.items() if k not in ("taxa", "galls", "facts")}
    tb["batch_type"] = "taxonomy"
    tb["taxa"] = [{"ref": "t1", "name_as_written": "Andricus quercuscalifornicus", "rank": "species"}]
    tb["acts"] = [{"id": "a1", "stance": "confirm", "kind": "name", "taxon": "t1",
                   "evidence": [{"item": "#/texts/1", "quote": "Andricus quercuscalifornicus"}]}]
    return tb


@pytest.fixture
def package(tmp_path, document, batch):
    """Write a package with a correct sha256 in each batch; returns a writer.

    gall defaults to the `batch` fixture; pass gall=None to leave it out.
    """
    default = object()

    def write(doc=None, gall=default, taxonomy=None):
        doc_bytes = json.dumps(doc if doc is not None else document).encode()
        (tmp_path / "document.json").write_bytes(doc_bytes)
        sha = hashlib.sha256(doc_bytes).hexdigest()
        batches = {"gall.json": batch if gall is default else gall, "taxonomy.json": taxonomy}
        for name, content in batches.items():
            if content is None:
                continue
            content = copy.deepcopy(content)
            content["source"]["document"]["sha256"] = sha
            (tmp_path / name).write_text(json.dumps(content), encoding="utf-8")
        return tmp_path

    return write
