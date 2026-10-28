"""The golden regression set: human verdicts on trial statements, and a scorer for new runs.

Five trial packages were checked by hand (output/trial-log-2026-10.md, matter 8546): each
check page showed a random sample of a package's statements (taxonomy acts and gall
Facts) and its dry-run name matches, and Jeff marked each right, wrong or unsure.

`export` turns those verdicts into golden/<source id>-<short name>.json. Each item keeps
the verdict, the note and the whole statement as the check page showed it, with every
local id (t3, g2, f41) replaced by what it stands for (names as written, generation,
quotes and pages), so a later run can be scored without the trial packages.

`score` matches each golden item in a new package for the same Source by meaning: Galls
by their identifying fields (Inducer, Host, generation, plant part, then the name as
written), statements by a natural key per kind. Each item is present (same key and
value), changed (same key, different value or stance) or missing. No API calls.

Format changes since the trial (2026-10-17 and 2026-10-26 decisions):
- range `include` was removed; a place where the Gall occurs outside its Hosts' ranges is
  a recorded occurrence. An include adjustment, on either side, is scored as an
  `occurrence` Fact at that place.
- season now means when the Gall forms and grows; detachable takes one value; generation
  values come from the Inducer's generation group. None of these changes a field's shape,
  so values are compared as they are: a season value replaced by another shows as
  `changed`, a generation added to or removed from a Gall shows in the Gall mapping.
"""

import json
import re
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from producer import document, paths

PROJECT = paths.PROJECT
GOLDEN_DIR = PROJECT / "golden"
TRIAL_DIR = PROJECT / "output" / "trial"
REPORT_NAME = "golden-score.json"
GOLDEN_FORMAT = 1

BATCHES = ("taxonomy", "gall", "name")
SINGLE_VALUED_TRAITS = {"detachable"}
IDENTIFYING = ("inducer", "host", "generation", "plant_part")  # galls[].identified_by
DESCRIPTION_SAME = 0.6  # word overlap (Jaccard) at or above which a description is unchanged
GALL_NAME_ALONE = 0.5  # name similarity that identifies a Gall when no identifying field agrees


@dataclass(frozen=True)
class TrialSource:
    """A checked trial package: where it is and where its verdicts were exported to."""

    source_id: int
    short: str
    name: str
    package: str  # directory under output/trial
    checks: str  # directory under the verdict export, holding checks/<doc id>.json
    check_page: str
    revisions: dict = field(default_factory=dict)


SOURCES = (
    TrialSource(
        98,
        "ashmead-1896",
        "Ashmead 1896",
        "98-ashmead-1896",
        "ashmead",
        "https://claude.ai/artifact/Ns3bRDFP95sUKkT3NUzW1x",
        revisions={
            "gall-f141": {
                "verdict": "right",
                "reason": "Recount (trial log, 2026-10-15): Jeff confirmed the ruptured/split "
                "definition is right, so this statement is right (Ashmead 40/40).",
            }
        },
    ),
    TrialSource(
        21,
        "osten-sacken-1862",
        "Osten Sacken 1862, Additions and corrections",
        "21-corrections-1862",
        "osten-sacken-1862",
        "https://claude.ai/artifact/2ZtVyD8m1cjqoq9kXLCn1z",
        revisions={
            "gall-f162": {
                "wrong_part": "evidence",
                "wrong_quotes": ["QuERCUS ALBA. White Oak."],
                "reason": "Trial log (2026-10-15): the Fact is right, but its second evidence "
                "is a heading about a different gall. Fixed when that quote goes and the Fact "
                "stays.",
            }
        },
    ),
    TrialSource(
        502,
        "floate-2010",
        "Floate 2010",
        "502-floate-2010-v2",
        "floate-2010",
        "https://claude.ai/artifact/LQ1sAQ6GFvC6csYnhCiiad",
    ),
    TrialSource(
        680,
        "nastasi-davis-2022",
        "Nastasi & Davis 2022",
        "680-nastasi-davis-2022",
        "nastasi-davis-2022",
        "https://claude.ai/artifact/LVcz9oNbpmdys2oMgrGq4h",
    ),
    TrialSource(
        729,
        "aphis-rubifolii",
        "InfluentialPoints, Aphis rubifolii",
        "729-aphis-rubifolii",
        "aphis-rubifolii",
        "https://claude.ai/artifact/CcjPZXZBZV58LsFNs9K81F",
    ),
)


# ------------------------------------------------------------------ reading a package


def read_json(path: Path) -> dict | None:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def load_package(path: Path) -> dict:
    pkg = {
        "taxonomy": read_json(path / "taxonomy.json"),
        "gall": read_json(path / "gall.json"),
        "dryrun": read_json(path / "dryrun.json"),
        "document": read_json(path / "document.json"),
    }
    if pkg["gall"] is None and pkg["taxonomy"] is None:
        raise FileNotFoundError(f"{path} has neither taxonomy.json nor gall.json")
    return pkg


# ------------------------------------------------------------------ names and text


def words(text: str) -> list[str]:
    return re.findall(r"[0-9a-z]+", unicodedata.normalize("NFKC", text).casefold())


def name_tokens(name: str) -> list[str]:
    """A scientific name as comparable tokens: case, punctuation, a parenthesised subgenus or
    authorship, 'sp.'/'spp.' and the hybrid sign don't count."""
    name = re.sub(r"\([^)]*\)", " ", unicodedata.normalize("NFKC", name))
    name = re.sub(r"\s[×⨯]\s?", " x ", name)  # noqa: RUF001 (the hybrid signs)
    return [t for t in words(name) if t not in ("sp", "spp")]


def names_match(a: str, b: str) -> bool:
    """Same tokens, where an initial matches the word it abbreviates ('Q. alba' = 'Quercus
    alba', 'C. q. inanis' = 'Cynips quercus inanis')."""
    ta, tb = name_tokens(a), name_tokens(b)
    if not ta or len(ta) != len(tb):
        return False
    return all(
        x == y or (len(x) == 1 and y.startswith(x)) or (len(y) == 1 and x.startswith(y))
        for x, y in zip(ta, tb, strict=True)
    )


def taxon_forms(taxon: dict) -> list[str]:
    return [n for n in (taxon.get("name_as_written"), taxon.get("name_reading")) if n]


def taxa_match(a: dict | None, b: dict | None) -> bool:
    if not a or not b:
        return False
    return any(names_match(x, y) for x in taxon_forms(a) for y in taxon_forms(b))


def similarity(a: str, b: str) -> float:
    """Word-set overlap (Jaccard), 0..1."""
    wa, wb = set(words(a)), set(words(b))
    if not wa and not wb:
        return 1.0
    return len(wa & wb) / len(wa | wb)


def taxon_label(taxon: dict | None) -> str:
    if not taxon:
        return "?"
    return taxon.get("name_reading") or taxon["name_as_written"]


# ------------------------------------------------------------------ describing statements


class Described:
    """Every statement of a package, with local ids replaced by what they refer to."""

    def __init__(self, pkg: dict):
        self.doc = pkg.get("document")
        self.printed = document.printed_pages(self.doc) if self.doc else {}
        gall = pkg.get("gall") or {"taxa": [], "galls": [], "facts": []}
        taxonomy = pkg.get("taxonomy") or {"taxa": [], "acts": []}
        gall_taxa = {t["ref"]: self.taxon(t) for t in gall.get("taxa", [])}
        self.galls = {g["ref"]: self.gall(g, gall_taxa) for g in gall.get("galls", [])}

        self.statements: dict[str, dict] = {}  # "gall-f3", "taxonomy-a1", "name-g2"
        relationships = {}
        for f in gall.get("facts", []):
            if f["kind"] == "relationship":
                relationships[f["id"]] = self.relationship(f, gall_taxa)
        for f in gall.get("facts", []):
            self.statements[f"gall-{f['id']}"] = self.fact(f, gall_taxa, relationships)
        tax_taxa = {t["ref"]: self.taxon(t) for t in taxonomy.get("taxa", [])}
        for a in taxonomy.get("acts", []):
            self.statements[f"taxonomy-{a['id']}"] = self.act(a, tax_taxa)
        self.has_names = pkg.get("dryrun") is not None
        for ref, match in ((pkg.get("dryrun") or {}).get("galls") or {}).items():
            if ref in self.galls:
                self.statements[f"name-{ref}"] = {
                    "kind": "name_match",
                    "gall": self.galls[ref],
                    "inducer_as_written": match.get("inducer"),
                    "outcome": match.get("outcome"),
                    "entries": sorted(match.get("entries") or []),
                }
        self.slot_values = {}
        for f in gall.get("facts", []):
            if f["kind"] == "trait":
                key = (f["gall"], f["trait"])
                self.slot_values.setdefault(key, set()).add(f["value"]["value"])

    @staticmethod
    def taxon(t: dict) -> dict:
        out = {"ref": t["ref"], "name_as_written": t["name_as_written"]}
        for key in ("name_reading", "rank", "sensu"):
            if t.get(key):
                out[key] = t[key]
        if t.get("new"):
            out["new"] = t["new"]["status"]
        return out

    @staticmethod
    def gall(g: dict, taxa: dict) -> dict:
        ident = g.get("identified_by", {})
        out = {"ref": g["ref"], "name_as_written": g["name_as_written"]}
        for key in ("inducer", "host"):
            if ident.get(key):
                out[key] = taxa.get(ident[key], {"ref": ident[key], "name_as_written": "?"})
        for key in ("generation", "plant_part"):
            if ident.get(key):
                out[key] = ident[key]
        for key in ("new", "formerly_undescribed"):
            if g.get(key):
                out[key] = True
        return out

    def evidence(self, items: list[dict]) -> list[dict]:
        out = []
        for e in items:
            if "statement" in e:
                out.append({"statement": e["statement"]})
                continue
            entry = {"item": e.get("item")}
            item = document.resolve(self.doc, e["item"]) if self.doc and e.get("item") else None
            if e.get("whole_item"):
                entry["whole_item"] = True
                if item is not None:
                    entry["text"] = document.item_text(item)
            else:
                entry["quote"] = e["quote"]
            pages = sorted({p["page_no"] for p in (item or {}).get("prov", [])})
            if pages:
                entry["pdf_page"] = pages[0]
            printed = e.get("page") or (self.printed.get(pages[0]) if pages else None)
            if printed:
                entry["page"] = printed
            if e.get("cites"):
                entry["cites"] = e["cites"]["as_written"]
            out.append({k: v for k, v in entry.items() if v is not None})
        return out

    def endpoint(self, ref: str, taxa: dict) -> dict:
        if ref.startswith("g"):
            return {"gall": self.galls.get(ref, {"ref": ref, "name_as_written": "?"})}
        return {"taxon": taxa.get(ref, {"ref": ref, "name_as_written": "?"})}

    def relationship(self, f: dict, taxa: dict) -> dict:
        out = {
            "kind": "relationship",
            "stance": f["stance"],
            "type": f["type"],
            "subject": self.endpoint(f["subject"], taxa),
            "object": self.endpoint(f["object"], taxa),
        }
        if f.get("gall_context"):
            out["gall_context"] = self.galls.get(f["gall_context"])
        return out

    def fact(self, f: dict, taxa: dict, relationships: dict) -> dict:
        kind = f["kind"]
        if kind == "relationship":
            out = dict(relationships[f["id"]])
        else:
            out = {"kind": kind, "stance": f["stance"]}
            if "gall" in f:
                out["gall"] = self.galls.get(f["gall"], {"ref": f["gall"], "name_as_written": "?"})
            if kind == "qualifier":
                out |= {"of": relationships.get(f["of"]), "qualifier": f["qualifier"]}
            for key in ("trait", "value", "adjustment", "place", "name"):
                if key in f:
                    out[key] = f[key]
            for key in ("when_as_written", "stage_as_written"):
                if f.get(key):
                    out[key] = f[key]
        out["evidence"] = self.evidence(f["evidence"])
        return out

    def act(self, a: dict, taxa: dict) -> dict:
        def t(ref):
            return taxa.get(ref, {"ref": ref, "name_as_written": "?"})

        out = {"kind": a["kind"], "stance": a["stance"]}
        for key in ("taxon", "parent", "name", "accepted"):
            if key in a:
                out[key] = t(a[key])
        if "into" in a:
            out["into"] = [t(r) for r in a["into"]]
        if a.get("authorship"):
            out["authorship"] = a["authorship"]["as_written"]
        for key in ("common_name", "status_as_written"):
            if a.get(key):
                out[key] = a[key]
        out["evidence"] = self.evidence(a["evidence"])
        return out

    def totals(self) -> dict:
        counts: dict[str, int] = {}
        for sid, s in self.statements.items():
            key = f"{sid.split('-')[0]}:{s['kind']}"
            counts[key] = counts.get(key, 0) + 1
        return {"galls": len(self.galls), "statements": dict(sorted(counts.items()))}


def item_order(item_id: str) -> tuple:
    batch, local = item_id.split("-", 1)
    return BATCHES.index(batch), int(re.sub(r"\D", "", local) or 0)


def label(s: dict) -> str:
    """One line a person can read."""

    def end(e):
        return taxon_label(e["taxon"]) if "taxon" in e else e["gall"]["name_as_written"]

    deny = " (deny)" if s.get("stance") == "deny" else ""
    kind = s["kind"]
    if kind == "relationship":
        return f"{end(s['subject'])} {s['type']} {end(s['object'])}{deny}"
    if kind == "qualifier":
        return f"{s['qualifier']} = {s['value']['value']} on [{label(s['of'])}]{deny}"
    if kind == "name_match":
        return f"{s['gall']['name_as_written']} -> {', '.join(s['entries']) or 'no entry'} ({s['outcome']})"
    gall = f" | {s['gall']['name_as_written']}" if "gall" in s else ""
    if kind == "trait":
        return f"{s['trait']} = {s['value']['value']}{deny}{gall}"
    if kind in ("range", "occurrence"):
        adj = s.get("adjustment", "occurs")
        return f"{adj} {s['place']['value']} ({s['place']['as_written']}){deny}{gall}"
    if kind == "alias":
        return f"common name '{s['name']}'{deny}{gall}"
    if kind == "description":
        return f"description{deny}{gall}"
    if kind == "name":
        return f"name {taxon_label(s['taxon'])}{deny}"
    if kind == "placement":
        return f"{taxon_label(s['taxon'])} placed in {taxon_label(s['parent'])}{deny}"
    if kind == "synonymy":
        return f"{taxon_label(s['name'])} = {taxon_label(s['accepted'])}{deny}"
    if kind == "split":
        return f"{taxon_label(s['taxon'])} split into {', '.join(taxon_label(t) for t in s['into'])}{deny}"
    if kind == "common_name":
        return f"{taxon_label(s['taxon'])} common name '{s['common_name']}'{deny}"
    return kind


# ------------------------------------------------------------------ export


def export_source(spec: TrialSource, package_dir: Path, checks_dir: Path) -> dict:
    """The golden document for one checked package."""
    pkg = load_package(package_dir)
    described = Described(pkg)
    checks = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in checks_dir.glob("*.json")}
    if not checks:
        raise ValueError(f"no verdicts in {checks_dir}")
    unknown = sorted(set(spec.revisions) - set(checks))
    if unknown:
        raise ValueError(f"revisions for unchecked items: {', '.join(unknown)}")

    items = []
    for doc_id in sorted(checks, key=item_order):
        check = checks[doc_id]
        statement = described.statements.get(doc_id)
        if statement is None:
            raise ValueError(f"{doc_id}: no such statement in {package_dir}")
        if check.get("verdict") not in ("right", "wrong", "unsure"):
            raise ValueError(f"{doc_id}: verdict {check.get('verdict')!r}")
        item = {"id": doc_id, "verdict": check["verdict"]}
        if (check.get("note") or "").strip():
            item["note"] = check["note"].strip()
        if "passing_mention" in check:
            item["passing_mention"] = check["passing_mention"]
        item["checked_at"] = check.get("at")
        revision = spec.revisions.get(doc_id)
        if revision:
            item["revision"] = {"reason": revision["reason"]}
            if revision.get("verdict") and revision["verdict"] != check["verdict"]:
                item["revision"] = {"from": check["verdict"], "reason": revision["reason"]}
                item["verdict"] = revision["verdict"]
            if revision.get("wrong_part"):
                item["wrong_part"] = revision["wrong_part"]
                item["wrong_quotes"] = revision["wrong_quotes"]
        item["statement"] = statement
        if statement["kind"] == "trait":
            slot = (statement["gall"]["ref"], statement["trait"])
            item["context"] = {"slot_values": sorted(described.slot_values.get(slot, ()))}
        items.append(item)

    envelope = pkg.get("gall") or pkg.get("taxonomy") or {}
    return {
        "golden_format": GOLDEN_FORMAT,
        "source": {"id": spec.source_id, "name": spec.name, "short": spec.short},
        "citation": envelope.get("source", {}).get("citation"),
        "package": spec.package,
        "package_format": {
            k: envelope.get(k) for k in ("format_version", "vocabulary_version", "producer")
        },
        "check_page": spec.check_page,
        "package_totals": described.totals(),
        "counts": counts(items),
        "items": items,
    }


def counts(items: list[dict]) -> dict:
    def tally(rows):
        out = {"right": 0, "wrong": 0, "unsure": 0}
        for r in rows:
            out[r["verdict"]] += 1
        return {k: v for k, v in out.items() if v}

    statements = [i for i in items if not i["id"].startswith("name-")]
    by_kind: dict[str, list] = {}
    for i in items:
        by_kind.setdefault(f"{i['id'].split('-')[0]}:{i['statement']['kind']}", []).append(i)
    return {
        "statements": tally(statements),
        "names": tally([i for i in items if i["id"].startswith("name-")]),
        "by_kind": {k: tally(v) for k, v in sorted(by_kind.items())},
    }


def write_golden(doc: dict, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{doc['source']['id']}-{doc['source']['short']}.json"
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


# ------------------------------------------------------------------ scoring


def current_shape(s: dict) -> tuple[dict, str | None]:
    """A statement in today's contract shape, and a note when it had to be mapped."""
    if s["kind"] == "range" and s.get("adjustment") == "include":
        mapped = {k: v for k, v in s.items() if k != "adjustment"} | {"kind": "occurrence"}
        return mapped, "range include -> occurrence (include was removed 2026-10-26)"
    return s, None


def galls_in(s: dict):
    for key, value in s.items():
        if key in ("gall", "gall_context") and isinstance(value, dict):
            yield value
        elif key in ("subject", "object", "of") and isinstance(value, dict):
            yield from galls_in(value)


def gall_score(g: dict, n: dict) -> float | None:
    """How well run Gall n matches golden Gall g, or None when their identities conflict."""
    for key in ("inducer", "host"):
        if g.get(key) and n.get(key) and not taxa_match(g[key], n[key]):
            return None
    if g.get("inducer") and not n.get("inducer"):
        return None
    for key in ("generation", "plant_part"):
        if g.get(key) and n.get(key) and g[key]["value"] != n[key]["value"]:
            return None
    agree = sum(bool(g.get(k)) == bool(n.get(k)) for k in IDENTIFYING)
    matched = sum(bool(g.get(k)) and bool(n.get(k)) for k in ("inducer", "host"))
    name = similarity(g["name_as_written"], n["name_as_written"])
    if not matched and name < GALL_NAME_ALONE:
        return None
    return agree + 2 * name


def identity(g: dict) -> dict:
    out = {"ref": g["ref"], "name_as_written": g["name_as_written"]}
    for key in ("inducer", "host"):
        if g.get(key):
            out[key] = taxon_label(g[key])
    for key in ("generation", "plant_part"):
        if g.get(key):
            out[key] = g[key]["value"]
    return out


def assign_galls(golden_galls: dict, run_galls: dict) -> tuple[dict, list]:
    """Golden Gall ref -> run Gall ref: best pairs first, one to one; a golden Gall left over
    shares the run Gall it fits best (two Galls merged into one)."""
    pairs = sorted(
        (
            (score, gref, nref)
            for gref, g in golden_galls.items()
            for nref, n in run_galls.items()
            if (score := gall_score(g, n)) is not None
        ),
        key=lambda p: (-p[0], p[1], p[2]),
    )
    mapping, used, shared = {}, set(), set()
    for _score, gref, nref in pairs:
        if gref not in mapping and nref not in used:
            mapping[gref] = nref
            used.add(nref)
    for _score, gref, nref in pairs:
        if gref not in mapping:
            mapping[gref] = nref
            shared.add(gref)

    report = []
    for gref in sorted(golden_galls, key=lambda r: int(re.sub(r"\D", "", r) or 0)):
        g = golden_galls[gref]
        row = {"golden": identity(g), "run": None}
        if gref in mapping:
            n = run_galls[mapping[gref]]
            row["run"] = identity(n)
            changes = [
                f"{k}: {row['golden'].get(k, 'none')} -> {row['run'].get(k, 'none')}"
                for k in IDENTIFYING
                if bool(g.get(k)) != bool(n.get(k))
            ]
            if changes:
                row["identity_changed"] = changes
            if gref in shared:
                row["shared"] = True
        report.append(row)
    return mapping, report


class Scorer:
    def __init__(self, golden: dict, run_dir: Path):
        self.golden = golden
        self.run_dir = run_dir
        pkg = load_package(run_dir)
        self.envelope = pkg.get("gall") or pkg.get("taxonomy") or {}
        self.run = Described(pkg)
        self.mappings: list[str] = []
        self.run_statements = {}
        mapped_run = 0
        for sid, s in self.run.statements.items():
            shaped, note = current_shape(s)
            mapped_run += note is not None
            self.run_statements[sid] = shaped
        if mapped_run:
            self.mappings.append(
                f"run: {mapped_run} range include adjustment(s) scored as occurrences"
            )
        golden_galls = {}
        for item in golden["items"]:
            for g in galls_in(item["statement"]):
                golden_galls.setdefault(g["ref"], g)
        self.gall_map, self.gall_report = assign_galls(golden_galls, self.run.galls)

    # -- keys

    def same_gall(self, g: dict | None, n: dict | None) -> bool:
        if not g or not n:
            return not g and not n
        return self.gall_map.get(g["ref"]) == n["ref"]

    def same_end(self, g: dict, n: dict) -> bool:
        if "taxon" in g:
            return "taxon" in n and taxa_match(g["taxon"], n["taxon"])
        return "gall" in n and self.same_gall(g["gall"], n["gall"])

    def same_relationship(self, g: dict, n: dict) -> bool:
        return (
            n["kind"] == "relationship"
            and self.same_end(g["subject"], n["subject"])
            and self.same_end(g["object"], n["object"])
            and self.same_gall(g.get("gall_context"), n.get("gall_context"))
        )

    def same_key(self, g: dict, n: dict) -> bool:
        kind = g["kind"]
        if n["kind"] != kind:
            return False
        if kind == "relationship":
            return self.same_relationship(g, n)
        if kind == "qualifier":
            return (
                g["qualifier"] == n["qualifier"]
                and bool(g.get("of")) == bool(n.get("of"))
                and (not g.get("of") or self.same_relationship(g["of"], n["of"]))
            )
        if kind == "name_match":
            return self.same_gall(g["gall"], n["gall"])
        if "gall" in g and not self.same_gall(g["gall"], n.get("gall")):
            return False
        if kind == "trait":
            return g["trait"] == n["trait"]
        if kind in ("range", "occurrence"):
            return g["place"]["value"] == n["place"]["value"]
        if kind == "alias":
            return words(g["name"]) == words(n["name"])
        if kind == "description":
            return True
        if kind == "synonymy":
            return taxa_match(g["name"], n["name"])
        if kind == "common_name":
            same_name = words(g["common_name"]) == words(n["common_name"])
            return same_name and taxa_match(g["taxon"], n["taxon"])
        return taxa_match(g.get("taxon"), n.get("taxon"))  # name, placement, split

    # -- values

    def value(self, s: dict):
        """(comparable, display) for the part of a statement its key leaves out."""
        kind = s["kind"]
        deny = " (deny)" if s.get("stance") == "deny" else ""
        if kind == "relationship":
            return (s["type"], s["stance"]), s["type"] + deny
        if kind in ("qualifier", "trait"):
            return (s["value"]["value"], s["stance"]), f"{s['value']['value']}{deny}"
        if kind == "range":
            return (s["adjustment"], s["stance"]), s["adjustment"] + deny
        if kind == "name_match":
            v = {"outcome": s["outcome"], "entries": s["entries"]}
            return (s["outcome"], tuple(s["entries"])), v
        if kind == "name":
            rank, new = s["taxon"].get("rank"), bool(s["taxon"].get("new"))
            return (rank, new, s["stance"]), f"{rank}{' (new)' if new else ''}{deny}"
        if kind == "placement":
            return (s["parent"], s["stance"]), taxon_label(s["parent"]) + deny
        if kind == "synonymy":
            return (s["accepted"], s["stance"]), taxon_label(s["accepted"]) + deny
        if kind == "split":
            return (s["into"], s["stance"]), ", ".join(taxon_label(t) for t in s["into"]) + deny
        return (s["stance"],), s["stance"]  # occurrence, alias, common_name

    def same_value(self, g: dict, n: dict) -> bool:
        gv, nv = self.value(g)[0], self.value(n)[0]
        kind = g["kind"]
        if kind in ("placement", "synonymy"):
            return gv[1] == nv[1] and taxa_match(gv[0], nv[0])
        if kind == "split":
            return (
                gv[1] == nv[1]
                and len(gv[0]) == len(nv[0])
                and all(any(taxa_match(a, b) for b in nv[0]) for a in gv[0])
            )
        return gv == nv

    def text(self, s: dict) -> str:
        return " ".join(e.get("quote") or e.get("text") or "" for e in s.get("evidence", []))

    # -- matching

    def match(self, item: dict) -> dict:
        golden_statement, note = current_shape(item["statement"])
        if note:
            self.mappings.append(f"{item['id']}: {note}")
        g = golden_statement
        result = {
            "id": item["id"],
            "verdict": item["verdict"],
            "kind": f"{item['id'].split('-')[0]}:{item['statement']['kind']}",
            "label": label(item["statement"]),
        }
        if item.get("wrong_part"):
            result["wrong_part"] = item["wrong_part"]
        if g["kind"] == "name_match" and not self.run.has_names:
            return result | {"status": "not scored", "reason": "the run has no dryrun.json"}
        batch = item["id"].split("-")[0]
        candidates = [
            (sid, n)
            for sid, n in self.run_statements.items()
            if sid.startswith(batch + "-") and self.same_key(g, n)
        ]
        if g["kind"] == "description":
            return result | self.match_description(g, candidates)
        if g["kind"] == "trait" and g["trait"] not in SINGLE_VALUED_TRAITS:
            return result | self.match_trait(item, g, candidates)

        exact = [(sid, n) for sid, n in candidates if self.same_value(g, n)]
        if exact:
            sid, n = exact[0]
            return result | {"status": "present", "run_id": sid} | self.evidence_check(item, n)
        if candidates:
            sid, n = candidates[0]
            return result | {"status": "changed", "run_id": sid} | self.both(g, n)
        return result | {"status": "missing"} | self.why_missing(g)

    def both(self, g: dict, n: dict) -> dict:
        return {"golden": self.value(g)[1], "run": self.value(n)[1]}

    def match_trait(self, item: dict, g: dict, candidates: list) -> dict:
        exact = [(sid, n) for sid, n in candidates if n["value"]["value"] == g["value"]["value"]]
        same = [(sid, n) for sid, n in exact if n["stance"] == g["stance"]]
        if same:
            return {"status": "present", "run_id": same[0][0]} | self.evidence_check(
                item, same[0][1]
            )
        if exact:  # the same value, now denied (or confirmed)
            sid, n = exact[0]
            return {"status": "changed", "run_id": sid} | self.both(g, n)
        before = set(item.get("context", {}).get("slot_values", [g["value"]["value"]]))
        new = sorted({n["value"]["value"] for _, n in candidates} - before)
        if new:
            return {"status": "changed", "golden": g["value"]["value"], "run": new}
        return {"status": "missing"} | self.why_missing(g)

    def match_description(self, g: dict, candidates: list) -> dict:
        if not candidates:
            return {"status": "missing"} | self.why_missing(g)
        best = max(candidates, key=lambda c: similarity(self.text(g), self.text(c[1])))
        score = round(similarity(self.text(g), self.text(best[1])), 2)
        status = "present" if score >= DESCRIPTION_SAME else "changed"
        out = {"status": status, "run_id": best[0], "similarity": score}
        if status == "changed":
            out["run"] = self.text(best[1])[:300]
        return out

    def evidence_check(self, item: dict, n: dict) -> dict:
        if item.get("wrong_part") != "evidence":
            return {}
        quotes = [" ".join(words(e.get("quote") or e.get("text") or "")) for e in n["evidence"]]
        bad = [
            q for q in item["wrong_quotes"] if any(" ".join(words(q)) in text for text in quotes)
        ]
        return {"wrong_evidence_still_cited": bad}

    def why_missing(self, g: dict) -> dict:
        lost = [x["ref"] for x in galls_in(g) if x["ref"] not in self.gall_map]
        return {"reason": f"Gall not found in the run: {', '.join(lost)}"} if lost else {}

    # -- report

    def report(self) -> dict:
        items = [self.match(item) for item in self.golden["items"]]
        return {
            "golden_format": GOLDEN_FORMAT,
            "source": self.golden["source"],
            "run": str(self.run_dir),
            "golden_package": self.golden["package"],
            "golden_package_format": self.golden.get("package_format"),
            "run_package_format": {
                k: self.envelope.get(k)
                for k in ("format_version", "vocabulary_version", "producer")
            },
            "run_totals": self.run.totals(),
            "golden_package_totals": self.golden.get("package_totals"),
            "mappings": self.mappings,
            "galls": self.gall_report,
            "items": items,
            "summary": summarize(items),
        }


def score(golden_doc: dict, run_dir: Path) -> dict:
    return Scorer(golden_doc, run_dir).report()


def summarize(items: list[dict]) -> dict:
    status_counts: dict[str, int] = {}
    for r in items:
        status_counts[r["status"]] = status_counts.get(r["status"], 0) + 1
    good, regressions, not_fixed, fixed, unsure, unscored = [], [], [], [], [], []
    for r in items:
        if r["status"] == "not scored":
            unscored.append(r)
        elif r["verdict"] == "unsure":
            unsure.append(r)
        elif "wrong_evidence_still_cited" in r:  # wrong citation, right Fact
            (not_fixed if r["wrong_evidence_still_cited"] else fixed).append(r)
            if not r["wrong_evidence_still_cited"]:
                good.append(r)
        elif r["verdict"] == "wrong" and r.get("status") == "present":
            not_fixed.append(r)
        elif r["verdict"] == "wrong":
            # A wrong citation whose Fact is gone lost a right Fact.
            (regressions if r.get("wrong_part") else fixed).append(r)
        elif r["status"] == "present":
            good.append(r)
        else:
            regressions.append(r)
    return {
        "status": status_counts,
        "right_and_present": len(good),
        "regressions": regressions,
        "not_fixed": not_fixed,
        "fixed": fixed,
        "unsure": unsure,
        "not_scored": unscored,
    }


def render(report: dict) -> str:
    s = report["summary"]
    src = report["source"]
    lines = [
        f"Golden set: {src['name']} (Source {src['id']})",
        f"  run: {report['run']}",
        f"  golden package: {report['golden_package']}",
    ]
    for side in ("golden_package_format", "run_package_format"):
        fmt = report.get(side) or {}
        producer = fmt.get("producer") or {}
        lines.append(
            f"  {side.split('_')[0]}: format {fmt.get('format_version')}, vocabulary "
            f"{fmt.get('vocabulary_version')}, {producer.get('model')} {producer.get('instructions_version')}"
        )
    lines.append("")
    total = len(report["items"])
    lines.append(
        f"{total} items: "
        + ", ".join(f"{n} {k}" for k, n in sorted(s["status"].items()))
        + f"; {s['right_and_present']} right and present"
    )
    for note in report["mappings"]:
        lines.append(f"  mapped: {note}")

    gall_notes = [
        g
        for g in report["galls"]
        if g["run"] is None or g.get("identity_changed") or g.get("shared")
    ]
    if gall_notes:
        lines += ["", "Galls"]
        for g in gall_notes:
            head = f"  {g['golden']['ref']} {g['golden']['name_as_written']}"
            if g["run"] is None:
                lines.append(f"{head}: not found in the run")
                continue
            notes = g.get("identity_changed", []) + (
                ["shares a run Gall"] if g.get("shared") else []
            )
            extra = "; ".join(notes)
            lines.append(f"{head} -> {g['run']['ref']} {g['run']['name_as_written']}: {extra}")

    def section(title, rows):
        if not rows:
            return
        lines.extend(["", f"{title} ({len(rows)})"])
        for r in rows:
            detail = r["status"]
            if r["status"] == "changed" and "golden" in r:
                detail += f": {r['golden']} -> {r['run']}"
            elif r["status"] == "changed" and "similarity" in r:
                detail += f": similarity {r['similarity']}"
            if r.get("reason"):
                detail += f" ({r['reason']})"
            if r.get("wrong_evidence_still_cited"):
                detail += f"; still cites {r['wrong_evidence_still_cited']}"
            lines.append(f"  {r['id']:<16} [{r['verdict']}] {r['label']}: {detail}")

    section("Possible regressions: right, now changed or missing", s["regressions"])
    section("Not fixed: wrong, still present", s["not_fixed"])
    section("Fixed: wrong, now gone or changed", s["fixed"])
    section("Unsure: for a person to look at", s["unsure"])
    section("Not scored", s["not_scored"])
    return "\n".join(lines) + "\n"


def find_golden(source_id: int, golden_dir: Path) -> Path:
    found = sorted(golden_dir.glob(f"{source_id}-*.json"))
    if len(found) != 1:
        raise FileNotFoundError(
            f"expected one golden file for Source {source_id} in {golden_dir}, found {len(found)}"
        )
    return found[0]


def infer_source(run_dir: Path) -> int | None:
    m = re.match(r"(\d+)-", run_dir.name)
    if m:
        return int(m.group(1))
    dry = read_json(run_dir / "dryrun.json")
    return dry.get("source_id") if dry else None
