"""A Gall's Gallformers note as a package (GALLFORMERS_STATEMENTS.md, "Reading a Gall's note").

`mix gallformers.import.notes` writes each note's package directory: document.json (the
note as one text item, #/texts/0) and note.json (the Gall, what identifies it, and the
date its statements take). `prepare` makes it ready for phase 3: document.txt, and the
taxonomy batch, which is always empty (a note states no taxonomic acts; its rulings go to
`unmapped`). Phases 3 to 6 then run as for any Source.
"""

import hashlib
import json
from pathlib import Path

from producer.document import load, render

NOTE_FILE = "note.json"


def is_note(package: Path) -> bool:
    return (package / NOTE_FILE).exists()


def read(package: Path) -> dict:
    return json.loads((package / NOTE_FILE).read_text(encoding="utf-8"))


def document(text: str, name: str) -> dict:
    """The note as a DoclingDocument: one body text item, #/texts/0, holding the whole text."""
    return {
        "schema_name": "DoclingDocument",
        "version": "1.7.0",
        "name": name,
        "furniture": {"self_ref": "#/furniture", "children": [], "content_layer": "furniture"},
        "body": {"self_ref": "#/body", "children": [{"$ref": "#/texts/0"}], "content_layer": "body"},
        "groups": [],
        "texts": [{
            "self_ref": "#/texts/0", "parent": {"$ref": "#/body"}, "children": [],
            "content_layer": "body", "label": "text", "prov": [], "orig": text, "text": text,
        }],
        "pictures": [],
        "tables": [],
        "pages": {},
    }  # fmt: skip


def source_block(package: Path) -> dict:
    data = read(package)
    sha = hashlib.sha256((package / "document.json").read_bytes()).hexdigest()
    return {
        "gallformers": True,
        "note": {
            "gallformers_gall_id": data["gallformers_gall_id"],
            "stated_on": data["stated_on"],
        },
        "document": {"file": "document.json", "sha256": sha},
    }


def gall_text(package: Path) -> str:
    """What the prompt tells the producer about the note's Gall."""
    data = read(package)
    inducer = data.get("inducer")
    lines = [
        f"- Gallformers ID (`gallformers_gall_id`): {data['gallformers_gall_id']}",
        f"- Name in Gallformers: {data['name']}",
        f"- Undescribed: {'yes' if data.get('undescribed') else 'no'}",
        f"- Inducer: {inducer['name']} ({inducer['rank']})" if inducer else "- Inducer: unknown",
        f"- Generation: {data.get('generation') or 'none'}",
        f"- Hosts: {', '.join(data.get('hosts') or []) or 'none recorded'}",
    ]
    return "\n".join(lines)


def prepare(package: Path) -> dict:
    """document.txt and the empty taxonomy batch, from document.json and note.json."""
    from producer.run import envelope

    (package / "document.txt").write_text(render(load(package / "document.json")), encoding="utf-8")
    taxonomy = {**envelope(package, 2), "taxa": [], "acts": []}
    (package / "taxonomy.json").write_text(
        json.dumps(taxonomy, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return {
        "note": read(package)["gallformers_gall_id"],
        "prepared": ["document.txt", "taxonomy.json"],
    }
