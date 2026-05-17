"""CLI entry point for the north-star ingestion pipeline.

Skeleton only. Bridges sync click commands to the async ``run_pipeline``
with a single ``asyncio.run(...)`` per invocation. The full subcommand set
will land as stages are implemented; for now the only command is ``run``,
and it surfaces a clear ``NotImplementedError`` until the runner is wired.
"""

from __future__ import annotations

import asyncio
import contextlib
import sys
from pathlib import Path

import click

from ingest.pipeline import load_pipeline, run_pipeline
from ingest.providers import load_config

DEFAULT_PIPELINE = "pipelines/default.yaml"
DEFAULT_CONFIG = "providers.yaml"
DEFAULT_OUTPUT = "./output"


class _Tee:
    """Write to multiple streams. Used to duplicate stdout/stderr into a run log
    so users see live progress while a copy lands in ``<src_dir>/run.log``.
    """

    def __init__(self, *streams) -> None:
        self.streams = streams

    def write(self, data) -> int:
        for s in self.streams:
            s.write(data)
        return len(data) if isinstance(data, str) else 0

    def flush(self) -> None:
        for s in self.streams:
            with contextlib.suppress(Exception):
                s.flush()

    def isatty(self) -> bool:
        return False


@click.group(invoke_without_command=True)
@click.pass_context
def cli(ctx: click.Context) -> None:
    """Source ingestion pipeline for gallformers."""
    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())


@cli.command()
@click.option(
    "-p",
    "--pipeline",
    "pipeline_path",
    default=DEFAULT_PIPELINE,
    show_default=True,
    help="Pipeline YAML config path (resolved relative to CWD)",
)
@click.option(
    "-s",
    "--source-id",
    required=True,
    type=str,
    help="Run identifier; used as the output subdirectory name (e.g. 'nicholls', 'felt-1940')",
)
@click.option(
    "-i", "--input", "input_path", default=None, help="Input file (optional when resuming)"
)
@click.option(
    "-c",
    "--config",
    "config_path",
    default=DEFAULT_CONFIG,
    show_default=True,
    help="Provider config YAML path (resolved relative to CWD)",
)
@click.option(
    "-o",
    "--output",
    "output_dir",
    default=DEFAULT_OUTPUT,
    show_default=True,
    help="Parent output directory; run lands at <output>/<source-id>/",
)
def run(
    pipeline_path: str,
    source_id: str,
    input_path: str | None,
    config_path: str,
    output_dir: str,
) -> None:
    """Run a multi-stage ingestion pipeline."""
    src_dir = Path(output_dir) / source_id
    src_dir.mkdir(parents=True, exist_ok=True)
    log_path = src_dir / "run.log"

    # Tee stdout+stderr into the run log alongside the run's artifacts.
    real_stdout, real_stderr = sys.stdout, sys.stderr
    with log_path.open("w", buffering=1) as log_file:
        sys.stdout = _Tee(real_stdout, log_file)
        sys.stderr = _Tee(real_stderr, log_file)
        try:
            try:
                pipeline = load_pipeline(pipeline_path)
            except (FileNotFoundError, ValueError) as exc:
                click.echo(f"Error: {exc}", err=True)
                sys.exit(1)

            try:
                provider_config = load_config(config_path)
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
        finally:
            sys.stdout, sys.stderr = real_stdout, real_stderr


if __name__ == "__main__":
    cli()
