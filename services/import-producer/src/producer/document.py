"""Read a DoclingDocument (as JSON) and render it for the producer.

Works on the JSON dict rather than docling's classes, so the batch checks and
the renderer read document.json exactly as Gallformers will.
"""

import json
import re
from collections import Counter
from collections.abc import Iterator
from pathlib import Path

ITEM_ARRAYS = ("texts", "tables", "pictures")


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve(doc: dict, ref: str) -> dict | None:
    """The item a reference like '#/texts/42' points at, or None."""
    parts = ref.split("/")
    if len(parts) != 3 or parts[0] != "#" or not parts[2].isdigit():
        return None
    array = doc.get(parts[1])
    index = int(parts[2])
    if not isinstance(array, list) or index >= len(array):
        return None
    return array[index]


def items(doc: dict) -> Iterator[dict]:
    """Every content item: body reading order first, then any orphans in array order."""
    seen: set[str] = set()

    def walk(node: dict) -> Iterator[dict]:
        for child in node.get("children", []):
            item = resolve(doc, child["$ref"])
            if item is None or item["self_ref"] in seen:
                continue
            seen.add(item["self_ref"])
            if item["self_ref"].split("/")[1] in ITEM_ARRAYS:
                yield item
            yield from walk(item)

    yield from walk(doc["body"])
    yield from walk(doc.get("furniture", {}))
    for array in ITEM_ARRAYS:
        for item in doc.get(array, []):
            if item["self_ref"] not in seen:
                seen.add(item["self_ref"])
                yield item


def table_rows(table: dict) -> list[str]:
    """Each row's cells joined with ' | ' (the guide's quote convention for table rows).

    A cell spanning several columns appears once.
    """
    rows = []
    for row in table.get("data", {}).get("grid", []):
        cells = [c["text"] for col, c in enumerate(row) if c["start_col_offset_idx"] == col]
        rows.append(" | ".join(cells))
    return rows


def item_text(item: dict) -> str:
    if "data" in item:
        return "\n".join(table_rows(item))
    return item.get("text", "")


PAGE_NUMBER = re.compile(r"^\s*(\d{1,4})\b|\b(\d{1,4})\s*$")


def printed_pages(doc: dict) -> dict[int, str]:
    """PDF page -> page number as printed, from numbers at the ends of running heads.

    One offset (printed - PDF page) must be supported by at least two pages. A
    page whose own heads confirm it gets the number; a page with no number in
    its heads gets it marked inferred ("~560"); a page whose heads contradict
    the offset (a plate, a reset) gets nothing.
    """
    candidates: dict[int, set[int]] = {}
    for item in items(doc):
        if item.get("content_layer") != "furniture" or not item.get("prov"):
            continue
        page = item["prov"][0]["page_no"]
        for match in PAGE_NUMBER.finditer(item.get("text", "")):
            candidates.setdefault(page, set()).add(int(match.group(1) or match.group(2)))

    offsets = Counter(n - page for page, numbers in candidates.items() for n in numbers)
    if not offsets:
        return {}
    offset, support = offsets.most_common(1)[0]
    if support < 2:
        return {}

    result = {}
    for page in sorted(int(p) for p in doc.get("pages", {})):
        expected = page + offset
        if page not in candidates:
            result[page] = f"~{expected}"
        elif expected in candidates[page]:
            result[page] = str(expected)
    return result


def pages(item: dict, printed: dict[int, str] | None = None) -> str:
    """'p12' (PDF page index), with '=515' appended when the printed page is known."""
    numbers = sorted({p["page_no"] for p in item.get("prov", [])})
    if not numbers:
        return "p?"
    first, last = numbers[0], numbers[-1]
    pdf = f"p{first}" if first == last else f"p{first}-{last}"
    printed = printed or {}
    if first in printed and last in printed:
        pdf += f"={printed[first]}" if first == last else f"={printed[first]}-{printed[last]}"
    return pdf


def render(doc: dict) -> str:
    """One line per item: '<ref> <pdf page>[=<printed page>] [<label>] <text>'; table rows below."""
    printed = printed_pages(doc)
    lines = []
    for item in items(doc):
        label = item.get("label", "?")
        if item.get("content_layer") == "furniture":
            label += ", furniture"
        head = f"{item['self_ref']} {pages(item, printed)} [{label}]"
        if "data" in item:
            lines.append(head)
            lines.extend(f"    {row}" for row in table_rows(item))
        else:
            text = " ".join(item.get("text", "").split())
            lines.append(f"{head} {text}" if text else head)
    return "\n".join(lines) + "\n"
