import hashlib
import json
import re

import pytest

from producer import note
from producer.review import build_review_prompt
from producer.run import build_prompt, run_phase

TEXT = "Observed in Maryland in [September](https://bugguide.net/node/view/1184622)."


@pytest.fixture
def package(tmp_path):
    """A note package as `mix gallformers.import.notes` writes it: document.json and note.json."""
    doc = note.document(TEXT, "gallformers-note-1518")
    (tmp_path / "document.json").write_text(json.dumps(doc), encoding="utf-8")
    (tmp_path / "note.json").write_text(
        json.dumps({
            "gallformers_gall_id": 1518,
            "name": "Lasioptera solani",
            "undescribed": False,
            "inducer": {"name": "Lasioptera solani", "rank": "species"},
            "generation": None,
            "hosts": ["Solanum carolinense"],
            "stated_on": "2026-10-30",
        }),
        encoding="utf-8",
    )  # fmt: skip
    return tmp_path


def envelope(prompt):
    block = re.search(r"```json\n(\{\n  \"format\".*?)\n```", prompt, re.S).group(1)
    return json.loads(block)


def test_a_note_document_is_one_text_item():
    doc = note.document(TEXT, "n")
    assert [t["self_ref"] for t in doc["texts"]] == ["#/texts/0"]
    assert doc["texts"][0]["text"] == TEXT
    assert doc["body"]["children"] == [{"$ref": "#/texts/0"}]


def test_prepare_renders_the_note_and_writes_an_empty_taxonomy_batch(package):
    note.prepare(package)
    assert (
        (package / "document.txt")
        .read_text(encoding="utf-8")
        .startswith("#/texts/0 p? [text] Observed in Maryland")
    )
    taxonomy = json.loads((package / "taxonomy.json").read_text(encoding="utf-8"))
    assert taxonomy["batch_type"] == "taxonomy"
    assert taxonomy["mode"] == "add"
    assert taxonomy["taxa"] == [] and taxonomy["acts"] == []
    assert taxonomy["source"] == note.source_block(package)


def test_the_source_block_names_the_gall_date_and_document(package):
    sha = hashlib.sha256((package / "document.json").read_bytes()).hexdigest()
    assert note.source_block(package) == {
        "gallformers": True,
        "note": {"gallformers_gall_id": 1518, "stated_on": "2026-10-30"},
        "document": {"file": "document.json", "sha256": sha},
    }


def test_the_phase3_prompt_reads_a_note(package):
    note.prepare(package)
    prompt = build_prompt(package, 3)
    env = envelope(prompt)
    assert env["mode"] == "add"
    assert env["source"] == note.source_block(package)
    assert "Reading a Gall's note" in prompt
    assert "## priv/import/GALLFORMERS_STATEMENTS.md" in prompt
    assert "Lasioptera solani" in prompt and "Solanum carolinense" in prompt
    assert "Fill in the rest of `source`" not in prompt
    assert not re.search(r"\$[a-z_]+\b", prompt.split("# The contract")[0])


def test_a_document_prompt_is_unchanged(package):
    (package / "note.json").unlink()
    (package / "document.txt").write_text("#/texts/0 p1 [text] x\n", encoding="utf-8")
    prompt = build_prompt(package, 3)
    assert "Fill in the rest of `source`" in prompt
    assert "GALLFORMERS_STATEMENTS.md\n" not in prompt


def test_phase2_is_not_run_on_a_note(package):
    note.prepare(package)
    assert "blocked" in run_phase(package, 2, dry_run=True)


def test_the_reviewer_gets_the_note_rules(package):
    note.prepare(package)
    (package / "gall.json").write_text("{}", encoding="utf-8")
    assert "## priv/import/GALLFORMERS_STATEMENTS.md" in build_review_prompt(package)
