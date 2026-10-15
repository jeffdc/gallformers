import pytest


def cell(text, row, col, col_end=None):
    return {
        "text": text,
        "start_row_offset_idx": row,
        "end_row_offset_idx": row + 1,
        "start_col_offset_idx": col,
        "end_col_offset_idx": col_end if col_end is not None else col + 1,
    }


def prov(page):
    return [{"page_no": page, "bbox": {}, "charspan": [0, 0]}]


@pytest.fixture
def doc():
    """A small DoclingDocument dict with the shapes Docling actually produces."""
    spanning = cell("Hemiptera", 1, 0, col_end=2)
    return {
        "schema_name": "DoclingDocument",
        "body": {
            "self_ref": "#/body",
            "children": [
                {"$ref": "#/texts/0"},
                {"$ref": "#/texts/1"},
                {"$ref": "#/groups/0"},
                {"$ref": "#/tables/0"},
                {"$ref": "#/pictures/0"},
            ],
        },
        "furniture": {"self_ref": "#/furniture", "children": []},
        "groups": [
            {
                "self_ref": "#/groups/0",
                "children": [{"$ref": "#/texts/2"}, {"$ref": "#/texts/3"}],
                "label": "list",
            }
        ],
        "texts": [
            {
                "self_ref": "#/texts/0",
                "label": "page_header",
                "content_layer": "furniture",
                "text": "506 Southeastern Naturalist Vol. 6, No. 3",
                "prov": prov(2),
                "children": [],
            },
            {
                "self_ref": "#/texts/1",
                "label": "text",
                "content_layer": "body",
                "text": "Galls of Asphondylia were common on\nSolanum caro- linense leaves.",
                "prov": prov(2),
                "children": [],
            },
            {
                "self_ref": "#/texts/2",
                "label": "list_item",
                "content_layer": "body",
                "text": "Gargaphia solani",
                "prov": prov(3),
                "children": [],
            },
            {
                "self_ref": "#/texts/3",
                "label": "list_item",
                "content_layer": "body",
                "text": "Leptinotarsa juncta",
                "prov": prov(3) + prov(4),
                "children": [],
            },
            {
                "self_ref": "#/texts/4",
                "label": "caption",
                "content_layer": "body",
                "text": "Figure 1. A gall.",
                "prov": prov(5),
                "children": [],
            },
            {
                "self_ref": "#/texts/5",
                "label": "text",
                "content_layer": "body",
                "text": "An orphan not reachable from the body.",
                "prov": prov(9),
                "children": [],
            },
        ],
        "tables": [
            {
                "self_ref": "#/tables/0",
                "label": "table",
                "content_layer": "body",
                "prov": prov(4),
                "children": [],
                "data": {
                    "num_rows": 3,
                    "num_cols": 2,
                    "grid": [
                        [cell("Herbivore species", 0, 0), cell("Range", 0, 1)],
                        [spanning, spanning],
                        [cell("Gargaphia solani", 2, 0), cell("AL AZ AR", 2, 1)],
                    ],
                },
            }
        ],
        "pictures": [
            {
                "self_ref": "#/pictures/0",
                "label": "picture",
                "content_layer": "body",
                "prov": prov(5),
                "children": [{"$ref": "#/texts/4"}],
                "captions": [{"$ref": "#/texts/4"}],
            }
        ],
    }
