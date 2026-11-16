# Public site, settled

Everything a visitor sees is decided, matches what's decided, and is listed for the release notes before cutover. Every public page already reads the new model (state report `/Users/jeff/dev/gallformers/docs/plans/2026-11-12-history-audit/state/1-public-site.md`); this phase settles how it should behave and closes the gaps.

## Rules

- **Behaviour is written down before it's changed** (Jeff, 2026-11-12, on the ID tool and search: document how it is supposed to work, then make it align).
- **Every change a visitor will notice goes on the release-notes list** (Jeff, 2026-11-12).
- **ID-tool parity with today is a release gate** (plan doc, *Release gates*).
- **Self-curating where it fits:** matches such as iNaturalist taxon ids are proposed by the system and confirmed by a curator.

## Done when

- How the ID tool and search behave is written down, the code matches it, and a fresh comparison with production shows only the expected differences.
- The API is released as v3 (decision 03d0), and v2 returns 410.
- The public data download works on the new tables.
- The known public bugs (Source page, rank pages, Host page, canonical tag) are fixed, and non-plant taxa have public pages.
- Every Gallformers taxon that has an iNaturalist counterpart is linked to it.
- The release-notes list covers every visible change, and Jeff has written the home page wording.

Sources: the 2026-11-12 history audit (state/1-public-site.md, Jeff's marks on the review page); Jeff, 2026-11-12 to 11-15.
