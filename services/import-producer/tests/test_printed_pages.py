from producer.document import printed_pages, render


def furniture(page, text):
    return {
        "self_ref": f"#/texts/{page}{len(text)}",
        "label": "page_header",
        "content_layer": "furniture",
        "text": text,
        "prov": [{"page_no": page}],
        "children": [],
    }


def make_doc(n_pages, headers):
    texts = [furniture(page, text) for page, text in headers]
    for i, t in enumerate(texts):
        t["self_ref"] = f"#/texts/{i}"
    return {
        "body": {"self_ref": "#/body", "children": [{"$ref": t["self_ref"]} for t in texts]},
        "texts": texts,
        "pages": {str(p): {} for p in range(1, n_pages + 1)},
    }


def test_offset_from_running_heads():
    doc = make_doc(
        5,
        [
            (2, "VOLUME 99, NUMBER 3"),
            (2, "561"),
            (3, "562 PROCEEDINGS OF THE ENTOMOLOGICAL SOCIETY"),
            (4, "VOLUME 99, NUMBER 3 563"),
        ],
    )
    assert printed_pages(doc) == {1: "~560", 2: "561", 3: "562", 4: "563", 5: "~564"}


def test_contradicting_page_is_left_out():
    doc = make_doc(4, [(1, "10"), (2, "11"), (3, "Plate 7"), (4, "13")])
    pages = printed_pages(doc)
    assert pages[1] == "10" and pages[4] == "13"
    assert 3 not in pages  # "7" contradicts the offset


def test_no_offset_without_two_agreeing_pages():
    assert printed_pages(make_doc(3, [(1, "506 Southeastern Naturalist")])) == {}


def test_years_and_volumes_are_not_page_numbers():
    doc = make_doc(3, [(1, "2007 Southeastern Naturalist"), (2, "2007"), (3, "Vol. 6")])
    assert printed_pages(doc) == {}


def test_render_shows_printed_page():
    doc = make_doc(3, [(1, "41"), (2, "42"), (3, "43")])
    assert render(doc).splitlines()[1] == "#/texts/1 p2=42 [page_header, furniture] 42"
