"""Locations of the import contract, read in place (never copied)."""

from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
REPO = PROJECT.parents[1]
CONTRACT = REPO / "priv" / "import"
VOCAB = CONTRACT / "vocab"
VALIDATOR = CONTRACT / "validate.py"
