"""The readiness gate (`validate.py --review`): phase 5 (review) and phase 6 (the producer's response).

A package is ready when review.json is well-formed, covers the batches as they now stand, and either
has no findings or every finding has a phase 6 response. Disputed findings (the producer disagrees)
don't block: they are reported for human review at intake. Plain `validate.py` (phase 4) never looks
at the review."""

import hashlib
import json

from conftest import validate


def found(package_dir, review=True):
    return validate.package_problems(package_dir, review=review)


def problems(package_dir, review=True):
    return [p for level, p in found(package_dir, review) if level == "error"]


def warnings(package_dir):
    return [p for level, p in found(package_dir) if level == "warning"]


def hashes(pkg):
    return {
        name: hashlib.sha256((pkg / name).read_bytes()).hexdigest()
        for name in ("taxonomy.json", "gall.json")
        if (pkg / name).exists()
    }


def write_review(pkg, findings=(), responded=False, **override):
    data = {"format": "gallformers-review", "reviewed": hashes(pkg), "findings": list(findings), **override}
    if responded:
        data["responded"] = {"result": hashes(pkg)}
    (pkg / "review.json").write_text(json.dumps(data), encoding="utf-8")
    return pkg


FINDING = {"batch": "gall.json", "id": "f2", "problem": "wrong_value", "reason": "the quote says Q. douglasii"}


def answered(decision, ident="f2"):
    return {**FINDING, "id": ident, "response": {"decision": decision, "reason": "checked against #/texts/42"}}


def test_phase4_ignores_the_review(package):
    pkg = write_review(package(), findings=[FINDING])
    assert problems(pkg, review=False) == []


def test_missing_review_fails_the_gate(package):
    assert any("no review.json" in p and "phase 5" in p for p in problems(package()))


def test_fresh_empty_review_passes(package):
    assert problems(write_review(package())) == []


def test_unanswered_findings_await_phase6(package):
    pkg = write_review(package(), findings=[FINDING])
    [error] = problems(pkg)
    assert "phase 6" in error and "f2" in error and "wrong_value" in error


def test_review_goes_stale_when_a_batch_changes(package):
    pkg = write_review(package())
    gall = json.loads((pkg / "gall.json").read_text(encoding="utf-8"))
    gall["facts"][1]["evidence"][0]["quote"] = "Common on Q. lobata"
    (pkg / "gall.json").write_text(json.dumps(gall), encoding="utf-8")
    assert any("stale" in p and "gall.json" in p for p in problems(pkg))


def test_review_must_cover_every_batch(package, taxonomy):
    pkg = write_review(package(taxonomy=taxonomy))
    data = json.loads((pkg / "review.json").read_text(encoding="utf-8"))
    del data["reviewed"]["taxonomy.json"]
    (pkg / "review.json").write_text(json.dumps(data), encoding="utf-8")
    assert any("stale" in p and "taxonomy.json" in p for p in problems(pkg))


def test_malformed_review(package):
    pkg = write_review(package(), findings=[{"batch": "gall.json", "id": "f2", "problem": "looks off"}])
    assert any("review.json" in p and "problem" in p for p in problems(pkg))


def test_finding_must_name_a_real_statement(package):
    pkg = write_review(package(), findings=[{**FINDING, "id": "f99"}])
    assert any("f99" in p and "not in gall.json" in p for p in problems(pkg))


def test_agreed_findings_pass(package):
    pkg = write_review(package(), findings=[answered("agree")], responded=True)
    assert problems(pkg) == []
    assert warnings(pkg) == []


def test_an_agreed_fix_may_remove_the_statement(package):
    """The fix for an agreed finding can delete the statement, so the id need not exist any more."""
    pkg = write_review(package(), findings=[answered("agree", ident="f99")], responded=True)
    assert problems(pkg) == []


def test_disputed_findings_pass_but_go_to_intake(package):
    pkg = write_review(package(), findings=[answered("disagree")], responded=True)
    assert problems(pkg) == []
    [warning] = warnings(pkg)
    assert "human review" in warning and "f2" in warning and "checked against #/texts/42" in warning


def test_a_disputed_statement_must_still_exist(package):
    pkg = write_review(package(), findings=[answered("disagree", ident="f99")], responded=True)
    assert any("f99" in p and "not in gall.json" in p for p in problems(pkg))


def test_every_finding_needs_a_response(package):
    pkg = write_review(package(), findings=[answered("agree"), {**FINDING, "id": "f1"}], responded=True)
    assert any("f1" in p and "no phase 6 response" in p for p in problems(pkg))


def test_batches_changed_after_phase6(package):
    pkg = write_review(package(), findings=[answered("agree")], responded=True)
    gall = json.loads((pkg / "gall.json").read_text(encoding="utf-8"))
    gall["facts"][1]["evidence"][0]["quote"] = "Common on Q. lobata"
    (pkg / "gall.json").write_text(json.dumps(gall), encoding="utf-8")
    assert any("changed after phase 6" in p and "gall.json" in p for p in problems(pkg))


def test_responses_are_well_formed(package):
    bad = {**FINDING, "response": {"decision": "maybe", "reason": "x"}}
    pkg = write_review(package(), findings=[bad], responded=True)
    assert any("review.json" in p and "decision" in p.lower() or "maybe" in p for p in problems(pkg))


def test_cli_review_flag(package, capsys):
    pkg = write_review(package())
    assert validate.main([str(pkg)]) == 0
    assert validate.main(["--review", str(pkg)]) == 0
    (pkg / "review.json").unlink()
    assert validate.main(["--review", str(pkg)]) == 1
    assert "no review.json" in capsys.readouterr().out


def test_cli_reports_disputes_without_failing(package, capsys):
    pkg = write_review(package(), findings=[answered("disagree")], responded=True)
    assert validate.main(["--review", str(pkg)]) == 0
    assert "human review" in capsys.readouterr().out


# -- 2026-11-02: format v4, the reviewer places every trait term blind (d213) -----------------
# review.json `placements`: per trait Fact, the reviewer's own category (or null) and whether it
# depends on the Gall, made without seeing the producer's suggestion.


def placement(ident="f5", category="tan", **fields):
    return {"id": ident, "category": None if category is None else {"value": category}, **fields}


def test_a_v4_review_places_every_trait_fact(package, batch_v4):
    pkg = write_review(package(gall=batch_v4))
    [error] = problems(pkg)
    assert "f5" in error and "placement" in error
    assert problems(write_review(package(gall=batch_v4), placements=[placement()])) == []


def test_a_placement_may_be_no_category_or_depend_on_the_gall(package, batch_v4):
    for p in (placement(category=None, reason="no colour value fits"), placement(depends_on_gall=True)):
        assert problems(write_review(package(gall=batch_v4), placements=[p])) == [], p


def test_a_placement_is_a_value_of_the_facts_trait(package, batch_v4):
    pkg = write_review(package(gall=batch_v4), placements=[placement(category="globular")])
    [error] = problems(pkg)
    assert "f5" in error and "globular" in error and "color" in error


def test_a_placement_names_a_trait_fact(package, batch_v4):
    pkg = write_review(package(gall=batch_v4), placements=[placement(), placement("f2"), placement("f99")])
    errors = problems(pkg)
    assert any("f2" in p and "not a trait Fact" in p for p in errors)
    assert any("f99" in p and "not a trait Fact" in p for p in errors)


def test_one_placement_per_fact_per_reviewer(package, batch_v4):
    two = [placement(reviewer="opus"), placement(reviewer="sonnet")]
    assert problems(write_review(package(gall=batch_v4), placements=two)) == []
    same = [placement(reviewer="opus"), placement(category="brown", reviewer="opus")]
    assert any("f5" in p and "more than once" in p for p in problems(write_review(package(gall=batch_v4), placements=same)))


def test_a_malformed_placement(package, batch_v4):
    pkg = write_review(package(gall=batch_v4), placements=[{"id": "f5", "category": "tan"}])
    assert any("placements/0/category" in p for p in problems(pkg))


def test_after_phase6_a_trait_fact_without_a_placement_goes_to_intake(package, batch_v4):
    """A trait Fact phase 6 added or rewrote has no blind placement: a curator places it."""
    b = json.loads(json.dumps(batch_v4))
    b["facts"].append({**b["facts"][4], "id": "f6", "term": "pale"})
    pkg = write_review(package(gall=b), findings=[answered("agree")], responded=True, placements=[placement()])
    assert problems(pkg) == []
    assert any("f6" in w and "placement" in w for w in warnings(pkg))


def test_after_phase6_a_placement_may_outlive_its_fact(package, batch_v4):
    pkg = write_review(package(gall=batch_v4), findings=[answered("agree")], responded=True,
                       placements=[placement(), placement("f9")])  # fmt: skip
    assert problems(pkg) == []


def test_a_v3_batch_needs_no_placements(package):
    assert problems(write_review(package())) == []


# -- 2026-11-03: one-sentence positions (d213) --------------------------------------------------
# A finding's `summary` is the checker's position in one sentence, its response's `summary` the
# producer's. Both optional: the review falls back to each side's first sentence.


def test_findings_and_responses_take_a_summary(package):
    finding = answered("disagree")
    finding["summary"] = "The quote names Q. douglasii, not Q. lobata."
    finding["response"]["summary"] = "The Source means Q. lobata here."
    pkg = write_review(package(), findings=[finding], responded=True)
    assert problems(pkg) == []


def test_a_summary_is_not_empty(package):
    finding = {**answered("disagree"), "summary": ""}
    assert any("findings/0/summary" in p for p in problems(write_review(package(), findings=[finding], responded=True)))
    finding = answered("disagree")
    finding["response"]["summary"] = ""
    pkg = write_review(package(), findings=[finding], responded=True)
    assert any("findings/0/response/summary" in p for p in problems(pkg))
