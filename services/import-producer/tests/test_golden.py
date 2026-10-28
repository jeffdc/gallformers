"""The golden regression set: export human verdicts, then score a new run against them."""

import copy
import json
from pathlib import Path

import pytest
from click.testing import CliRunner

from producer import golden
from producer.cli import cli

# ---------------------------------------------------------------- fixtures


def ev(quote, item="#/texts/1"):
    return [{"item": item, "quote": quote}]


def base_package():
    """A checked package in the trial's format: two generations of one wasp, a Host-only
    Gall, a taxonomy batch, and the dry run's name matches."""
    taxonomy = {
        "batch_type": "taxonomy",
        "taxa": [
            {"ref": "t1", "name_as_written": "ANDRICUS FOO", "name_reading": "Andricus foo", "rank": "species", "new": {"status": "new species"}},
            {"ref": "t2", "name_as_written": "Andricus", "rank": "genus"},
            {"ref": "t3", "name_as_written": "Cynips bar", "rank": "species"},
        ],
        "acts": [
            {"id": "a1", "stance": "confirm", "kind": "name", "taxon": "t1", "evidence": ev("ANDRICUS FOO, new species.")},
            {"id": "a2", "stance": "confirm", "kind": "placement", "taxon": "t1", "parent": "t2", "evidence": ev("Genus ANDRICUS")},
            {"id": "a3", "stance": "confirm", "kind": "synonymy", "name": "t3", "accepted": "t1", "evidence": ev("= Cynips bar")},
        ],
    }  # fmt: skip
    gall = {
        "batch_type": "gall",
        "taxa": [
            {"ref": "t1", "name_as_written": "ANDRICUS FOO", "name_reading": "Andricus foo", "rank": "species"},
            {"ref": "t2", "name_as_written": "Q. alba", "rank": "species"},
            {"ref": "t3", "name_as_written": "Quercus virens", "rank": "species"},
            {"ref": "t4", "name_as_written": "Synergus", "rank": "genus"},
        ],
        "galls": [
            {"ref": "g1", "name_as_written": "the agamic stem gall of A. foo",
             "identified_by": {"inducer": "t1", "generation": {"value": "agamic", "as_written": "agamic"}}},
            {"ref": "g2", "name_as_written": "the sexual leaf gall of A. foo",
             "identified_by": {"inducer": "t1", "generation": {"value": "sexgen", "as_written": "sexual"}}},
            {"ref": "g3", "name_as_written": "woody swelling of the limb of the live oak",
             "identified_by": {"host": "t3"}},
            {"ref": "g4", "name_as_written": "small woolly galls on live oak leaves",
             "identified_by": {"host": "t3"}},
        ],
        "facts": [
            {"id": "f1", "stance": "confirm", "kind": "relationship", "type": "inducer_of", "subject": "t1", "object": "g1", "evidence": ev("ANDRICUS FOO")},
            {"id": "f2", "stance": "confirm", "kind": "relationship", "type": "host_of", "subject": "t2", "object": "g1", "evidence": ev("on Q. alba")},
            {"id": "f3", "stance": "confirm", "kind": "trait", "gall": "g1", "trait": "color", "value": {"value": "red", "as_written": "reddish"}, "evidence": ev("reddish")},
            {"id": "f4", "stance": "confirm", "kind": "trait", "gall": "g1", "trait": "color", "value": {"value": "brown", "as_written": "brown"}, "evidence": ev("brown")},
            {"id": "f5", "stance": "confirm", "kind": "trait", "gall": "g1", "trait": "detachable", "value": {"value": "integral", "as_written": "in the stem"}, "evidence": ev("in the stem")},
            {"id": "f6", "stance": "confirm", "kind": "trait", "gall": "g2", "trait": "plant_part", "value": {"value": "lower leaf", "as_written": "under side"}, "evidence": ev("under side of the leaf")},
            {"id": "f7", "stance": "confirm", "kind": "trait", "gall": "g3", "trait": "season", "value": {"value": "Winter", "as_written": "in winter"}, "evidence": ev("found in winter")},
            {"id": "f8", "stance": "confirm", "kind": "trait", "gall": "g4", "trait": "texture", "value": {"value": "woolly", "as_written": "wooly"}, "evidence": ev("wooly galls")},
            {"id": "f9", "stance": "confirm", "kind": "relationship", "type": "inquiline_of", "subject": "t4", "object": "g3", "evidence": ev("Synergus lives in it")},
            {"id": "f10", "stance": "confirm", "kind": "description", "gall": "g1",
             "evidence": [{"item": "#/texts/2", "whole_item": True}, {"item": "#/texts/1", "quote": "A reddish swelling of the stem"}]},
            {"id": "f11", "stance": "confirm", "kind": "range", "gall": "g4", "adjustment": "include", "place": {"value": "MX", "as_written": "Mexico"}, "evidence": ev("also in Mexico")},
            {"id": "f12", "stance": "confirm", "kind": "relationship", "type": "host_of", "subject": "t3", "object": "g4",
             "evidence": ev("on live oak") + ev("QUERCUS ALBA. White Oak.", item="#/texts/3")},
            {"id": "f13", "stance": "confirm", "kind": "alias", "gall": "g2", "name": "Foo leaf gall", "evidence": ev("Foo leaf gall")},
        ],
    }  # fmt: skip
    dryrun = {
        "source_id": 7,
        "galls": {
            "g1": {"name_as_written": "the agamic stem gall of A. foo", "inducer": "ANDRICUS FOO", "generation": "agamic", "outcome": "resolved", "entries": ["Andricus foo (agamic)"]},
            "g2": {"name_as_written": "the sexual leaf gall of A. foo", "inducer": "ANDRICUS FOO", "generation": "sexgen", "outcome": "ambiguous", "entries": ["Andricus foo (sexgen)", "Callirhytis foo (sexgen)"]},
        },
    }  # fmt: skip
    document = {
        "schema_name": "DoclingDocument",
        "body": {"self_ref": "#/body", "children": []},
        "texts": [
            {"self_ref": "#/texts/0", "label": "text", "text": "Title", "prov": [{"page_no": 1}]},
            {"self_ref": "#/texts/1", "label": "text", "text": "A reddish swelling of the stem.", "prov": [{"page_no": 2}]},
            {"self_ref": "#/texts/2", "label": "text", "text": "Gall.-A hard, woody swelling, brown when old.", "prov": [{"page_no": 2}]},
            {"self_ref": "#/texts/3", "label": "text", "text": "QUERCUS ALBA. White Oak.", "prov": [{"page_no": 3}]},
        ],
        "pages": {"1": {}, "2": {}, "3": {}},
    }  # fmt: skip
    return {"taxonomy": taxonomy, "gall": gall, "dryrun": dryrun, "document": document}


def write_package(path: Path, pkg: dict) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    names = {"taxonomy": "taxonomy.json", "gall": "gall.json", "dryrun": "dryrun.json", "document": "document.json"}  # fmt: skip
    for key, name in names.items():
        if pkg.get(key) is not None:
            (path / name).write_text(json.dumps(pkg[key]), encoding="utf-8")
    return path


VERDICTS = {
    "gall-f1": {"verdict": "right"},
    "gall-f2": {"verdict": "right"},
    "gall-f3": {"verdict": "right"},
    "gall-f5": {"verdict": "right"},
    "gall-f6": {"verdict": "right"},
    "gall-f7": {"verdict": "wrong", "note": "Found in winter is not formed in winter."},
    "gall-f8": {"verdict": "unsure", "note": "Hard to say."},
    "gall-f9": {"verdict": "right"},
    "gall-f10": {"verdict": "right"},
    "gall-f11": {"verdict": "right"},
    "gall-f12": {"verdict": "wrong", "note": "The second passage is about a different gall."},
    "gall-f13": {"verdict": "right", "passing_mention": True},
    "taxonomy-a1": {"verdict": "right"},
    "taxonomy-a2": {"verdict": "right"},
    "taxonomy-a3": {"verdict": "right"},
    "name-g1": {"verdict": "right"},
    "name-g2": {"verdict": "unsure", "note": "Generation unclear."},
}

SPEC = golden.TrialSource(
    source_id=7,
    short="foo-1900",
    name="Foo 1900",
    package="7-foo-1900",
    checks="foo",
    check_page="https://example.org/check",
    revisions={
        "gall-f12": {
            "wrong_part": "evidence",
            "wrong_quotes": ["QUERCUS ALBA. White Oak."],
            "reason": "The Fact is right; the second evidence is about a different gall.",
        }
    },
)


def write_checks(path: Path, verdicts: dict) -> Path:
    checks = path / SPEC.checks / "checks"
    checks.mkdir(parents=True)
    for doc_id, v in verdicts.items():
        (checks / f"{doc_id}.json").write_text(
            json.dumps({"at": "2026-10-15T17:00:00Z", "note": "", **v}), encoding="utf-8"
        )
    return path


@pytest.fixture
def exported(tmp_path):
    trial = tmp_path / "trial"
    write_package(trial / SPEC.package, base_package())
    verdicts = write_checks(tmp_path / "verdicts", VERDICTS)
    return golden.export_source(SPEC, trial / SPEC.package, verdicts / SPEC.checks / "checks")


def score(exported, tmp_path, pkg, name="run"):
    run = write_package(tmp_path / name, pkg)
    return golden.score(exported, run)


def status(report, item_id):
    return next(r for r in report["items"] if r["id"] == item_id)


# ---------------------------------------------------------------- export


def test_export_keeps_every_verdict_with_self_contained_statements(exported):
    assert exported["source"] == {"id": 7, "name": "Foo 1900", "short": "foo-1900"}
    assert exported["package"] == "7-foo-1900"
    assert [i["id"] for i in exported["items"]][:3] == ["taxonomy-a1", "taxonomy-a2", "taxonomy-a3"]
    assert len(exported["items"]) == len(VERDICTS)

    f2 = next(i for i in exported["items"] if i["id"] == "gall-f2")
    assert f2["verdict"] == "right"
    statement = f2["statement"]
    assert statement["kind"] == "relationship" and statement["type"] == "host_of"
    assert statement["subject"]["taxon"]["name_as_written"] == "Q. alba"
    gall = statement["object"]["gall"]
    assert gall["inducer"]["name_reading"] == "Andricus foo"
    assert gall["generation"]["value"] == "agamic"
    assert gall["name_as_written"] == "the agamic stem gall of A. foo"
    assert statement["evidence"][0]["quote"] == "on Q. alba"
    assert statement["evidence"][0]["pdf_page"] == 2


def test_export_keeps_notes_passing_mentions_and_whole_item_text(exported):
    items = {i["id"]: i for i in exported["items"]}
    assert items["gall-f7"]["note"] == "Found in winter is not formed in winter."
    assert items["gall-f13"]["passing_mention"] is True
    desc = items["gall-f10"]["statement"]
    assert desc["evidence"][0]["text"] == "Gall.-A hard, woody swelling, brown when old."
    # The other values of a multi-valued Trait, to tell a replaced value from a dropped one.
    assert items["gall-f3"]["context"]["slot_values"] == ["brown", "red"]


def test_export_records_name_matches(exported):
    g2 = next(i for i in exported["items"] if i["id"] == "name-g2")
    assert g2["verdict"] == "unsure"
    assert g2["statement"]["outcome"] == "ambiguous"
    assert g2["statement"]["entries"] == ["Andricus foo (sexgen)", "Callirhytis foo (sexgen)"]
    assert g2["statement"]["gall"]["generation"]["value"] == "sexgen"


def test_export_applies_revisions_from_the_trial_log(exported):
    f12 = next(i for i in exported["items"] if i["id"] == "gall-f12")
    assert f12["verdict"] == "wrong"
    assert f12["wrong_part"] == "evidence"
    assert f12["revision"]["reason"].startswith("The Fact is right")


def test_export_can_revise_a_verdict(tmp_path):
    trial = tmp_path / "trial"
    write_package(trial / SPEC.package, base_package())
    verdicts = write_checks(tmp_path / "verdicts", VERDICTS)
    spec = golden.TrialSource(
        **{**SPEC.__dict__, "revisions": {"gall-f7": {"verdict": "right", "reason": "Recount."}}}
    )
    doc = golden.export_source(spec, trial / SPEC.package, verdicts / SPEC.checks / "checks")
    f7 = next(i for i in doc["items"] if i["id"] == "gall-f7")
    assert f7["verdict"] == "right"
    assert f7["revision"] == {"from": "wrong", "reason": "Recount."}
    assert doc["counts"]["statements"] == {"right": 13, "wrong": 1, "unsure": 1}


def test_export_fails_on_a_verdict_for_an_unknown_statement(tmp_path):
    trial = tmp_path / "trial"
    write_package(trial / SPEC.package, base_package())
    verdicts = write_checks(tmp_path / "verdicts", VERDICTS | {"gall-f99": {"verdict": "right"}})
    with pytest.raises(ValueError, match="gall-f99"):
        golden.export_source(SPEC, trial / SPEC.package, verdicts / SPEC.checks / "checks")


# ---------------------------------------------------------------- score


def test_the_checked_package_scores_all_present_against_itself(exported, tmp_path):
    report = score(exported, tmp_path, base_package())
    assert {r["status"] for r in report["items"]} == {"present"}
    assert report["summary"]["regressions"] == []
    assert [r["id"] for r in report["summary"]["not_fixed"]] == ["gall-f7", "gall-f12"]


def renumbered(pkg):
    """The same content with every local id renumbered and the lists reordered."""
    pkg = copy.deepcopy(pkg)
    gall = pkg["gall"]
    gmap = {"g1": "g4", "g2": "g3", "g3": "g2", "g4": "g1"}
    tmap = {"t1": "t4", "t2": "t3", "t3": "t2", "t4": "t1"}
    for t in gall["taxa"]:
        t["ref"] = tmap[t["ref"]]
    for g in gall["galls"]:
        g["ref"] = gmap[g["ref"]]
        g["identified_by"] = {
            k: (tmap[v] if k in ("inducer", "host") else v) for k, v in g["identified_by"].items()
        }
    n = len(gall["facts"])
    for i, f in enumerate(gall["facts"]):
        f["id"] = f"f{n - i + 20}"
        for k in ("subject", "object"):
            if k in f:
                f[k] = gmap.get(f[k]) or tmap.get(f[k])
        if "gall" in f:
            f["gall"] = gmap[f["gall"]]
    gall["facts"].reverse()
    gall["galls"].reverse()
    pkg["dryrun"]["galls"] = {gmap[k]: v for k, v in pkg["dryrun"]["galls"].items()}
    for a in pkg["taxonomy"]["acts"]:
        a["id"] = "a" + str(int(a["id"][1:]) + 10)
    return pkg


def test_matching_ignores_renumbered_ids(exported, tmp_path):
    report = score(exported, tmp_path, renumbered(base_package()))
    assert {r["status"] for r in report["items"]} == {"present"}
    mapping = {m["golden"]["ref"]: m["run"]["ref"] for m in report["galls"]}
    assert mapping == {"g1": "g4", "g2": "g3", "g3": "g2", "g4": "g1"}


def facts_of(pkg):
    return {f["id"]: f for f in pkg["gall"]["facts"]}


def test_a_changed_value_shows_both(exported, tmp_path):
    pkg = base_package()
    facts = facts_of(pkg)
    facts["f5"]["value"] = {"value": "detachable", "as_written": "falls off"}
    facts["f9"]["type"] = "parasitoid_of"
    facts["f3"]["value"] = {"value": "orange", "as_written": "orange"}  # red replaced
    report = score(exported, tmp_path, pkg)

    f5 = status(report, "gall-f5")
    assert f5["status"] == "changed"
    assert (f5["golden"], f5["run"]) == ("integral", "detachable")
    f9 = status(report, "gall-f9")
    assert f9["status"] == "changed"
    assert (f9["golden"], f9["run"]) == ("inquiline_of", "parasitoid_of")
    f3 = status(report, "gall-f3")
    assert f3["status"] == "changed"
    assert f3["run"] == ["orange"]
    assert [r["id"] for r in report["summary"]["regressions"]] == ["gall-f3", "gall-f5", "gall-f9"]


def test_a_denied_statement_is_a_change(exported, tmp_path):
    pkg = base_package()
    facts_of(pkg)["f2"]["stance"] = "deny"
    f2 = status(score(exported, tmp_path, pkg), "gall-f2")
    assert f2["status"] == "changed"
    assert "deny" in f2["run"]


def test_a_dropped_statement_is_missing(exported, tmp_path):
    pkg = base_package()
    pkg["gall"]["facts"] = [f for f in pkg["gall"]["facts"] if f["id"] not in ("f4", "f3", "f13")]
    pkg["taxonomy"]["acts"] = [a for a in pkg["taxonomy"]["acts"] if a["id"] != "a2"]
    report = score(exported, tmp_path, pkg)
    assert status(report, "gall-f3")["status"] == "missing"  # brown was there before: not a swap
    assert status(report, "gall-f13")["status"] == "missing"
    assert status(report, "taxonomy-a2")["status"] == "missing"
    assert [r["id"] for r in report["summary"]["regressions"]] == [
        "taxonomy-a2",
        "gall-f3",
        "gall-f13",
    ]


def test_a_wrong_statement_that_is_gone_is_fixed(exported, tmp_path):
    pkg = base_package()
    facts = facts_of(pkg)
    facts["f7"]["value"] = {"value": "Fall", "as_written": "autumn"}
    report = score(exported, tmp_path, pkg)
    f7 = status(report, "gall-f7")
    assert f7["status"] == "changed"
    assert f7["run"] == ["Fall"]
    assert [r["id"] for r in report["summary"]["fixed"]] == ["gall-f7"]
    assert [r["id"] for r in report["summary"]["not_fixed"]] == ["gall-f12"]

    pkg["gall"]["facts"] = [f for f in pkg["gall"]["facts"] if f["id"] != "f7"]
    report = score(exported, tmp_path, pkg, name="run2")
    assert status(report, "gall-f7")["status"] == "missing"
    assert [r["id"] for r in report["summary"]["fixed"]] == ["gall-f7"]


def test_a_wrong_citation_is_fixed_when_its_quote_goes(exported, tmp_path):
    pkg = base_package()
    facts_of(pkg)["f12"]["evidence"] = ev("on live oak")
    report = score(exported, tmp_path, pkg)
    assert status(report, "gall-f12")["status"] == "present"
    assert [r["id"] for r in report["summary"]["fixed"]] == ["gall-f12"]
    assert report["summary"]["regressions"] == []

    pkg["gall"]["facts"] = [f for f in pkg["gall"]["facts"] if f["id"] != "f12"]
    report = score(exported, tmp_path, pkg, name="run2")
    # The Fact itself was right: losing it is a regression, not a fix.
    assert [r["id"] for r in report["summary"]["regressions"]] == ["gall-f12"]


def test_a_gall_is_identified_by_inducer_and_generation(exported, tmp_path):
    pkg = base_package()
    facts = facts_of(pkg)
    facts["f6"]["gall"] = "g1"  # the leaf gall's plant part, now on the agamic gall
    report = score(exported, tmp_path, pkg)
    assert status(report, "gall-f6")["status"] == "missing"
    mapping = {m["golden"]["ref"]: m["run"]["ref"] for m in report["galls"]}
    assert mapping["g1"] == "g1" and mapping["g2"] == "g2"


def test_host_only_galls_are_told_apart_by_name(exported, tmp_path):
    pkg = base_package()
    g3, g4 = pkg["gall"]["galls"][2], pkg["gall"]["galls"][3]
    g3["ref"], g4["ref"] = "g4", "g3"
    for f in pkg["gall"]["facts"]:
        for k in ("gall", "object"):
            if f.get(k) in ("g3", "g4"):
                f[k] = {"g3": "g4", "g4": "g3"}[f[k]]
    g3["name_as_written"] = "woody swelling of a live oak limb"
    report = score(exported, tmp_path, pkg)
    assert {r["status"] for r in report["items"]} == {"present"}


def test_a_lost_gall_identity_is_reported(exported, tmp_path):
    pkg = base_package()
    pkg["gall"]["galls"][1]["identified_by"]["generation"] = {"value": "agamic", "as_written": "x"}
    pkg["gall"]["galls"][0]["identified_by"]["generation"] = {"value": "sexgen", "as_written": "y"}
    report = score(exported, tmp_path, pkg)
    # Galls follow their generation, not their position: the facts no longer match.
    assert status(report, "gall-f6")["status"] == "missing"
    assert status(report, "gall-f3")["status"] == "missing"


def test_names_match_through_abbreviations_and_ocr_readings(exported, tmp_path):
    pkg = base_package()
    taxa = {t["ref"]: t for t in pkg["gall"]["taxa"]}
    taxa["t2"]["name_as_written"] = "Quercus alba"
    taxa["t1"] = {"ref": "t1", "name_as_written": "Andricus foo", "rank": "species"}
    pkg["gall"]["taxa"] = list(taxa.values())
    report = score(exported, tmp_path, pkg)
    assert {r["status"] for r in report["items"]} == {"present"}


def test_an_old_include_adjustment_matches_a_recorded_occurrence(exported, tmp_path):
    pkg = base_package()
    f11 = facts_of(pkg)["f11"]
    del f11["adjustment"]
    f11["kind"] = "occurrence"
    report = score(exported, tmp_path, pkg)
    assert status(report, "gall-f11")["status"] == "present"
    assert any("include" in m for m in report["mappings"])


def test_a_rewritten_description_is_changed(exported, tmp_path):
    pkg = base_package()
    facts_of(pkg)["f10"]["evidence"] = ev("Title", item="#/texts/0")
    f10 = status(score(exported, tmp_path, pkg), "gall-f10")
    assert f10["status"] == "changed"
    assert f10["similarity"] < 0.5


def test_name_matches_compare_the_entries(exported, tmp_path):
    pkg = base_package()
    pkg["dryrun"]["galls"]["g2"] = {**pkg["dryrun"]["galls"]["g2"], "outcome": "resolved", "entries": ["Andricus foo (sexgen)"]}  # fmt: skip
    report = score(exported, tmp_path, pkg)
    g2 = status(report, "name-g2")
    assert g2["status"] == "changed"
    assert g2["run"] == {"outcome": "resolved", "entries": ["Andricus foo (sexgen)"]}
    assert [r["id"] for r in report["summary"]["unsure"]] == ["gall-f8", "name-g2"]


def test_name_matches_need_a_dry_run(exported, tmp_path):
    pkg = base_package()
    pkg["dryrun"] = None
    report = score(exported, tmp_path, pkg)
    assert status(report, "name-g1")["status"] == "not scored"
    assert report["summary"]["regressions"] == []


# ---------------------------------------------------------------- CLI


def test_cli_exports_and_scores(tmp_path):
    trial = write_package(tmp_path / "trial" / SPEC.package, base_package()).parent
    verdicts = write_checks(tmp_path / "verdicts", VERDICTS)
    out = tmp_path / "golden"
    runner = CliRunner()
    result = runner.invoke(
        cli,
        ["golden", "export", "--verdicts", str(verdicts), "--trial", str(trial), "--out", str(out)],
        obj={"sources": (SPEC,)},
    )
    assert result.exit_code == 0, result.output
    assert (out / "7-foo-1900.json").exists()

    run = write_package(tmp_path / "7-foo-1900-rerun", renumbered(base_package()))
    result = runner.invoke(cli, ["golden", "score", str(run), "--golden", str(out)])
    assert result.exit_code == 0, result.output
    assert "present" in result.output
    report = json.loads((run / "golden-score.json").read_text())
    assert report["source"]["id"] == 7

    elsewhere = tmp_path / "report.json"
    result = runner.invoke(
        cli,
        [
            "golden",
            "score",
            str(run),
            "--golden",
            str(out),
            "--source",
            "7",
            "--out",
            str(elsewhere),
        ],
    )
    assert result.exit_code == 0, result.output
    assert elsewhere.exists()


# ---------------------------------------------------------------- the real trial packages

TRIAL = golden.PROJECT / "output" / "trial"


@pytest.mark.skipif(not TRIAL.exists(), reason="the trial packages are local only")
@pytest.mark.parametrize("spec", golden.SOURCES, ids=lambda s: s.short)
def test_each_checked_package_scores_all_present_against_its_golden_file(spec, tmp_path):
    golden_file = golden.GOLDEN_DIR / f"{spec.source_id}-{spec.short}.json"
    doc = json.loads(golden_file.read_text(encoding="utf-8"))
    report = golden.score(doc, TRIAL / spec.package)
    assert [r for r in report["items"] if r["status"] != "present"] == []
