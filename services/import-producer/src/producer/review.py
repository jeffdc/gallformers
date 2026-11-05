"""Phase 5: fresh Claude Code sessions check the batches against the document.

Each reviewer runs in a scratch directory holding only document.json,
document.txt, taxonomy.json and gall.json, so it never sees the producer's
notes or prompts. It can read and write there, with no shell. The driver
fixes `reviewed` (the batch hashes) and `reviewers`. Several models review in
turn (they catch different errors); their findings are merged into one
review.json, each naming its reviewer. Phase 6 answers the findings.

In a format 4 gall batch the reviewer places every trait term blind: its copy
of gall.json has each trait Fact's `category` and `depends_on_gall` removed,
and it writes its own in `placements`. The placements are merged like the
findings, each naming its reviewer.
"""

import json
import shlex
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from string import Template

from producer import note, paths
from producer.run import (
    MODEL,
    NOTE_CONTRACT_FILES,
    TIMEOUT_S,
    child_env,
    claude_base,
    result_event,
    run_tool,
    sha256,
)

PROMPT = paths.PROJECT / "prompts" / "verifier.md"
REVIEWERS = ("claude-opus-5-5", "claude-sonnet-5-5")
STAGED = ("document.json", "document.txt", "taxonomy.json", "gall.json")
BLINDED = ("category", "depends_on_gall")

CONTRACT_FILES = (
    "VERIFY_GUIDE.md",
    "PRODUCER_GUIDE.md",
    "schema/review.schema.json",
    "schema/common.schema.json",
    "schema/taxonomy.schema.json",
    "schema/gall.schema.json",
    "vocab/ranks.schema.json",
    "vocab/relationships.schema.json",
    "vocab/traits.schema.json",
    "vocab/traits.json",
)


def instructions_version() -> str:
    return f"verifier.md@{sha256(PROMPT)[:12]}"


def blind(gall: dict) -> dict:
    """The gall batch as the reviewer sees it: each trait Fact without the producer's category."""
    facts = [
        {k: v for k, v in f.items() if k not in BLINDED} if f.get("kind") == "trait" else f
        for f in gall.get("facts", [])
    ]
    return {**gall, "facts": facts}


def is_v4(gall: dict) -> bool:
    return gall.get("format_version") == 4


def gall_text(package: Path) -> str:
    """gall.json for the reviewer: blind when it is format 4, otherwise as it is."""
    text = (package / "gall.json").read_text(encoding="utf-8")
    gall = json.loads(text)
    if not is_v4(gall):
        return text
    return json.dumps(blind(gall), indent=2, ensure_ascii=False) + "\n"


def stage(package: Path, work: Path) -> None:
    for name in STAGED:
        if name == "gall.json":
            (work / name).write_text(gall_text(package), encoding="utf-8")
        else:
            shutil.copy2(package / name, work / name)


def contract_text(extra: tuple[str, ...] = ()) -> str:
    parts = []
    for name in (*CONTRACT_FILES, *extra):
        text = (paths.CONTRACT / name).read_text(encoding="utf-8")
        fence = "markdown" if name.endswith(".md") else "json"
        parts.append(f"## priv/import/{name}\n\n```{fence}\n{text.rstrip()}\n```")
    return "\n\n".join(parts)


def build_review_prompt(package: Path, model: str = MODEL) -> str:
    fixed = {
        "reviewed": {name: sha256(package / name) for name in ("taxonomy.json", "gall.json")},
        "reviewers": [{"model": model, "instructions_version": instructions_version()}],
    }
    return Template(PROMPT.read_text(encoding="utf-8")).substitute(
        fixed=json.dumps(fixed, indent=2),
        contract=contract_text(NOTE_CONTRACT_FILES if note.is_note(package) else ()),
        taxonomy=(package / "taxonomy.json").read_text(encoding="utf-8").rstrip(),
        gall=gall_text(package).rstrip(),
        document=(package / "document.txt").read_text(encoding="utf-8"),
    )


def review_command(effort: str, model: str = MODEL) -> list[str]:
    return claude_base(effort, tools="Read,Write,Grep", model=model)


def validate(package: Path, review: bool = False) -> dict:
    """Phase 4 (and with review=True, the readiness gate): the contract's validate.py."""
    args = ["uv", "run", str(paths.VALIDATOR), *(["--review"] if review else []), str(package)]
    return run_tool(args, package)


def merge_reviews(reviews: list[dict]) -> dict:
    """One review.json from several reviewers of the same batches; each finding names its reviewer."""
    reviewed = reviews[0]["reviewed"]
    if any(r["reviewed"] != reviewed for r in reviews):
        raise ValueError("the reviews cover different batches")
    merged = {"format": "gallformers-review", "reviewed": reviewed, "reviewers": [], "findings": []}
    placements = []
    for review in reviews:
        reviewers = review.get("reviewers", [])
        merged["reviewers"].extend(reviewers)
        model = reviewers[0].get("model") if reviewers else None
        for finding in review["findings"]:
            merged["findings"].append({**finding, "reviewer": finding.get("reviewer", model)})
        for placement in review.get("placements", []):
            placements.append({**placement, "reviewer": placement.get("reviewer", model)})
    if placements:
        merged["placements"] = placements
    return merged


def missing_placements(gall: dict, review: dict) -> dict[str, list[str]]:
    """Format 4: the trait Facts each reviewer left unplaced, by reviewer (empty when none). A
    placement naming no reviewer counts for every reviewer."""
    if not is_v4(gall):
        return {}
    traits = [f["id"] for f in gall.get("facts", []) if f.get("kind") == "trait"]
    reviewers = [r.get("model") for r in review.get("reviewers", [])] or [None]
    out = {}
    for reviewer in reviewers:
        placed = {
            p["id"] for p in review.get("placements", []) if p.get("reviewer") in (None, reviewer)
        }
        missing = [ident for ident in traits if ident not in placed]
        if missing:
            out[reviewer or "reviewer"] = missing
    return out


def review_once(package: Path, model: str, effort: str, dry_run: bool) -> tuple[dict, dict | None]:
    """One reviewer's run: its record, and its review (None if it wrote none)."""
    prompt = build_review_prompt(package, model=model)
    (package / f"phase5.{model}.prompt.md").write_text(prompt, encoding="utf-8")
    command = review_command(effort, model=model)
    record: dict = {
        "model": model,
        "prompt_chars": len(prompt),
        "command": shlex.join(command) + f" < phase5.{model}.prompt.md",
    }
    if dry_run:
        return record, None

    stream = package / f"phase5.{model}.stream.jsonl"
    review = None
    with tempfile.TemporaryDirectory(prefix="gallformers-review-") as tmp:
        work = Path(tmp)
        stage(package, work)
        started = time.monotonic()
        with stream.open("w", encoding="utf-8") as out:
            proc = subprocess.run(
                command, input=prompt, stdout=out, stderr=subprocess.STDOUT,
                cwd=work, env=child_env(), text=True, timeout=TIMEOUT_S,
            )  # fmt: skip
        record["seconds"] = round(time.monotonic() - started)
        record["exit"] = proc.returncode
        written = work / "review.json"
        if written.exists():
            review = json.loads(written.read_text(encoding="utf-8"))
            shutil.copy2(written, package / f"review.{model}.json")
    result = result_event(stream) or {}
    record["claude"] = {
        k: result.get(k) for k in ("subtype", "is_error", "num_turns", "total_cost_usd", "usage")
    }
    record["findings"] = None if review is None else len(review.get("findings", []))
    return record, review


def run_review(
    package: Path,
    effort: str = "high",
    dry_run: bool = False,
    models: tuple[str, ...] = REVIEWERS,
) -> dict:
    """Phase 5. Runs only when phase 4 passes. Each model reviews in turn; their findings are
    merged into review.json, and readiness (validate.py --review) is checked."""
    package = package.resolve()
    if not dry_run:
        phase4 = validate(package)
        if phase4["exit"] != 0:
            return {
                "phase": 5,
                "blocked": "phase 4 fails; fix the batches first",
                "validate": phase4,
            }
    record: dict = {
        "phase": 5,
        "effort": effort,
        "instructions_version": instructions_version(),
        "reviewers": [],
    }
    reviews = []
    for model in models:
        sub, review = review_once(package, model, effort, dry_run)
        record["reviewers"].append(sub)
        if review is not None:
            reviews.append(review)
    if dry_run:
        return record
    if len(reviews) != len(models):
        record["error"] = "a reviewer wrote no review.json; nothing merged"
        return record

    merged = merge_reviews(reviews)
    (package / "review.json").write_text(
        json.dumps(merged, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    record["findings"] = len(merged["findings"])
    record["placements"] = len(merged.get("placements", []))
    gall = json.loads((package / "gall.json").read_text(encoding="utf-8"))
    missing = missing_placements(gall, merged)
    if missing:
        record["missing_placements"] = missing
        record["error"] = "a reviewer left trait terms unplaced: re-run phase 5"
    record["ready"] = validate(package, review=True)
    return record
