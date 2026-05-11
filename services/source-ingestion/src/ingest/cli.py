"""CLI entry point for the north-star ingestion pipeline.

Skeleton only. Bridges sync click commands to the async ``run_pipeline``
with a single ``asyncio.run(...)`` per invocation. The full subcommand set
will land as stages are implemented; for now the only command is ``run``,
and it surfaces a clear ``NotImplementedError`` until the runner is wired.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import click

from ingest.pipeline import load_pipeline, run_pipeline
from ingest.providers import load_config

DEFAULT_CONFIG = Path(__file__).parent.parent.parent / "providers.example.yaml"


@click.group(invoke_without_command=True)
@click.pass_context
def cli(ctx: click.Context) -> None:
    """Source ingestion pipeline for gallformers."""
    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())


@cli.command()
@click.option("-p", "--pipeline", "pipeline_path", required=True, help="Pipeline YAML config path")
@click.option("--source-id", required=True, type=str, help="Source ID")
@click.option(
    "-i", "--input", "input_path", default=None, help="Input file (optional when resuming)"
)
@click.option("--config", "config_path", default=None, help="Provider config YAML path")
@click.option("-o", "--output", "output_dir", default="./output", help="Output directory")
def run(
    pipeline_path: str,
    source_id: str,
    input_path: str | None,
    config_path: str | None,
    output_dir: str,
) -> None:
    """Run a multi-stage ingestion pipeline."""
    try:
        pipeline = load_pipeline(pipeline_path)
    except (FileNotFoundError, ValueError) as exc:
        click.echo(f"Error: {exc}", err=True)
        sys.exit(1)

    config_file = config_path or str(DEFAULT_CONFIG)
    try:
        provider_config = load_config(config_file)
    except (FileNotFoundError, ValueError) as exc:
        click.echo(f"Error: {exc}", err=True)
        sys.exit(1)

    click.echo(f"Running pipeline '{pipeline['name']}' for source {source_id}")
    try:
        asyncio.run(
            run_pipeline(
                pipeline=pipeline,
                source_id=source_id,
                input_path=input_path,
                provider_config=provider_config,
                output_dir=output_dir,
            )
        )
    except NotImplementedError as exc:
        click.echo(f"Pipeline runner not yet wired: {exc}", err=True)
        sys.exit(2)


if __name__ == "__main__":
    cli()
