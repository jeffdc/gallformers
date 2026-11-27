# Gallformers Traits to GallOnt Mapping

> **History.** Generated 2026-02-14 from the old `gall_traits` schema, for matter eb47. The Trait values it maps are today's apart from generation (now generation groups); the current values are in [`priv/import/vocab/traits.json`](../../../priv/import/vocab/traits.json). The GallOnt files it was built from were deleted in cleanup step 10; GallOnt is published at purl.obolibrary.org/obo/gallont.owl.

Generated 2026-02-14 from GallOnt v2024-04-19 and current gallformers gall_traits schema.

Sources:
- GallOnt OBO: `gallont.obo` (in this directory)
- GallOnt paper: https://bdj.pensoft.net/article/128585/
- GallOnt browser: https://www.ebi.ac.uk/ols4/ontologies/gallont
- Prior Lab scoring protocols: "Gall phenotype scoring protocols.docx"

## Legend

- **Direct** = same concept, similar granularity
- **Close** = semantically similar, minor differences in scope or definition
- **Partial** = overlapping but one side is broader/narrower
- **GF-specific** = exists only in gallformers
- **GallOnt-specific** = exists only in GallOnt/PATO/Prior Lab protocols

---

## 1. Shape (GF: 13 values)

| GF Value | GallOnt Term | GallOnt ID | Match |
|----------|-------------|------------|-------|
| sphere | spheroid | PATO:0001865 | Direct |
| globular | subspherical | PATO:0005014 | Direct |
| conical | — | — | GF-specific |
| cylindrical | cylindrical | PATO:0001873 | Direct |
| spindle | fusiform / spindle-shaped | PATO:0002400 / PATO:0001409 | Direct |
| cup | cupuliform | GALLONT:0000015 | Direct |
| hemispherical | tholiform (dome-shaped) | PATO:0002335 | Close |
| linear | — | — | GF-specific |
| rosette | rosette gall | GALLONT:0000038 | Close (GallOnt treats as gall type, not shape) |
| spangle/button | discoid | PATO:0001874 | Close |
| cluster | plant gall aggregate | GALLONT:0000049 | Close (GallOnt treats as structural concept) |
| numerous | — | — | GF-specific (quantity, not shape) |
| tuft | — | — | GF-specific |

### GallOnt shapes not in GF

| GallOnt Term | ID | Description |
|-------------|-----|-------------|
| caneliform | GALLONT:0000014 | Resembling a canele (French pastry) |
| echinoform | GALLONT:0000016 | Radiating spine-like processes (sea urchin) |
| infundibuliform | GALLONT:0000017 | Funnel-shaped |
| lenticular | GALLONT:0000018 | Lentil-shaped, biconvex |
| semiterete | GALLONT:0000019 | Semicircular cross-section |
| elliptic | PATO:0000947 | Oval with two axes of symmetry |
| reniform | PATO:0001871 | Kidney-shaped |
| clavate | PATO:0001883 | Club-shaped |
| pear-shaped | PATO:0005002 | Tapering at top, bulging at base |
| tubular | PATO:0002299 | Hollow cylinder |
| lobed | PATO:0001979 | Partly divided into lobes |
| auriculate | PATO:0001981 | Ear-shaped |
| botryoidal | PATO:0001907 | Grape-cluster surface |
| cuneate | PATO:0001955 | Wedge-shaped |
| subelliptical | PATO:0005004 | Almost an ellipse |

---

## 2. Texture (GF: 24 values)

| GF Value | GallOnt Term | GallOnt ID | Match |
|----------|-------------|------------|-------|
| hairy | hairy | PATO:0000454 | Direct (GallOnt splits into subtypes below) |
| woolly | — | — | Implied but no specific PATO term found |
| pubescent | — | — | Standard botanical term, likely in Plant Ontology |
| hairless | unornamented | PATO:0002442 | Partial (unornamented is broader) |
| spiky/thorny | spiny | PATO:0001365 | Direct |
| erineum | erineum | GALLONT:0000048 | Direct (also a gall type in GallOnt) |
| bumpy | knobbled | PATO:0002427 | Close |
| wrinkly | rugose | PATO:0001359 | Direct |
| spotted | mottled | PATO:0002274 | Close (mottled is color pattern in GallOnt) |
| striped | banded / barred | PATO:0001946 / PATO:0002276 | Close (GallOnt distinguishes H vs V) |
| ribbed | corrugated | GALLONT:0000022 | Direct (GallOnt synonym: "ribbed") |
| mottled | mottled | PATO:0002274 | Direct |
| stiff | non-fragile | PATO:0001716 | Partial |
| areola | — | — | GF-specific |
| glaucous | — | — | GF-specific (waxy coating) |
| honeydew | — | — | GF-specific (secretion) |
| leafy | — | — | GF-specific |
| mealy | — | — | GF-specific |
| resinous dots | — | — | GF-specific |
| ruptured/split | — | — | GF-specific (developmental stage marker) |
| succulent | — | — | GF-specific |

### GallOnt textures not in GF

| GallOnt Term | ID | Description |
|-------------|-----|-------------|
| smooth | PATO:0000701 | Surface free of roughness |
| rough | PATO:0000700 | Irregular surface |
| hispid | PATO:0002339 | Covered with stiff/rough hairs |
| hispidulous | PATO:0002340 | Minutely hispid |
| arachnose | PATO:0002344 | Fine entangled hairs, cobweb appearance |
| fimbriated | PATO:0002311 | Fringe of hairlike projections |
| warty | PATO:0001361 | Wart-like projections |
| viscid | PATO:0001370 | Sticky/clammy coating |
| felt-like | GALLONT:0000029 | Short dense fine hairs resembling felt |
| pruinose | GALLONT:0000030 | Whitish powdery film |
| crackled | GALLONT:0000023 | Network of surface cracks |
| dimpled | GALLONT:0000024 | Surface depressions |
| faceted | GALLONT:0000026 | Covered with facets |
| moss-like | GALLONT:0000027 | Appearance/consistency of moss |
| papery | GALLONT:0000028 | Thin and dry like paper |

---

## 3. Walls (GF: 8 values)

| GF Value | GallOnt Term | GallOnt ID | Match |
|----------|-------------|------------|-------|
| thick | solid | GALLONT:0000012 | Close (solid = no macroscopic spaces beyond larval chamber) |
| thin | — | — | No direct match |
| radiating-fibers | filamentous | GALLONT:0000008 | Direct (larval chamber suspended by radiating fibers) |
| spongy | pithy | GALLONT:0000010 | Close (tissue resembles pith) |
| hollow | plant gall cavity | GALLONT:0000003 | Close (structural concept) |
| false chamber | — | — | GF-specific |
| mycelium lining | — | — | GF-specific |
| ostiole | — | — | GF-specific (opening) |
| slit | — | — | GF-specific |

---

## 4. Cells/Chambers (GF: 4 values)

| GF Value | GallOnt Term | GallOnt ID | Match |
|----------|-------------|------------|-------|
| monothalamous | monothalamous | GALLONT:0000009 | **Exact** |
| polythalamous | polythalamous | GALLONT:0000011 | **Exact** |
| free-rolling | roly-poly gall / detached chamber | GALLONT:0000037 / GALLONT:0000006 | Direct |
| not applicable | — | — | GF-specific sentinel value |

---

## 5. Detachable (GF: 4 values)

| GF Value | GallOnt Term | GallOnt ID | Match |
|----------|-------------|------------|-------|
| detachable | deciduous | PATO:0001730 | Direct |
| integral | non-deciduous | PATO:0001732 | Direct |
| both | — | — | GF models variability; GallOnt doesn't |
| unknown | — | — | GF-specific sentinel |

### GallOnt additions

| GallOnt Term | ID | Description |
|-------------|-----|-------------|
| shedability | PATO:0001729 | Parent quality for deciduous/non-deciduous |
| semideciduous | GALLONT:0000031 | Can be detached but normally stays attached |

The Prior Lab protocol also distinguishes semideciduous. This is a value GF lacks.

---

## 6. Plant Parts / Location (GF: 15 values)

| GF Value | GallOnt / Plant Ontology Term | PO ID | Match |
|----------|-------------------------------|-------|-------|
| upper leaf | adaxial leaf epidermis | PO:0006018 | Direct |
| lower leaf | abaxial leaf epidermis | PO:0006019 | Direct |
| leaf midrib | leaf vascular system | PO:0000036 | Close |
| on leaf veins | leaf lamina vascular system | PO:0000048 | Close |
| between leaf veins | leaf lamina | PO:0025060 | Partial |
| at leaf vein angles | — | — | No direct match |
| leaf edge | — | — | No specific PO "margin" term found |
| petiole | petiole lamina / stalk | PO:0025129 / PO:0025066 | Direct |
| bud | vegetative shoot apex | PO:0025223 | Close |
| stem | stem epidermis | PO:0025178 | Direct |
| flower | reproductive shoot system | PO:0025082 | Close |
| fruit | fruit | PO:0009001 | Direct |
| underground (roots+) | root | PO:0009005 | Direct |

### Prior Lab locations not in GF

- twig (= branch, PO:0025073)
- inflorescence
- cambium
- fruit cupule
- fruit cotyledon
- fruit stalk

---

## 7. Alignment (GF: 5 values)

| GF Value | GallOnt Term | Match |
|----------|-------------|-------|
| integral | — | Overlaps with detachable concept |
| erect | — | No GallOnt match |
| drooping | — | No GallOnt match |
| leaning | — | No GallOnt match |
| supine | — | No GallOnt match |

GallOnt does not model alignment/orientation as a category. This is a **GF-unique axis**.

The Prior Lab protocol has **sessile / pedicellate / semi-pedicellate** (PATO:0001436 / PATO:0001438) which describes attachment style, not orientation. This is a distinct concept from GF's alignment.

---

## 8. Colors (GF: 12 values)

| GF Value | GallOnt/PATO Term | PATO ID | Match |
|----------|------------------|---------|-------|
| brown | brown | PATO:0000952 | Direct |
| pink | pink | PATO:0000954 | Direct |
| green | light green | PATO:0001250 | Close |
| yellow | light yellow | PATO:0001264 | Close |
| red | — | — | Standard, in PATO |
| orange | — | — | Standard |
| white | — | — | Standard |
| black | — | — | Standard |
| gray | — | — | Standard |
| purple | — | — | Standard |
| tan | light brown | PATO:0001246 | Close |
| UV | — | — | GF-specific (fluorescence) |

### GallOnt color additions

| GallOnt Term | ID | Description |
|-------------|-----|-------------|
| yellow-green | PATO:0001941 | Compound color |
| yellow-brown | PATO:0002411 | Compound color |
| red-brown | PATO:0001287 | Compound color |
| marbled | PATO:0002273 | Color pattern: variegated like marble |
| linear color gradient | GALLONT:0000021 | Color transitions from one pole to other |

GallOnt also distinguishes color *patterns* (banded, barred, netted, mottled) as separate from base color.

---

## 9. Forms / Gall Types (GF: 25 values)

| GF Value | GallOnt Term | GallOnt ID | Match |
|----------|-------------|------------|-------|
| bullet | bullet gall | GALLONT:0000036 | **Exact** |
| leaf blister | blister gall | GALLONT:0000034 | **Exact** |
| oak apple | — | — | GF-specific |
| rosette | rosette gall | GALLONT:0000038 | **Exact** |
| leaf curl | — | — | GF-specific |
| leaf edge fold | — | — | GF-specific |
| leaf edge roll | — | — | GF-specific |
| leaf snap | — | — | GF-specific |
| leaf spot | — | — | GF-specific |
| pocket | — | — | GF-specific |
| pip | — | — | GF-specific |
| plum | — | — | GF-specific |
| scale | — | — | GF-specific |
| stem club | — | — | GF-specific |
| witches broom | — | — | GF-specific |
| hidden cell | — | — | GF-specific |
| abrupt swelling | — | — | GF-specific |
| tapered swelling | — | — | GF-specific |
| modified capitulum | — | — | GF-specific |
| non-gall | — | — | GF-specific |
| rust | — | — | GF-specific |

### GallOnt gall types not in GF

| GallOnt Term | ID | Description |
|-------------|-----|-------------|
| bud gall | GALLONT:0000035 | Gall located on a bud |
| roly-poly gall | GALLONT:0000037 | Detached chamber rolls inside hollow space |
| erineum | GALLONT:0000048 | Mite-induced increased hairiness on leaf |
| zoocecidium | GALLONT:0000050 | Animal-induced gall (parent type) |
| plant gall aggregate | GALLONT:0000049 | Multiple individual galls in aggregation |

---

## 10. Seasons (GF: 4 values)

| GF Value | GallOnt Match |
|----------|--------------|
| Spring | — |
| Summer | — |
| Fall | — |
| Winter | — |

GallOnt does not model seasonality. The Prior Lab protocol captures **month-level phenology** (start month, peak month, end month) which is significantly more granular than GF's season checkboxes.

---

## Concepts in GallOnt / Prior Lab with No GF Equivalent

| Concept | Source | ID(s) | Description |
|---------|--------|-------|-------------|
| Visibility | Prior Lab + PATO | PATO:0001998 | Conspicuous vs inconspicuous |
| Attachment style | Prior Lab + PATO | PATO:0001436, PATO:0001438 | Sessile / pedicellate / semi-pedicellate |
| Semideciduous | GallOnt + Prior Lab | GALLONT:0000031 | Sometimes detaches, sometimes doesn't |
| Size (quantitative) | Prior Lab | — | Max diameter (mm), height; small/medium/large categories |
| Spatial pattern | Prior Lab + GallOnt | GALLONT:0000020, PATO:0001609, PATO:0001629 | Solitary / clustered / confluent (GF has "cluster" as shape only) |
| Internal larval chamber | Prior Lab + GallOnt | GALLONT:0000005, GALLONT:0000006 | None / free-rolling / suspended |
| Internal gall tissue | Prior Lab + GallOnt | GALLONT:0000007 | Distinct category from walls |
| Nutritive tissue | GallOnt | GALLONT:0000040 | Tissue fed upon by inhabitants |
| Emergence hole | GallOnt | GALLONT:0000002 | Opening from which organism emerged |
| Kapello | GallOnt | GALLONT:0000004 | Ant-attracting dispersal structure |
| Abscission zone | GallOnt | GALLONT:0000051 | Where gall separates from plant |
| Dehiscence zone | GallOnt | GALLONT:0000053 | Rupture site in gall |
| Nectarous | GallOnt | GALLONT:0000013 | Gall has nectaries |
| Fragility | GallOnt + PATO | GALLONT:0000032, PATO:0001662 | Brittle / fragile / non-fragile |
| Opacity | PATO | PATO:0000957 | Opaque / translucent |

---

## Summary

### Well-aligned categories
- **Cells/chambers**: Near-perfect alignment (monothalamous, polythalamous, free-rolling)
- **Detachable**: Good alignment with GallOnt adding semideciduous
- **Plant parts**: Good coverage with Plant Ontology terms

### Partially aligned categories
- **Shape**: ~5 direct matches out of 13 GF values; GallOnt has ~15 shapes GF lacks
- **Texture**: ~7 matches out of 24 GF values; GallOnt has ~15 textures GF lacks
- **Colors**: Basic colors align; GallOnt adds compound colors and color patterns
- **Forms**: 3 exact matches; most GF forms are practical field terms without ontology equivalents

### GF-unique categories
- **Alignment** (orientation on plant): Not modeled in GallOnt at all
- **Seasons**: GallOnt doesn't model phenology (Prior Lab uses month-level granularity)

### Major GallOnt concepts GF lacks entirely
- Attachment style (sessile/pedicellate)
- Spatial pattern as a distinct axis (solitary/clustered/confluent)
- Quantitative size measurements
- Internal structure as a separate category from walls
- Structural properties (fragility, opacity)
- Specialized structures (emergence hole, kapello, abscission/dehiscence zones, nectaries)
