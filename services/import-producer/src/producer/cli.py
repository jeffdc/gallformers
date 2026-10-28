"""Command line: `uv run produce <command>`."""

import json
from pathlib import Path

import click

from producer import paths


@click.group()
def cli():
    """Turn a Source (PDF) into a Gallformers import package."""


@cli.command("convert-url")
@click.argument("url")
@click.option(
    "-o", "--out", "out_dir", required=True, type=click.Path(file_okay=False, path_type=Path)
)
def convert_url(url, out_dir):
    """Phase 1 for a web page: URL -> document.json (free, local)."""
    from producer.convert import convert_url as run_convert_url

    click.echo(json.dumps(run_convert_url(url, out_dir), indent=2))


@cli.command()
@click.argument("pdf", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option(
    "-o", "--out", "out_dir", required=True, type=click.Path(file_okay=False, path_type=Path)
)
@click.option(
    "--ocr",
    type=click.Choice(["auto", "force", "off"]),
    default="auto",
    show_default=True,
    help="auto: scans keep the better of their own text and fresh OCR.",
)
def convert(pdf, out_dir, ocr):
    """Phase 1: PDF -> document.json (free, local)."""
    from producer.convert import convert as run_convert

    record = run_convert(pdf, out_dir, ocr=ocr)
    click.echo(json.dumps(record, indent=2))


@cli.command()
@click.argument("package", type=click.Path(exists=True, file_okay=False, path_type=Path))
def render(package):
    """Re-render <package>/document.txt from document.json."""
    from producer.document import load
    from producer.document import render as run_render

    (package / "document.txt").write_text(
        run_render(load(package / "document.json")), encoding="utf-8"
    )


@cli.command()
@click.argument("package", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.option(
    "--phase",
    type=click.IntRange(2, 6),
    required=True,
    help="2: taxonomy, 3: galls, 4: validate, 5: review, 6: respond",
)
@click.option(
    "--effort",
    type=click.Choice(["low", "medium", "high", "xhigh", "max"]),
    default="high",
    show_default=True,
)
@click.option(
    "--model",
    "models",
    multiple=True,
    help="Phase 5 reviewer model; repeat for several (default: Opus 5.5 and Sonnet 5.5).",
)
@click.option(
    "--dry-run", is_flag=True, help="Write the prompt and show the command; don't run Claude."
)
def phase(package, phase, effort, models, dry_run):
    """Run one phase on the package.

    2, 3, 5 and 6 run headless Claude Code (uses subscription usage); 4 runs validate.py (free).
    Phases 5 and 6 run only when phase 4 passes; 6 answers the findings of 5.
    """
    from producer.respond import run_respond
    from producer.review import REVIEWERS, run_review, validate
    from producer.run import append_run, run_phase

    if not (package / "document.txt").exists():
        raise click.ClickException(f"{package} has no document.txt; run `produce convert` first")
    if phase in (4, 5, 6):
        missing = [n for n in ("taxonomy.json", "gall.json") if not (package / n).exists()]
        if missing:
            raise click.ClickException(
                f"{package} has no {', '.join(missing)}; run phases 2 and 3 first"
            )
    if phase == 4:
        result = validate(package.resolve())
        click.echo(result["output"])
        raise SystemExit(result["exit"])
    if phase == 5:
        record = run_review(package, effort=effort, dry_run=dry_run, models=models or REVIEWERS)
    elif phase == 6:
        record = run_respond(package, effort=effort, dry_run=dry_run)
    else:
        record = run_phase(package, phase, effort=effort, dry_run=dry_run)
    if not dry_run:
        append_run(package, record)
    click.echo(json.dumps(record, indent=2))


@cli.group("golden")
@click.pass_context
def golden_group(ctx):
    """Golden regression set: the human-checked trial statements (free, no API calls)."""
    ctx.ensure_object(dict)


@golden_group.command("export")
@click.option(
    "--verdicts",
    required=True,
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    help="The check pages' exported verdicts: <dir>/<name>/checks/<doc id>.json.",
)
@click.option(
    "--trial",
    type=click.Path(file_okay=False, path_type=Path),
    default=paths.PROJECT / "output" / "trial",
    show_default=True,
    help="Directory holding the checked packages.",
)
@click.option(
    "--out",
    type=click.Path(file_okay=False, path_type=Path),
    default=paths.PROJECT / "golden",
    show_default=True,
)
@click.pass_context
def golden_export(ctx, verdicts, trial, out):
    """Write golden/<source id>-<short name>.json from the verdicts and checked packages."""
    from producer import golden

    for spec in ctx.obj.get("sources", golden.SOURCES):
        doc = golden.export_source(spec, trial / spec.package, verdicts / spec.checks / "checks")
        path = golden.write_golden(doc, out)
        c = doc["counts"]
        click.echo(f"{path.name}: statements {c['statements']}, name matches {c['names']}")


@golden_group.command("score")
@click.argument("run_dir", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.option(
    "--source", "source_id", type=int, help="Gallformers Source id (default: from the dir name)."
)
@click.option(
    "--golden",
    "golden_dir",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    default=paths.PROJECT / "golden",
    show_default=True,
)
@click.option(
    "--out",
    type=click.Path(dir_okay=False, path_type=Path),
    help="JSON report path (default: <run-dir>/golden-score.json).",
)
def golden_score(run_dir, source_id, golden_dir, out):
    """Score a new package for one of the golden Sources against the human verdicts."""
    from producer import golden

    source_id = source_id or golden.infer_source(run_dir)
    if source_id is None:
        raise click.ClickException(f"can't tell which Source {run_dir} is; pass --source")
    try:
        golden_file = golden.find_golden(source_id, golden_dir)
    except FileNotFoundError as e:
        raise click.ClickException(str(e)) from e
    report = golden.score(json.loads(golden_file.read_text(encoding="utf-8")), run_dir)
    out = out or run_dir / golden.REPORT_NAME
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    click.echo(golden.render(report))
    click.echo(f"report: {out}")


@cli.command("lookup-place")
@click.argument("name")
def lookup_place(name):
    """Find Gallformers place codes for a place name (or code)."""
    from producer.places import load_places, lookup

    results = lookup(name, load_places())
    if not results:
        click.echo(f"no place matches {name!r}")
    for place in results:
        country = f", {place['country']}" if place["country"] and place["type"] != "country" else ""
        click.echo(f"{place['code']}\t{place['name']} ({place['type']}{country})")
