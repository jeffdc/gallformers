"""Tests for the extract-facts stage.

Instructor's async client is mocked at the
``instructor.from_litellm`` boundary so the stage code under test runs
through its scrub/wrap logic without hitting any provider.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

from ingest.extract_facts import _LLMFacts, _record_id_from_candidate, extract_facts
from ingest.schemas import (
    Candidate,
    ConfidenceBucket,
    Evidence,
    GallMaker,
    GallTraits,
    Host,
    ProseParagraph,
    ScientificNameCell,
    SupportStatus,
    Taxonomy,
    TraitCell,
)


def _evidence(block_id: str, quote: str = "q", page: int = 1) -> Evidence:
    return Evidence(block_id=block_id, page=page, char_start=0, char_end=1, quote=quote)


def _name_cell(value: str | None, *, evidence_block_id: str = "S_0001") -> ScientificNameCell:
    return ScientificNameCell(
        value=value,
        evidence=[_evidence(evidence_block_id)],
        support_status=SupportStatus.SUPPORTED,
        confidence=0.9,
    )


def _trait_cell(
    original: str, suggested: list[str], *, evidence_block_id: str = "S_0001"
) -> TraitCell:
    return TraitCell(
        original=original,
        suggested=suggested,
        evidence=[_evidence(evidence_block_id)],
        support_status=SupportStatus.SUPPORTED,
        confidence=0.9,
    )


def _prose(span_id: str, text: str, page: int = 1) -> ProseParagraph:
    return ProseParagraph(
        span_id=span_id, page=page, char_start=0, char_end=max(len(text), 1), text=text
    )


def _candidate(cid: str = "C_001", generation: str = "unspecified") -> Candidate:
    return Candidate(
        candidate_id=cid,
        gall_maker_mention="Andricus quercuscalifornicus",
        mention_span_ids=["S_0001"],
        sample_agreement=3,
        generation=generation,
    )


def _llm_facts(
    *,
    name_evidence_block: str = "S_0001",
    trait_evidence_block: str = "S_0001",
) -> _LLMFacts:
    return _LLMFacts(
        gall_maker=GallMaker(
            scientific_name=_name_cell(
                "Andricus quercuscalifornicus", evidence_block_id=name_evidence_block
            ),
            taxonomy=Taxonomy(),
        ),
        hosts=[
            Host(
                scientific_name=_name_cell(
                    "Quercus agrifolia", evidence_block_id=name_evidence_block
                )
            )
        ],
        gall_traits=GallTraits(
            color=_trait_cell("red", ["red"], evidence_block_id=trait_evidence_block),
        ),
        location=None,
        confidence_bucket=ConfidenceBucket.HIGH,
    )


def _mock_completion(prompt_tokens: int = 100, completion_tokens: int = 50):
    completion = MagicMock()
    completion.usage = MagicMock()
    completion.usage.prompt_tokens = prompt_tokens
    completion.usage.completion_tokens = completion_tokens
    return completion


def _install_mock_client(mocker, facts: _LLMFacts, completion=None):
    """Stub Instructor's async client. Returns the mock for further assertions."""
    if completion is None:
        completion = _mock_completion()
    mock_client = MagicMock()
    mock_client.create_with_completion = AsyncMock(return_value=(facts, completion))
    mocker.patch("ingest.extract_facts.make_instructor_client", return_value=mock_client)
    mocker.patch("ingest.extract_facts._safe_completion_cost", return_value=0.05)
    return mock_client


class TestRecordIdFromCandidate:
    def test_basic_mapping(self):
        assert _record_id_from_candidate("C_001") == "R_001"
        assert _record_id_from_candidate("C_042") == "R_042"

    def test_no_underscore_still_works(self):
        assert _record_id_from_candidate("foo") == "R_foo"


class TestExtractFactsHappyPath:
    async def test_returns_record_with_correct_ids(self, mocker):
        _install_mock_client(mocker, _llm_facts())
        record, call = await extract_facts(
            candidate=_candidate("C_007"),
            evidence_prose=[_prose("S_0001", "some text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="extract prompt",
            prompt_sha256="a" * 64,
        )
        assert record.record_id == "R_007"
        assert record.candidate_id == "C_007"
        assert record.gall_maker.scientific_name.value == "Andricus quercuscalifornicus"
        assert record.hosts[0].scientific_name.value == "Quercus agrifolia"
        assert record.gall_traits.color is not None
        assert record.gall_traits.color.suggested == ["red"]

    async def test_record_carries_full_evidence_prose(self, mocker):
        """Every span in the pack appears in the record's evidence_prose so the
        UI can render the full curator-facing prose pack with per-span signals."""
        _install_mock_client(mocker, _llm_facts())
        prose = [
            _prose("S_0001", "Andricus quercuscalifornicus first paragraph.", page=4),
            _prose("S_0002", "Second paragraph with biology details.", page=4),
            _prose("S_0003", "Distribution prose across the southwest.", page=5),
        ]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001", "S_0002", "S_0003"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        assert [p.span_id for p in record.evidence_prose] == ["S_0001", "S_0002", "S_0003"]
        assert [p.text for p in record.evidence_prose] == [p.text for p in prose]

    async def test_is_cited_true_for_spans_referenced_by_any_cell(self, mocker):
        """A span is is_cited=True if any extracted fact's Evidence.block_id
        references it. Spans that no cell cites are is_cited=False."""
        # _llm_facts() cites S_0001 from gall_maker.scientific_name, hosts[0].scientific_name,
        # and gall_traits.color. S_0002 is in the pack but not cited.
        _install_mock_client(mocker, _llm_facts())
        prose = [
            _prose("S_0001", "Andricus quercuscalifornicus is the gall maker.", page=1),
            _prose("S_0002", "An unrelated paragraph not cited by any fact.", page=1),
        ]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001", "S_0002"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        by_span = {p.span_id: p for p in record.evidence_prose}
        assert by_span["S_0001"].is_cited is True
        assert by_span["S_0002"].is_cited is False

    async def test_cited_by_fields_lists_all_citing_paths_sorted(self, mocker):
        """cited_by_fields enumerates every field path whose evidence references
        this span. Multiple citations of the same span list every field; paths
        are stable-sorted for deterministic curator-facing output."""
        _install_mock_client(mocker, _llm_facts())
        prose = [_prose("S_0001", "Some text.", page=1)]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        # _llm_facts cites S_0001 from gall_maker.scientific_name, hosts[0].scientific_name,
        # and gall_traits.color.
        assert record.evidence_prose[0].cited_by_fields == [
            "gall_maker.scientific_name",
            "gall_traits.color",
            "hosts[0].scientific_name",
        ]

    async def test_relevance_high_when_cited(self, mocker):
        """A cited span is HIGH regardless of mention/length signals."""
        _install_mock_client(mocker, _llm_facts())  # cites S_0001
        # Short text, not a mention — would be LOW without the citation.
        cand = Candidate(
            candidate_id="C_001",
            gall_maker_mention="Andricus quercuscalifornicus",
            mention_span_ids=[],
            sample_agreement=3,
            generation="unspecified",
        )
        prose = [_prose("S_0001", "short")]
        record, _ = await extract_facts(
            candidate=cand,
            evidence_prose=prose,
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        assert record.evidence_prose[0].relevance == "high"

    async def test_relevance_medium_when_mention_and_long_text(self, mocker):
        """is_mention + length>=80, not cited → MEDIUM."""
        _install_mock_client(mocker, _llm_facts())  # cites S_0001 only
        long_text = "X" * 80  # exactly the floor
        prose = [
            _prose("S_0001", "cited span"),
            ProseParagraph(
                span_id="S_0002",
                page=1,
                char_start=0,
                char_end=len(long_text),
                text=long_text,
                is_mention=True,
                name_occurrences=0,
            ),
        ]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001", "S_0002"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        by_span = {p.span_id: p for p in record.evidence_prose}
        assert by_span["S_0002"].relevance == "medium"

    async def test_relevance_medium_when_name_appears_and_long_text(self, mocker):
        """name_occurrences>=1 + length>=80, not cited, not a mention → MEDIUM."""
        _install_mock_client(mocker, _llm_facts())
        # name_occurrences=1 (set explicitly), is_mention=False, length=80 → MEDIUM
        long_text = "Y" * 80
        prose = [
            _prose("S_0001", "cited span"),
            ProseParagraph(
                span_id="S_0002",
                page=1,
                char_start=0,
                char_end=len(long_text),
                text=long_text,
                is_mention=False,
                name_occurrences=1,
            ),
        ]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001", "S_0002"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        by_span = {p.span_id: p for p in record.evidence_prose}
        assert by_span["S_0002"].relevance == "medium"

    async def test_relevance_low_when_short_text_even_with_mention(self, mocker):
        """is_mention but length<80 → LOW. Headings and table-row fragments get
        demoted by the length floor."""
        _install_mock_client(mocker, _llm_facts())
        short_text = "Acraspis quercushirta (Bassett, 1864)"  # 37 chars
        prose = [
            _prose("S_0001", "cited span"),
            ProseParagraph(
                span_id="S_0002",
                page=1,
                char_start=0,
                char_end=len(short_text),
                text=short_text,
                is_mention=True,
                name_occurrences=1,
            ),
        ]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001", "S_0002"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        by_span = {p.span_id: p for p in record.evidence_prose}
        assert by_span["S_0002"].relevance == "low"

    async def test_relevance_low_when_no_signal(self, mocker):
        """Not cited, not a mention, no name in text → LOW regardless of length."""
        _install_mock_client(mocker, _llm_facts())
        long_text = "Unrelated content. " * 10  # long but no signal
        prose = [
            _prose("S_0001", "cited span"),
            ProseParagraph(
                span_id="S_0002",
                page=1,
                char_start=0,
                char_end=len(long_text),
                text=long_text,
                is_mention=False,
                name_occurrences=0,
            ),
        ]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001", "S_0002"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="z" * 64,
        )
        by_span = {p.span_id: p for p in record.evidence_prose}
        assert by_span["S_0002"].relevance == "low"

    async def test_abstaining_record_carries_evidence_prose(self, mocker):
        """When Instructor fails, the abstaining record still preserves the
        evidence prose; curators can still read the source even when trait
        extraction gave up."""
        mock_client = MagicMock()
        mock_client.create_with_completion = AsyncMock(
            side_effect=RuntimeError("instructor gave up")
        )
        mocker.patch("ingest.extract_facts.make_instructor_client", return_value=mock_client)
        mocker.patch("ingest.extract_facts._safe_completion_cost", return_value=0.0)

        prose = [_prose("S_0001", "Some paragraph the curator should still see.", page=2)]
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=prose,
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="q" * 64,
        )
        assert record.evidence_prose == prose

    async def test_record_inherits_generation_from_candidate(self, mocker):
        """Each GallRecord carries through its candidate's biological generation,
        so dual-generation species emit two distinct records downstream."""
        _install_mock_client(mocker, _llm_facts())
        record, _ = await extract_facts(
            candidate=_candidate("C_009", generation="sexgen"),
            evidence_prose=[_prose("S_0001", "some text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="extract prompt",
            prompt_sha256="g" * 64,
        )
        assert record.generation == "sexgen"

    async def test_abstaining_record_preserves_generation(self, mocker):
        """When Instructor fails, the abstaining record still carries the
        candidate's generation; downstream must always see a consistent shape."""
        mock_client = MagicMock()
        mock_client.create_with_completion = AsyncMock(
            side_effect=RuntimeError("instructor gave up")
        )
        mocker.patch("ingest.extract_facts.make_instructor_client", return_value=mock_client)
        mocker.patch("ingest.extract_facts._safe_completion_cost", return_value=0.0)

        record, _ = await extract_facts(
            candidate=_candidate("C_010", generation="agamic"),
            evidence_prose=[_prose("S_0001", "text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="h" * 64,
        )
        assert record.generation == "agamic"

    async def test_call_record_carries_usage_and_cost(self, mocker):
        _install_mock_client(mocker, _llm_facts(), completion=_mock_completion(120, 40))
        _, call = await extract_facts(
            candidate=_candidate(),
            evidence_prose=[_prose("S_0001", "text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="b" * 64,
        )
        assert call.input_tokens == 120
        assert call.output_tokens == 40
        assert call.cost_usd == 0.05  # patched
        assert call.provider == "deepinfra"
        assert call.usage_estimated is False
        assert call.status == "ok"


class TestSpanIdScrub:
    async def test_evidence_outside_allowed_set_is_dropped(self, mocker):
        # All evidence cites a block not in the allowed set.
        _install_mock_client(mocker, _llm_facts(name_evidence_block="S_BOGUS"))
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=[_prose("S_0001", "text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="c" * 64,
        )
        # All evidence for the gall_maker name was filtered out (it cited S_BOGUS),
        # so the cell's value is nulled and support_status flips to abstained.
        assert record.gall_maker.scientific_name.value is None
        assert record.gall_maker.scientific_name.support_status == SupportStatus.ABSTAINED
        assert record.gall_maker.scientific_name.evidence == []

    async def test_trait_with_invalid_evidence_nulls_suggested_keeps_original(self, mocker):
        _install_mock_client(mocker, _llm_facts(trait_evidence_block="S_BOGUS"))
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=[_prose("S_0001", "text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="d" * 64,
        )
        color = record.gall_traits.color
        assert color is not None
        assert color.suggested == []  # cleared
        assert color.original == "red"  # source phrase preserved
        assert color.support_status == SupportStatus.ABSTAINED

    async def test_valid_evidence_passes_through(self, mocker):
        _install_mock_client(mocker, _llm_facts())
        record, _ = await extract_facts(
            candidate=_candidate(),
            evidence_prose=[_prose("S_0001", "text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="e" * 64,
        )
        # Name evidence survives; value preserved.
        assert record.gall_maker.scientific_name.value == "Andricus quercuscalifornicus"
        assert len(record.gall_maker.scientific_name.evidence) == 1
        assert record.gall_maker.scientific_name.evidence[0].block_id == "S_0001"


class TestExtractFactsGracefulFailure:
    async def test_instructor_failure_returns_abstaining_record(self, mocker):
        """When Instructor exhausts retries on schema validation, extract_facts
        returns a fully-abstaining GallRecord plus an error-status record —
        the pipeline must keep running."""
        mock_client = MagicMock()
        mock_client.create_with_completion = AsyncMock(
            side_effect=RuntimeError("instructor gave up after retries")
        )
        mocker.patch("ingest.extract_facts.make_instructor_client", return_value=mock_client)
        mocker.patch("ingest.extract_facts._safe_completion_cost", return_value=0.0)

        record, call = await extract_facts(
            candidate=_candidate("C_007"),
            evidence_prose=[_prose("S_0001", "text")],
            allowed_span_ids=["S_0001"],
            model="deepinfra/test",
            prompt="p",
            prompt_sha256="f" * 64,
        )

        # The record keeps stable IDs but every field abstains.
        assert record.record_id == "R_007"
        assert record.candidate_id == "C_007"
        assert record.gall_maker.scientific_name.value is None
        assert record.gall_maker.scientific_name.support_status == SupportStatus.ABSTAINED
        assert record.hosts == []
        # The call record carries error metadata for the manifest.
        assert call.status == "error"
        assert call.error_detail is not None
        assert "RuntimeError" in call.error_detail
