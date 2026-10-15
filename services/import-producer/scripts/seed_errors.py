"""Copy a package and plant known errors in its batches, to measure phase 5 recall.

Usage: uv run python scripts/seed_errors.py <easy|hard> <package> <seeded-package> <manifest.json>

The manifest (what was planted) is written outside the seeded package, so the
phase 5 reviewer never sees it. Every planted error keeps its quotes real, so
the seeded package still passes phase 4. The errors are specific to the
Ashmead 1896 package (output/trial/98-ashmead-1896).

easy: blatant contradictions, some with internal tells.
hard: self-consistent mistakes a careful producer could make; tells removed
(unused declarations, contradicting unmapped entries) and ids renumbered.
"""

import copy
import json
import shutil
import sys
from pathlib import Path

FILES = ("document.json", "document.txt", "convert.json", "taxonomy.json", "gall.json")


def by_id(items: list[dict], key: str = "id") -> dict[str, dict]:
    return {item[key]: item for item in items}


def ref_named(taxa: list[dict], name: str) -> str:
    return next(t["ref"] for t in taxa if t["name_as_written"] == name)


def seed_easy(taxonomy: dict, gall: dict) -> list[dict]:
    facts = by_id(gall["facts"])
    acts = by_id(taxonomy["acts"])
    planted = []

    def plant(batch: str, target: str, kind: str, change: str) -> None:
        planted.append({"seed": f"S{len(planted) + 1}", "batch": batch, "id": target,
                        "kind": kind, "change": change})  # fmt: skip

    facts["f18"]["subject"] = ref_named(gall["taxa"], "Q. alba")
    plant("gall.json", "f18", "wrong_target", "host Quercus emoryi -> Q. alba")

    facts["f49"]["stance"] = "deny"
    plant("gall.json", "f49", "wrong_stance", "color brown confirm -> deny")

    facts["f213"]["value"]["value"] = "green"
    plant("gall.json", "f213", "wrong_value", "color black -> green")

    facts["f152"]["value"]["value"] = "underground (roots+)"
    plant("gall.json", "f152", "wrong_value", "plant_part stem -> underground (roots+)")

    facts["f88"]["evidence"] = copy.deepcopy(facts["f86"]["evidence"])
    plant("gall.json", "f88", "unsupported", "pubescent: evidence swapped for 'very hard, ovate…'")

    facts["f232"]["gall"] = "g32"
    plant("gall.json", "f232", "wrong_target", "texture woolly moved from g33 to g32")

    facts["f226"]["type"] = "inquiline_of"
    plant("gall.json", "f226", "wrong_type", "Callirhytis lasius inducer_of -> inquiline_of")

    acts["a44"]["parent"] = ref_named(taxonomy["taxa"], "ANDRICUS")
    plant("taxonomy.json", "a44", "wrong_value", "Amphibolips trizonata placed in Andricus")

    return planted


def insert_after(items: list[dict], anchor_id: str, new: dict, key: str = "id") -> None:
    index = next(i for i, item in enumerate(items) if item[key] == anchor_id)
    items.insert(index + 1, new)


def renumber(items: list[dict], prefix: str, planted: list[dict]) -> None:
    """Give items sequential ids again, so inserted ones don't stand out; fix the manifest."""
    mapping = {}
    for n, item in enumerate(items, start=1):
        mapping[item["id"]] = f"{prefix}{n}"
        item["id"] = mapping[item["id"]]
    for p in planted:
        p["id"] = mapping.get(p["id"], p["id"])


def seed_hard(taxonomy: dict, gall: dict) -> list[dict]:
    facts = by_id(gall["facts"])
    planted = []

    def plant(batch: str, target: str, kind: str, change: str) -> None:
        planted.append({"seed": f"H{len(planted) + 1}", "batch": batch, "id": target,
                        "kind": kind, "change": change})  # fmt: skip

    def evidence(item: str, quote: str, page: str) -> list[dict]:
        return [{"item": item, "quote": quote, "page": page}]

    # Host taken from a comparison with another species.
    facts["f11"]["subject"] = ref_named(gall["taxa"], "Q. alba")
    facts["f11"]["evidence"] = evidence(
        "#/texts/34", "whereas that species is developed from the buds of Q. alba", "114"
    )
    gall["taxa"] = [t for t in gall["taxa"] if t["name_as_written"] != "Q. obtusiloba"]
    plant("gall.json", "f11", "wrong_target", "g2 host from the comparison species (Q. alba)")

    # Season from a laboratory rearing date.
    insert_after(gall["facts"], "f162", {
        "id": "x2", "stance": "confirm", "kind": "trait", "gall": "g22", "trait": "season",
        "value": {"value": "Summer", "as_written": "June"},
        "evidence": evidence("#/texts/205", "reared during June, 1882, from galls received May 2, 1882", "126"),
    })  # fmt: skip
    plant("gall.json", "x2", "unsupported", "g22 season Summer from a rearing date")

    # A hedge stated as a Fact; its unmapped entry removed.
    lep = f"t{max(int(t['ref'][1:]) for t in gall['taxa']) + 1}"
    gall["taxa"].append({"ref": lep, "name_as_written": "Lepidopteron", "rank": "order"})
    insert_after(gall["facts"], "f248", {
        "id": "x3", "stance": "confirm", "kind": "relationship", "type": "inquiline_of",
        "subject": lep, "object": "g36",
        "evidence": evidence("#/texts/349", "It is also quite probable that the Lepidopteron is inquilinous in the galls produced by this species.", "134"),
    })  # fmt: skip
    gall["unmapped"] = [u for u in gall["unmapped"] if not u["term"].startswith("quite probable")]
    plant("gall.json", "x3", "rule", "hedged 'quite probable' inquiline stated as confirm")

    # Plausible but wrong definition fits.
    facts["f20"]["value"]["value"] = "globular"
    plant("gall.json", "f20", "wrong_value", "'semiglobular' -> globular (was hemispherical)")

    insert_after(gall["facts"], next(f["id"] for f in gall["facts"] if f.get("gall") == "g37"), {
        "id": "x5", "stance": "confirm", "kind": "trait", "gall": "g37", "trait": "texture",
        "value": {"value": "hairless", "as_written": "smooth"},
        "evidence": evidence("#/texts/363", "An irregularly rounded, abrupt, smooth sweliing", "135"),
    })  # fmt: skip
    gall["unmapped"] = [
        u for u in gall["unmapped"] if not (u["term"] == "smooth" and u.get("gall") == "g37")
    ]
    plant("gall.json", "x5", "wrong_value", "'smooth' -> hairless (no hairs mentioned)")

    # Description of the wasp, not the gall.
    facts["f26"]["evidence"][0]["item"] = "#/texts/44"
    plant("gall.json", "f26", "unsupported", "g4 description is the Gallfly paragraph")

    # An existing genus marked new.
    holcaspis = ref_named(taxonomy["taxa"], "HOLCASPIS")
    next(t for t in taxonomy["taxa"] if t["ref"] == holcaspis)["new"] = {"status": "new genus"}
    insert_after(taxonomy["acts"], "a1", {
        "id": "x7", "stance": "confirm", "kind": "name", "taxon": holcaspis,
        "evidence": evidence("#/texts/211", "Genus HOLCASPIS, Mayr.", "126"),
    })  # fmt: skip
    plant("taxonomy.json", "x7", "wrong_value", "Holcaspis, Mayr marked as a new genus")

    renumber(gall["facts"], "f", planted)
    renumber(taxonomy["acts"], "a", planted)
    return planted


SEEDS = {"easy": seed_easy, "hard": seed_hard}


def main(seed_set: str, package: Path, seeded: Path, manifest: Path) -> None:
    seeded.mkdir(parents=True, exist_ok=False)
    for name in FILES:
        shutil.copy2(package / name, seeded / name)
    taxonomy = json.loads((seeded / "taxonomy.json").read_text(encoding="utf-8"))
    gall = json.loads((seeded / "gall.json").read_text(encoding="utf-8"))
    planted = SEEDS[seed_set](taxonomy, gall)
    for name, batch in (("taxonomy.json", taxonomy), ("gall.json", gall)):
        (seeded / name).write_text(
            json.dumps(batch, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    manifest.write_text(json.dumps(planted, indent=2) + "\n", encoding="utf-8")
    print(f"planted {len(planted)} errors; manifest: {manifest}")


if __name__ == "__main__":
    main(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]))
