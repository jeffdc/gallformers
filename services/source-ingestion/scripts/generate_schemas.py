"""Generate JSON Schema 2020-12 files from the Pydantic models in ingest/schemas.py.

Iterates `ARTIFACT_MODELS`; writes one `*.schema.json` per artifact under `schemas/`.

The generated files are the contract surface for server-side consumers (Elixir
validates against them without depending on Python). They are committed.

CI guard: run this script; if `schemas/` changes, the Pydantic models drifted
from the committed JSON Schemas and CI fails until the diff is committed.

Run:
    cd services/source-ingestion
    uv run python scripts/generate_schemas.py [--output schemas]
"""

from __future__ import annotations

import json
from pathlib import Path

import click

from ingest.schemas import ARTIFACT_MODELS, SCHEMA_VERSION


@click.command()
@click.option(
    "--output",
    type=click.Path(file_okay=False, dir_okay=True, writable=True, path_type=Path),
    default=Path("schemas"),
    show_default=True,
    help="Directory to write generated *.schema.json files into.",
)
def main(output: Path) -> None:
    """Regenerate all JSON Schema files from the current Pydantic models."""
    output.mkdir(parents=True, exist_ok=True)

    written: list[tuple[Path, str, str]] = []
    for artifact_filename, model in ARTIFACT_MODELS.items():
        # foo.json -> foo.schema.json; foo.jsonl -> foo.schema.json
        stem = artifact_filename.rsplit(".", 1)[0]
        schema_path = output / f"{stem}.schema.json"

        schema = model.model_json_schema()
        # Pydantic emits 2020-12-style schemas but doesn't include the $schema /
        # $id markers. Inject them so the files are self-describing for the
        # server-side validator.
        wrapped = {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": f"https://gallformers.org/schemas/{stem}.schema.json",
            "title": f"{model.__name__} (artifact: {artifact_filename})",
            "x-schema-version": SCHEMA_VERSION,
            **schema,
        }

        # Stable, sorted output so the CI drift guard is deterministic.
        schema_path.write_text(
            json.dumps(wrapped, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        )
        written.append((schema_path, artifact_filename, model.__name__))

    click.echo(f"Generated {len(written)} schema files in {output}:")
    for path, artifact, model_name in written:
        click.echo(f"  {path.name:35s} <- {model_name} (for {artifact})")


if __name__ == "__main__":
    main()
