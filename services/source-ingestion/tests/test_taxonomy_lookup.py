"""Tests for the taxonomy-lookup stage (GBIF).

``httpx.AsyncClient.get`` is mocked at the boundary so no real network
calls are made.
"""

from __future__ import annotations

import json
from unittest.mock import AsyncMock, MagicMock

import httpx
import pytest

from ingest.schemas import (
    Evidence,
    ScientificNameCell,
    SupportStatus,
    TaxonomyLookupSource,
    TaxonomyLookupStatus,
)
from ingest.taxonomy_lookup import (
    _cache_key,
    _parse_gbif_response,
    enrich_name_cell,
    lookup_name,
)


def _gbif_response(
    *,
    match_type: str = "EXACT",
    status: str = "ACCEPTED",
    usage_key: int = 2879294,
    scientific_name: str = "Quercus alba L.",
    canonical_name: str = "Quercus alba",
    kingdom: str = "Plantae",
    family: str = "Fagaceae",
    confidence: int = 99,
    accepted: str | None = None,
) -> dict:
    out = {
        "usageKey": usage_key,
        "scientificName": scientific_name,
        "canonicalName": canonical_name,
        "rank": "SPECIES",
        "status": status,
        "confidence": confidence,
        "matchType": match_type,
        "kingdom": kingdom,
        "family": family,
        "genus": canonical_name.split()[0] if canonical_name else None,
    }
    if accepted:
        out["acceptedScientificName"] = accepted
    return out


def _mock_response(payload: dict, status_code: int = 200):
    """Build a fake httpx Response."""
    response = MagicMock()
    response.status_code = status_code
    response.json = MagicMock(return_value=payload)
    response.raise_for_status = MagicMock()
    if status_code >= 400:
        response.raise_for_status.side_effect = httpx.HTTPStatusError(
            "boom", request=MagicMock(), response=response
        )
    return response


# ─── Pure-function tests ──────────────────────────────────────────────────


class TestCacheKey:
    def test_same_inputs_yield_same_key(self):
        assert _cache_key("Quercus alba", "Plantae") == _cache_key("Quercus alba", "Plantae")

    def test_different_kingdom_yields_different_key(self):
        assert _cache_key("X", "Plantae") != _cache_key("X", "Animalia")

    def test_no_kingdom_treated_consistently(self):
        # None and "" produce the same key (both empty).
        assert _cache_key("X", None) == _cache_key("X", None)


class TestParseGbifResponse:
    def test_exact_match_populates_match(self):
        lookup = _parse_gbif_response("Quercus alba", _gbif_response())
        assert lookup.source == TaxonomyLookupSource.GBIF
        assert lookup.status == TaxonomyLookupStatus.EXACT
        assert lookup.match is not None
        assert lookup.match.scientific_name == "Quercus alba L."
        assert lookup.match.canonical_name == "Quercus alba"
        assert lookup.match.kingdom == "Plantae"
        assert lookup.match.family == "Fagaceae"
        assert lookup.match.source_key == "2879294"
        assert lookup.match.url == "https://www.gbif.org/species/2879294"
        assert lookup.confidence == pytest.approx(0.99)

    def test_fuzzy_match_typed_as_fuzzy(self):
        lookup = _parse_gbif_response(
            "Querc alba", _gbif_response(match_type="FUZZY", confidence=85)
        )
        assert lookup.status == TaxonomyLookupStatus.FUZZY
        assert lookup.confidence == pytest.approx(0.85)

    def test_synonym_status_promotes_to_synonym(self):
        raw = _gbif_response(status="SYNONYM", accepted="Quercus dumosa")
        lookup = _parse_gbif_response("Quercus berberidifolia", raw)
        assert lookup.status == TaxonomyLookupStatus.SYNONYM
        assert lookup.match is not None
        assert lookup.match.accepted_name == "Quercus dumosa"

    def test_no_match_has_null_match(self):
        raw = _gbif_response(match_type="NONE")
        lookup = _parse_gbif_response("Xenoxyz nothere", raw)
        assert lookup.status == TaxonomyLookupStatus.NO_MATCH
        assert lookup.match is None

    def test_higherrank_treated_as_no_match(self):
        raw = _gbif_response(match_type="HIGHERRANK")
        lookup = _parse_gbif_response("Quercus", raw)
        assert lookup.status == TaxonomyLookupStatus.NO_MATCH


# ─── lookup_name HTTP behavior ────────────────────────────────────────────


class TestLookupName:
    async def test_happy_path_uses_provided_client(self, mocker):
        client = MagicMock()
        client.get = AsyncMock(return_value=_mock_response(_gbif_response()))

        lookup = await lookup_name("Quercus alba", client=client)

        client.get.assert_awaited_once()
        # First positional arg is URL, second is the kwargs dict via params=...
        call_kwargs = client.get.call_args.kwargs
        assert call_kwargs["params"]["name"] == "Quercus alba"
        assert "kingdom" not in call_kwargs["params"]
        assert lookup.status == TaxonomyLookupStatus.EXACT

    async def test_http_error_yields_api_error_lookup(self, mocker):
        client = MagicMock()
        client.get = AsyncMock(return_value=_mock_response({}, status_code=503))

        lookup = await lookup_name("Quercus alba", client=client)

        assert lookup.status == TaxonomyLookupStatus.API_ERROR
        assert lookup.match is None

    async def test_connection_error_yields_api_error_lookup(self, mocker):
        client = MagicMock()
        client.get = AsyncMock(side_effect=httpx.ConnectError("boom"))

        lookup = await lookup_name("Quercus alba", client=client)
        assert lookup.status == TaxonomyLookupStatus.API_ERROR

    async def test_empty_name_skips_http_call(self):
        # client absent — would fail if a call was attempted.
        lookup = await lookup_name("   ")
        assert lookup.status == TaxonomyLookupStatus.NO_MATCH

    async def test_cache_hit_skips_http_call(self, tmp_path, mocker):
        # Pre-seed cache.
        cache_dir = tmp_path / "cache"
        cache_dir.mkdir()
        payload = _gbif_response()
        key = _cache_key("Quercus alba", None)
        (cache_dir / f"{key}.json").write_text(json.dumps(payload))

        client = MagicMock()
        client.get = AsyncMock()

        lookup = await lookup_name("Quercus alba", client=client, cache_dir=cache_dir)

        client.get.assert_not_awaited()
        assert lookup.status == TaxonomyLookupStatus.EXACT

    async def test_cache_miss_writes_through(self, tmp_path):
        cache_dir = tmp_path / "cache"
        client = MagicMock()
        client.get = AsyncMock(return_value=_mock_response(_gbif_response()))

        await lookup_name("Quercus alba", client=client, cache_dir=cache_dir)

        key = _cache_key("Quercus alba", None)
        cache_file = cache_dir / f"{key}.json"
        assert cache_file.exists()
        assert "Quercus alba" in cache_file.read_text()


# ─── enrich_name_cell ─────────────────────────────────────────────────────


class TestEnrichNameCell:
    async def test_appends_lookup_to_taxonomy_lookups(self, mocker):
        cell = ScientificNameCell(
            value="Quercus alba",
            evidence=[Evidence(block_id="p1-b0", page=1, char_start=0, char_end=1, quote="q")],
            support_status=SupportStatus.SUPPORTED,
            confidence=0.9,
        )
        client = MagicMock()
        client.get = AsyncMock(return_value=_mock_response(_gbif_response()))

        new_cell = await enrich_name_cell(cell, client=client, kingdom_hint="Plantae")

        assert len(new_cell.taxonomy_lookups) == 1
        assert new_cell.taxonomy_lookups[0].source == TaxonomyLookupSource.GBIF
        assert new_cell.taxonomy_lookups[0].status == TaxonomyLookupStatus.EXACT
        # Kingdom hint propagated to the request.
        call_kwargs = client.get.call_args.kwargs
        assert call_kwargs["params"]["kingdom"] == "Plantae"

    async def test_empty_value_cell_skipped(self, mocker):
        cell = ScientificNameCell(
            value=None,
            evidence=[],
            support_status=SupportStatus.ABSTAINED,
            confidence=0.0,
        )
        client = MagicMock()
        client.get = AsyncMock()

        new_cell = await enrich_name_cell(cell, client=client)

        client.get.assert_not_awaited()
        assert new_cell.taxonomy_lookups == []
