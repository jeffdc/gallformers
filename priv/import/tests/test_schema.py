"""Layer 1, the schemas: every example is valid; each mutation is rejected or accepted as the contract says."""

import json

import pytest
from conftest import CONTRACT, EXAMPLES, as_v3, example


BATCHES = [p for p in sorted(EXAMPLES.glob("*/*.json")) if p.name != "document.json"]


@pytest.mark.parametrize("path", BATCHES, ids=lambda p: f"{p.parent.name}/{p.name}")
def test_examples_are_valid(path, schema_errors):
    batch = example(path.parent.name, path.name)
    assert schema_errors(batch) == []


@pytest.mark.parametrize("package", sorted(p for p in EXAMPLES.iterdir() if p.is_dir()), ids=lambda p: p.name)
def test_example_packages_pass_every_check(package):
    from conftest import validate

    errors = [m for level, m in validate.package_problems(package) if level == "error"]
    assert errors == []


def errors_mention(errors, *words):
    return any(all(w in e for w in words) for e in errors)


# -- rejections that predate the 2026-10-08 changes ------------------------------


def test_unknown_trait_category(paper, schema_errors):
    paper["facts"][5]["category"]["value"] = "beige"
    assert errors_mention(schema_errors(paper), "facts/5/category/value")


def test_controlled_value_needs_as_written(paper, schema_errors):
    # f5, a qualifier: controlled values other than Traits keep value + as_written.
    del paper["facts"][4]["value"]["as_written"]
    assert errors_mention(schema_errors(paper), "facts/4/value", "as_written")


def test_extra_property(paper, schema_errors):
    paper["facts"][0]["confidence"] = 0.9
    assert schema_errors(paper)


def test_host_of_needs_a_taxon_subject(paper, schema_errors):
    paper["facts"][1]["subject"] = "g2"
    assert errors_mention(schema_errors(paper), "facts/1/subject")


def test_whole_item_excludes_quote(paper, schema_errors):
    paper["facts"][10]["evidence"][1]["quote"] = "x"
    assert schema_errors(paper)


def test_unknown_rank(paper, schema_errors):
    paper["taxa"][0]["rank"] = "clade"
    assert errors_mention(schema_errors(paper), "taxa/0/rank")


# -- 2026-10-08: ranks above family -----------------------------------------------


@pytest.mark.parametrize("rank", ["kingdom", "phylum", "class", "order", "suborder", "superfamily"])
def test_ranks_above_family_are_accepted(paper, schema_errors, rank):
    paper["taxa"][3]["rank"] = rank
    assert schema_errors(paper) == []


# -- 2026-10-08: empty taxonomy batch means "states no acts" ----------------------


def test_empty_taxonomy_batch_is_valid(revision, schema_errors):
    revision["taxa"] = []
    revision["acts"] = []
    assert schema_errors(revision) == []


# -- 2026-10-08: new optional fields ----------------------------------------------


def test_status_as_written_on_acts(revision, schema_errors):
    revision["acts"][7]["status_as_written"] = "syn. nov."
    revision["acts"][0]["status_as_written"] = "nomen dubium"
    assert schema_errors(revision) == []
    revision["acts"][7]["status_as_written"] = ""
    assert errors_mention(schema_errors(revision), "status_as_written")


def test_name_reading_on_taxa(paper, schema_errors):
    paper["taxa"][0]["name_reading"] = "Andricus quercuscalifornicus"
    assert schema_errors(paper) == []
    paper["taxa"][0]["name_reading"] = ""
    assert errors_mention(schema_errors(paper), "name_reading")


def test_formerly_undescribed_on_galls(paper, schema_errors):
    paper["galls"][0]["formerly_undescribed"] = True
    assert schema_errors(paper) == []
    paper["galls"][0]["formerly_undescribed"] = "yes"
    assert errors_mention(schema_errors(paper), "formerly_undescribed")


def test_range_only_adjustment(paper, schema_errors):
    paper["facts"][8]["adjustment"] = "only"
    assert schema_errors(paper) == []
    paper["facts"][8]["adjustment"] = "mostly"
    assert errors_mention(schema_errors(paper), "adjustment")


def test_cites_on_quote_evidence(paper, schema_errors):
    paper["facts"][1]["evidence"][0]["cites"] = {"as_written": "Kinsey 1923"}
    assert schema_errors(paper) == []
    paper["facts"][1]["evidence"][0]["cites"] = {}
    assert errors_mention(schema_errors(paper), "cites")


# -- 2026-10-25: formats are checked, as Gallformers' importer checks them -------


def test_malformed_url_is_rejected(paper, schema_errors):
    paper["facts"][1]["evidence"][0]["url"] = "not a url"
    assert errors_mention(schema_errors(paper), "facts/1/evidence/0/url")


def test_malformed_produced_at_is_rejected(paper, schema_errors):
    paper["produced_at"] = "yesterday"
    assert errors_mention(schema_errors(paper), "produced_at")


# -- 2026-10-15: additions from the trial ----------------------------------------


def test_plant_part_in_identified_by(paper, schema_errors):
    """Tells apart two Galls of one Inducer on one Host (a collar gall and a spindle gall)."""
    paper["galls"][0]["identified_by"]["plant_part"] = {"value": "stem", "as_written": "collar of the stem"}
    assert schema_errors(paper) == []
    paper["galls"][0]["identified_by"]["plant_part"] = {"value": "trunk", "as_written": "trunk"}
    assert errors_mention(schema_errors(paper), "plant_part")


def test_sensu_on_taxa(revision, schema_errors):
    """A misapplied name: the Source's usage, not the author's species."""
    revision["taxa"][0]["sensu"] = "O. S. non Harris"
    assert schema_errors(revision) == []
    revision["taxa"][0]["sensu"] = ""
    assert errors_mention(schema_errors(revision), "sensu")


def test_common_name_act(revision, schema_errors):
    revision["acts"].append({
        "id": "a99", "stance": "confirm", "kind": "common_name", "taxon": "t3",
        "common_name": "exemplary oak gall wasp",
        "evidence": [{"item": "#/texts/120", "quote": "Andricus exemplaris Smith & Jones, sp. nov.", "page": "12"}],
    })  # fmt: skip
    assert schema_errors(revision) == []
    del revision["acts"][-1]["common_name"]
    assert errors_mention(schema_errors(revision), "common_name")


def test_taxonomic_act_unmapped_slot(revision, schema_errors):
    revision["unmapped"] = [{
        "term": "Syn. C. confluens Harris ?", "slot": "taxonomic_act",
        "evidence": [{"item": "#/texts/120", "quote": "Andricus exemplaris Smith & Jones, sp. nov.", "page": "12"}],
    }]  # fmt: skip
    assert schema_errors(revision) == []


# -- 2026-10-23: recorded occurrences --------------------------------------------


def occurrence(**fields):
    return {
        "id": "f99", "stance": "confirm", "kind": "occurrence", "gall": "g1",
        "place": {"value": "US-CA", "as_written": "Mt. Diablo, California"},
        "evidence": [{"item": "#/texts/42", "quote": "common on Q. lobata throughout the hills", "page": "58"}],
        **fields,
    }  # fmt: skip


def test_occurrence_with_place_only(paper, schema_errors):
    paper["facts"].append(occurrence())
    assert schema_errors(paper) == []


def test_occurrence_with_when_and_stage(paper, schema_errors):
    paper["facts"].append(occurrence(when_as_written="July 1961", stage_as_written="mature, adults emerging"))
    assert schema_errors(paper) == []


def test_occurrence_needs_a_place(paper, schema_errors):
    fact = occurrence()
    del fact["place"]
    paper["facts"].append(fact)
    assert errors_mention(schema_errors(paper), "place")


def test_occurrence_place_is_a_place_code(paper, schema_errors):
    paper["facts"].append(occurrence(place={"value": "Mt. Diablo", "as_written": "Mt. Diablo"}))
    assert errors_mention(schema_errors(paper), "place")


def test_occurrence_when_and_stage_are_not_empty(paper, schema_errors):
    paper["facts"].append(occurrence(when_as_written=""))
    assert errors_mention(schema_errors(paper), "when_as_written")
    paper["facts"][-1] = occurrence(stage_as_written="")
    assert errors_mention(schema_errors(paper), "stage_as_written")


def test_occurrence_takes_no_coordinates(paper, schema_errors):
    paper["facts"].append(occurrence(coordinates="37.88 N, 121.91 W"))
    assert errors_mention(schema_errors(paper), "facts/16", "coordinates")


# -- 2026-10-26: a Gall's range never leaves its Hosts' ranges --------------------


def test_range_include_adjustment_is_rejected(paper, schema_errors):
    # A place where the Gall occurs but no Host grows is a recorded occurrence.
    paper["facts"][8]["adjustment"] = "include"
    assert errors_mention(schema_errors(paper), "adjustment")


# -- 2026-10-30: Gallformers statements quoting a Gall's note ----------------------


def note_example():
    return example("gallformers-note")


def test_a_note_needs_its_document(schema_errors):
    batch = note_example()
    del batch["source"]["document"]
    assert errors_mention(schema_errors(batch), "source", "document")


def test_a_gallformers_document_needs_a_note(schema_errors):
    batch = note_example()
    del batch["source"]["note"]
    assert errors_mention(schema_errors(batch), "source", "note")


def test_a_note_names_its_gall_and_date(schema_errors):
    batch = note_example()
    del batch["source"]["note"]["stated_on"]
    assert errors_mention(schema_errors(batch), "stated_on")
    batch = note_example()
    batch["source"]["note"]["gallformers_gall_id"] = "587"
    assert errors_mention(schema_errors(batch), "gallformers_gall_id")


# -- 2026-10-27: generation groups -------------------------------------------------
# Which group applies to a Gall depends on its Inducer's taxon, which the validator can't
# see; Gallformers checks that on import. The validator checks the value is a generation.


def generation_vocab():
    traits = json.loads((CONTRACT / "vocab" / "traits.json").read_text(encoding="utf-8"))
    schema = json.loads((CONTRACT / "vocab" / "traits.schema.json").read_text(encoding="utf-8"))
    return traits["traits"]["generation"], set(schema["$defs"]["generation"]["enum"])


def test_unknown_generation_value_is_rejected(paper, schema_errors):
    paper["galls"][0]["identified_by"]["generation"] = {"value": "vernal", "as_written": "vernal generation"}
    assert errors_mention(schema_errors(paper), "galls/0/identified_by/generation")


def test_generation_needs_as_written(paper, schema_errors):
    del paper["galls"][0]["identified_by"]["generation"]["as_written"]
    assert errors_mention(schema_errors(paper), "as_written")


def test_every_generation_value_is_in_the_schema():
    generation, allowed = generation_vocab()
    listed = {v["value"] for v in generation["values"]}
    assert listed == allowed


def test_generation_groups_draw_on_the_schema_values_once_each():
    # A value names its group, so no value is in two groups.
    generation, allowed = generation_vocab()
    grouped = [value for group in generation.get("groups", []) for value in group["values"]]
    assert set(grouped) <= allowed
    assert len(grouped) == len(set(grouped))


# -- 2026-11-02: format v4, Traits carry the Source's term and a suggested category (d213) ----
# A trait Fact has `term` (the Source's term, verbatim) and `category` (a value of its Trait, or
# null when none fits), and may say `depends_on_gall`. Format v3 batches (value + as_written)
# still validate: packages already delivered are v3.


def test_examples_are_format_v4():
    assert {example(p.parent.name, p.name)["format_version"] for p in BATCHES} == {4}


def test_a_trait_fact_has_a_term_and_a_category(paper, schema_errors):
    assert paper["facts"][5]["term"] == "pale tan"
    assert paper["facts"][5]["category"] == {"value": "tan"}
    assert schema_errors(paper) == []


def test_no_category_when_none_fits(paper, schema_errors):
    paper["facts"][5]["category"] = None
    assert schema_errors(paper) == []


def test_the_category_is_required(paper, schema_errors):
    del paper["facts"][5]["category"]
    assert errors_mention(schema_errors(paper), "facts/5", "category")


def test_the_term_is_required_and_not_empty(paper, schema_errors):
    paper["facts"][5]["term"] = ""
    assert errors_mention(schema_errors(paper), "facts/5/term")
    del paper["facts"][5]["term"]
    assert errors_mention(schema_errors(paper), "facts/5", "term")


def test_the_category_is_only_a_value(paper, schema_errors):
    paper["facts"][5]["category"] = {"value": "tan", "as_written": "pale tan"}
    assert errors_mention(schema_errors(paper), "facts/5/category")


def test_depends_on_gall(paper, schema_errors):
    paper["facts"][5]["depends_on_gall"] = True
    assert schema_errors(paper) == []
    paper["facts"][5]["category"] = None
    assert schema_errors(paper) == []
    paper["facts"][5]["depends_on_gall"] = False
    assert errors_mention(schema_errors(paper), "facts/5/depends_on_gall")


def test_a_v4_trait_fact_takes_no_value(paper, schema_errors):
    paper["facts"][5]["value"] = {"value": "tan", "as_written": "pale tan"}
    assert errors_mention(schema_errors(paper), "facts/5", "value")


def test_v4_unmapped_takes_no_trait_slot(paper, schema_errors):
    # A Trait term that fits no value is a trait Fact with category null.
    entry = {"term": "lignified", "slot": "texture", "gall": "g1",
             "evidence": [{"item": "#/texts/44", "quote": "becoming lignified in the second year"}]}  # fmt: skip
    paper["unmapped"] = [entry]
    assert errors_mention(schema_errors(paper), "unmapped/0/slot")
    for slot in ("other", "generation", "place"):
        paper["unmapped"] = [{**entry, "slot": slot}]
        assert schema_errors(paper) == [], slot


def test_format_versions_3_and_4_only(paper, schema_errors):
    paper["format_version"] = 5
    assert errors_mention(schema_errors(paper), "format_version")


def test_a_v3_batch_still_validates(paper, schema_errors):
    v3 = as_v3(paper)
    assert v3["facts"][5]["value"] == {"value": "tan", "as_written": "pale tan"}
    assert schema_errors(v3) == []
    v3["unmapped"] = [{"term": "lignified", "slot": "texture", "gall": "g1",
                       "evidence": [{"item": "#/texts/44", "quote": "becoming lignified in the second year"}]}]  # fmt: skip
    assert schema_errors(v3) == []


def test_v3_unknown_trait_value(paper, schema_errors):
    v3 = as_v3(paper)
    v3["facts"][5]["value"]["value"] = "beige"
    assert errors_mention(schema_errors(v3), "facts/5/value/value")


def test_v3_trait_value_needs_as_written(paper, schema_errors):
    v3 = as_v3(paper)
    del v3["facts"][5]["value"]["as_written"]
    assert errors_mention(schema_errors(v3), "facts/5/value", "as_written")


def test_a_v3_trait_fact_takes_no_term(paper, schema_errors):
    v3 = as_v3(paper)
    v3["facts"][5]["term"] = "pale tan"
    assert errors_mention(schema_errors(v3), "facts/5", "term")


def test_taxonomy_batches_take_either_version(revision, schema_errors):
    for version in (3, 4):
        assert schema_errors({**revision, "format_version": version}) == []


# -- 2026-11-03: each unmapped entry's topic, for grouping the Hedges (d213) -------------------
# Optional: v4 packages delivered before it lack it, and the review shows those under "Other".


TOPICS = ("names", "inducer", "host", "range", "gall", "other")


def hedge(**fields):
    return {"term": "probably the same as C. confluens", "slot": "other", "gall": "g1",
            "evidence": [{"item": "#/texts/44", "quote": "becoming lignified in the second year"}], **fields}  # fmt: skip


def test_an_unmapped_entry_takes_a_topic(paper, schema_errors):
    for topic in TOPICS:
        paper["unmapped"] = [hedge(topic=topic)]
        assert schema_errors(paper) == [], topic
    paper["unmapped"] = [hedge()]
    assert schema_errors(paper) == []


def test_an_unknown_topic_is_rejected(paper, schema_errors):
    paper["unmapped"] = [hedge(topic="taxonomy")]
    assert errors_mention(schema_errors(paper), "unmapped/0/topic")


def test_topics_in_taxonomy_and_v3_batches(paper, revision, schema_errors):
    revision["unmapped"] = [{**hedge(topic="names"), "slot": "taxonomic_act"}]
    del revision["unmapped"][0]["gall"]
    assert schema_errors(revision) == []
    v3 = as_v3(paper)
    v3["unmapped"] = [hedge(topic="gall")]
    assert schema_errors(v3) == []


# -- 2026-11-03: a Host declared by its common name (d213 Task 6) ---------------


def test_a_host_declared_by_its_common_name(paper, schema_errors):
    """A common name never paired with a scientific name: the Source's words, no rank needed."""
    paper["taxa"][2] = {"ref": "t3", "name_as_written": "the black oak", "common_name": True}
    assert schema_errors(paper) == []
    paper["taxa"][2]["name_reading"] = "the black oak"
    paper["taxa"][2]["rank"] = "species"
    assert schema_errors(paper) == []


def test_a_scientific_name_still_needs_its_rank(paper, schema_errors):
    del paper["taxa"][2]["rank"]
    assert errors_mention(schema_errors(paper), "taxa/2", "rank")


def test_common_name_is_a_flag(paper, schema_errors):
    paper["taxa"][2]["common_name"] = "black oak"
    assert errors_mention(schema_errors(paper), "taxa/2/common_name")


@pytest.mark.parametrize("field,value", [("new", {"status": "sp. nov."}), ("sensu", "non Harris"), ("gallformers_taxon_id", 7)])
def test_a_common_name_takes_no_scientific_claims(paper, schema_errors, field, value):
    paper["taxa"][2] = {"ref": "t3", "name_as_written": "the black oak", "common_name": True, field: value}
    assert errors_mention(schema_errors(paper), "taxa/2")
    del paper["taxa"][2]["common_name"]
    paper["taxa"][2]["rank"] = "species"
    assert schema_errors(paper) == []


# -- 2026-11-06: a Gallformers statement citing a Source (curation, ec2c) -----------


def statement_example():
    return example("gallformers-statement")


def test_cites_on_statement_evidence(schema_errors):
    batch = statement_example()
    evidence = batch["facts"][1]["evidence"][0]
    evidence["cites"] = {"as_written": "Weld 1959", "source_id": 42}
    assert schema_errors(batch) == []
    evidence["cites"] = {"as_written": "Weld 1959"}
    assert schema_errors(batch) == []


def test_cites_on_statement_evidence_needs_as_written(schema_errors):
    batch = statement_example()
    batch["facts"][1]["evidence"][0]["cites"] = {"source_id": 42}
    assert errors_mention(schema_errors(batch), "cites")
    batch["facts"][1]["evidence"][0]["cites"] = {"as_written": "Weld 1959", "source_id": "42"}
    assert errors_mention(schema_errors(batch), "source_id")


def test_cites_on_quote_evidence_takes_no_source_id(paper, schema_errors):
    paper["facts"][1]["evidence"][0]["cites"] = {"as_written": "Kinsey 1923", "source_id": 42}
    assert errors_mention(schema_errors(paper), "cites")
