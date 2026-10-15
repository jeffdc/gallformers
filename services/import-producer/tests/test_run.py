import hashlib
import json
import re

import pytest

from producer.run import build_prompt, child_env, claude_command


@pytest.fixture
def package(tmp_path, doc):
    (tmp_path / "document.json").write_text(json.dumps(doc), encoding="utf-8")
    (tmp_path / "document.txt").write_text(
        "#/texts/1 p2 [text] Galls of Asphondylia\n", encoding="utf-8"
    )
    return tmp_path


def envelope(prompt):
    block = re.search(r"```json\n(\{\n  \"format\".*?)\n```", prompt, re.S).group(1)
    return json.loads(block)


def test_prompt_has_no_unfilled_placeholders(package):
    for phase in (2, 3):
        prompt = build_prompt(package, phase)
        assert not re.search(r"\$[a-z_]+\b", prompt.split("# The contract")[0])


def test_prompt_carries_contract_document_and_envelope(package):
    prompt = build_prompt(package, 3)
    assert "# Gallformers import — producer guide" in prompt
    assert "#/texts/1 p2 [text] Galls of Asphondylia" in prompt
    env = envelope(prompt)
    assert env["batch_type"] == "gall"
    assert env["mode"] == "replace"
    expected = hashlib.sha256((package / "document.json").read_bytes()).hexdigest()
    assert env["source"]["document"]["sha256"] == expected
    assert env["producer"]["model"] == "claude-opus-5-5"


def test_phase3_describes_the_taxonomy_batch(package):
    assert "no taxonomy.json" in build_prompt(package, 3)
    (package / "taxonomy.json").write_text('{"acts": [{"id": "a1"}]}', encoding="utf-8")
    prompt = build_prompt(package, 3)
    assert "read it first" in prompt and "Its `acts` are empty" not in prompt
    (package / "taxonomy.json").write_text('{"acts": []}', encoding="utf-8")
    assert "Its `acts` are empty" in build_prompt(package, 3)


def test_prompt_carries_trait_definitions(package):
    assert "## priv/import/vocab/traits.json" in build_prompt(package, 3)


def test_only_validate_and_lookup_are_allowed(package):
    cmd = claude_command(package, "high")
    allowed = cmd[cmd.index("--allowedTools") + 1 : cmd.index("--permission-mode")]
    assert len(allowed) == 2
    assert "validate.py" in allowed[0] and "lookup-place" in allowed[1]


def test_command_bills_subscription_and_is_locked_down(package):
    cmd = claude_command(package, "high")
    assert "--bare" not in cmd  # --bare only authenticates with ANTHROPIC_API_KEY
    assert cmd[cmd.index("--model") + 1] == "claude-opus-5-5"
    assert "--safe-mode" in cmd
    assert cmd[cmd.index("--permission-prompts") + 1] == "none"


def test_child_env_drops_api_key_and_session_vars(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "x")
    monkeypatch.setenv("CLAUDECODE", "1")
    monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", "abc")
    monkeypatch.setenv("PATH", "/usr/bin")
    env = child_env()
    assert "ANTHROPIC_API_KEY" not in env
    assert not any(k.startswith("CLAUDE") for k in env)
    assert env["PATH"] == "/usr/bin"
