# /// script
# requires-python = ">=3.10"
# dependencies = ["jsonschema>=4.18", "referencing>=0.30"]
# ///
"""Validate Gallformers import batches against the schemas (layer 1).

Usage:
    uv run priv/import/validate.py PATH [PATH ...]
    python3 priv/import/validate.py PATH [PATH ...]   # needs jsonschema >= 4.18

PATH is a batch file (taxonomy.json / gall.json) or a package directory, in
which case every taxonomy.json and gall.json in it is validated.

Only the schemas are checked here. The Gallformers dry run (layer 2: name and
Gall resolution, quote verification, cross-reference rules) runs on import;
see PRODUCER_GUIDE.md section 7.

Exit status: 0 if every batch is valid, 1 otherwise.
"""

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parent
BATCH_FILES = ("taxonomy.json", "gall.json")


def load_registry():
    registry = Registry()
    schemas = {}
    paths = sorted((ROOT / "schema").glob("*.json")) + sorted((ROOT / "vocab").glob("*.schema.json"))
    for path in paths:
        contents = json.loads(path.read_text(encoding="utf-8"))
        registry = registry.with_resource(contents["$id"], Resource.from_contents(contents))
        schemas[path.name] = contents
    return registry, schemas


def batch_paths(args):
    for arg in args:
        path = Path(arg)
        if path.is_dir():
            found = [path / name for name in BATCH_FILES if (path / name).exists()]
            if not found:
                yield path, "no taxonomy.json or gall.json in this directory"
            for batch in found:
                yield batch, None
        else:
            yield path, None


def errors_for(path, registry, schemas):
    try:
        batch = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return ["file not found"]
    except json.JSONDecodeError as exc:
        return [f"not valid JSON: {exc}"]

    if not isinstance(batch, dict) or batch.get("format") != "gallformers-import":
        return ['not a Gallformers import batch (expected "format": "gallformers-import")']
    batch_type = batch.get("batch_type")
    if batch_type not in ("taxonomy", "gall"):
        return [f'batch_type must be "taxonomy" or "gall", got {batch_type!r}']

    validator = Draft202012Validator(
        schemas[f"{batch_type}.schema.json"],
        registry=registry,
        format_checker=Draft202012Validator.FORMAT_CHECKER,
    )
    found = sorted(validator.iter_errors(batch), key=lambda e: list(map(str, e.absolute_path)))
    return [f"{'/'.join(map(str, e.absolute_path)) or '(root)'}: {e.message}" for e in found]


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2

    registry, schemas = load_registry()
    failed = 0
    for path, problem in batch_paths(argv):
        errors = [problem] if problem else errors_for(path, registry, schemas)
        if errors:
            failed += 1
            print(f"INVALID {path}")
            for error in errors:
                print(f"  {error}")
        else:
            print(f"valid   {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
