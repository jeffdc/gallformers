import hashlib
import json
import re

import pytest

from producer.review import (
    blind,
    build_review_prompt,
    merge_reviews,
    missing_placements,
    review_command,
    stage,
)


@pytest.fixture
def package(tmp_path, doc):
    pkg = tmp_path / "pkg"
    pkg.mkdir()
    (pkg / "document.json").write_text(json.dumps(doc), encoding="utf-8")
    (pkg / "document.txt").write_text(
        "#/texts/1 p2 [text] Galls of Asphondylia\n", encoding="utf-8"
    )
    (pkg / "taxonomy.json").write_text('{"acts": []}', encoding="utf-8")
    (pkg / "gall.json").write_text('{"facts": [{"id": "f1"}]}', encoding="utf-8")
    (pkg / "notes-phase3.md").write_text("producer's private reasoning", encoding="utf-8")
    (pkg / "phase3.prompt.md").write_text("producer prompt", encoding="utf-8")
    return pkg


def test_stage_copies_only_the_package_files(package, tmp_path):
    work = tmp_path / "work"
    work.mkdir()
    stage(package, work)
    assert sorted(p.name for p in work.iterdir()) == [
        "document.json",
        "document.txt",
        "gall.json",
        "taxonomy.json",
    ]


def test_prompt_fixes_reviewed_hashes_and_carries_the_guides(package):
    prompt = build_review_prompt(package)
    assert not re.search(r"\$[a-z_]+\b", prompt.split("# The contract")[0])
    fixed = json.loads(re.search(r"```json\n(\{.*?\})\n```", prompt, re.S).group(1))
    for name in ("taxonomy.json", "gall.json"):
        assert fixed["reviewed"][name] == hashlib.sha256((package / name).read_bytes()).hexdigest()
    assert fixed["reviewers"] == [
        {
            "model": "claude-opus-5-5",
            "instructions_version": fixed["reviewers"][0]["instructions_version"],
        }
    ]
    assert "## priv/import/VERIFY_GUIDE.md" in prompt
    assert "## priv/import/schema/review.schema.json" in prompt
    assert '{"facts": [{"id": "f1"}]}' in prompt
    assert "producer's private reasoning" not in prompt


def test_phase5_waits_for_phase4(package, monkeypatch):
    import producer.review as review

    monkeypatch.setattr(
        review, "validate", lambda pkg, review=False: {"exit": 1, "output": "INVALID"}
    )
    monkeypatch.setattr(review.subprocess, "run", lambda *a, **k: pytest.fail("phase 5 ran"))
    record = review.run_review(package)
    assert record["blocked"].startswith("phase 4 fails")
    assert not (package / "phase5.prompt.md").exists()


def test_reviewer_has_no_shell(tmp_path):
    cmd = review_command("high")
    assert cmd[cmd.index("--tools") + 1] == "Read,Write,Grep"
    assert "--allowedTools" not in cmd
    assert "--safe-mode" in cmd and "--bare" not in cmd


def test_reviewer_model_can_be_chosen(package):
    """A cheaper reviewer can be tried; the review records which model reviewed."""
    cmd = review_command("high", model="claude-sonnet-5-5")
    assert cmd[cmd.index("--model") + 1] == "claude-sonnet-5-5"
    prompt = build_review_prompt(package, model="claude-sonnet-5-5")
    fixed = json.loads(re.search(r"```json\n(\{.*?\})\n```", prompt, re.S).group(1))
    assert fixed["reviewers"][0]["model"] == "claude-sonnet-5-5"


def one_review(model, *ids, reviewed=None):
    return {
        "format": "gallformers-review",
        "reviewed": reviewed or {"gall.json": "a" * 64},
        "reviewers": [{"model": model, "instructions_version": "verifier.md@x"}],
        "findings": [
            {"batch": "gall.json", "id": i, "problem": "unsupported", "reason": "r"} for i in ids
        ],
    }


def test_merge_reviews_keeps_every_finding_and_names_its_reviewer():
    merged = merge_reviews([one_review("opus", "f1", "f2"), one_review("sonnet", "f2")])
    assert [m["model"] for m in merged["reviewers"]] == ["opus", "sonnet"]
    assert [(f["id"], f["reviewer"]) for f in merged["findings"]] == [
        ("f1", "opus"), ("f2", "opus"), ("f2", "sonnet")
    ]  # fmt: skip


def test_merge_reviews_needs_the_same_batches():
    with pytest.raises(ValueError, match="different batches"):
        merge_reviews([one_review("opus"), one_review("sonnet", reviewed={"gall.json": "b" * 64})])


# -- format v4: the reviewer places every trait term blind (d213) ---------------------------

TRAIT = {"id": "f2", "stance": "confirm", "kind": "trait", "gall": "g1", "trait": "shape",
         "term": "swelling", "category": {"value": "abrupt swelling"}, "depends_on_gall": True,
         "evidence": [{"item": "#/texts/1", "quote": "swelling"}]}  # fmt: skip
HOST = {"id": "f1", "kind": "relationship", "type": "host_of", "subject": "t1", "object": "g1"}


def v4_gall(*facts):
    return {"format_version": 4, "facts": list(facts or (HOST, TRAIT))}


@pytest.fixture
def v4_package(package):
    (package / "gall.json").write_text(json.dumps(v4_gall()), encoding="utf-8")
    return package


def test_blind_drops_the_producers_categories_only():
    blinded = blind(v4_gall())
    assert blinded["facts"][0] == HOST
    assert blinded["facts"][1] == {
        k: v for k, v in TRAIT.items() if k not in ("category", "depends_on_gall")
    }
    assert TRAIT["category"] == {"value": "abrupt swelling"}  # the batch itself is untouched


def test_stage_gives_the_reviewer_a_blind_gall_batch(v4_package, tmp_path):
    work = tmp_path / "work"
    work.mkdir()
    stage(v4_package, work)
    staged = json.loads((work / "gall.json").read_text(encoding="utf-8"))
    assert "category" not in staged["facts"][1] and "depends_on_gall" not in staged["facts"][1]
    assert json.loads((v4_package / "gall.json").read_text(encoding="utf-8")) == v4_gall()


def test_the_prompt_shows_the_blind_batch_but_fixes_the_real_hash(v4_package):
    prompt = build_review_prompt(v4_package)
    batches = prompt.split("# The batches")[1].split("# The document")[0]
    assert '"term": "swelling"' in batches
    assert "abrupt swelling" not in batches and "depends_on_gall" not in batches
    fixed = json.loads(re.search(r"```json\n(\{.*?\})\n```", prompt, re.S).group(1))
    assert (
        fixed["reviewed"]["gall.json"]
        == hashlib.sha256((v4_package / "gall.json").read_bytes()).hexdigest()
    )


def test_a_v3_batch_is_staged_as_it_is(package, tmp_path):
    work = tmp_path / "work"
    work.mkdir()
    stage(package, work)
    assert (work / "gall.json").read_bytes() == (package / "gall.json").read_bytes()


def test_merge_reviews_keeps_each_reviewers_placements():
    opus = one_review("opus") | {
        "placements": [{"id": "f2", "category": {"value": "abrupt swelling"}}]
    }
    sonnet = one_review("sonnet") | {
        "placements": [{"id": "f2", "category": None, "depends_on_gall": True}]
    }
    merged = merge_reviews([opus, sonnet])
    assert merged["placements"] == [
        {"id": "f2", "category": {"value": "abrupt swelling"}, "reviewer": "opus"},
        {"id": "f2", "category": None, "depends_on_gall": True, "reviewer": "sonnet"},
    ]
    assert "placements" not in merge_reviews([one_review("opus")])


def test_missing_placements_are_listed_per_reviewer():
    review = merge_reviews([
        one_review("opus") | {"placements": [{"id": "f2", "category": None}]},
        one_review("sonnet") | {"placements": []},
    ])  # fmt: skip
    assert missing_placements(v4_gall(), review) == {"sonnet": ["f2"]}
    assert missing_placements({"format_version": 3, "facts": [TRAIT]}, review) == {}


def test_version_follows_the_verify_guide(package, contract):
    from conftest import edit

    def version():
        prompt = build_review_prompt(package)
        return re.search(r'"instructions_version": "([^"]+)"', prompt).group(1)

    before = version()
    assert before.startswith("verifier.md@")
    edit(contract / "VERIFY_GUIDE.md")
    assert version() != before
