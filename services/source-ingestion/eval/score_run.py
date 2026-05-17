"""Score a pipeline run against the eval-set labels.

For each pipeline output directory paired with a source_id, this script:

  1. Loads the labeled blocks from eval/output/labels/<source_id>.json.
  2. Reads the pipeline's per-candidate evidence_pack.txt
     (the closest analog to the future assembled species_account).
  3. Matches labeled species to pipeline candidates by name (stripping
     (sexgen)/(agamic) generation suffixes).
  4. For each labeled species, uses the same block-match logic as
     match_descriptions.py to compute coverage of labels against the
     pipeline's evidence pack.

Reports per-source recall + the gap to the eval-set "recoverable" ceiling.
The eval-set ceiling tells us what's theoretically extractable from the
PDF; pipeline coverage tells us how much the pipeline actually got.

Run:
    uv run python eval/score_run.py
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent))
from match_descriptions import match_block, normalize  # noqa: E402

PIPELINE_OUTPUT_DIR = Path(__file__).parent.parent / "output"
LABELS_DIR = Path(__file__).parent / "output" / "labels"
REPORT_PATH = Path(__file__).parent / "output" / "baseline_report.md"

# Map pipeline output directory name → eval source_id.
# Only the runs that correspond to a source in the eval set.
RUN_TO_SOURCE: dict[str, int] = {
    "nicholls": 559,       # Nicholls 2022 Pairing
    "cuesta": 554,         # Cuesta-Porta 2022 Druon
    "cuesta-feron": 755,   # Cuesta-Porta 2023 Feron
    "nastasi-davis": 680,  # Nastasi & Davis 2022 Field Guide
    "melika-1997": 78,     # Melika & Abrahamson 1997 Neuroterus
    "melika-2002-chapter": 34,  # Melika & Abrahamson 2002 Cynipid World Review chapter
    "medianero-cameroni": 305,  # Medianero 2014 Callirhytis cameroni
    "wise-2007": 184,           # Wise 2007 Solanum
    "gagne-moser-2013-hackberries": 122,  # Gagne & Moser 2013 Hackberries
    "gagne-2017-catalogue": 66,  # Gagne 2017 World Catalogue
    "ashmead-1896": 98,          # Ashmead 1896 USNM Cynipidous Galls
    "kinsey-1929": 50,           # Kinsey 1929 Gall Wasp Genus Cynips
    "felt-1917-key": 7,          # Felt 1917 Key to American Insect Galls
    "gagne-2008-hickories": 123, # Gagne 2008 Gall Midges of Hickories
}

_GEN_SUFFIX_RE = re.compile(r"\s*\((sexgen|agamic|sexual|asexual)\)\s*$", re.IGNORECASE)

_SUFFIX_TO_GEN = {
    "sexgen": "sexgen",
    "sexual": "sexgen",
    "agamic": "agamic",
    "asexual": "agamic",
}


def parse_generation_suffix(name: str) -> tuple[str, str]:
    """Split 'X (sexgen)' into ('X', 'sexgen'). No suffix → ('X', 'unspecified').

    Labels have entries like 'Andricus balanaspis (sexgen)'. The pipeline
    now emits per-generation candidates; this lets the scorer match
    (base_name, generation) ↔ (candidate.gall_maker_mention,
    candidate.generation).
    """
    m = _GEN_SUFFIX_RE.search(name)
    if not m:
        return name.strip(), "unspecified"
    base = _GEN_SUFFIX_RE.sub("", name).strip()
    gen = _SUFFIX_TO_GEN[m.group(1).lower()]
    return base, gen


@dataclass
class SpeciesScore:
    species_id: int
    species_name: str
    eval_coverage: float  # ceiling: what's recoverable from PDF
    pipeline_coverage: float  # what the pipeline actually captured
    candidate_id: str | None  # matched pipeline candidate, or None
    n_blocks: int


@dataclass
class SourceScore:
    source_id: int
    run_name: str
    label: str
    species: list[SpeciesScore] = field(default_factory=list)
    unmatched_species: list[str] = field(default_factory=list)

    @property
    def avg_pipeline_coverage(self) -> float:
        if not self.species:
            return 0.0
        return sum(s.pipeline_coverage for s in self.species) / len(self.species)

    @property
    def avg_eval_coverage(self) -> float:
        if not self.species:
            return 0.0
        return sum(s.eval_coverage for s in self.species) / len(self.species)

    @property
    def recall_vs_ceiling(self) -> float:
        ceiling = sum(s.eval_coverage for s in self.species)
        if ceiling == 0:
            return 0.0
        actual = sum(s.pipeline_coverage for s in self.species)
        return actual / ceiling


def load_candidate_evidence_packs(run_dir: Path) -> dict[str, tuple[str, str, str]]:
    """Returns {candidate_id: (gall_maker_mention, generation, evidence_pack_text)}.

    `generation` defaults to ``"unspecified"`` when the candidate predates the
    generation-aware schema (graceful degradation across runs).
    """
    candidates = json.loads((run_dir / "candidates.json").read_text())
    out = {}
    for c in candidates["candidates"]:
        cid = c["candidate_id"]
        gen = c.get("generation", "unspecified")
        ep_path = run_dir / "candidates" / cid / "evidence_pack.txt"
        text = ep_path.read_text() if ep_path.exists() else ""
        out[cid] = (c["gall_maker_mention"], gen, text)
    return out


def score_source(run_name: str, source_id: int) -> SourceScore:
    labels = json.loads((LABELS_DIR / f"{source_id}.json").read_text())
    run_dir = PIPELINE_OUTPUT_DIR / run_name
    candidates = load_candidate_evidence_packs(run_dir)

    # Primary lookup: (normalized_name, generation) → (candidate_id, evidence_pack_text).
    # Fallback lookup: name-only → unspecified candidate, used as graceful
    # degradation when a label has a generation suffix but the pipeline
    # produced only an unspecified candidate (pre-Step-1 baseline).
    cand_by_key: dict[tuple[str, str], tuple[str, str]] = {}
    cand_by_name_unspecified: dict[str, tuple[str, str]] = {}
    for cid, (mention, gen, text) in candidates.items():
        norm_name = mention.strip().lower()
        cand_by_key[(norm_name, gen)] = (cid, text)
        if gen == "unspecified":
            cand_by_name_unspecified[norm_name] = (cid, text)

    score = SourceScore(source_id=source_id, run_name=run_name, label=labels["label"])

    for sp in labels["species"]:
        base_name, label_gen = parse_generation_suffix(sp["species_name"])
        norm_label_name = base_name.lower()
        matched = cand_by_key.get((norm_label_name, label_gen))
        # Graceful fallback for pre-Step-1 runs that only emit unspecified candidates.
        if matched is None and label_gen != "unspecified":
            matched = cand_by_name_unspecified.get(norm_label_name)

        if matched is None:
            score.unmatched_species.append(sp["species_name"])
            score.species.append(SpeciesScore(
                species_id=sp["species_id"],
                species_name=sp["species_name"],
                eval_coverage=sp["coverage"],
                pipeline_coverage=0.0,
                candidate_id=None,
                n_blocks=len(sp["blocks"]),
            ))
            continue

        cid, ep_text = matched
        ep_norm = normalize(ep_text)

        # Re-match each labeled block against the pipeline's evidence pack.
        total_chars = 0
        matched_chars = 0
        for b in sp["blocks"]:
            block_text = b["block_text"]
            res = match_block(block_text, ep_norm)
            total_chars += res.block_chars
            if res.match_kind in ("exact", "fuzzy"):
                matched_chars += res.block_chars
        pipeline_coverage = (matched_chars / total_chars) if total_chars > 0 else 0.0

        score.species.append(SpeciesScore(
            species_id=sp["species_id"],
            species_name=sp["species_name"],
            eval_coverage=sp["coverage"],
            pipeline_coverage=pipeline_coverage,
            candidate_id=cid,
            n_blocks=len(sp["blocks"]),
        ))
    return score


def write_report(scores: list[SourceScore]) -> None:
    lines = [
        "# Baseline pipeline coverage report",
        "",
        "Compares current pipeline's `evidence_pack.txt` per candidate "
        "against eval-set labels.",
        "",
        "**Eval cov** = ceiling: fraction of labeled blocks recoverable from the source PDF (matcher).",
        "**Pipe cov** = actual: fraction of labeled blocks present in the pipeline's evidence pack.",
        "**Recall vs ceiling** = how much of what's reachable the pipeline actually captured.",
        "",
        "## Per source",
        "",
        "| Source | n species | Matched | Avg eval cov | Avg pipe cov | Recall vs ceiling |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for s in scores:
        matched_n = sum(1 for sp in s.species if sp.candidate_id is not None)
        lines.append(
            f"| {s.label} | {len(s.species)} | {matched_n}/{len(s.species)} | "
            f"{s.avg_eval_coverage*100:.1f}% | {s.avg_pipeline_coverage*100:.1f}% | "
            f"{s.recall_vs_ceiling*100:.1f}% |"
        )

    # Per-species detail
    for s in scores:
        lines.append("")
        lines.append(f"## {s.label} (source {s.source_id})")
        lines.append("")
        if s.unmatched_species:
            lines.append(f"**Unmatched species ({len(s.unmatched_species)})**: "
                         + ", ".join(s.unmatched_species))
            lines.append("")
        lines.append("| Species | Blocks | Eval cov | Pipe cov | Δ |")
        lines.append("|---|---:|---:|---:|---:|")
        for sp in sorted(s.species, key=lambda x: x.species_name):
            delta = sp.pipeline_coverage - sp.eval_coverage
            sign = "+" if delta >= 0 else ""
            cid_mark = f" `{sp.candidate_id}`" if sp.candidate_id else " *(unmatched)*"
            lines.append(
                f"| {sp.species_name}{cid_mark} | {sp.n_blocks} | "
                f"{sp.eval_coverage*100:.1f}% | {sp.pipeline_coverage*100:.1f}% | "
                f"{sign}{delta*100:.1f}% |"
            )

    REPORT_PATH.write_text("\n".join(lines))


def main() -> None:
    scores = []
    for run_name, source_id in RUN_TO_SOURCE.items():
        run_dir = PIPELINE_OUTPUT_DIR / run_name
        if not (run_dir / "candidates.json").exists():
            print(f"Skipping {run_name} (no run at {run_dir})", flush=True)
            continue
        print(f"Scoring {run_name} (source {source_id})...", flush=True)
        s = score_source(run_name, source_id)
        matched_n = sum(1 for sp in s.species if sp.candidate_id is not None)
        print(f"  {len(s.species)} labeled species, {matched_n} matched. "
              f"Avg eval cov {s.avg_eval_coverage*100:.1f}%, "
              f"avg pipe cov {s.avg_pipeline_coverage*100:.1f}%, "
              f"recall vs ceiling {s.recall_vs_ceiling*100:.1f}%",
              flush=True)
        scores.append(s)
    write_report(scores)
    print(f"\nReport written to {REPORT_PATH}")


if __name__ == "__main__":
    main()
