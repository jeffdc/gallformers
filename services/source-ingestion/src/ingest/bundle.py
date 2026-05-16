"""Bundle stage: tarball the 9 contract artifacts into ``bundle.tar.gz``.

Deterministic. Reads from a working directory containing the artifacts and
writes a single tarball. With ``--include-candidates`` the per-candidate
scratch under ``candidates/`` is also included for full-reproducibility
debugging bundles.

The expected artifacts (always required when ``verify_complete=True``):

- ``manifest.json``
- ``source.pdf``
- ``raw_text.jsonl``
- ``normalized_text.jsonl``
- ``sections.json``
- ``metadata.json``
- ``claims.json``
- ``verified_claims.json``
- ``review_artifact.json``

The bundle's tar member names are flat (no leading directory) so consumers
can extract them directly. ``source.pdf`` may be a stub when running stub
pipelines; the bundle's contract is "9 files present", not "9 files real."
"""

from __future__ import annotations

import tarfile
from pathlib import Path

REQUIRED_ARTIFACTS: list[str] = [
    "manifest.json",
    "source.pdf",
    "raw_text.jsonl",
    "normalized_text.jsonl",
    "sections.json",
    "metadata.json",
    "claims.json",
    "verified_claims.json",
    "review_artifact.json",
]


def write_bundle(
    source_dir: Path,
    output: Path,
    *,
    include_candidates: bool = False,
    verify_complete: bool = True,
) -> None:
    """Tar the 9 contract artifacts (optionally plus per-candidate scratch).

    Args:
        source_dir: directory holding the artifacts. Typically the per-paper
            output directory.
        output: target ``.tar.gz`` path.
        include_candidates: if True, also bundles the ``candidates/`` subtree.
        verify_complete: if True (default), raise ``FileNotFoundError`` when
            any required artifact is missing.

    Raises:
        FileNotFoundError: When ``verify_complete=True`` and an artifact
            from ``REQUIRED_ARTIFACTS`` is absent.
    """
    if verify_complete:
        missing = [name for name in REQUIRED_ARTIFACTS if not (source_dir / name).exists()]
        if missing:
            raise FileNotFoundError(
                f"Cannot assemble bundle; missing artifact(s) in {source_dir}: {missing}"
            )

    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, "w:gz") as tar:
        for name in REQUIRED_ARTIFACTS:
            path = source_dir / name
            if path.exists():
                tar.add(path, arcname=name)
        if include_candidates:
            candidates_dir = source_dir / "candidates"
            if candidates_dir.is_dir():
                tar.add(candidates_dir, arcname="candidates")
