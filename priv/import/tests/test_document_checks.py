"""Layer 1, the document checks: what validate.py can verify from the package alone, no Gallformers data."""

import copy

from conftest import validate


def problems(package_dir, level="error"):
    return [p for lvl, p in validate.package_problems(package_dir) if lvl == level]


def test_clean_package(package):
    assert problems(package()) == []


def test_validate_main_reports_document_errors(package, batch, capsys):
    bad = copy.deepcopy(batch)
    bad["facts"][1]["evidence"][0]["quote"] = "Rare on Q. lobata"
    assert validate.main([str(package(gall=bad))]) == 1
    assert "quote not found" in capsys.readouterr().out


def test_quote_across_line_break_hyphen_and_whitespace(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][0]["evidence"].append({"item": "#/texts/1", "quote": "are globular  and pale tan"})
    assert problems(package(gall=b)) == []


def test_quote_in_another_item_names_it(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][1]["evidence"][0]["quote"] = "external parasitoid of the gall wasp larva"
    [error] = problems(package(gall=b))
    assert "facts/1/evidence/0" in error and "found in #/texts/3" in error


def test_missing_item(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][1]["evidence"][0]["item"] = "#/texts/99"
    assert any("#/texts/99 does not exist" in p for p in problems(package(gall=b)))


def test_quote_needs_an_item_when_there_is_a_document(package, batch):
    b = copy.deepcopy(batch)
    del b["facts"][1]["evidence"][0]["item"]
    assert any("needs an item" in p for p in problems(package(gall=b)))


def test_whole_item_needs_text(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][3]["evidence"][0]["item"] = "#/pictures/0"
    assert any("has no text" in p for p in problems(package(gall=b)))


def test_document_hash_mismatch(package, batch, tmp_path):
    pkg = package()
    (pkg / "document.json").write_text('{"changed": true}', encoding="utf-8")
    assert any("sha256" in p for p in problems(pkg))


def test_undeclared_refs(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][0]["subject"] = "t9"
    b["facts"][1]["object"] = "g7"
    errors = problems(package(gall=b))
    assert any("t9" in p for p in errors) and any("g7" in p for p in errors)


def test_duplicate_ids(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][1]["id"] = "f1"
    assert any("duplicate" in p and "f1" in p for p in problems(package(gall=b)))


def test_qualifier_type_must_be_allowed(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][3]["of"] = "f1"
    assert any("parasitism_mode" in p and "inducer_of" in p for p in problems(package(gall=b)))


def test_one_inducer_per_gall(package, batch):
    b = copy.deepcopy(batch)
    second = copy.deepcopy(b["facts"][0])
    second.update(id="f9", subject="t3")
    b["facts"].append(second)
    assert any("more than one inducer" in p for p in problems(package(gall=b)))


def test_new_gall_needs_a_fact(package, batch):
    b = copy.deepcopy(batch)
    b["galls"].append({"ref": "g2", "name_as_written": "x", "new": True, "identified_by": {"host": "t2"}})
    assert any("g2" in p and "no Facts" in p for p in problems(package(gall=b)))


def test_one_description_per_gall(package, batch):
    b = copy.deepcopy(batch)
    for fid in ("f7", "f8"):
        b["facts"].append({"id": fid, "stance": "confirm", "kind": "description", "gall": "g1",
                           "evidence": [{"item": "#/texts/1", "whole_item": True}]})
    assert any("more than one description" in p for p in problems(package(gall=b)))


def test_unused_taxon_is_a_warning(package, batch):
    b = copy.deepcopy(batch)
    b["taxa"].append({"ref": "t5", "name_as_written": "Quercus", "rank": "genus"})
    pkg = package(gall=b)
    assert problems(pkg) == []
    assert any("t5" in p for p in problems(pkg, "warning"))


def test_missing_document_is_an_error(package):
    pkg = package()
    (pkg / "document.json").unlink()
    assert any("document.json is missing" in p for p in problems(pkg))


def test_document_none_is_no_longer_allowed(package, batch):
    b = copy.deepcopy(batch)
    b["source"]["document"] = {"none": "scanned, unreadable"}
    pkg = package()
    import json

    (pkg / "gall.json").write_text(json.dumps(b), encoding="utf-8")
    assert any("source/document" in p for p in problems(pkg))


def above_family(taxonomy, kind, ranks, **fields):
    taxonomy["taxa"] += [
        {"ref": f"t{i}", "name_as_written": f"Taxon {i}", "rank": rank} for i, rank in enumerate(ranks, start=2)
    ]
    taxonomy["acts"].append({"id": "a2", "stance": "confirm", "kind": kind, **fields,
                             "evidence": [{"item": "#/texts/1", "quote": "Andricus quercuscalifornicus"}]})
    return taxonomy


def test_synonymy_above_family_is_rejected(package, taxonomy):
    tb = above_family(taxonomy, "synonymy", ["superfamily", "superfamily"], name="t3", accepted="t2")
    assert any("above family" in p for p in problems(package(gall=None, taxonomy=tb)))


def test_split_above_family_is_rejected(package, taxonomy):
    tb = above_family(taxonomy, "split", ["order", "order"], taxon="t2", into=["t2", "t3"])
    assert any("above family" in p for p in problems(package(gall=None, taxonomy=tb)))


def test_placement_above_family_is_fine(package, taxonomy):
    tb = above_family(taxonomy, "placement", ["superfamily", "family"], taxon="t3", parent="t2")
    assert problems(package(gall=None, taxonomy=tb)) == []


def test_empty_taxonomy_batch_validates(package, taxonomy):
    taxonomy["taxa"], taxonomy["acts"] = [], []
    assert problems(package(gall=None, taxonomy=taxonomy)) == []


def without_inducer_fact(batch, **gall_flags):
    b = copy.deepcopy(batch)
    b["facts"] = [f for f in b["facts"] if f["id"] != "f1" and f.get("of") != "f1"]
    b["galls"][0].update(gall_flags)
    return b


def named_inducer(messages):
    return [p for p in messages if "g1" in p and "t1" in p and "inducer_of" in p]


def test_a_new_gall_needs_its_inducer_fact(package, batch):
    """A Gall the batch introduces, identified by its Inducer, must state that Inducer (found when an
    edit removed the Fact but left identified_by naming it)."""
    pkg = package(gall=without_inducer_fact(batch, new=True))
    assert named_inducer(problems(pkg))
    pkg = package(gall=without_inducer_fact(batch, formerly_undescribed=True))
    assert named_inducer(problems(pkg))


def test_an_existing_gall_without_its_inducer_fact_is_a_warning(package, batch):
    """For a Gall Gallformers already holds, the Inducer in identified_by is how it is looked up."""
    pkg = package(gall=without_inducer_fact(batch))
    assert not named_inducer(problems(pkg))
    assert named_inducer(problems(pkg, level="warning"))


def occurrence(gall="g1"):
    return {"id": "f9", "stance": "confirm", "kind": "occurrence", "gall": gall,
            "place": {"value": "US-CA", "as_written": "throughout the hills"},
            "evidence": [{"item": "#/texts/2", "quote": "Common on Q. lobata throughout the hills"}]}


def test_occurrence_is_checked(package, batch):
    b = copy.deepcopy(batch)
    b["facts"].append(occurrence())
    assert problems(package(gall=b)) == []
    b["facts"][-1] = occurrence(gall="g7")
    assert any("facts/4" in p and "g7" in p for p in problems(package(gall=b)))


def test_an_occurrence_is_a_fact_about_a_new_gall(package, batch):
    b = copy.deepcopy(batch)
    b["galls"].append({"ref": "g2", "name_as_written": "x", "new": True, "identified_by": {"host": "t2"}})
    b["facts"].append(occurrence(gall="g2"))
    assert not any("no Facts" in p for p in problems(package(gall=b)))


def test_inducer_fact_must_name_the_identified_inducer(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][0]["subject"] = "t3"
    b["galls"][0]["new"] = True
    assert named_inducer(problems(package(gall=b)))
