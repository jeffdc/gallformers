"""Taxonomy-lookup stage: GBIF name resolution with disk cache.

For each scientific-name cell that survived verification, hit GBIF's
``/v1/species/match`` endpoint and append a ``TaxonomyLookup`` to the cell's
``taxonomy_lookups`` list. The server appends a WCVP entry for plant names
during bundle import; the pipeline only writes GBIF.

GBIF outages are tolerated: ``on_api_error="continue"`` means a failed
lookup produces a ``TaxonomyLookup`` with ``status="api_error"`` and no
match — the bundle still assembles. The reviewer sees "lookup unavailable"
rather than a misleading "no match."

Cache: per-query disk JSON files keyed by ``(name, kingdom_hint)``. Taxonomy
moves slowly; cache TTL is effectively unbounded (the cache directory can be
purged when the user wants fresh results).
"""

from __future__ import annotations

import asyncio
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx

from ingest.schemas import (
    ScientificNameCell,
    TaxonomyLookup,
    TaxonomyLookupSource,
    TaxonomyLookupStatus,
    TaxonomyMatch,
)

GBIF_MATCH_URL = "https://api.gbif.org/v1/species/match"

# Map GBIF matchType values to our TaxonomyLookupStatus enum.
_MATCH_TYPE_TO_STATUS: dict[str, TaxonomyLookupStatus] = {
    "EXACT": TaxonomyLookupStatus.EXACT,
    "FUZZY": TaxonomyLookupStatus.FUZZY,
    "HIGHERRANK": TaxonomyLookupStatus.NO_MATCH,
    "NONE": TaxonomyLookupStatus.NO_MATCH,
}


def _cache_key(name: str, kingdom_hint: str | None) -> str:
    """Build a stable filename-safe cache key for a query."""
    payload = json.dumps({"name": name, "kingdom": kingdom_hint or ""}, sort_keys=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def _cache_get(cache_dir: Path | None, key: str) -> dict[str, Any] | None:
    if cache_dir is None:
        return None
    path = cache_dir / f"{key}.json"
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _cache_put(cache_dir: Path | None, key: str, payload: dict[str, Any]) -> None:
    if cache_dir is None:
        return
    cache_dir.mkdir(parents=True, exist_ok=True)
    (cache_dir / f"{key}.json").write_text(json.dumps(payload))


def _parse_gbif_response(name: str, raw: dict[str, Any]) -> TaxonomyLookup:
    """Convert a GBIF /species/match response to our TaxonomyLookup shape."""
    match_type = (raw.get("matchType") or "NONE").upper()
    status = _MATCH_TYPE_TO_STATUS.get(match_type, TaxonomyLookupStatus.NO_MATCH)

    # Promote ACCEPTED→EXACT and detect SYNONYM from the response's `status`
    # rather than matchType (GBIF reports them separately).
    gbif_status = (raw.get("status") or "").upper()
    if gbif_status == "SYNONYM" and status in (
        TaxonomyLookupStatus.EXACT,
        TaxonomyLookupStatus.FUZZY,
    ):
        status = TaxonomyLookupStatus.SYNONYM

    confidence_pct = raw.get("confidence")
    confidence = (
        (float(confidence_pct) / 100.0) if isinstance(confidence_pct, (int, float)) else None
    )

    if status == TaxonomyLookupStatus.NO_MATCH:
        match = None
    else:
        usage_key = raw.get("usageKey")
        match = TaxonomyMatch(
            scientific_name=raw.get("scientificName") or name,
            rank=(raw.get("rank") or None) and raw["rank"].lower(),
            kingdom=raw.get("kingdom"),
            phylum=raw.get("phylum"),
            class_name=raw.get("class"),
            order=raw.get("order"),
            family=raw.get("family"),
            genus=raw.get("genus"),
            canonical_name=raw.get("canonicalName"),
            accepted_name=(
                raw.get("acceptedScientificName") or raw.get("accepted")
                if status == TaxonomyLookupStatus.SYNONYM
                else None
            ),
            source_key=str(usage_key) if usage_key is not None else None,
            url=f"https://www.gbif.org/species/{usage_key}" if usage_key is not None else None,
        )

    return TaxonomyLookup(
        source=TaxonomyLookupSource.GBIF,
        status=status,
        match=match,
        confidence=confidence,
        queried_at=datetime.now(UTC),
    )


async def lookup_name(
    name: str,
    *,
    kingdom_hint: str | None = None,
    cache_dir: Path | None = None,
    client: httpx.AsyncClient | None = None,
    timeout: float = 30.0,
) -> TaxonomyLookup:
    """Resolve a single scientific name via GBIF. Cached if ``cache_dir`` is provided.

    On any HTTP error, returns a ``TaxonomyLookup`` with
    ``status=TaxonomyLookupStatus.API_ERROR`` and ``match=None``. The bundle
    still assembles; the reviewer sees "lookup unavailable".
    """
    if not name.strip():
        return TaxonomyLookup(
            source=TaxonomyLookupSource.GBIF,
            status=TaxonomyLookupStatus.NO_MATCH,
            match=None,
            confidence=None,
            queried_at=datetime.now(UTC),
        )

    key = _cache_key(name, kingdom_hint)
    cached = _cache_get(cache_dir, key)
    if cached is not None:
        return _parse_gbif_response(name, cached)

    params: dict[str, str] = {"name": name}
    if kingdom_hint:
        params["kingdom"] = kingdom_hint

    owns_client = client is None
    if client is None:
        client = httpx.AsyncClient(timeout=timeout)

    try:
        try:
            response = await client.get(GBIF_MATCH_URL, params=params)
            response.raise_for_status()
            raw = response.json()
            _cache_put(cache_dir, key, raw)
            return _parse_gbif_response(name, raw)
        except (httpx.HTTPError, json.JSONDecodeError):
            return TaxonomyLookup(
                source=TaxonomyLookupSource.GBIF,
                status=TaxonomyLookupStatus.API_ERROR,
                match=None,
                confidence=None,
                queried_at=datetime.now(UTC),
            )
    finally:
        if owns_client:
            await client.aclose()


async def enrich_name_cell(
    cell: ScientificNameCell,
    *,
    kingdom_hint: str | None = None,
    cache_dir: Path | None = None,
    client: httpx.AsyncClient | None = None,
    timeout: float = 30.0,
) -> ScientificNameCell:
    """Append a GBIF TaxonomyLookup to a ScientificNameCell.

    Skips the lookup when the cell's value is empty (abstained / nulled).
    The cell's existing ``taxonomy_lookups`` are preserved; the GBIF lookup
    is appended.
    """
    if not cell.value:
        return cell
    lookup = await lookup_name(
        cell.value,
        kingdom_hint=kingdom_hint,
        cache_dir=cache_dir,
        client=client,
        timeout=timeout,
    )
    return cell.model_copy(update={"taxonomy_lookups": [*cell.taxonomy_lookups, lookup]})


async def enrich_cells_concurrently(
    cells_with_kingdoms: list[tuple[ScientificNameCell, str | None]],
    *,
    cache_dir: Path | None = None,
    max_workers: int = 8,
    timeout: float = 30.0,
) -> list[ScientificNameCell]:
    """Enrich many cells in parallel with a shared ``httpx.AsyncClient``.

    Used by the pipeline's taxonomy-lookup stage to process every name in
    a paper without opening a fresh HTTP connection per call. Concurrency
    is capped by ``max_workers`` via an ``asyncio.Semaphore``.
    """
    semaphore = asyncio.Semaphore(max_workers)

    async with httpx.AsyncClient(timeout=timeout) as client:

        async def _one(cell: ScientificNameCell, kingdom: str | None) -> ScientificNameCell:
            async with semaphore:
                return await enrich_name_cell(
                    cell,
                    kingdom_hint=kingdom,
                    cache_dir=cache_dir,
                    client=client,
                    timeout=timeout,
                )

        return await asyncio.gather(*[_one(cell, kingdom) for cell, kingdom in cells_with_kingdoms])
