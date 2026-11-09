"""Layer 1, the document checks: what validate.py can verify from the package alone, no Gallformers data."""

import copy
import json

from conftest import example, validate


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


def note_batch(batch):
    """`batch` as Gallformers statements quoting a Gall's note: the `document` fixture's #/texts/2."""
    b = copy.deepcopy(batch)
    b["mode"] = "add"
    b["source"] = {
        "gallformers": True,
        "note": {"gallformers_gall_id": 587, "stated_on": "2026-10-30"},
        "document": {"file": "document.json", "sha256": "0" * 64},
    }
    b["facts"] = [b["facts"][1]]
    b["facts"][0]["evidence"][0]["item"] = "#/texts/0"
    del b["taxa"][2]
    return b


def note_document(document, text="Common on Q. lobata throughout the hills; earlier records from Q. douglasii are misidentifications."):
    doc = copy.deepcopy(document)
    doc["texts"] = [{**doc["texts"][2], "self_ref": "#/texts/0", "text": text}]
    doc["body"]["children"] = [{"$ref": "#/texts/0"}]
    doc["tables"], doc["pictures"] = [], []
    return doc


def test_a_note_batch_quotes_its_note(package, batch, document):
    assert problems(package(doc=note_document(document), gall=note_batch(batch))) == []


def test_a_note_batch_takes_no_statement_evidence(package, batch, document):
    b = note_batch(batch)
    b["facts"][0]["evidence"] = [{"statement": {"text": "Seen on Q. lobata.", "stated_on": "2026-10-30"}}]
    assert any("quotes its note" in p for p in problems(package(doc=note_document(document), gall=b)))


def test_a_note_document_is_one_text_item(package, batch, document):
    assert any(
        "one text item" in p for p in problems(package(doc=document, gall=note_batch(batch)))
    )


def test_statements_without_a_note_are_unchanged(package, batch):
    b = note_batch(batch)
    b["source"] = {"gallformers": True}
    b["facts"][0]["evidence"] = [{"statement": {"text": "Seen on Q. lobata.", "stated_on": "2026-10-30"}}]
    pkg = package(gall=None)
    (pkg / "gall.json").write_text(json.dumps(b), encoding="utf-8")
    assert problems(pkg) == []


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


# -- 2026-11-02: format v4, a trait Fact's term is the Source's own words (d213) --------------


def test_a_v4_package_is_clean(package, batch_v4):
    assert problems(package(gall=batch_v4)) == []


def test_the_term_is_in_its_evidence(package, batch_v4):
    b = copy.deepcopy(batch_v4)
    b["facts"][4]["term"] = "light brown"
    [error] = problems(package(gall=b))
    assert "facts/4" in error and "term" in error and "light brown" in error


def test_the_term_is_matched_as_quotes_are_and_ignoring_case(package, batch_v4):
    b = copy.deepcopy(batch_v4)
    b["facts"][4].update(trait="shape", term="Globular", category={"value": "globular"})
    b["facts"][4]["evidence"] = [{"item": "#/texts/1", "quote": "are globular  and pale tan"}]
    assert problems(package(gall=b)) == []
    b["facts"][4]["term"] = "glob- ular"
    assert problems(package(gall=b)) == []


def test_the_term_may_come_from_a_whole_item(package, batch_v4):
    b = copy.deepcopy(batch_v4)
    b["facts"][4]["term"] = "large stem galls"
    b["facts"][4]["evidence"] = [{"item": "#/texts/1", "whole_item": True}]
    assert problems(package(gall=b)) == []


def test_a_statement_term_is_not_checked(package, batch_v4):
    """Without a document there is nothing to find the term in."""
    b = copy.deepcopy(batch_v4)
    b["source"] = {"gallformers": True}
    b["mode"] = "add"
    for f in b["facts"]:
        f["evidence"] = [{"statement": {"text": "Seen on Q. lobata.", "stated_on": "2026-10-30"}}]
    pkg = package(gall=None)
    (pkg / "gall.json").write_text(json.dumps(b), encoding="utf-8")
    assert problems(pkg) == []


# -- 2026-11-03: a Host declared by its common name (d213 Task 6) ---------------


def common_name_host(b, ref="t2"):
    for t in b["taxa"]:
        if t["ref"] == ref:
            t.clear()
            t.update(ref=ref, name_as_written="the black oak", common_name=True)
    return b


def test_a_common_name_may_be_a_host(package, batch):
    b = common_name_host(copy.deepcopy(batch))
    b["galls"][0]["identified_by"]["host"] = "t2"
    assert problems(package(gall=b)) == []


def test_a_common_name_is_only_ever_a_host(package, batch):
    b = common_name_host(copy.deepcopy(batch), "t1")
    errors = problems(package(gall=b))
    assert any("t1" in p and "common name" in p and "Host" in p for p in errors), errors


def test_a_common_name_takes_no_taxonomic_act(package, taxonomy):
    taxonomy["taxa"][0] = {"ref": "t1", "name_as_written": "the black oak", "common_name": True}
    errors = problems(package(gall=None, taxonomy=taxonomy))
    assert any("t1" in p and "common name" in p for p in errors), errors


# -- a reading fix (matter 87a1): a held Source's statements, read again --------------


def reading_package(tmp_path, gall):
    """A reading fix's package: its gall batch alone (no document: its quotes are the stored Source's)."""
    (tmp_path / "gall.json").write_text(json.dumps(gall), encoding="utf-8")
    return tmp_path


def test_a_reading_fix_passes(tmp_path):
    assert problems(reading_package(tmp_path, example("reading-fix"))) == []


def test_unstated_and_replaces_only_in_a_reading_fix(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][0]["unstated"] = True
    b["facts"][1]["replaces"] = "f1"
    errors = problems(package(gall=b))
    assert any("facts/0" in p and "only in a reading fix" in p for p in errors)
    assert any("facts/1" in p and "only in a reading fix" in p for p in errors)


def test_a_gallformers_item_id_only_in_a_reading_fix(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][0]["evidence"][0]["gallformers_document_item_id"] = 7
    assert any("gallformers_document_item_id" in p and "only in a reading fix" in p for p in problems(package(gall=b)))


def test_replaces_names_an_unstated_fact_of_the_batch(tmp_path):
    b = example("reading-fix")
    b["facts"][1]["replaces"] = "f9"
    errors = problems(reading_package(tmp_path, b))
    assert any("replaces f9, which is not an unstated Fact in this batch" in p for p in errors)


def test_an_unstated_fact_replaces_nothing(tmp_path):
    b = example("reading-fix")
    b["facts"][0]["replaces"] = "f2"
    errors = problems(reading_package(tmp_path, b))
    assert any("facts/0" in p and "an unstated Fact replaces nothing" in p for p in errors)


def test_a_reading_fix_may_quote_a_whole_stored_item(tmp_path):
    b = example("reading-fix")
    b["facts"][1]["evidence"] = [{"whole_item": True, "gallformers_document_item_id": 1234}]
    assert problems(reading_package(tmp_path, b)) == []


def test_a_reading_fix_may_say_why(tmp_path):
    b = example("reading-fix")
    b["source"]["reading_of"]["why"] = "Weld names Q. lobata; we read the next line."
    assert problems(reading_package(tmp_path, b)) == []
    b["source"]["reading_of"]["why"] = ""
    assert any("why" in p for p in problems(reading_package(tmp_path, b)))


def reading_taxonomy(tmp_path, acts, accept=False):
    """A taxonomic reading fix's package: its taxonomy batch alone."""
    reading_of = {"gallformers_source_id": 59}
    if accept:
        reading_of["accept"] = True
    tb = {
        "format": "gallformers-import", "format_version": 4, "vocabulary_version": "2026-10-11",
        "batch_type": "taxonomy", "mode": "add", "batch_id": "0b5e3a52-6d0f-4c41-9d6e-1f2a3b4c5d07",
        "produced_at": "2026-11-08T14:00:00Z", "producer": {"name": "gallformers-curation", "version": "1"},
        "source": {"reading_of": reading_of},
        "taxa": [
            {"ref": "t1", "name_as_written": "Aphis rubifolii", "rank": "species"},
            {"ref": "t2", "name_as_written": "Aphis", "rank": "genus"},
            {"ref": "t3", "name_as_written": "Amphorophora", "rank": "genus"},
        ],
        "acts": acts,
    }
    (tmp_path / "taxonomy.json").write_text(json.dumps(tb), encoding="utf-8")
    return tmp_path


QUOTE = [{"quote": "Aphis rubifolii", "gallformers_document_item_id": 7, "page": "3"}]


def test_a_taxonomic_reading_fix_passes(tmp_path):
    acts = [
        {"id": "a1", "stance": "confirm", "kind": "placement", "taxon": "t1", "parent": "t2", "unstated": True, "evidence": QUOTE},
        {"id": "a2", "stance": "confirm", "kind": "placement", "taxon": "t1", "parent": "t3", "replaces": "a1", "evidence": QUOTE},
    ]
    assert problems(reading_taxonomy(tmp_path, acts, accept=True)) == []


def test_unstated_and_replaces_acts_only_in_a_reading_fix(package, taxonomy):
    tb = copy.deepcopy(taxonomy)
    tb["acts"][0]["unstated"] = True
    errors = problems(package(gall=None, taxonomy=tb))
    assert any("acts/0" in p and "only in a reading fix" in p for p in errors), errors


def test_a_replacing_act_names_an_unstated_act(tmp_path):
    acts = [{"id": "a1", "stance": "confirm", "kind": "placement", "taxon": "t1", "parent": "t3", "replaces": "a9", "evidence": QUOTE}]
    errors = problems(reading_taxonomy(tmp_path, acts))
    assert any("replaces a9, which is not an unstated act in this batch" in p for p in errors), errors


def test_a_reading_fix_of_a_source_with_no_quotes_carries_none(tmp_path):
    b = example("reading-fix")
    for fact in b["facts"]:
        fact["evidence"] = []
    assert problems(reading_package(tmp_path, b)) == []


def test_evidence_is_needed_outside_a_reading_fix(package, batch):
    b = copy.deepcopy(batch)
    b["facts"][0]["evidence"] = []
    assert any("facts/0" in p and "evidence" in p and "at least one" in p for p in problems(package(gall=b)))


def test_accept_is_only_for_a_reading_fix_of_taxonomy(tmp_path):
    b = example("reading-fix")
    b["source"]["reading_of"]["accept"] = True
    assert any("accept" in p for p in problems(reading_package(tmp_path, b)))
