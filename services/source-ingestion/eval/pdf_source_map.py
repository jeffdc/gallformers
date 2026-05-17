"""PDF filename → DB source_id mapping for the eval set.

Manually curated by matching the user's test_sources directory against
the gallformers source table. Excludes Weld 1959 (id 14) per user
direction: already fully ingested, idiosyncratic curator-annotation
format, not representative of future ingestion workload.

Also excludes 4 sources confirmed broken during eval-set construction
(see EXCLUDED below for reasons).
"""

from pathlib import Path

PDF_DIR = Path.home() / "Desktop" / "test_sources"

# (pdf_filename, source_id, label)
PDF_SOURCE_MAP: list[tuple[str, int, str]] = [
    ("Nicholls et al 2022 - Pairing of sexual and asexual generations of Nearctic oak gallwasps, with new synonyms and new species names.pdf", 559, "Nicholls 2022 — Pairing"),
    ("Cuesta-Porta et al 2023 - Re-establishment of the Nearctic oak cynipid gall wasp genus Feron , including the description of six new species.pdf", 755, "Cuesta-Porta 2023 — Feron"),
    ("Cuesta-Porta_2022_Druon.pdf", 554, "Cuesta-Porta 2022 — Druon"),
    ("Nastasi & Davis Field Guide to the Herb and Bramble Gall Wasps of North America.pdf", 680, "Nastasi & Davis 2022 — Field Guide"),
    ("1997_Melika_Abe_Proc_Entomol_Soc_Wash_Neurotus.pdf", 78, "Melika & Abrahamson 1997 — Neuroterus"),
    ("2002_Melika_Abrahamsn_Book_Chapter_Cynipid_World_Review.pdf", 34, "Melika & Abrahamson 2002 — Chapter"),
    ("Callirhytis cameroni- A New Species of Oak Gall Wasp (Hymenoptera- Cynipidae- Cynipini) in Panama medianero2014.pdf", 305, "Medianero 2014 — Callirhytis cameroni"),
    ("Gagne_2017_World_Cat_4th_ed.pdf", 66, "Gagne 2017 — World Catalogue"),
    ("Galls of USNM - Ashmead.pdf", 98, "Ashmead 1896 — USNM"),
    ("Herbivores of Solanum carolinese in Northern Virginia - wise2007.pdf", 184, "Wise 2007 — Solanum"),
    ("Plant Galls and Gallmakers - Felt.pdf", 200, "Felt 1940 — Plant Galls and Gall Makers"),
    ("The_Gall_Wasp_Genus_Cynips - Kinsey.pdf", 50, "Kinsey 1929 — Gall Wasp Genus Cynips"),
    ("felt galls newyorkstatemuse2001917newy.pdf", 7, "Felt 1917 — Key to American Insect Galls"),
    ("gagne hackberry galls.pdf", 122, "Gagne & Moser 2013 — Hackberries"),
    ("gall midges of hickories.pdf", 123, "Gagne 2008 — Hickories"),
    ("weld - notes on cynipid galls 1922.pdf", 75, "Weld 1922 — Notes on Cynipid Galls"),
    ("weld - notes on gall-inhabiting cynipid wasps.pdf", 9, "Weld 1926 — Field notes"),
    ("weld-gallflies producing subterranean galls on oak.pdf", 45, "Weld 1921 — Subterranean Gallflies"),
    ("weld-new american cynipid galls 1944.pdf", 93, "Weld 1944 — New American"),
    ("2000_Melika_Abe_Proc_Entomol_Soc_Wash_Loxaulus.pdf", 103, "Melika & Abrahamson 2000 — Loxaulus"),
    ("A Study of Acraspi erincei - 1914 - Triggerson.pdf", 117, "Triggerson 1914 — Acraspis erincei"),
]

# Excluded mappings (kept here so we don't accidentally re-add them).
#
# - source 292 (Nicholls 2018 Palaearctic Cerris): filename heuristic
#   matched a Melika 2010 PDF that is a different paper not in the DB.
#   Source 292's actual PDF is not in test_sources.
# - source 589 (Wang 2014 Andricus China): DB description for this row
#   talks about Exobasidium japonicum (a fungus on azaleas), not the
#   Andricus oak gallwasp the PDF describes. Curator data-quality issue.
