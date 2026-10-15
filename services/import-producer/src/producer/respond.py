"""Phase 6: the producer answers each phase 5 finding once.

A fresh Claude Code session, working in the package directory as the producer
did, fixes the statements it agrees with and writes responses.json (one
answer per numbered finding). The driver records the answers on their
findings in review.json and adds `responded` (the batch hashes it leaves), so
the agent never edits review.json itself. Disputed findings go to a human at
intake; nothing is reviewed again.
"""

import json
import shlex
import subprocess
import time
from pathlib import Path
from string import Template

from producer import paths
from producer.review import validate
from producer.run import (
    CONTRACT_FILES,
    MODEL,
    TIMEOUT_S,
    child_env,
    claude_base,
    commands,
    result_event,
    run_tool,
    sha256,
)

PROMPT = paths.PROJECT / "prompts" / "responder.md"
DECISIONS = ("agree", "disagree")


def instructions_version() -> str:
    return f"responder.md@{sha256(PROMPT)[:12]}"


def contract_text() -> str:
    parts = []
    for name in (*CONTRACT_FILES, "VERIFY_GUIDE.md", "schema/review.schema.json"):
        text = (paths.CONTRACT / name).read_text(encoding="utf-8")
        fence = "markdown" if name.endswith(".md") else "json"
        parts.append(f"## priv/import/{name}\n\n```{fence}\n{text.rstrip()}\n```")
    return "\n\n".join(parts)


def numbered(review: dict) -> list[dict]:
    return [{"n": n, **finding} for n, finding in enumerate(review["findings"], start=1)]


def build_respond_prompt(package: Path) -> str:
    review = json.loads((package / "review.json").read_text(encoding="utf-8"))
    return Template(PROMPT.read_text(encoding="utf-8")).substitute(
        findings=json.dumps(numbered(review), indent=2, ensure_ascii=False),
        validate_cmd=commands(package)["validate_cmd"],
        contract=contract_text(),
        taxonomy=(package / "taxonomy.json").read_text(encoding="utf-8").rstrip(),
        gall=(package / "gall.json").read_text(encoding="utf-8").rstrip(),
        document=(package / "document.txt").read_text(encoding="utf-8"),
    )


def respond_command(package: Path, effort: str) -> list[str]:
    allowed = [f"Bash({commands(package)['validate_cmd']})"]
    base = claude_base(effort, tools="Read,Write,Edit,Grep,Bash")
    at = base.index("--permission-mode")
    return [*base[:at], "--allowedTools", *allowed, *base[at:]]


def apply_responses(review: dict, answers: list[dict], result: dict, responder: dict) -> dict:
    """review.json with each answer on its finding and `responded` added; ValueError if any
    finding is unanswered, answered twice, or answered with something other than agree/disagree
    and a reason."""
    count = len(review["findings"])
    problems, by_n = [], {}
    for answer in answers:
        n = answer.get("n")
        if not isinstance(n, int) or not 1 <= n <= count:
            problems.append(f"answer for unknown finding {n!r}")
        elif n in by_n:
            problems.append(f"finding {n} is answered more than once")
        else:
            by_n[n] = answer
            if answer.get("decision") not in DECISIONS:
                problems.append(f"finding {n}: decision must be agree or disagree")
            if not str(answer.get("reason") or "").strip():
                problems.append(f"finding {n}: the reason is empty")
    problems += [f"finding {n} has no answer" for n in range(1, count + 1) if n not in by_n]
    if problems:
        raise ValueError("; ".join(problems))

    findings = [
        {
            **finding,
            "response": {"decision": by_n[n]["decision"], "reason": by_n[n]["reason"].strip()},
        }
        for n, finding in enumerate(review["findings"], start=1)
    ]
    return {**review, "findings": findings, "responded": {"responder": responder, "result": result}}


def run_respond(package: Path, effort: str = "high", dry_run: bool = False) -> dict:
    """Phase 6. Needs a phase 5 review with unanswered findings, and phase 4 passing."""
    package = package.resolve()
    review_path = package / "review.json"
    if not review_path.exists():
        return {"phase": 6, "blocked": "no review.json: run phase 5 first"}
    review = json.loads(review_path.read_text(encoding="utf-8"))
    if not review.get("findings"):
        return {"phase": 6, "blocked": "the review has no findings: nothing to answer"}
    if review.get("responded"):
        return {"phase": 6, "blocked": "already answered: re-run phase 5 for a new review"}
    if not dry_run:
        phase4 = validate(package)
        if phase4["exit"] != 0:
            return {
                "phase": 6,
                "blocked": "phase 4 fails; fix the batches first",
                "validate": phase4,
            }

    prompt = build_respond_prompt(package)
    (package / "phase6.prompt.md").write_text(prompt, encoding="utf-8")
    command = respond_command(package, effort)
    record: dict = {
        "phase": 6,
        "model": MODEL,
        "effort": effort,
        "instructions_version": instructions_version(),
        "findings": len(review["findings"]),
        "prompt_chars": len(prompt),
        "command": shlex.join(command) + " < phase6.prompt.md",
    }
    if dry_run:
        return record

    stream = package / "phase6.stream.jsonl"
    started = time.monotonic()
    with stream.open("w", encoding="utf-8") as out:
        proc = subprocess.run(
            command, input=prompt, stdout=out, stderr=subprocess.STDOUT,
            cwd=package, env=child_env(), text=True, timeout=TIMEOUT_S,
        )  # fmt: skip
    record["seconds"] = round(time.monotonic() - started)
    record["exit"] = proc.returncode
    result = result_event(stream) or {}
    record["claude"] = {
        k: result.get(k) for k in ("subtype", "is_error", "num_turns", "total_cost_usd", "usage")
    }

    answers_path = package / "responses.json"
    if not answers_path.exists():
        record["error"] = "no responses.json written"
        return record
    hashes = {
        name: sha256(package / name)
        for name in ("taxonomy.json", "gall.json")
        if (package / name).exists()
    }
    responder = {"model": MODEL, "instructions_version": instructions_version()}
    try:
        answered = apply_responses(
            review, json.loads(answers_path.read_text(encoding="utf-8")), hashes, responder
        )
    except (ValueError, json.JSONDecodeError) as exc:
        record["error"] = f"responses.json: {exc}"
        return record
    review_path.write_text(
        json.dumps(answered, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    decisions = [f["response"]["decision"] for f in answered["findings"]]
    record["agreed"] = decisions.count("agree")
    record["disputed"] = decisions.count("disagree")
    record["validate"] = run_tool(shlex.split(commands(package)["validate_cmd"]), package)
    record["ready"] = validate(package, review=True)
    return record
