import json

import pytest

from producer.respond import apply_responses, build_respond_prompt, respond_command

REVIEW = {
    "format": "gallformers-review",
    "reviewed": {"gall.json": "a" * 64},
    "reviewers": [{"model": "opus"}],
    "findings": [
        {"batch": "gall.json", "id": "f1", "problem": "unsupported", "reason": "no such text"},
        {"batch": "gall.json", "id": "f2", "problem": "wrong_type", "reason": "an inquiline"},
    ],
}
RESULT = {"gall.json": "b" * 64}
RESPONDER = {"model": "opus", "instructions_version": "responder.md@x"}


@pytest.fixture
def package(tmp_path, doc):
    pkg = tmp_path / "pkg"
    pkg.mkdir()
    (pkg / "document.json").write_text(json.dumps(doc), encoding="utf-8")
    (pkg / "document.txt").write_text(
        "#/texts/1 p2 [text] Galls of Asphondylia\n", encoding="utf-8"
    )
    (pkg / "taxonomy.json").write_text('{"acts": []}', encoding="utf-8")
    (pkg / "gall.json").write_text('{"facts": [{"id": "f1"}, {"id": "f2"}]}', encoding="utf-8")
    (pkg / "review.json").write_text(json.dumps(REVIEW), encoding="utf-8")
    return pkg


def test_responses_are_recorded_on_their_findings():
    answers = [
        {"n": 2, "decision": "disagree", "reason": "the flies emerged from the gall's tissue"},
        {"n": 1, "decision": "agree", "reason": "removed f1"},
    ]
    review = apply_responses(REVIEW, answers, RESULT, RESPONDER)
    assert [f["response"]["decision"] for f in review["findings"]] == ["agree", "disagree"]
    assert review["responded"] == {"responder": RESPONDER, "result": RESULT}
    assert "response" not in REVIEW["findings"][0]  # the input is left alone


def test_every_finding_needs_exactly_one_answer():
    with pytest.raises(ValueError, match="finding 2 has no answer"):
        apply_responses(REVIEW, [{"n": 1, "decision": "agree", "reason": "x"}], RESULT, RESPONDER)
    twice = [{"n": 1, "decision": "agree", "reason": "x"}] * 2 + [
        {"n": 2, "decision": "agree", "reason": "y"}
    ]
    with pytest.raises(ValueError, match="finding 1 is answered more than once"):
        apply_responses(REVIEW, twice, RESULT, RESPONDER)


def test_answers_must_be_agree_or_disagree_with_a_reason():
    bad = [
        {"n": 1, "decision": "maybe", "reason": "x"},
        {"n": 2, "decision": "agree", "reason": ""},
    ]
    with pytest.raises(ValueError) as err:
        apply_responses(REVIEW, bad, RESULT, RESPONDER)
    assert "finding 1" in str(err.value) and "finding 2" in str(err.value)


def test_prompt_numbers_the_findings_and_carries_the_contract(package):
    prompt = build_respond_prompt(package)
    assert '"n": 2' in prompt and "an inquiline" in prompt
    assert "## priv/import/PRODUCER_GUIDE.md" in prompt
    assert "responses.json" in prompt
    assert "validate.py" in prompt


def test_responder_may_only_run_the_validator(package):
    cmd = respond_command(package, "high")
    assert cmd[cmd.index("--tools") + 1] == "Read,Write,Edit,Grep,Bash"
    allowed = cmd[cmd.index("--allowedTools") + 1 : cmd.index("--permission-mode")]
    assert len(allowed) == 1 and "validate.py" in allowed[0]
