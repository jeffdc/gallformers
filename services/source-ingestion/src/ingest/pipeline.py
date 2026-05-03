"""Pipeline runner: load YAML configs and execute multi-stage ingestion pipelines."""

from __future__ import annotations

import json
from pathlib import Path

import click
import yaml

from ingest.extract import extract_text
from ingest.llm import (
    MetadataResult,
    TokenUsage,
    clean_text,
    extract_data,
    extract_metadata,
)
from ingest.ocr import ocr_pdf
from ingest.output import assemble_document, build_frontmatter
from ingest.preprocess import preprocess
from ingest.providers import ProviderConfig, resolve_model

VALID_STEPS = frozenset(
    {
        "extract",
        "ocr",
        "preprocess",
        "llm-clean",
        "metadata",
        "data-extract",
        "assemble",
    }
)


def load_pipeline(config_path: str) -> dict:
    """Load and validate a pipeline YAML config.

    Returns the parsed pipeline dict with 'name' and 'stages' keys.

    Raises:
        FileNotFoundError: If the config file does not exist.
        ValueError: On invalid config structure or unknown step types.
    """
    path = Path(config_path)
    if not path.exists():
        raise FileNotFoundError(f"Pipeline config not found: {config_path}")

    with path.open() as f:
        raw = yaml.safe_load(f)

    if not isinstance(raw, dict) or "pipeline" not in raw:
        raise ValueError(
            f"Pipeline config must contain a top-level 'pipeline' key: {config_path}"
        )

    pipeline = raw["pipeline"]

    if "name" not in pipeline:
        raise ValueError(f"Pipeline config must contain a 'name' field: {config_path}")

    if "stages" not in pipeline or not pipeline["stages"]:
        raise ValueError(
            f"Pipeline config must contain a non-empty 'stages' list: {config_path}"
        )

    _validate_stages(pipeline["stages"])

    return pipeline


def _validate_stages(stages: list[dict]) -> None:
    """Validate that all step types in a stage list are known."""
    for stage in stages:
        if "step" in stage:
            if stage["step"] not in VALID_STEPS:
                raise ValueError(
                    f"Unknown step type: {stage['step']!r}. "
                    f"Valid steps: {', '.join(sorted(VALID_STEPS))}"
                )
        elif "fork" in stage:
            for _branch_name, branch_stages in stage["fork"].items():
                _validate_stages(branch_stages)
        else:
            raise ValueError(f"Stage must contain either 'step' or 'fork': {stage}")


def run_pipeline(
    pipeline: dict,
    source_id: str | int,
    input_path: str | None,
    provider_config: dict,
    output_dir: str = "./output",
) -> None:
    """Execute a pipeline, running stages in sequence.

    Args:
        pipeline: Parsed pipeline config from load_pipeline().
        source_id: Source ID for output naming.
        input_path: Path to initial input file. Can be None when resuming
            a pipeline where early steps already have cached output.
        provider_config: Provider config dict for resolving models.
        output_dir: Base output directory.
    """
    name = pipeline["name"]
    stages = pipeline["stages"]
    source_dir = Path(output_dir) / str(source_id)
    source_dir.mkdir(parents=True, exist_ok=True)

    # Track state as we move through stages
    current_input = input_path
    step_outputs: dict[str, str] = {}  # step type -> most recent output path
    step_number = 0

    for stage in stages:
        if "fork" in stage:
            if current_input is None:
                raise ValueError(
                    "Fork stage needs to run but no input file is available. "
                    "Provide -i/--input to supply the initial input file."
                )
            _run_fork(
                fork_config=stage["fork"],
                name=name,
                source_id=source_id,
                current_input=current_input,
                step_number=step_number,
                step_outputs=step_outputs,
                provider_config=provider_config,
                source_dir=source_dir,
            )
            # After a fork, there's no single "current_input" — forks are terminal
            # or each branch continues independently. We don't rejoin.
            continue

        step_number += 1
        step_type = stage["step"]

        output_path = _output_path_for_step(
            source_dir, name, step_number, step_type, source_id
        )

        if output_path.exists():
            click.echo(f"Skipping {step_type} (output exists: {output_path})")
            current_input = str(output_path)
            step_outputs[step_type] = str(output_path)
            continue

        if current_input is None:
            raise ValueError(
                f"Step '{step_type}' needs to run but no input file is available. "
                f"Provide -i/--input to supply the initial input file."
            )

        click.echo(f"Running {step_type} (step {step_number})...")

        _run_step(
            step_type=step_type,
            stage=stage,
            input_path=current_input,
            output_path=output_path,
            source_id=source_id,
            step_outputs=step_outputs,
            provider_config=provider_config,
        )

        current_input = str(output_path)
        step_outputs[step_type] = str(output_path)


def _run_fork(
    fork_config: dict,
    name: str,
    source_id: str | int,
    current_input: str,
    step_number: int,
    step_outputs: dict[str, str],
    provider_config: dict,
    source_dir: Path,
) -> None:
    """Run forked branches of the pipeline."""
    for branch_name, branch_stages in fork_config.items():
        branch_input = current_input
        branch_outputs = dict(step_outputs)  # copy shared state

        for i, stage in enumerate(branch_stages, start=step_number + 1):
            step_type = stage["step"]

            output_path = _output_path_for_fork_step(
                source_dir, name, branch_name, i, step_type, source_id
            )

            if output_path.exists():
                click.echo(
                    f"Skipping {step_type} [{branch_name}] (output exists: {output_path})"
                )
                branch_input = str(output_path)
                branch_outputs[step_type] = str(output_path)
                continue

            click.echo(f"Running {step_type} [{branch_name}] (step {i})...")

            _run_step(
                step_type=step_type,
                stage=stage,
                input_path=branch_input,
                output_path=output_path,
                source_id=source_id,
                step_outputs=branch_outputs,
                provider_config=provider_config,
            )

            branch_input = str(output_path)
            branch_outputs[step_type] = str(output_path)


def _output_path_for_step(
    source_dir: Path, name: str, step_number: int, step_type: str, source_id: str | int
) -> Path:
    """Build output path for a regular (non-fork) step."""
    if step_type == "assemble":
        return source_dir / f"{name}-{source_id}.md"
    ext = ".json" if step_type in ("metadata", "data-extract") else ".md"
    return source_dir / f"{name}-{step_number}-{step_type}{ext}"


def _output_path_for_fork_step(
    source_dir: Path,
    name: str,
    branch_name: str,
    step_number: int,
    step_type: str,
    source_id: str | int,
) -> Path:
    """Build output path for a forked step."""
    if step_type == "assemble":
        return source_dir / f"{name}-{branch_name}-{source_id}.md"
    ext = ".json" if step_type in ("metadata", "data-extract") else ".md"
    return source_dir / f"{name}-{branch_name}-{step_number}-{step_type}{ext}"


def _run_step(
    step_type: str,
    stage: dict,
    input_path: str,
    output_path: Path,
    source_id: str | int,
    step_outputs: dict[str, str],
    provider_config: dict,
) -> None:
    """Dispatch and run a single pipeline step."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if step_type == "extract":
        _run_extract(input_path, output_path)
    elif step_type == "ocr":
        provider = resolve_model(stage["model"], provider_config)
        _run_ocr(input_path, output_path, provider=provider)
    elif step_type == "preprocess":
        _run_preprocess(input_path, output_path)
    elif step_type == "llm-clean":
        provider = resolve_model(stage["model"], provider_config)
        _run_llm_clean(input_path, output_path, provider=provider)
    elif step_type == "metadata":
        provider = resolve_model(stage["model"], provider_config)
        _run_metadata(input_path, output_path, provider=provider)
    elif step_type == "data-extract":
        provider = resolve_model(stage["model"], provider_config)
        _run_data_extract(
            input_path, output_path, provider=provider, step_outputs=step_outputs
        )
    elif step_type == "assemble":
        _run_assemble(
            input_path, output_path, source_id=source_id, step_outputs=step_outputs
        )


def _run_extract(input_path: str, output_path: Path, **kwargs: object) -> None:
    text = extract_text(input_path)
    output_path.write_text(text)


def _run_ocr(
    input_path: str, output_path: Path, *, provider: ProviderConfig, **kwargs: object
) -> None:
    result = ocr_pdf(input_path, provider)
    output_path.write_text(result.text)


def _run_preprocess(input_path: str, output_path: Path, **kwargs: object) -> None:
    text = Path(input_path).read_text()
    result = preprocess(text)
    output_path.write_text(result)


def _run_llm_clean(
    input_path: str, output_path: Path, *, provider: ProviderConfig, **kwargs: object
) -> None:
    text = Path(input_path).read_text()
    result = clean_text(text, provider)
    output_path.write_text(result.text)


def _run_data_extract(
    input_path: str,
    output_path: Path,
    *,
    provider: ProviderConfig,
    step_outputs: dict[str, str],
    **kwargs: object,
) -> None:
    # Read from llm-clean output (the cleaned text), not the previous step
    # which may be metadata JSON or other non-text output.
    text_path = step_outputs.get("llm-clean", input_path)
    text = Path(text_path).read_text()
    result = extract_data(text, provider)
    output_path.write_text(json.dumps(result.records, indent=2))


def _run_metadata(
    input_path: str, output_path: Path, *, provider: ProviderConfig, **kwargs: object
) -> None:
    text = Path(input_path).read_text()
    result = extract_metadata(text, provider)
    data = {
        "title": result.title,
        "authors": result.authors,
        "year": result.year,
        "doi": result.doi,
    }
    output_path.write_text(json.dumps(data, indent=2))


def _run_assemble(
    input_path: str,
    output_path: Path,
    *,
    source_id: str | int,
    step_outputs: dict[str, str],
    **kwargs: object,
) -> None:
    """Assemble final document from cleaned text and metadata.

    Uses the llm-clean output as the document body (falling back to
    input_path if llm-clean hasn't run). This ensures the body is always
    the cleaned text, not output from later steps like data-extract.
    """
    metadata_path = step_outputs.get("metadata")
    if not metadata_path:
        raise ValueError(
            "assemble step requires a preceding metadata step, but none was found"
        )

    # Prefer llm-clean output as body; fall back to input_path for pipelines
    # that don't have steps after llm-clean (e.g., no data-extract).
    body_path = step_outputs.get("llm-clean", input_path)
    body = Path(body_path).read_text()
    meta_raw = Path(metadata_path).read_text()
    meta_data = json.loads(meta_raw)

    meta = MetadataResult(
        title=meta_data.get("title"),
        authors=meta_data.get("authors", []),
        year=meta_data.get("year"),
        doi=meta_data.get("doi"),
        usage=TokenUsage(0, 0),
    )

    frontmatter = build_frontmatter(source_id, meta)
    document = assemble_document(frontmatter, body)
    output_path.write_text(document)
