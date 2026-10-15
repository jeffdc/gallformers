from producer.document import item_text, items, render, resolve, table_rows


def test_resolve_ref(doc):
    assert resolve(doc, "#/texts/2")["text"] == "Gargaphia solani"
    assert resolve(doc, "#/texts/99") is None
    assert resolve(doc, "#/nonsense/0") is None


def test_items_follow_reading_order_then_orphans(doc):
    refs = [i["self_ref"] for i in items(doc)]
    assert refs == [
        "#/texts/0",
        "#/texts/1",
        "#/texts/2",
        "#/texts/3",
        "#/tables/0",
        "#/pictures/0",
        "#/texts/4",
        "#/texts/5",
    ]


def test_table_rows_join_cells_and_collapse_spans(doc):
    assert table_rows(doc["tables"][0]) == [
        "Herbivore species | Range",
        "Hemiptera",
        "Gargaphia solani | AL AZ AR",
    ]


def test_item_text(doc):
    assert item_text(doc["texts"][2]) == "Gargaphia solani"
    assert item_text(doc["tables"][0]).splitlines()[2] == "Gargaphia solani | AL AZ AR"
    assert item_text(doc["pictures"][0]) == ""


def test_render_one_line_per_item_with_ref_page_and_label(doc):
    lines = render(doc).splitlines()
    assert (
        lines[0]
        == "#/texts/0 p2 [page_header, furniture] 506 Southeastern Naturalist Vol. 6, No. 3"
    )
    assert (
        lines[1]
        == "#/texts/1 p2 [text] Galls of Asphondylia were common on Solanum caro- linense leaves."
    )
    assert "#/texts/3 p3-4 [list_item] Leptinotarsa juncta" in lines


def test_render_tables_as_indented_rows(doc):
    lines = render(doc).splitlines()
    start = lines.index("#/tables/0 p4 [table]")
    assert lines[start + 1 : start + 4] == [
        "    Herbivore species | Range",
        "    Hemiptera",
        "    Gargaphia solani | AL AZ AR",
    ]


def test_render_pictures_without_text(doc):
    assert "#/pictures/0 p5 [picture]" in render(doc).splitlines()
