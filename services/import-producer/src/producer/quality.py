"""Phase-0 quality report: is this DoclingDocument good enough to quote from?"""

import re
from collections import Counter
from pathlib import Path

from producer.document import item_text, items

WORD = re.compile(r"\S+")
# Tokens a clean text rarely has: letters and digits mixed inside a word
# ("l0wer", "Q.1obata"), or characters outside ordinary scientific prose.
PROSE_SYMBOLS = (
    "‘’“”"  # curly quotes
    "&%/+±×⨯°§*?!<>=|©·♀♂µ"  # ± × ⨯ ° § © · ♀ ♂ µ
    "–—-"  # en dash, em dash, hyphen
)
SUSPICIOUS = re.compile(
    r"[A-Za-z][0-9]+[A-Za-z]|[0-9][A-Za-z]{2,}[0-9]|\b[01][a-z]{3,}"
    rf"|[^\w\s.,;:()\[\]'\"{re.escape(PROSE_SYMBOLS)}]"
)


def suspicious_rate(text: str) -> float:
    tokens = WORD.findall(text)
    if not tokens:
        return 0.0
    return sum(bool(SUSPICIOUS.search(t)) for t in tokens) / len(tokens)


def nonspace(text: str) -> int:
    """Characters other than whitespace. Scan text layers (BHL's especially) pad heavily with
    whitespace, so raw lengths make a document look like it lost text it didn't."""
    return sum(not c.isspace() for c in text)


def report(doc: dict, text_layer_chars: int | None = None) -> dict:
    """text_layer_chars: non-whitespace characters in the PDF's own text layer, if any."""
    labels: Counter[str] = Counter()
    body_chars_by_page: Counter[int] = Counter()
    body_text = []
    for item in items(doc):
        layer = item.get("content_layer", "body")
        labels[f"{item.get('label')}{'' if layer == 'body' else ' (' + layer + ')'}"] += 1
        if layer != "body":
            continue
        text = item_text(item)
        body_text.append(text)
        for prov in item.get("prov", [])[:1]:
            body_chars_by_page[prov["page_no"]] += nonspace(text)

    page_count = len(doc.get("pages", {}))
    empty_pages = [p for p in range(1, page_count + 1) if body_chars_by_page[p] < 100]
    body_chars = sum(nonspace(t) for t in body_text)
    result = {
        "pages": page_count,
        "items": sum(labels.values()),
        "labels": dict(labels.most_common()),
        "tables": len(doc.get("tables", [])),
        "body_chars_nonspace": body_chars,
        "pages_under_100_body_chars": empty_pages,
        "suspicious_token_rate": round(suspicious_rate("\n".join(body_text)), 4),
    }
    if text_layer_chars:
        result["text_layer_chars_nonspace"] = text_layer_chars
        result["coverage_vs_text_layer"] = round(body_chars / text_layer_chars, 3)
    return result


def text_layer_chars(pdf: Path) -> int:
    """Non-whitespace characters in the PDF's own text layer."""
    import pymupdf

    with pymupdf.open(pdf) as doc:
        return sum(nonspace(page.get_text()) for page in doc)
