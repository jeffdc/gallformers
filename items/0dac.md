---
plan: taxogall
phase: d51b
title: Map each of the 224 lost old Gall aliases to a synonym, former label or common name
stage: committed
docs:
  - .mull/matters/b5bd-taxonomy-migration.md
created: "2026-11-09T20:38:18Z"
updated: "2026-11-12T02:23:22Z"
---

**What Jeff wants (2026-11-05).** The Gall page's "Also known as" must include **all** of a Gall's old names, old common names included. Today some old aliases don't reach the new model, so this item is a migration check: map each old Gall alias to a synonym, a former label or a common name, so that every old name shows on the Gall page.

**How the gap was found** (design-system work, 2026-11-05). Production's Gall page lists the Gall's own aliases (old `alias` / `alias_species`: 2,196 "scientific" aliases on Galls, 283 common). The new Gall page reads the Inducer's synonyms (`taxon_names` whose status is not `accepted`) plus the Gall's current former labels and codes (`alias_facts` of kind `former_label` or `code`). Comparing names exactly, **224 of the 2,196 old scientific aliases appear nowhere in the new model: 209 on described Galls, 15 on undescribed ones.** The 283 old common names all arrive (as `alias_facts` of kind `common_name`; rechecked 2026-11-11 on `gallformers_taxogall`: 0 missing).

The matter's own reading of the 224:
- Some are formatting: a generation qualifier dropped or added ("Callirhytis furva (agamic)", "Andricus lustrans" without "(agamic)"). The migration stores synonyms without a trailing generation tag or author citation (`aliases.csv` rule), so an exact comparison misses them.
- Some look really lost: misapplied names with an authority ("Callaspidia confluens Fitch, non Harris" on 582), and common names filed as scientific ("Blue Gum Chalcid Wasp" on 607).

**The query** (reproduced 2026-11-11 on `gallformers_taxogall`; it returns exactly 224 rows, 209 described and 15 undescribed). It runs on a converted copy that still has the old tables:

```sql
with old as (
  select a.id alias_id, a.name, s.id gall_id, g.undescribed
  from alias a join alias_species ast on ast.alias_id = a.id
  join species s on s.id = ast.species_id and s.taxoncode = 'gall'
  join gall_index g on g.gall_id = s.id
  where a.type = 'scientific'
)
select o.gall_id, o.undescribed, o.alias_id, o.name
from old o
where not exists (select 1 from gall_index gi join taxon_names tn on tn.taxon_id = gi.inducer_taxon_id
                  where gi.gall_id = o.gall_id and tn.name = o.name and tn.status <> 'accepted')
  and not exists (select 1 from alias_facts af
                  where af.gall_id = o.gall_id and af.name = o.name and af.kind in ('former_label', 'code'))
order by o.gall_id, o.name;
```

**What the 224 are, by their `aliases.csv` decision** (the two right-hand columns below were worked out on 2026-11-11 from `priv/catalog_migration/aliases.csv`, matching on `owner_id` + `alias_id`, and from the Gall's Inducer names; check them before acting on them):
- **116 were decided `synonym`** (rule 1: synonym of the species-level Inducer; Jeff 2026-10-26):
  - 82 are in the model as a synonym without their trailing generation tag. They are formatting only, unless the page should show the tagged form;
  - 3 equal the Inducer's accepted name;
  - **31 appear nowhere.** These are mostly names with an author citation or a qualifier ("Rhodites radicum Riley", "Cynips mellea var E Kinsey", "Callaspidia confluens Fitch, non Harris"), common names filed as scientific ("Blue Gum Chalcid Wasp", "Sunburst Gall Wasp", "Striped Volcano Gall Wasp (unisexual generation)"), and a few with stray whitespace in the old row.
- **108 were decided `drop`** (rule 2, Jeff 2026-10-26):
  - 80 "identical to the gall name", which includes old host-code forms such as "Eriophyes cerasicrumena (on-p-serotina)" and "(q-bicolor)";
  - 27 blank aliases;
  - 1 not a name ("refdfd" on 1117).

  Jeff's 2026-11-05 "all the synonyms" came after these drop decisions, so whether the rule-2 drops that are real names (the 80) should now show is for Jeff. Blank rows and "refdfd" have nothing to show.

**What to do.**
1. For each of the 224, choose its meaning: `synonym` (with `target` if it belongs to another taxon), `common_name`, `former_label`, `code` or `drop`. The vocabulary and the rules for each are in `Gallformers.CatalogMigration.Aliases` (moduledoc). A former label or code is never a taxon name, because a name in taxon synonymy feeds import name resolution and causes silent wrong matches (`b5bd` M2: "sort by meaning, not by field").
   - A common name filed as scientific is a `common_name`.
   - A misapplied name with "non Harris" is not a plain synonym of the Inducer. Settle with Jeff whether it is dropped, or kept with the authority it needs. Synonyms are stored without author citations, and names are unique per taxon only.
2. Record each decision as a row in `priv/catalog_migration/aliases.csv` (`owner, owner_id, alias_id, name, type, decision, target, note`). The note says who decided and when, as the existing rows do. This is the only route to the cutover: only the curated files and preview's replay log reach production (`b5bd`, "Plants kept twice"). A fix made by hand on a local database does not carry.
3. Where a decided synonym is lost by normalisation (author dropped, whitespace), say whether the Gall page should show the name as written. If it should, the fix is in how the migration stores the name, not in `aliases.csv`. Ask Jeff before changing the normalisation rule.
4. Add a test case for each new kind of decision as old-style seed rows (`priv/repo/test_seeds.sql`), with the curated decision in `test/support/fixtures/catalog_migration/aliases.csv` (per CLAUDE.md), test first.

**Done when** the query above, re-run after a strict catalog migration (`MIX_ENV=dev PGDATABASE=<copy> mix gallformers.catalog.migrate --no-s3`, nothing pending), returns only aliases Jeff has agreed to drop, plus any he has agreed may show only in a normalised form. Every other old Gall alias then shows on the Gall page as a synonym, former label or common name.

**The 224** (`gallformers_taxogall`, 2026-11-11; Gall IDs are the old species IDs, which Galls keep):

| Gall | Gall's displayed name | alias | old alias | aliases.csv | in the new model |
|---|---|---|---|---|---|
| 582 | Amphibolips quercusinanis (sexgen) | 7675 | Callaspidia confluens Fitch, non Harris | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 582 | Amphibolips quercusinanis (sexgen) | 7676 | Callaspidia confluenta Fitch, non Harris | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 607 | Leptocybe invasa | 9602 | Blue Gum Chalcid Wasp | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 607 | Leptocybe invasa | 9603 | Bluegum Chalcid Wasp | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 860 | Trigonaspis polita (agamic) | 11210 | Diplolepis polita (Bassett) | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 899 | Atrusca unica (agamic) | 7705 | Cynips mellea var E Kinsey | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1024 | Diastrophus turgidus | 10542 | Rhodites radicum Riley | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1025 | Diastrophus radicum | 10543 | Rhodites radicum Gillette | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1033 | Feron stellare (agamic) | 11161 | Sunburst Gall Wasp | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1111 | Neuroterus bussae (sexgen) | 6793 | Neuroterus niger (alimas) | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1259 | Phylloteras campanulatum (agamic) | 12793 | Euxystotera campanulatum Lyon | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1317 | Neuroterus quercusbatatus (sexgen) | 6644 | Neuroterus batatus var batatus form bisexualis *(stray whitespace in the old row)* | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1339 | Neuroterus quercusbatatus (sexgen) (on Quercus bicolor) | 6656 | Neuroterus noxiosus *(stray whitespace in the old row)* | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1370 | Feron atrimentum (agamic) | 11113 | Striped Volcano Gall Wasp (unisexual generation) | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1396 | Diplolepis radicum | 10548 | Rhodites radicum Osten Sacken | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1425 | Antistrophus bicolor | 10505 | Aulax bicolor Kieffer | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1431 | Aulacidea harringtoni | 10526 | Aulax bicolor Gillette | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 1607 | Antron douglasii (agamic) | 9388 | Antron douglasii *(stray whitespace in the old row)* | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 2121 | Atrusca brevipennata (agamic) | 11848 | Cynips dugesi var A | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3392 | Atrusca dugesi (agamic) | 11741 | Cynips dugesi (dugesi) | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3393 | Atrusca pupoides (agamic) | 11783 | Cynips dugesi (pupoides) | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3396 | Cynips mellea (rydbergiana) (agamic) | 10562 | Cynips mellea var D Kinsey | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3911 | Atrusca spiculi (agamic) | 11801 | Cynips spiculi | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3912 | Atrusca spinalis (agamic) | 11803 | Cynips spinalis | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3913 | Atrusca spinescens (agamic) | 11805 | Cynips spinescens | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3914 | Atrusca spinifera (agamic) | 11807 | Cynips spinifera | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3915 | Atrusca subnigra (agamic) | 11812 | Cynips (dugesi) subnigra | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3916 | Atrusca vasta (agamic) | 11821 | Cynips vasta | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3916 | Atrusca vasta (agamic) | 11824 | Cynips vulgata | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 3927 | Atrusca tigrina (agamic) | 11814 | Cynips (aggregata) tigrina | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 5320 | Callirhytis patiens (agamic) | 11186 | Andricus patiens Bassett | synonym (rule 1: synonym of the species-level Inducer) | nowhere |
| 562 | Dryocosmus quercusnotha (agamic) | 12484 | Callirhytis furva (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 569 | Feron apiarium (agamic) | 10959 | Andricus apiarium (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 572 | Druon pattoni (agamic) | 12031 | Andricus pattoni (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 575 | Andricus lustrans (agamic) | 12020 | Callirhytis vaccinii (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 744 | Andricus balanaspis (agamic) | 8697 | Callirhytis balanaspis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 827 | Feron discale (agamic) | 11061 | Andricus discalis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 831 | Xanthoteras radicola (sexgen) | 12542 | Trigonaspis radicola (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 836 | Callirhytis quercusfutilis (agamic) | 5007 | Callirhytis futilis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 844 | Feron clarkei (sexgen) | 11124 | Andricus clarkei (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 862 | Sphaeroteras carolina (agamic) | 11058 | Atrusca carolina (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 869 | Feron comatum (sexgen) | 11134 | Andricus comata (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 869 | Feron comatum (sexgen) | 11132 | Feron comata (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 895 | Druon quercuslanigerum (agamic) | 10695 | Andricus quercuslanigera (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 956 | Sphaeroteras pulchripennis (agamic) | 10588 | Sphaerotheras pulchripennis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 956 | Sphaeroteras pulchripennis (agamic) | 10580 | Trigonaspis pulchripennis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 965 | Striatoandricus aciculatus (agamic) | 9127 | Andricus aciculatus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 981 | Bassettia flavipes (sexgen) | 8728 | Callirhytis flavipes (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1033 | Feron stellare (agamic) | 11160 | Andricus stellaris (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1093 | Dryocosmus quercuspalustris (agamic) | 12485 | Zopheroteras guttatum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1129 | Callirhytis quercusfutilis (sexgen) | 5363 | Callirhytis futilis (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1180 | Melikaiella congregata (sexgen) | 12477 | Callirhytis congregata (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1313 | Amphibolips quercuspomiformis (agamic) | 7645 | Callirhytis quercuspomiformis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1365 | Besbicus conspicuus (agamic) | 12782 | Cynips conspicuus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1368 | Besbicus heldae (agamic) | 12783 | Cynips heldae (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1369 | Feron albicomus (agamic) | 11553 | Andricus albicomus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1370 | Feron atrimentum (agamic) | 11112 | Andricus atrimentus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1371 | Feron atrimentum (sexgen) | 11114 | Andricus atrimentus (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1372 | Feron bakkeri (agamic) | 11117 | Andricus bakkeri (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1377 | Feron crystallinum (agamic) | 11135 | Andricus crystallinus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1378 | Feron crystallinum (sexgen) | 11137 | Andricus crystallinus (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1379 | Feron discularis (agamic) | 11911 | Andricus discularis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1486 | Feron gigas (agamic) | 11144 | Andricus gigas (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1487 | Feron gigas (sexgen) | 11142 | Andricus gigas (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1511 | Feron kingi (agamic) | 11147 | Andricus kingi (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1516 | Feron parmula (agamic) | 11642 | Andricus parmula (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1557 | Feron pattersonae (agamic) | 11551 | Andricus pattersonae (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1558 | Feron dumosae (sexgen) | 11180 | Andricus pattersonae (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1559 | Feron pattersonae (sexgen) | 11107 | Andricus pedicellatum (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1559 | Feron pattersonae (sexgen) | 11106 | Andricus pedicellatus (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1560 | Feron stellulum (agamic) | 11646 | Andricus stellulus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1601 | Atrusca trimaculosa (agamic) | 9471 | Sphaeroteras trimaculosum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1607 | Antron douglasii (agamic) | 9386 | Cynips douglasii (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1615 | Besbicus multipunctatus (agamic) | 12791 | Cynips multipunctata (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1724 | Antron quercusechinus (agamic) | 10035 | Cynips quercusechinus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1725 | Antron quercusechinus (sexgen) | 12788 | Cynips quercusechinus (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1727 | Feron scutellum (agamic) | 11157 | Andricus scutella (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1729 | Feron tubifaciens (agamic) | 11172 | Andricus tubifaciens (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1732 | Chrysolepicynips castanopsidis (agamic) | 12480 | Dryocosmus castanopsidis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1733 | Feron amphorus (agamic) | 10965 | Andricus amphorus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1821 | Besbicus maculosus (agamic) | 12784 | Cynips maculosus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1855 | Besbicus mirabilis (agamic) | 12789 | Cynips mirabilis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1902 | Neuroterus asymmetricus (agamic) | 12478 | Dryocosmus asymmetricus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 1906 | Heteroecus sanctaeclarae (agamic) | 12257 | Heteroecus sanctae-clarae (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2128 | Neuroterus quercicola (pacificus) (agamic) | 5619 | Neuroterus quercicola pacificus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2129 | Plagiotrochus amenti (agamic) | 10928 | Plagiotrochus suberi (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2134 | Neuroterus varians (agamic) | 11462 | Neuroterus quercicola var. pacificus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2143 | Antron douglasii (sexgen) | 6770 | Cynips douglasii (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2441 | Feron sulfureum (agamic) | 11164 | Andricus sulfureus (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2445 | Feron tecturnarum (agamic) | 10979 | Andricus tecturnarum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2500 | Striatoandricus barriosi (agamic) | 10204 | Andricus barriosi (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2538 | Feron splendens (agamic) | 11158 | Andricus splendens (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2539 | Feron caepula (agamic) | 10968 | Andricus caepula (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2697 | Chrysolepicynips juliae (sexgen) | 12481 | Dryocosmus juliae (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 2808 | Feron californicum (agamic) | 12237 | Andricus californicum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3224 | Chrysolepicynips demartinii (agamic) | 12483 | Dryocosmus demartinii (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3225 | Chrysolepicynips juliae (agamic) | 12776 | Dryocosmus juliae (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3226 | Chrysolepicynips rileypokei (sexgen) | 12777 | Dryocosmus rileypokei (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3227 | Chrysolepicynips rileypokei (agamic) | 12482 | Dryocosmus rileypokei (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3588 | Druon quercuslanigerum (sexgen) | 8467 | Andricus quercuslanigera (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3760 | Atrusca rubella (agamic) | 7792 | Cynips rubella (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3761 | Sphaeroteras sagata (agamic) | 11833 | Cynips sagata (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3793 | Disholcaspis mexicana (agamic) | 7805 | Andricus tamaulipensis (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3812 | Feron tibiale (agamic) | 11170 | Feron tostum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3812 | Feron tibiale (agamic) | 11171 | Feron uterinum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3818 | Feron vitreum (agamic) | 11174 | Feron validum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3819 | Feron cylindratum (agamic) | 11139 | Xystoteras cylindratum (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3835 | Trigonaspis innocens (agamic) | 7816 | Biorhiza innocens (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3836 | Trigonaspis nitellina (agamic) | 7818 | Biorhiza nitellina (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3860 | Striatoandricus georgei (agamic) | 10856 | Andricus georgei (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 3861 | Striatoandricus maesi (agamic) | 10183 | Andricus maesi (agamic) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 4291 | Besbicus mirabilis (sexgen) | 12790 | Cynips mirabilis (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 4845 | Feron kingi (sexgen) | 11182 | Andricus kingi (sexgen) | synonym (rule 1: synonym of the species-level Inducer) | as a synonym without its generation tag |
| 768 | Neuroterus quercusverrucarum (agamic) | 8761 | Neuroterus quercusverrucarum | synonym (rule 1: synonym of the species-level Inducer) | as the Inducer's accepted name |
| 810 | Belonocnema treatae (agamic) | 9146 | Belonocnema treatae | synonym (rule 1: synonym of the species-level Inducer) | as the Inducer's accepted name |
| 871 | Neuroterus perminimus (agamic) | 5463 | Neuroterus perminimus | synonym (rule 1: synonym of the species-level Inducer) | as the Inducer's accepted name |
| 633 | Eriophyes cerasicrumena (on Prunus serotina) | 12259 | Eriophyes cerasicrumena (on-p-serotina) | drop (rule 2: identical to the gall name) | nowhere |
| 870 | Neuroterus niger (agamic) | 10373 | Neuroterus niger (niger) | drop (rule 2: identical to the gall name) | nowhere |
| 1005 | Hamamelistes spinosus (on Hamamelis) (undescribed) | 12254 | Hamamelistes spinosus (on-hamamelis) | drop (rule 2: identical to the gall name) | nowhere |
| 1109 | Neuroterus saltatorius (texanus) (agamic) | 7022 | Neuroterus saltatorius (texanus) | drop (rule 2: identical to the gall name) | nowhere |
| 1117 | Aceria trinema | 5988 | refdfd | drop (rule 2: not a name (stray text)) | nowhere |
| 1339 | Neuroterus quercusbatatus (sexgen) (on Quercus bicolor) | 12256 | Neuroterus quercusbatatus (sexgen) (q-bicolor) | drop (rule 2: identical to the gall name) | nowhere |
| 1421 | Antistrophus rufus | 10485 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 1468 | Diplolepis lens | 3788 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 1996 | Neuroterus quercicola (pacificus) (sexgen) (on Quercus lobata) | 12262 | Neuroterus quercicola (pacificus) (sexgen) (q-lobata) | drop (rule 2: identical to the gall name) | nowhere |
| 2120 | Neuroterus q-macrocarpa-fuzzy-flower-gall (sexgen) (undescribed) | 9730 | Neuroterus q-macrocarpa-fuzzy-flower-gall | drop (rule 2: identical to the gall name) | nowhere |
| 2255 | Hamamelistes spinosus (on Betula) | 12255 | Hamamelistes spinosus (on-betula) | drop (rule 2: identical to the gall name) | nowhere |
| 2280 | Contarinia rudbeckiae | 3000 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 2456 | Feron q-arizonica-prolonged-vein (sexgen) (undescribed) | 11669 | Feron q-arizonica-prolonged-vein | drop (rule 2: identical to the gall name) | nowhere |
| 2573 | Xanthoteras emoryi (agamic) | 9004 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 2688 | Eriosoma lanigerum (on Malus) | 12260 | Eriosoma lanigerum (on-malus) | drop (rule 2: identical to the gall name) | nowhere |
| 3138 | Macrodiplosis lobe-fold-mine (undescribed) | 8312 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 3167 | Neuroterus quercicola (pacificus) (sexgen) (on Quercus douglasii) | 12261 | Neuroterus quercicola (pacificus) (sexgen) (q-douglasii) | drop (rule 2: identical to the gall name) | nowhere |
| 3200 | Phylloteras q-alba-red-margin-spangle (agamic) (undescribed) | 10653 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 3248 | Eriophyes cerasicrumena (on Prunus americana) | 12268 | Eriophyes cerasicrumena (on-p-americana) | drop (rule 2: identical to the gall name) | nowhere |
| 3452 | Pemphigus nortonii | 8207 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 3863 | Harmandiola castaneae | 7956 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 3979 | Hormaphis cornu (on Hamamelis) | 12264 | Hormaphis cornu (on-hamamelis) | drop (rule 2: identical to the gall name) | nowhere |
| 3981 | Hormaphis cornu (on Betula) | 12263 | Hormaphis cornu (on-betula) | drop (rule 2: identical to the gall name) | nowhere |
| 4002 | Lasioptera psedrae | 8100 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4015 | Neolasioptera v-hastata-stem-swelling (undescribed) | 8116 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4044 | Asphondylia c-annuum-bud-flower-fruit-gall (undescribed) | 8210 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4089 | Eriosoma lanigerum (on Ulmus) | 12265 | Eriosoma lanigerum (on-ulmus) | drop (rule 2: identical to the gall name) | nowhere |
| 4092 | Prociphilus caryae (on Amelanchier) | 12266 | Prociphilus caryae (on-amelanchier) | drop (rule 2: identical to the gall name) | nowhere |
| 4400 | Exobasidium arctostaphyli | 9096 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4406 | Klambothrips myopori | 9108 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4713 | Aceria baccharices | 10261 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4771 | Hayhurstia atriplicis | 10102 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4806 | Asphondylia c-jepsonii-round-bud-gall (undescribed) | 11881 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 4960 | Scirtothrips coccolobae | 10759 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5057 | Exobasidium dimorphosporum | 10831 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5065 | Exobasidium sydowianum | 11424 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5068 | Exobasidium r-menziesii-galls-from-taxon-split (undescribed) | 10838 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5079 | Aceria neobeevori | 10862 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5398 | Exobasidium florifolium-nom-prov (undescribed) | 11377 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5423 | Taphrina p-fremontii-leaf-blister (undescribed) | 11405 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5673 | Asphondylia s-mellifera-leaf-snap-gall (undescribed) | 11684 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5673 | Asphondylia s-mellifera-leaf-snap-gall (undescribed) | 11683 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5726 | Unknown (Unknown) c-scandens-leaf-wrinkle (undescribed) | 12225 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 5726 | Unknown (Unknown) c-scandens-leaf-wrinkle (undescribed) | 12226 | *(blank)* | drop (rule 2: blank alias) | nowhere |
| 581 | Amphibolips confluenta | 11648 | Amphibolips confluenta (agamic) | drop (rule 2: identical to the gall name) | as a synonym without its generation tag |
| 902 | Callirhytis floridana | 12696 | Callirhytis floridana (agamic) | drop (rule 2: identical to the gall name) | as a synonym without its generation tag |
| 1368 | Besbicus heldae (agamic) | 7043 | Besbicus heldae (agamic) | drop (rule 2: identical to the gall name) | as a synonym without its generation tag |
| 3793 | Disholcaspis mexicana (agamic) | 7806 | Disholcaspis mexicana (agamic) | drop (rule 2: identical to the gall name) | as a synonym without its generation tag |
| 575 | Andricus lustrans (agamic) | 12024 | Andricus lustrans | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 595 | Callirhytis quercuspunctata (agamic) | 8341 | Callirhytis quercuspunctata | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 633 | Eriophyes cerasicrumena (on Prunus serotina) | 5492 | Eriophyes cerasicrumena | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 696 | Eriophyes sorbi | 170 | Eriophyes sorbi | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 710 | Belonocnema kinseyi (agamic) | 9145 | Belonocnema kinseyi | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 762 | Neuroterus christi (sexgen) | 9981 | Neuroterus christi | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 765 | Neuroterus quercusirregularis (sexgen) | 7730 | Neuroterus quercusirregularis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 767 | Neuroterus quercusminutissimus (agamic) | 9996 | Neuroterus quercusminutissimus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 778 | Gymnosporangium juniperi-virginianae (telial) | 12631 | Gymnosporangium juniperi-virginianae | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 811 | Loxaulus pattersoni (agamic) | 7011 | Loxaulus pattersoni | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 812 | Andricus quercusfoliatus (agamic) | 9369 | Andricus quercusfoliatus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 813 | Callirhytis quercusbatatoides (agamic) | 9364 | Callirhytis quercusbatatoides | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 814 | Disholcaspis cinerosa (agamic) | 11275 | Disholcaspis cinerosa | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 815 | Disholcaspis fungiformis (agamic) | 7025 | Disholcaspis fungiformis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 816 | Disholcaspis quercusvirens (agamic) | 11298 | Disholcaspis quercusvirens | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 823 | Callirhytis quercusclavigera (agamic) | 3004 | Callirhytis quercusclavigera | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 824 | Antron quercusnubila (agamic) | 8713 | Antron quercusnubila | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 831 | Xanthoteras radicola (sexgen) | 9382 | Xanthoteras radicola | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 847 | Andricus clavula | 6402 | Andricus clavula | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 850 | Disholcaspis quercusglobulus (agamic) | 12147 | Disholcaspis quercusglobulus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 866 | Neuroterus umbilicatus (agamic) | 8871 | Neuroterus umbilicatus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 870 | Neuroterus niger (agamic) | 10374 | Neuroterus niger | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 888 | Loxaulus maculipennis (agamic) | 12232 | Loxaulus maculipennis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 896 | Bassettia pallida (agamic) | 8733 | Bassettia pallida | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 897 | Odontocynips nebulosa (agamic) | 7021 | Odontocynips nebulosa | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 956 | Sphaeroteras pulchripennis (agamic) | 10583 | Sphaeroteras pulchripennis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 962 | Callirhytis turnerii (sexgen) | 12528 | Callirhytis turnerii | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 972 | Disholcaspis pattersoni (agamic) | 5633 | Disholcaspis pattersoni | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1097 | Amphibolips globus (agamic) | 869 | Amphibolips globus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1107 | Loxaulus virginianae (agamic) | 11394 | Loxaulus virginianae | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1169 | Dryocosmus archboldi (sexgen) | 6777 | Dryocosmus archboldi | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1313 | Amphibolips quercuspomiformis (agamic) | 7642 | Amphibolips quercuspomiformis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1314 | Amphibolips quercuspomiformis (sexgen) | 10711 | Amphibolips quercuspomiformis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1317 | Neuroterus quercusbatatus (sexgen) | 6646 | Neuroterus quercusbatatus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1433 | Antistrophus pisum | 10402 | Antistrophus pisum | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1601 | Atrusca trimaculosa (agamic) | 9474 | Atrusca trimaculosa | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1723 | Neuroterus washingtonensis (sexgen) | 5314 | Neuroterus washingtonensis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1724 | Antron quercusechinus (agamic) | 10033 | Antron quercusechinus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1725 | Antron quercusechinus (sexgen) | 10038 | Antron quercusechinus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1879 | Asphondylia diervillae | 4150 | Asphondylia diervillae | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 1906 | Heteroecus sanctaeclarae (agamic) | 10338 | Heteroecus sanctaeclarae | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2092 | Andricus rotundula (agamic) | 7093 | Andricus rotundula | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2096 | Protobalandricus spectabilis (agamic) | 10595 | Protobalandricus spectabilis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2099 | Heteroecus devorus (sexgen) | 7388 | Heteroecus devorus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2102 | Paracraspis insolens (agamic) | 9130 | Paracraspis insolens | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2103 | Paracraspis patelloides (agamic) | 7446 | Paracraspis patelloides | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2249 | Dros sessile (agamic) | 10352 | Dros sessile | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2428 | Neuroterus alexandrae (sexgen) | 7385 | Neuroterus alexandrae | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2474 | Dros viscidum (agamic) | 10349 | Dros viscidum | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2481 | Antron acraspiformis (agamic) | 9136 | Antron acraspiformis | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2638 | Melikaiella cameroni (sexgen) | 12798 | Melikaiella cameroni | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2700 | Cecidomyia lappa | 11888 | Cecidomyia lappa | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2732 | Tetraneura akinire | 10757 | Tetraneura akinire | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2765 | Trisetacus juniperinus | 4113 | Trisetacus juniperinus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 2884 | Phylloxera globosa | 4614 | Phylloxera globosa | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 3136 | Antron tomkursari (agamic) | 6768 | Antron tomkursari | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 3219 | Heteroecus crescentus (sexgen) | 7389 | Heteroecus crescentus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 3823 | Andricus opertus (agamic) | 10554 | Andricus opertus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 4276 | Neuroterus floccosus (agamic) | 8757 | Neuroterus floccosus | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |
| 5462 | Heterotrioza chenopodii | 11958 | Heterotrioza chenopodii | drop (rule 2: identical to the gall name) | as the Inducer's accepted name |

From matter b5bd, 'Gall synonyms in the new model': Jeff (2026-11-05) wants every old alias in 'Also known as'. A migration check. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
