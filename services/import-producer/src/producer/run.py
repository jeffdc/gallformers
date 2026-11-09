"""Phases 2 and 3: one headless Claude Code run per phase.

The producer is Claude Code (`claude -p`) on the user's subscription, with the
contract and the document in its prompt and a narrow tool set: read and write
in the package directory, and two Bash commands (the contract's validate.py,
lookup-place). It fixes its own validation errors before it stops.
"""

import hashlib
import json
import os
import shlex
import subprocess
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from string import Template

from producer import note, paths

MODEL = "claude-opus-5-5"
PROMPT = paths.PROJECT / "prompts" / "producer.md"
PRODUCER_VERSION = "0.1.0"
TIMEOUT_S = 60 * 60

BATCH_FILE = {2: "taxonomy.json", 3: "gall.json"}

PHASE_TASK = {
    2: "the **taxonomy batch** (phase 2): the taxonomic acts this Source states.",
    3: "the **gall batch** (phase 3): what this Source states about Galls.",
}

PHASE_RULES = {
    2: """## Phase 2

Follow PRODUCER_GUIDE.md, "Phase 2 — Taxonomy batch". Write taxonomy.json even when the Source states no acts (empty `taxa` and `acts`), and say why in `notes-phase2.md`.""",
    3: """## Phase 3

Follow PRODUCER_GUIDE.md, "Phase 3 — Gall batch", using taxon names as they stand after phase 2. $taxonomy_note

Under "Judgement calls" in `notes-phase3.md`, list the trait terms you gave no category or marked `depends_on_gall`, with the categories you weighed.""",
}

# Contract files, in the order the prompt presents them. places.json is left out
# (too large); the producer reaches it through lookup-place.
CONTRACT_FILES = (
    "PRODUCER_GUIDE.md",
    "schema/common.schema.json",
    "schema/taxonomy.schema.json",
    "schema/gall.schema.json",
    "vocab/ranks.schema.json",
    "vocab/licenses.schema.json",
    "vocab/relationships.schema.json",
    "vocab/traits.schema.json",
    "vocab/traits.json",
    "examples/simple-paper/gall.json",
    "examples/revision/taxonomy.json",
    "examples/revision/gall.json",
    "examples/retraction/gall.json",
)

# Added for a Gall's Gallformers note (producer.note).
NOTE_CONTRACT_FILES = (
    "GALLFORMERS_STATEMENTS.md",
    "examples/gallformers-note/gall.json",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def versioned(prompt: Path, contract: str) -> str:
    """A prompt template's hash and that of the contract it carries (the guides,
    schemas, vocabulary and examples): lets the golden set trace output changes
    to prompt or guide changes."""
    digest = hashlib.sha256(contract.encode("utf-8")).hexdigest()
    return f"{prompt.name}@{sha256(prompt)[:12]} contract@{digest[:12]}"


def instructions_version(package: Path) -> str:
    return versioned(PROMPT, contract_text(NOTE_CONTRACT_FILES if note.is_note(package) else ()))


def contract_text(extra: tuple[str, ...] = ()) -> str:
    parts = []
    for name in (*CONTRACT_FILES, *extra):
        text = (paths.CONTRACT / name).read_text(encoding="utf-8")
        fence = "markdown" if name.endswith(".md") else "json"
        parts.append(f"## priv/import/{name}\n\n```{fence}\n{text.rstrip()}\n```")
    return "\n\n".join(parts)


def vocabulary_version() -> str:
    """The newest date among the vocab files that carry one."""
    versions = []
    for name in ("places.json", "traits.json"):
        data = json.loads((paths.VOCAB / name).read_text(encoding="utf-8"))
        versions.append(data["vocabulary_version"])
    return max(versions)


def commands(package: Path) -> dict[str, str]:
    return {
        "validate_cmd": f"uv run {paths.VALIDATOR} {package}",
        "lookup_cmd": f"uv run --directory {paths.PROJECT} produce lookup-place",
    }


def envelope(package: Path, phase: int) -> dict:
    """The values the run fixes. A Gall's note (producer.note) has its whole Source block."""
    source = (
        note.source_block(package)
        if note.is_note(package)
        else {"document": {"file": "document.json", "sha256": sha256(package / "document.json")}}
    )
    return {
        "format": "gallformers-import",
        "format_version": 4,
        "vocabulary_version": vocabulary_version(),
        "batch_type": "taxonomy" if phase == 2 else "gall",
        "mode": "add" if note.is_note(package) else "replace",
        "batch_id": str(uuid.uuid4()),
        "produced_at": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "producer": {
            "name": "gallformers-import-producer-poc",
            "version": PRODUCER_VERSION,
            "model": MODEL,
            "instructions_version": instructions_version(package),
        },
        "source": source,
    }


SOURCE_INSTRUCTIONS = (
    "Fill in the rest of `source` (kind, title, authors, authored, citation, identifiers, "
    "license) from the document itself."
)

NOTE_INSTRUCTIONS = """This Source is Gallformers itself, and the document is one Gall's Gallformers note. The `source` above is complete: copy it as it is. Follow GALLFORMERS_STATEMENTS.md, "Reading a Gall's note", as well as the producer guide. The note's Gall, as Gallformers holds it:

$gall"""


def build_prompt(package: Path, phase: int) -> str:
    batch_file = BATCH_FILE[phase]
    is_note = note.is_note(package)

    taxonomy = package / "taxonomy.json"
    source_hint = ""
    taxonomy_note = "There is no taxonomy.json: phase 2 has not been run on this Source."
    if phase == 3 and taxonomy.exists():
        taxonomy_note = "The phase 2 taxonomy batch is `taxonomy.json` in your working directory; read it first."
        source_hint = "Use the same `source` block as `taxonomy.json` (same Source), apart from the values above."
        if not json.loads(taxonomy.read_text(encoding="utf-8")).get("acts"):
            taxonomy_note += " Its `acts` are empty: the Source states no taxonomic acts."

    source_instructions = (
        Template(NOTE_INSTRUCTIONS).substitute(gall=note.gall_text(package))
        if is_note
        else f"{SOURCE_INSTRUCTIONS} {source_hint}".rstrip()
    )
    rules = Template(PHASE_RULES[phase]).safe_substitute(taxonomy_note=taxonomy_note)
    return Template(PROMPT.read_text(encoding="utf-8")).substitute(
        phase=phase,
        batch_file=batch_file,
        phase_task=PHASE_TASK[phase],
        envelope=json.dumps(envelope(package, phase), indent=2),
        source_instructions=source_instructions,
        phase_rules=rules,
        contract=contract_text(NOTE_CONTRACT_FILES if is_note else ()),
        document=(package / "document.txt").read_text(encoding="utf-8"),
        **commands(package),
    )


def claude_base(effort: str, tools: str, model: str = MODEL) -> list[str]:
    """Headless Claude Code on the subscription, in safe mode, editing only its working directory."""
    return [
        "claude",
        "-p",
        "--model", model,
        "--effort", effort,
        "--safe-mode",  # no CLAUDE.md, hooks, skills, memory, MCP
        "--tools", tools,
        "--permission-mode", "acceptEdits",  # edits inside the working dir only
        "--permission-prompts", "none",  # anything else that would prompt is denied
        "--output-format", "stream-json",
        "--verbose",
        "--no-session-persistence",
    ]  # fmt: skip


def claude_command(package: Path, effort: str) -> list[str]:
    cmd = commands(package)
    allowed = [f"Bash({cmd['validate_cmd']})", f"Bash({cmd['lookup_cmd']} *)"]
    base = claude_base(effort, tools="Read,Write,Edit,Grep,Bash")
    at = base.index("--permission-mode")
    return [*base[:at], "--allowedTools", *allowed, *base[at:]]


def child_env() -> dict[str, str]:
    """This environment minus anything that would bill an API key or attach to this session."""
    drop = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN")
    return {k: v for k, v in os.environ.items() if k not in drop and not k.startswith("CLAUDE")}


def result_event(stream: Path) -> dict | None:
    result = None
    for line in stream.read_text(encoding="utf-8").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "result":
            result = event
    return result


def run_tool(args: list[str], cwd: Path) -> dict:
    proc = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    return {"exit": proc.returncode, "output": (proc.stdout + proc.stderr).strip()}


def run_phase(package: Path, phase: int, effort: str = "high", dry_run: bool = False) -> dict:
    package = package.resolve()
    if phase == 2 and note.is_note(package):
        return {"phase": 2, "blocked": "a note's taxonomy batch is empty; `produce note` writes it"}
    prompt = build_prompt(package, phase)
    (package / f"phase{phase}.prompt.md").write_text(prompt, encoding="utf-8")
    command = claude_command(package, effort)
    record: dict = {
        "phase": phase,
        "model": MODEL,
        "effort": effort,
        "instructions_version": instructions_version(package),
        "prompt_chars": len(prompt),
        "command": shlex.join(command) + f" < phase{phase}.prompt.md",
    }
    if dry_run:
        return record

    stream = package / f"phase{phase}.stream.jsonl"
    started = time.monotonic()
    with stream.open("w", encoding="utf-8") as out:
        proc = subprocess.run(
            command,
            input=prompt,
            stdout=out,
            stderr=subprocess.STDOUT,
            cwd=package,
            env=child_env(),
            text=True,
            timeout=TIMEOUT_S,
        )
    record["seconds"] = round(time.monotonic() - started)
    record["exit"] = proc.returncode

    result = result_event(stream) or {}
    record["claude"] = {
        k: result.get(k)
        for k in (
            "subtype",
            "is_error",
            "num_turns",
            "duration_ms",
            "total_cost_usd",
            "usage",
            "modelUsage",
        )
    }
    batch = package / BATCH_FILE[phase]
    record["batch_written"] = batch.exists()
    if batch.exists():
        cmd = commands(package)
        record["validate"] = run_tool(shlex.split(cmd["validate_cmd"]), package)
    return record


def append_run(package: Path, record: dict) -> None:
    log = package / "run.json"
    runs = json.loads(log.read_text(encoding="utf-8")) if log.exists() else []
    runs.append({"at": datetime.now(UTC).isoformat(timespec="seconds"), **record})
    log.write_text(json.dumps(runs, indent=2), encoding="utf-8")
