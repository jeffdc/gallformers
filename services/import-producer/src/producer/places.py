"""Map a Source's place name to Gallformers place codes (vocab/places.json)."""

import json
import unicodedata
from pathlib import Path

from producer.paths import VOCAB


def fold(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold().strip()


def load_places(path: Path = VOCAB / "places.json") -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["places"]


def lookup(query: str, places: list[dict], limit: int = 15) -> list[dict]:
    """Places whose code equals, or whose name contains, the query; best matches first."""
    q = fold(query)
    countries = {p["code"]: p["name"] for p in places if p["type"] == "country"}
    ranked = []
    for place in places:
        name = fold(place["name"])
        if fold(place["code"]) == q or name == q:
            rank = 0
        elif name.startswith(q):
            rank = 1
        elif q in name:
            rank = 2
        else:
            continue
        country = countries.get(place["code"].split("-", 1)[0], "")
        ranked.append((rank, place["name"], {**place, "country": country}))
    return [entry for *_, entry in sorted(ranked, key=lambda r: (r[0], r[1]))][:limit]
