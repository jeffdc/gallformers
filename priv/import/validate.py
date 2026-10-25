# /// script
# requires-python = ">=3.10"
# dependencies = ["jsonschema>=4.18", "referencing>=0.30", "rfc3339-validator", "rfc3987"]
# ///
"""Validate a Gallformers import package (phase 4), and with --review, the readiness gate (phases 5 and 6).

Usage:
    uv run priv/import/validate.py [--review] PATH [PATH ...]
    python3 priv/import/validate.py [--review] PATH [PATH ...]   # needs jsonschema >= 4.18, rfc3339-validator, rfc3987

PATH is a batch file (taxonomy.json / gall.json) or a package directory, in
which case every taxonomy.json and gall.json in it is validated.

Phase 4 checks:
- the schemas (shape and controlled values);
- the package: document.json present and matching its sha256, every quote
  found in its document item, references declared, ids unique, qualifier
  targets, one Inducer per Gall, new Galls have Facts, at most one description
  per Gall, no synonymy or split above family.

--review adds the readiness gate, for package directories: review.json exists
and is well-formed; with no findings, it covers the current batches; with
findings, every one has a phase 6 response and the batches are the ones phase 6
left. Disputed findings (the producer disagrees) are reported, for human review
at intake, without failing.

Exit status: 0 if everything checked is free of errors (warnings allowed), 1 otherwise.

Tests: uv run --with pytest --with "jsonschema>=4.18" --with "referencing>=0.30" --with rfc3339-validator --with rfc3987 pytest priv/import/tests
"""

import hashlib
import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parent
BATCH_FILES = ("taxonomy.json", "gall.json")

# Highest to lowest; acts that merge or divide taxa stop at family (PRODUCER_GUIDE.md, Phase 2).
RANK_ORDER = [
    "kingdom", "subkingdom", "phylum", "subphylum", "class", "subclass", "infraclass",
    "superorder", "order", "suborder", "infraorder", "superfamily", "family", "subfamily",
    "tribe", "subtribe", "genus", "subgenus", "section", "species", "subspecies", "variety", "form",
]  # fmt: skip

# PRODUCER_GUIDE.md, Phase 3: Qualifiers
QUALIFIER_TARGETS = {
    "required_for_formation": {"symbiont_of"},
    "lethality": {"inquiline_of", "cecidophage_in"},
    "parasitism_mode": {"parasitoid_in", "parasitoid_of"},
}
TAXON_TO_TAXON = {"parasitoid_of", "vectored_by", "predator_of"}
GALL_TO_GALL = {"modified_form_of", "alternate_generation_of"}
DOCUMENT_ITEMS = ("texts", "tables", "pictures")


# -- the schemas -------------------------------------------------------------------


def load_registry():
    registry = Registry()
    schemas = {}
    paths = sorted((ROOT / "schema").glob("*.json")) + sorted((ROOT / "vocab").glob("*.schema.json"))
    for path in paths:
        contents = json.loads(path.read_text(encoding="utf-8"))
        registry = registry.with_resource(contents["$id"], Resource.from_contents(contents))
        schemas[path.name] = contents
    return registry, schemas


def schema_errors(batch, registry, schemas):
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


# -- the document (a DoclingDocument, as JSON) -------------------------------------


def resolve(doc, ref):
    """The item a reference like '#/texts/42' points at, or None."""
    parts = ref.split("/")
    if len(parts) != 3 or parts[0] != "#" or not parts[2].isdigit():
        return None
    array = doc.get(parts[1])
    index = int(parts[2])
    if not isinstance(array, list) or index >= len(array):
        return None
    return array[index]


def items(doc):
    """Every content item: body reading order first, then any not reachable from it."""
    seen = set()

    def walk(node):
        for child in node.get("children", []):
            item = resolve(doc, child.get("$ref", ""))
            if item is None or item["self_ref"] in seen:
                continue
            seen.add(item["self_ref"])
            if item["self_ref"].split("/")[1] in DOCUMENT_ITEMS:
                yield item
            yield from walk(item)

    yield from walk(doc.get("body", {}))
    yield from walk(doc.get("furniture", {}))
    for array in DOCUMENT_ITEMS:
        for item in doc.get(array, []):
            if item["self_ref"] not in seen:
                seen.add(item["self_ref"])
                yield item


def item_text(item):
    """An item's text; a table's rows, cells joined with ' | ' (a cell spanning columns once)."""
    if "data" in item:
        rows = []
        for row in item["data"].get("grid", []):
            cells = [c["text"] for col, c in enumerate(row) if c["start_col_offset_idx"] == col]
            rows.append(" | ".join(cells))
        return "\n".join(rows)
    return item.get("text", "")


def normalize(text):
    text = unicodedata.normalize("NFKC", text).replace("­", "")
    return " ".join(text.split())


def dehyphenate(text):
    """Join words broken across a line ('glob- ular' -> 'globular')."""
    return re.sub(r"(\w)-\s+(\w)", r"\1\2", text)


def quote_in(quote, text):
    q, t = normalize(quote), normalize(text)
    return q in t or dehyphenate(q) in dehyphenate(t)


# -- the package checks ------------------------------------------------------------


class PackageChecks:
    """Checks one batch against itself and its document. Problems are (level, message)."""

    def __init__(self, batch, doc, document_sha256):
        self.batch = batch
        self.doc = doc
        self.document_sha256 = document_sha256
        self.problems = []
        self.used_taxa = set()
        self.used_galls = set()

    def error(self, message):
        self.problems.append(("error", message))

    def warning(self, message):
        self.problems.append(("warning", message))

    def declared(self, key):
        refs = [x.get("ref") for x in self.batch.get(key, [])]
        for ref, count in Counter(refs).items():
            if count > 1:
                self.error(f"{key}: duplicate ref {ref}")
        return set(refs)

    def unique_ids(self, key):
        for ident, count in Counter(x.get("id") for x in self.batch.get(key, [])).items():
            if count > 1:
                self.error(f"{key}: duplicate id {ident}")

    def taxon(self, ref, where):
        if ref is None:
            return
        self.used_taxa.add(ref)
        if ref not in self.taxa:
            self.error(f"{where}: taxon {ref} is not declared in taxa")

    def gall(self, ref, where):
        if ref is None:
            return
        self.used_galls.add(ref)
        if ref not in self.galls:
            self.error(f"{where}: Gall {ref} is not declared in galls")

    def evidence(self, evidence, where):
        for i, ev in enumerate(evidence):
            path = f"{where}/evidence/{i}"
            if "statement" in ev or self.doc is None:
                continue
            ref = ev.get("item")
            if ref is None:
                self.error(f"{path}: the package has a document, so evidence needs an item")
                continue
            item = resolve(self.doc, ref)
            if item is None:
                self.error(f"{path}: item {ref} does not exist in document.json")
            elif ev.get("whole_item"):
                if not item_text(item).strip():
                    self.error(f"{path}: whole_item {ref} has no text")
            elif not quote_in(ev.get("quote", ""), item_text(item)):
                quote = ev.get("quote", "")
                elsewhere = [o["self_ref"] for o in items(self.doc) if quote_in(quote, item_text(o))]
                hint = f"; found in {', '.join(elsewhere[:3])}" if elsewhere else "; not found anywhere in the document"
                self.error(f"{path}: quote not found in {ref}{hint}: {quote[:80]!r}")

    def above_family(self, ref):
        rank = self.ranks.get(ref)
        return rank in RANK_ORDER and RANK_ORDER.index(rank) < RANK_ORDER.index("family")

    def taxonomy_batch(self):
        self.unique_ids("acts")
        for i, act in enumerate(self.batch.get("acts", [])):
            where = f"acts/{i}"
            for key in ("taxon", "parent", "name", "accepted"):
                self.taxon(act.get(key), where)
            for ref in act.get("into", []):
                self.taxon(ref, where)
            kind = act.get("kind")
            if kind == "synonymy" and (self.above_family(act.get("name")) or self.above_family(act.get("accepted"))):
                self.error(f"{where}: synonymy above family is not supported")
            if kind == "split" and self.above_family(act.get("taxon")):
                self.error(f"{where}: split above family is not supported")
            self.evidence(act.get("evidence", []), where)

    def gall_batch(self):
        facts = self.batch.get("facts", [])
        by_id = {f.get("id"): f for f in facts}
        self.unique_ids("facts")
        for i, g in enumerate(self.batch.get("galls", [])):
            ident = g.get("identified_by", {})
            self.taxon(ident.get("inducer"), f"galls/{i}/identified_by")
            self.taxon(ident.get("host"), f"galls/{i}/identified_by")

        inducers, descriptions, about, inducer_of = Counter(), Counter(), set(), set()
        for i, fact in enumerate(facts):
            where = f"facts/{i}"
            kind = fact.get("kind")
            if kind == "relationship":
                rtype = fact.get("type")
                if rtype in TAXON_TO_TAXON:
                    self.taxon(fact.get("subject"), where)
                    self.taxon(fact.get("object"), where)
                    self.gall(fact.get("gall_context"), where)
                    about.add(fact.get("gall_context"))
                elif rtype in GALL_TO_GALL:
                    self.gall(fact.get("subject"), where)
                    self.gall(fact.get("object"), where)
                    about.update({fact.get("subject"), fact.get("object")})
                else:
                    self.taxon(fact.get("subject"), where)
                    self.gall(fact.get("object"), where)
                    about.add(fact.get("object"))
                if rtype == "inducer_of" and fact.get("stance") == "confirm":
                    inducers[fact.get("object")] += 1
                    inducer_of.add((fact.get("subject"), fact.get("object")))
            elif kind == "qualifier":
                target = by_id.get(fact.get("of"))
                if target is None:
                    self.error(f"{where}: qualifier points at {fact.get('of')}, which is not a Fact in this batch")
                elif target.get("kind") != "relationship":
                    self.error(f"{where}: qualifier points at {fact.get('of')}, which is not a Relationship Fact")
                else:
                    allowed = QUALIFIER_TARGETS.get(fact.get("qualifier"), set())
                    if target.get("type") not in allowed:
                        self.error(
                            f"{where}: {fact.get('qualifier')} is not allowed on {target.get('type')} "
                            f"(allowed: {', '.join(sorted(allowed))})"
                        )
            else:
                self.gall(fact.get("gall"), where)
                about.add(fact.get("gall"))
                if kind == "description":
                    descriptions[fact.get("gall")] += 1
            self.evidence(fact.get("evidence", []), where)

        for gall, count in inducers.items():
            if count > 1:
                self.error(f"Gall {gall} has more than one inducer_of Fact ({count})")
        for gall, count in descriptions.items():
            if count > 1:
                self.error(f"Gall {gall} has more than one description Fact ({count})")
        for g in self.batch.get("galls", []):
            if g.get("new") and g.get("ref") not in about:
                self.error(f"Gall {g.get('ref')} is new but has no Facts about it")
            inducer = g.get("identified_by", {}).get("inducer")
            if inducer and (inducer, g.get("ref")) not in inducer_of:
                # A Gall the batch introduces must state its Inducer; for one Gallformers already
                # holds, the Inducer is only how it is looked up, so the Fact is optional.
                report = self.error if g.get("new") or g.get("formerly_undescribed") else self.warning
                report(
                    f"Gall {g.get('ref')} is identified by Inducer {inducer} but has no confirmed "
                    f"inducer_of Fact from {inducer}"
                )

    def run(self):
        self.taxa = self.declared("taxa")
        self.galls = self.declared("galls")
        self.ranks = {t.get("ref"): t.get("rank") for t in self.batch.get("taxa", [])}
        expected = self.batch.get("source", {}).get("document", {}).get("sha256")
        if self.document_sha256 and expected and expected != self.document_sha256:
            self.error(f"source.document.sha256 is {expected}, but document.json hashes to {self.document_sha256}")

        if self.batch.get("batch_type") == "taxonomy":
            self.taxonomy_batch()
        else:
            self.gall_batch()

        for i, entry in enumerate(self.batch.get("unmapped", [])):
            self.gall(entry.get("gall"), f"unmapped/{i}")
            self.evidence(entry.get("evidence", []), f"unmapped/{i}")

        for ref in sorted(self.taxa - self.used_taxa):
            self.warning(f"taxon {ref} is declared but never used")
        for ref in sorted(self.galls - self.used_galls):
            self.warning(f"Gall {ref} is declared but never used")
        return self.problems


def document_for(batch_path, batch):
    """(document dict, sha256) when the batch names a document.json beside it, else (None, None)."""
    if batch.get("source", {}).get("document", {}).get("file") != "document.json":
        return None, None
    path = batch_path.parent / "document.json"
    if not path.exists():
        return None, None
    data = path.read_bytes()
    return json.loads(data), hashlib.sha256(data).hexdigest()


def batch_problems(path, registry, schemas):
    """All problems for one batch file: schema errors first, then the package checks."""
    try:
        batch = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return [("error", "file not found")]
    except json.JSONDecodeError as exc:
        return [("error", f"not valid JSON: {exc}")]
    problems = [("error", e) for e in schema_errors(batch, registry, schemas)]
    if not isinstance(batch, dict):
        return problems
    named = batch.get("source", {}).get("document", {}).get("file")
    if named and not (path.parent / named).exists():
        problems.append(("error", f"{named} is missing beside this batch"))
    doc, sha = document_for(path, batch)
    return problems + PackageChecks(batch, doc, sha).run()


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


def review_problems(package, registry, schemas):
    """The readiness gate: review.json exists, is well-formed and covers the batches as they stand;
    each finding is answered in phase 6. Disputed findings are warnings, for human review at intake."""
    path = package / "review.json"
    if not path.exists():
        return [("error", "no review.json: run phase 5")]
    try:
        review = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [("error", f"not valid JSON: {exc}")]
    validator = Draft202012Validator(schemas["review.schema.json"], registry=registry)
    errors = [
        f"{'/'.join(map(str, e.absolute_path)) or '(root)'}: {e.message}"
        for e in sorted(validator.iter_errors(review), key=lambda e: list(map(str, e.absolute_path)))
    ]
    if errors:
        return [("error", e) for e in errors]

    problems = []
    statements, current = {}, {}
    for name in BATCH_FILES:
        batch_path = package / name
        if not batch_path.exists():
            continue
        current[name] = hashlib.sha256(batch_path.read_bytes()).hexdigest()
        batch = json.loads(batch_path.read_text(encoding="utf-8"))
        statements[name] = {x.get("id") for key in ("acts", "facts") for x in batch.get(key, [])} | {
            x.get("ref") for key in ("taxa", "galls") for x in batch.get(key, [])
        }

    responded = review.get("responded")
    if responded:
        # After phase 6 the batches are the ones the producer left, not the ones reviewed.
        for name, digest in current.items():
            if responded["result"].get(name) != digest:
                problems.append(("error", f"{name} changed after phase 6: re-run phase 4, then phases 5 and 6"))
    else:
        for name, digest in current.items():
            if review["reviewed"].get(name) != digest:
                problems.append(("error", f"review is stale for {name}: re-run phase 4, then phase 5"))

    for finding in review["findings"]:
        name, ident = finding["batch"], finding["id"]
        label = f"{name} {ident} ({finding['problem']})"
        response = finding.get("response")
        if response and response["decision"] == "agree":
            continue  # fixed in phase 6; the fix may have removed the statement
        if ident not in statements.get(name, set()):
            problems.append(("error", f"finding {ident} is not in {name}"))
        elif response:
            problems.append(("warning", f"disputed, for human review at intake: {label}: reviewer: {finding['reason']} | producer: {response['reason']}"))
        elif responded:
            problems.append(("error", f"finding {label} has no phase 6 response"))
        else:
            problems.append(("error", f"phase 5 finding awaits phase 6: {label}: {finding['reason']}"))
    return problems


def package_problems(path, registry=None, schemas=None, review=False):
    """Phase 4 problems for every batch in a package directory (or one batch file), and with
    review=True the phase 5 gate, as (level, 'file: message')."""
    if registry is None:
        registry, schemas = load_registry()
    out = []
    for batch, problem in batch_paths([path]):
        found = [("error", problem)] if problem else batch_problems(batch, registry, schemas)
        out.extend((level, f"{batch.name}: {message}") for level, message in found)
    if review and Path(path).is_dir():
        found = review_problems(Path(path), registry, schemas)
        out.extend((level, f"review.json: {message}") for level, message in found)
    return out


def report(path, found):
    errors = [m for level, m in found if level == "error"]
    warnings = [m for level, m in found if level == "warning"]
    print(f"{'INVALID' if errors else 'valid  '} {path}")
    for message in errors:
        print(f"  {message}")
    for message in warnings:
        print(f"  warning: {message}")
    return bool(errors)


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2

    review = "--review" in argv
    paths = [a for a in argv if a != "--review"]
    registry, schemas = load_registry()
    failed = 0
    for path, problem in batch_paths(paths):
        found = [("error", problem)] if problem else batch_problems(path, registry, schemas)
        failed += report(path, found)
    if review:
        for arg in paths:
            package = Path(arg)
            if package.is_dir():
                failed += report(package / "review.json", review_problems(package, registry, schemas))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
