"""JSONL serialization for Pydantic models.

Used by every JSONL artifact in the bundle (raw_text.jsonl,
normalized_text.jsonl). One JSON object per line; validates on read.
"""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

from pydantic import BaseModel


def write_jsonl(items: Iterable[BaseModel], path: Path) -> None:
    """Write each Pydantic model instance as one JSON line.

    ``Iterable`` rather than ``list`` so callers can pass any subtype-narrowed
    list (e.g., ``list[RawTextBlock]``) without invariance errors.
    """
    with path.open("w") as f:
        for item in items:
            _ = f.write(item.model_dump_json() + "\n")


def read_jsonl[T: BaseModel](path: Path, model: type[T]) -> list[T]:
    """Read and validate JSONL lines into model instances. Skips empty lines."""
    items: list[T] = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if line:
                items.append(model.model_validate_json(line))
    return items
