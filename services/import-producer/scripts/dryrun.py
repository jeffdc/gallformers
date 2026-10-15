"""Approximate the Gallformers dry run (layer 2) against the local database, and diff Facts.

    uv run python scripts/dryrun.py output/<package> <gallformers source id>

Read-only against gallformers_dev. Writes <package>/dryrun.json and prints a summary.

This is an approximation, not the real import: name resolution here is exact
match on species, taxonomy and scientific aliases, plus expansion of genus
abbreviations ("Q. alba") from full names in the same batch. Anything smarter
is the importer's job; this measures how far simple resolution gets.
"""

import json
import re
import subprocess
import sys
import unicodedata
from collections import defaultdict
from difflib import SequenceMatcher, get_close_matches
from pathlib import Path

DB = "gallformers_dev"
GENERATION_SUFFIX = {
    "agamic": "agamic",
    "sexual": "sexgen",
    "spring": "spring generation",
    "summer": "summer generation",
    "autumn": "autumn generation",
}
TRAIT_TABLES = {
    "plant_part": ("gall_plant_part", "plant_part", "plant_part_id", "part"),
    "color": ("gall_color", "color", "color_id", "color"),
    "shape": ("gall_shape", "shape", "shape_id", "shape"),
    "texture": ("gall_texture", "texture", "texture_id", "texture"),
    "form": ("gall_form", "form", "form_id", "form"),
    "walls": ("gall_walls", "walls", "walls_id", "walls"),
    "cells": ("gall_cells", "cells", "cells_id", "cells"),
    "alignment": ("gall_alignment", "alignment", "alignment_id", "alignment"),
    "season": ("gall_season", "season", "season_id", "season"),
}


def query(sql: str):
    out = subprocess.run(
        ["psql", "-d", DB, "-At", "-c", f"SELECT coalesce(json_agg(t), '[]') FROM ({sql}) t"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return json.loads(out)


def norm(name: str) -> str:
    name = " ".join(name.replace(" ", " ").split())
    return re.sub(r"\s+(sp|spp)\.?$", "", name)


def loose(name: str) -> str:
    """Mechanical normalization an importer could safely apply: case, 'var.' vs 'var',
    subgenus in parentheses, hybrid sign, punctuation spacing."""
    name = re.sub(r"^(\S+)\s+\([A-Z][a-z]+\)", r"\1", norm(name))  # Cynips (Acraspis) hirta
    name = re.sub(r"\b(var|f|form|subsp|ssp)\.", r"\1", name)
    name = re.sub(r"\s[×⨯xX]\s", " x ", name)
    return name.casefold()


def base(name: str) -> str:
    """Gall entry name without its trailing '(agamic)' / '(on Betula)' qualifier."""
    return re.sub(r"\s*\([^)]*\)$", "", name).strip()


def suffix(name: str) -> str | None:
    m = re.search(r"\(([^)]*)\)$", name)
    return m.group(1) if m else None


class Index:
    def __init__(self, source_id: int):
        self.species = {r["id"]: r for r in query("SELECT id, name, taxoncode FROM species")}
        self.taxonomy = {r["id"]: r for r in query("SELECT id, name, type, rank FROM taxonomy")}
        self.by_species_name = defaultdict(set)  # base name -> species ids
        for s in self.species.values():
            self.by_species_name[base(s["name"])].add(s["id"])
        self.by_taxon_name = defaultdict(set)
        for t in self.taxonomy.values():
            self.by_taxon_name[t["name"]].add(t["id"])
        self.alias_species = defaultdict(set)
        for r in query(
            "SELECT a.name, x.species_id FROM alias a JOIN alias_species x ON x.alias_id = a.id "
            "WHERE a.type = 'scientific'"
        ):
            self.alias_species[norm(r["name"])].add(r["species_id"])
        self.alias_taxonomy = defaultdict(set)
        for r in query(
            "SELECT a.name, x.taxonomy_id FROM alias a JOIN taxonomy_alias x ON x.alias_id = a.id "
            "WHERE a.type = 'scientific'"
        ):
            self.alias_taxonomy[norm(r["name"])].add(r["taxonomy_id"])
        self.by_epithet = defaultdict(set)  # second word of a species name -> species ids
        for s in self.species.values():
            parts = base(s["name"]).split()
            if len(parts) >= 2:
                self.by_epithet[parts[1].casefold()].add(s["id"])
        self.all_names = list(
            set(self.by_species_name) | set(self.by_taxon_name) | set(self.alias_species)
        )
        self.loose = defaultdict(set)
        for name, ids in self.by_species_name.items():
            self.loose[loose(name)] |= {f"s{i}" for i in ids}
        for name, ids in self.by_taxon_name.items():
            self.loose[loose(name)] |= {f"t{i}" for i in ids}
        for name, ids in self.alias_species.items():
            self.loose[loose(name)] |= {f"s{i}" for i in ids}
        for name, ids in self.alias_taxonomy.items():
            self.loose[loose(name)] |= {f"t{i}" for i in ids}
        self.undescribed = {
            r["species_id"] for r in query("SELECT species_id FROM gall_traits WHERE undescribed")
        }
        self.hosts = defaultdict(set)
        for r in query("SELECT gall_species_id g, host_species_id h FROM gallhost"):
            self.hosts[r["g"]].add(r["h"])
        self.traits = defaultdict(lambda: defaultdict(set))
        for trait, (link, table, fk, col) in TRAIT_TABLES.items():
            for r in query(
                f"SELECT l.species_id s, v.{col} v FROM {link} l JOIN {table} v ON v.id = l.{fk}"
            ):
                self.traits[r["s"]][trait].add(r["v"])
        for r in query(
            "SELECT species_id s, detachable v FROM gall_traits WHERE detachable IS NOT NULL"
        ):
            self.traits[r["s"]]["detachable"].add(r["v"])
        self.descriptions = {
            r["species_id"]: r["description"] or ""
            for r in query(
                f"SELECT species_id, description FROM species_source WHERE source_id = {source_id}"
            )
        }
        self.source_entries = set(self.descriptions)

    def lookup(self, name: str) -> tuple[str, set[str]]:
        """('species'|'taxon'|'alias', targets) or ('', set())."""
        if name in self.by_species_name:
            return "exact", {f"s{i}" for i in self.by_species_name[name]}
        if name in self.by_taxon_name:
            return "exact", {f"t{i}" for i in self.by_taxon_name[name]}
        if name in self.alias_species:
            return "synonym", {f"s{i}" for i in self.alias_species[name]}
        if name in self.alias_taxonomy:
            return "synonym", {f"t{i}" for i in self.alias_taxonomy[name]}
        if loose(name) in self.loose:
            return "normalized", set(self.loose[loose(name)])
        return "", set()

    def label(self, target: str) -> str:
        kind, ident = target[0], int(target[1:])
        if kind == "s":
            return base(self.species[ident]["name"])
        return self.taxonomy[ident]["name"]


def expand_abbreviation(
    name: str, genera: set[str], index: Index
) -> tuple[str, str, set[str]] | None:
    """Try every genus with the abbreviation's initial; accept only if exactly one resolves.

    `genera` are the genera written in full in the batch or the Source's document,
    which is the context an importer would have.
    """
    m = re.match(r"^([A-Z])\.\s*(.+)$", name)
    if not m:
        return None
    hits = []
    for genus in sorted(g for g in genera if g.startswith(m.group(1))):
        method, targets = index.lookup(f"{genus} {m.group(2)}")
        if targets:
            hits.append((f"{genus} {m.group(2)}", method, targets))
    return hits[0] if len(hits) == 1 else None


QUERCUS_NAME = re.compile(
    r"^(?:\S+\s+(?:q\.|quercus[-\s]?)|[A-Z]\.\s*Q\.)\s*([a-z][a-z-]+)$", re.IGNORECASE
)  # "Cynips q. spongifica", "C. quercus-spongifica", "C.Q. INANIS"


def quercus_epithet(name: str, index: Index) -> set[str]:
    """19th-century oak-gall names: "Cynips q. spongifica" / "C. quercus spongifica" is today's
    epithet "quercusspongifica", usually in another genus. Match the fused epithet across all
    genera; the caller accepts it only when it names one species."""
    m = QUERCUS_NAME.match(norm(name))
    if not m:
        return set()
    epithet = "quercus" + m.group(1).replace("-", "").casefold()
    return {f"s{i}" for i in index.by_epithet.get(epithet, set())}


def resolve_taxa(
    taxa: list[dict], index: Index, new_names: set[str], doc_genera: set[str]
) -> dict[str, dict]:
    genera = doc_genera | {
        norm(t.get("name_reading") or t["name_as_written"]).split()[0]
        for t in taxa
        if not re.match(r"^[A-Z]\.", t["name_as_written"])
    }
    # Headings print genera in capitals ("QUERCUS PRINOS"); a genus is the same either way.
    genera = {g.capitalize() for g in genera if g.isalpha()}
    results = {}
    for t in taxa:
        name = norm(t["name_as_written"])
        method, targets = index.lookup(name)
        if not targets:
            expanded = expand_abbreviation(name, genera, index)
            if expanded:
                name, method, targets = expanded
                method = f"abbreviation+{method}"
        if not targets and t.get("name_reading"):
            method, targets = index.lookup(norm(t["name_reading"]))
            method = f"name_reading+{method}" if targets else ""
        if not targets:
            for written in filter(None, (t.get("name_reading"), t["name_as_written"])):
                found = quercus_epithet(written, index)
                if len({index.label(x) for x in found}) == 1:
                    method, targets = "quercus-epithet", found
                    break
        canonical = {index.label(x) for x in targets}
        if targets and len(canonical) > 1:
            outcome = "ambiguous"
        elif targets:
            outcome = method
        elif "new" in t or name in new_names:
            outcome = "new (expected)"
        else:
            near = get_close_matches(name, index.all_names, n=1, cutoff=0.85)
            outcome = "near-miss" if near else "unresolved"
            canonical = set(near)
        results[t["ref"]] = {
            "name_as_written": t["name_as_written"],
            "rank": t["rank"],
            "outcome": outcome,
            "targets": sorted(targets),
            "canonical": sorted(canonical),
        }
    return results


def gall_entries_for(target_names: set[str], index: Index) -> list[int]:
    return [
        sid
        for name in target_names
        for sid in index.by_species_name.get(name, set())
        if index.species[sid]["taxoncode"] == "gall"
    ]


def host_species(targets: list[str], index: Index) -> set[int]:
    """Species ids a resolved host taxon stands for; a genus stands for all its species."""
    ids = set()
    for target in targets:
        if target.startswith("s"):
            ids.add(int(target[1:]))
        else:
            genus = index.label(target)
            ids |= {
                sid for sid, s in index.species.items() if base(s["name"]).startswith(genus + " ")
            }
    return ids


def batch_hosts(batch: dict, taxa: dict[str, dict], index: Index) -> dict[str, set[int]]:
    """Per Gall ref, the Gallformers species ids of the Hosts the batch states for it."""
    hosts = defaultdict(set)
    for g in batch["galls"]:
        if g["identified_by"].get("host"):
            hosts[g["ref"]] |= host_species(
                taxa.get(g["identified_by"]["host"], {}).get("targets", []), index
            )
    for f in batch.get("facts", []):
        if f.get("type") == "host_of" and f.get("stance") == "confirm":
            hosts[f["object"]] |= host_species(taxa.get(f["subject"], {}).get("targets", []), index)
    return hosts


def undescribed_candidates(genus: str | None, hosts: set[int], index: Index) -> list[int]:
    """Undescribed Gall entries in the inducer's genus that share a Host with the batch's Gall.
    Gallformers names them like 'Antistrophus l-juncea-collar-gall'."""
    return sorted(
        sid
        for sid in index.undescribed
        if index.hosts[sid] & hosts
        and (
            genus is None
            or base(index.species[sid]["name"]).split()[0].casefold() == genus.casefold()
        )
    )


DESCRIPTOR_STOP = {"gall", "galls", "the", "of", "on", "a", "sp", "spp", "wasp", "unknown"}


def descriptor(entry_name: str) -> set[str]:
    """The descriptive words of a placeholder name: 'Antistrophus l-juncea-collar-gall' -> {collar}.
    The host abbreviation (an initial and an epithet) comes first and is dropped."""
    tail = re.sub(
        r"^\S+(\s+\([^)]*\))?\s+", "", base(entry_name)
    )  # drop genus / 'Unknown (Family)'
    parts = tail.split("-")
    return {p for p in parts[2:] if p not in DESCRIPTOR_STOP} if len(parts) > 2 else set()


def gall_words(g: dict, batch: dict) -> set[str]:
    traits = {
        (f.get("value") or {}).get("value", "")
        for f in batch.get("facts", [])
        if f.get("gall") == g["ref"] and f.get("kind") == "trait"
    }
    return words(g["name_as_written"] + " " + " ".join(traits))


def rank_by_descriptor(
    chosen: list[int], g: dict, batch: dict, index: Index
) -> tuple[list[int], bool]:
    """Keep the candidates whose descriptive words best match the batch's Gall; also say whether the
    best match shares any word at all."""
    seen = gall_words(g, batch)
    scored = [(len(descriptor(index.species[c]["name"]) & seen), c) for c in chosen]
    best = max((s for s, _ in scored), default=0)
    return [c for s, c in scored if s == best], best > 0


def resolve_galls(batch: dict, taxa: dict[str, dict], index: Index) -> dict[str, dict]:
    results = {}
    hosts = batch_hosts(batch, taxa, index)
    for g in batch["galls"]:
        ident = g["identified_by"]
        inducer = taxa.get(ident.get("inducer", ""), {})
        generation = ident.get("generation", {}).get("value")
        candidates = gall_entries_for(set(inducer.get("canonical", [])), index)
        if inducer.get("outcome") in ("near-miss", "unresolved", None):
            candidates = []
        wanted = GENERATION_SUFFIX.get(generation) if generation else None
        if wanted:
            exact = [c for c in candidates if suffix(index.species[c]["name"]) == wanted]
            bare = [c for c in candidates if suffix(index.species[c]["name"]) is None]
            chosen = exact or bare
        else:
            chosen = candidates
        if len(chosen) == 1:
            outcome = "resolved"
        elif len(chosen) > 1:
            outcome = "ambiguous"
        elif g.get("new"):
            outcome = "new (expected)"
        elif inducer.get("rank") not in ("species", "subspecies", "variety", "form"):
            written = inducer.get("canonical") or [inducer.get("name_as_written") or ""]
            genus = written[0].split()[0] if written[0] else None
            chosen = undescribed_candidates(genus, hosts[g["ref"]], index)
            if chosen:
                chosen, words_agree = rank_by_descriptor(chosen, g, batch, index)
            if len(chosen) == 1 and words_agree:
                outcome = "undescribed: one candidate (admin confirms)"
            elif len(chosen) == 1:
                outcome = "undescribed: one candidate, description differs (admin checks)"
            elif chosen:
                outcome = "undescribed: several candidates (admin picks)"
            else:
                outcome = "undescribed (genus-level inducer)"
        else:
            outcome = "no entry"
        results[g["ref"]] = {
            "name_as_written": g["name_as_written"],
            "inducer": inducer.get("name_as_written"),
            "generation": generation,
            "new": bool(g.get("new")),
            "outcome": outcome,
            "entries": [index.species[c]["name"] for c in chosen],
            "entry_ids": chosen,
            "linked_to_source": any(c in index.source_entries for c in chosen),
        }
    # Two of the batch's Galls can't be the same undescribed entry: send both to the admin.
    claims = defaultdict(list)
    for ref, r in results.items():
        if r["outcome"].startswith("undescribed: one candidate"):
            claims[r["entry_ids"][0]].append(ref)
    for refs in claims.values():
        if len(refs) > 1:
            for ref in refs:
                results[ref]["outcome"] = (
                    "undescribed: candidate shared with another Gall (admin picks)"
                )
    return results


def words(text: str) -> set[str]:
    return set(re.findall(r"[a-z]{3,}", text.lower()))


def normalize(text: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", text).split())


def diff_facts(batch: dict, taxa: dict, galls: dict, index: Index, doc: dict) -> dict:
    from producer.document import item_text, resolve

    per_gall = {}
    for ref, g in galls.items():
        if g["outcome"] != "resolved":
            continue
        entry = g["entry_ids"][0]
        facts = [f for f in batch["facts"] if ref in (f.get("object"), f.get("gall"))]
        host_targets = {
            int(t[1:])
            for f in facts
            if f.get("type") == "host_of" and f["stance"] == "confirm"
            for t in taxa[f["subject"]]["targets"]
            if t.startswith("s")
        }
        db_hosts = index.hosts.get(entry, set())
        trait_rows = {}
        for trait in [*TRAIT_TABLES, "detachable"]:
            batch_values = {
                f["value"]["value"]
                for f in facts
                if f["kind"] == "trait" and f["trait"] == trait and f["stance"] == "confirm"
            }
            db_values = index.traits[entry].get(trait, set())
            if batch_values or db_values:
                trait_rows[trait] = {
                    "both": sorted(batch_values & db_values),
                    "batch_only": sorted(batch_values - db_values),
                    "db_only": sorted(db_values - batch_values),
                }
        description = next((f for f in facts if f["kind"] == "description"), None)
        quotes = ""
        if description:
            parts = []
            for ev in description["evidence"]:
                item = resolve(doc, ev.get("item", "")) if ev.get("item") else None
                parts.append(
                    item_text(item) if ev.get("whole_item") and item else ev.get("quote", "")
                )
            quotes = " ".join(parts)
        db_desc = index.descriptions.get(entry, "")
        per_gall[ref] = {
            "entry": index.species[entry]["name"],
            "hosts": {
                "both": sorted(index.label(f"s{h}") for h in host_targets & db_hosts),
                "batch_only": sorted(index.label(f"s{h}") for h in host_targets - db_hosts),
                "db_only": sorted(index.label(f"s{h}") for h in db_hosts - host_targets),
            },
            "traits": trait_rows,
            "description": {
                "db_has_one_for_source": bool(db_desc),
                "batch_has_one": bool(quotes),
                "db_words_in_batch": round(
                    len(words(db_desc) & words(quotes)) / len(words(db_desc)), 2
                )
                if db_desc and quotes
                else None,
                "similarity": round(
                    SequenceMatcher(None, normalize(db_desc), normalize(quotes)).ratio(), 2
                )
                if db_desc and quotes
                else None,
            },
        }
    return per_gall


def main(package: Path, source_id: int):
    index = Index(source_id)
    doc = json.loads((package / "document.json").read_text(encoding="utf-8"))
    report: dict = {"source_id": source_id}
    text = (package / "document.txt").read_text(encoding="utf-8")
    doc_genera = {
        t["name"]
        for t in index.taxonomy.values()
        if t["type"] == "genus" and re.search(rf"\b{re.escape(t['name'])}\b", text)
    }
    new_names: set[str] = set()
    taxonomy_path = package / "taxonomy.json"
    if taxonomy_path.exists():
        tb = json.loads(taxonomy_path.read_text(encoding="utf-8"))
        tax = resolve_taxa(tb["taxa"], index, set(), doc_genera)
        report["taxonomy_taxa"] = tax
        new_names = {norm(t["name_as_written"]) for t in tb["taxa"]}
    gb = json.loads((package / "gall.json").read_text(encoding="utf-8"))
    taxa = resolve_taxa(gb["taxa"], index, new_names, doc_genera)
    galls = resolve_galls(gb, taxa, index)
    report["gall_taxa"] = taxa
    report["galls"] = galls
    report["facts"] = diff_facts(gb, taxa, galls, index, doc)
    linked = {index.species[s]["name"] for s in index.source_entries}
    found = {e for g in galls.values() for e in g["entries"] if g["outcome"] == "resolved"}
    # Entries the admin queue would show as a candidate (ambiguous or undescribed matches).
    candidates = {e for g in galls.values() for e in g["entries"]}
    report["db_entries_for_source"] = {
        "linked": sorted(linked),
        "not_found_by_batch": sorted(linked - found),
        "not_found_even_as_candidate": sorted(linked - candidates),
    }
    (package / "dryrun.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    def tally(rows):
        counts: dict[str, int] = defaultdict(int)
        for r in rows.values():
            counts[r["outcome"]] += 1
        return dict(counts)

    print(f"== {package.name} (source {source_id})")
    if "taxonomy_taxa" in report:
        print("taxonomy names:", tally(report["taxonomy_taxa"]))
    print("gall-batch names:", tally(taxa))
    print("galls:", tally(galls))
    entries = report["db_entries_for_source"]
    print(
        f"DB entries for this Source: {len(entries['linked'])}; "
        f"matched {len(entries['linked']) - len(entries['not_found_by_batch'])}, "
        f"candidate only {len(entries['not_found_by_batch']) - len(entries['not_found_even_as_candidate'])}, "
        f"not found {len(entries['not_found_even_as_candidate'])}"
    )
    print("not found even as a candidate:", entries["not_found_even_as_candidate"])


if __name__ == "__main__":
    main(Path(sys.argv[1]), int(sys.argv[2]))
