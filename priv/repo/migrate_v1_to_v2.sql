-- ============================================================================
-- Gallformers V1 to V2 Schema Migration (Complete)
-- ============================================================================
-- This script migrates a clean V1 database all the way to the final V2 schema.
-- It includes:
--   1. All existing V1→V2 changes from main branch
--   2. All new restructuring to match structure_target.sql
--
-- IMPORTANT: Run this against a COPY of your database first!
--
-- Usage:
--   sqlite3 database.sqlite < migrate_v1_to_v2.sql
-- ============================================================================

BEGIN TRANSACTION;
PRAGMA foreign_keys = ON;

-- ============================================================================
-- PART 1: Existing V2 Changes (from main branch migrations)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Add timestamp columns to core tables
-- ---------------------------------------------------------------------------
ALTER TABLE species ADD COLUMN inserted_at TEXT;
ALTER TABLE species ADD COLUMN updated_at TEXT;
UPDATE species SET inserted_at = datetime('now'), updated_at = datetime('now');

ALTER TABLE taxonomy ADD COLUMN inserted_at TEXT;
ALTER TABLE taxonomy ADD COLUMN updated_at TEXT;
UPDATE taxonomy SET inserted_at = datetime('now'), updated_at = datetime('now');

ALTER TABLE source ADD COLUMN inserted_at TEXT;
ALTER TABLE source ADD COLUMN updated_at TEXT;
UPDATE source SET inserted_at = datetime('now'), updated_at = datetime('now');

ALTER TABLE host ADD COLUMN inserted_at TEXT;
ALTER TABLE host ADD COLUMN updated_at TEXT;
UPDATE host SET inserted_at = datetime('now'), updated_at = datetime('now');

ALTER TABLE alias ADD COLUMN inserted_at TEXT;
ALTER TABLE alias ADD COLUMN updated_at TEXT;
UPDATE alias SET inserted_at = datetime('now'), updated_at = datetime('now');

-- ---------------------------------------------------------------------------
-- Create species_fts (full-text search)
-- ---------------------------------------------------------------------------
CREATE VIRTUAL TABLE species_fts USING fts5(
  species_id UNINDEXED,
  name,
  aliases,
  tokenize='porter unicode61',
  prefix='2 3'
);

INSERT INTO species_fts(species_id, name, aliases)
SELECT
  s.id,
  s.name,
  COALESCE(GROUP_CONCAT(a.name, ' '), '')
FROM species s
LEFT JOIN aliasspecies als ON als.species_id = s.id
LEFT JOIN alias a ON a.id = als.alias_id
GROUP BY s.id;

-- ---------------------------------------------------------------------------
-- Create articles table
-- ---------------------------------------------------------------------------
CREATE TABLE articles (
  id INTEGER PRIMARY KEY NOT NULL,
  slug TEXT NOT NULL,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  content TEXT NOT NULL,
  tags TEXT,
  is_published BOOLEAN DEFAULT 0 NOT NULL,
  description TEXT,
  published_at TEXT,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX articles_slug_index ON articles(slug);
CREATE INDEX articles_is_published_index ON articles(is_published);


-- ---------------------------------------------------------------------------
-- Insert the articles that were ported from the old markdown files.
-- ---------------------------------------------------------------------------
INSERT INTO articles VALUES(1,'undescribedfaq','FAQ About Undescribed Galls','Adam Kranz',replace('# Preface\n\nAt the time of writing, of the 3112 galls listed on the Gallformers database, 1117 are undescribed. That ratio has not changed significantly since the early days of the site and isn''t likely to change much in the future. \nYou might reasonably wonder, if a gall can be distinctly identified by its morphology and host plant, such that we can represent it with its own Gallformers entry and consistently apply a Gallformers Code to observations, in what sense is it "undescribed", and what would it take to change that?\n\nA gall is part of the extended phenotype of the inducing organism, and in many cases the traits of the gall are sufficient to identify the species that induced it. The traits of the gall can often even be used to make an educated guess about what other species the inducer is related to.\n\nRegardless, the rules of taxonomy dictate that in order to formally describe a new species, taxonomists need to examine a physical specimen of the inducing organism. The species isn''t considered "described" until their description is published in a peer-reviewed academic journal (so species described in grad school theses but never published in a journal are still considered undescribed). \n\nOne of our main goals at Gallformers is to facilitate you, an amateur or academic naturalist, in the process of collecting and rearing such a specimen and getting it to an appropriate taxonomist. \n\nRaising an inducer is not hard, but each individual attempt has low odds of success. The biggest reason experts are more likely to succeed is not any particular technique but because they search harder and collect galls in larger numbers than any individual amateur. As a community, we can distribute that effort across many observers. So while you might not be successful yourself, you are still contributing to the process that builds the knowledge we need for someone to eventually succeed. \n\n# Being Prepared\n\nWhen in the field looking for undescribed galls you need to be prepared if you want to maximize your chances of success in collecting and rearing. Bringing a couple of basic tools with you will greatly improve your odds.\n\n- Something to cut or cross-section galls. e.g., a small sharp pocket knife. I like pruning shears\n- Containers for collection. Ziploc bags, organza bags, and small plastic vials are each useful for different purposes\n- A way to capture the details of the collection. Ideally a geotagged photograph of the gall, plus a written tag to associate the physical collection with that image and track it going forward\n\nWhen you collect a gall it is critically important that you capture several pieces of information. Without this information the specimen can be useless:\n\n- Date of collection\n- Location of collection: ideally Lat/Long (smart phone cameras often append this information to photographs automatically, but check first to make sure if you plan to rely on this method); if not, at least write down locale info and a rough description of the location so a future observer could find the site\n- Host plant species. If there is any uncertainty, and even if not, it''s best to take photos of diagnostic features of the plant that will allow others to confirm your ID. This is especially important if you''re in a location you can''t conveniently return to\n\n# So, You Have an Interesting Gall, Now What?\n\nSo if you find a gall you determine to be undescribed (or perhaps a described gall that is of interest for other reasons), what should you do?\nThe answer varies significantly depending on the taxon of the inducer. \n\n## 1. Broadly place the taxon of the inducer. \nMost galls can be placed taxonomically by comparison to other galls using the ID tool. For a truly new, unknown gall, or a gall listed as Unknown on Gallformers, the first step is to figure out what the likely taxon of the inducer is. This can sometimes be done with obvious external features, like rust fruiting bodies or mite erineum, but in general it requires dissection. \n\nCarefully cut apart the gall. For most galls, a scalpel is a good tool for this (disposable ones are cheap online); thick-walled or woody galls you''ll be better off with pruning shears or a sharper wood-carving knife. Try to make a shallow cut and then pull or pry the gall apart rather than passing the knife through the center of the gall, which destroys the larva. \n\nOnce you''ve made the section, photograph both the structure of the gall and the larvae as well as you can. This information should allow us to approximately place the inducer relative to known species.\n\n## 2. Determine the gall''s development timeline\nGenerally speaking, the most difficult part of collecting an inducer specimen is making your collection at the right time. To do that, you need to have a reasonable idea of when the inducer is likely to reach different points of its life cycle. If you find a gall that already has emergence holes, you''re either too late or just in time (if the galls are abundant, section one to determine if others may still have inducers within). \n\nTo help determine when a gall should be collected, I''ve [created a phenology tool](https://megachile.shinyapps.io/doycalc/) that presents records from the literature and from iNaturalist and extrapolates to latitudes with no data. The records in the tool are incomplete both because existing information hasn''t been imported and because it simply doesn''t exist yet. Use phenology of apparently-related galls where possible. Otherwise, any information you obtain in collecting and rearing will help improve the tool for future users. \n\nThere are a few ways to investigate the phenology of a gall, and all of them are valuable even if you don''t end up successfully rearing an inducer. \nIf you can conveniently revisit the site, the most informative and least invasive is to simply check the gall at frequent intervals (2x a week is ideal) until you see evidence of emergence, which will give us at least one estimate of its emergence timing. \n\nIf you aren''t likely to see it again, you should collect it immediately and try to rear it (see below). If you succeed, great; if not, then we know to wait a bit longer next time. If you don''t want to take it home, or you have a lot of galls in front of you, it''s once again informative to cut one open to see what developmental stage the inducer is in. This also lets us better calibrate future collections.\n\n## 3. Collect at the right time  \nOnce your gall is in the right stage for collection (pupae or adults; sometimes large larvae), depending on the taxon, you can either collect the sample directly or take the gall off the plant and bring it home to complete maturation. When removing the gall from the plant, it''s often wise to collect not just the gall but the general area of the plant the gall is on, like stem sections above and below a stem gall or the full leaf or even twig for a leaf gall. \n\nIn every case, collecting more specimens is better for science and generally (but not necessarily or universally--use your discretion) not a threat to populations.\n\nIn a Pucciniales rust or an eriophyid mite gall, #2 is where the tricky part ends: if you collect the gall at the right time (when it is sporulating for a rust, when it is fresh for a mite gall), you just need to dry it and store it in an envelope. \n\nFor other taxa, like aphids, midges, or wasps, collections can''t be made until after the point when the inducer no longer relies on the plant to complete its maturation. This happens at different life stages for different inducing taxa, but there are some general patterns. \n\nHemipteran inducers like aphids, phylloxera, and psyllids exist as nymphs for much of the gall''s growth, and eventually produce winged adults at maturation. These winged adults are the ones necessary for description, and they typically hang out in the gall for some time before leaving through an opening called an ostiole. These can be collected directly from the gall as adults and preserved (see below).\n\nCynipid wasps exist as larvae for most of the gall''s growth, and if the gall is collected in the larval stage they will likely die rather than emerge. Once they begin to pupate, however, they no longer need to feed on the gall and will likely survive to emerge from pupation and chew their way out of the gall. \n\nCecidomyiid midges exist as larvae in the gall and either pupate in the gall or emerge as a larva and pupate in the soil. The appropriate time to collect may vary by species for this group.\n\n## 4. Bring the gall home to rear\nNow that you''ve collected the gall, you need to store it in a sealed container so that whatever emerges won''t escape. For spring galls on fresh, succulent, tissue, these need to be watertight so that the gall doesn''t dry out. These will likely emerge within a relatively short timespan, so mold is often not a fatal issue. Ziplocs are a good choice but jars also work. Don''t worry about air holes; inducers are small and don''t use much oxygen before they emerge. Agamic cynipini or other detachable overwintering galls need to be kept humid but not too much so. Try to replicate the conditions they might experience overwintering outdoors in the leaf litter to the extent possible. We have had success for some galls with simple mesh bags indoors, however. Note that the emergence may be within a day or less of collection, but it may also take more than two years. If nothing has emerged yet, that may mean it''s just waiting for the right moment.\n\nFor cecidomyiid midges, the process can be more involved. See [this post by Charley Eiseman](https://bugtracks.wordpress.com/rearing/) for more information, but you may need to transfer the larva/pupae from the gall container into soil and potentially refrigerate it over the winter before an adult can emerge.\n\n## 5. Preserve what you reared\nOnce you have a specimen in hand, you need to preserve it to make sure your hard work doesn''t go to waste through rot or degradation. The primary concern here is water: DNA-destroying enzymes are only functional when water is present. Water can be removed either by storing the specimen in a low-humidity environment like a freezer, or using a high-proof ethanol. Low proof ethanol (70%) is not ideal because it contains substantial proportion of water; 95% is great. \n\nFor eriophyid mite and rust galls, preservation means drying the tissue and storing it in a paper envelope. \n\nFor other arthropods, adults should be killed in a freezer and stored there dry until they can be mailed to a taxonomist. To ship the specimens, pack with cotton or tissue to prevent them from being damaged by rattling around the container. The galls from which these arthropods emerged should be preserved as well if possible--in many cases they can also simply be dried; if they are especially succulent or fleshy, they are likely no longer worth preserving by the time the adult emerges.\n\nSome small specimens are prone to collapse or shrivel if dried. These can be better preserved in ethanol, but it must be high proof (95%). If you do choose to use ethanol, note that it dissolves both pen ink and graphite, and care must be taken to avoid smearing labels. A key concern is ensuring that the specimen can always be associated with its collection information, so making sure the label remains legible is crucial. Ideally, labels should be printed on a printer rather than written with pen or pencil, but if you do use pen or pencil, make sure the alcohol is sealed properly and the writing will not be in contact with it. \n\n## 5.5 Inquilines\nUnfortunately, it''s as likely as not that you''ve gone through this whole process and ended up with something that isn''t the inducer specimen needed to describe the gall. Depending on the gall, the adult arthropod emerging from your gall may be vastly more likely to be another species that displaced the inducer. Luckily these are also of scientific interest and can be preserved the same way. This is another reason rearing an inducer often takes many attempts.\n\n## 6. Mail your specimens to a taxonomist\n[Contact the Gallformers team](mailto:gallformers@gmail.com) and we will do our best to help you network with someone who can describe your specimen. We have contacts working on most groups, with the conspicuous exception of eriophyid mites, which seem to be underserved taxonomically right now.\n','\n',char(10)),'["faq","taxonomy"]',1,NULL,NULL,'2026-01-26T22:14:08','2026-01-26T22:14:08');
INSERT INTO articles VALUES(2,'patrons','Gallformers Patrons','Adam Kranz',replace('Thank you to all our Patrons!\n\n# Oak tier:\n\n- Madeleine Doney\n- Joshua Newbend\n\n# Cecidomyiid tier:\n\n- Timothy Frey\n- Kathleen Sweetman\n\n# Cynipid tier:\n\n- Andrew Deans\n- Leslie Flint\n- Ellen Martinson\n- Dale Ball\n\n# Eriophyid tier:\n\n- Mark Apgar\n- Lisa Appelbaum\n- Deborah Barber\n- Bird Bird\n- Tricia Bippus\n- Mimi Brown\n- Andrew Cameron\n- Catherine Chang\n- Ruta Daugavietis\n- Andrew Forbes\n- Jennifer Flynn\n- G Froelich\n- Chris Friesen\n- Michael Gates\n- Bert Harris\n- Sara Ruth Harrison\n- Noriko Ito\n- Henrik Kibak\n- Joseph L\n- Karlyn Lewis\n- Moe Morelock\n- Maureen Murphy\n- Robert Riedl\n- ribbon\n- cassi saari\n- Carrie Seltzer\n- Ramsey Sullivan\n- Scott Ulian\n- Linyi Zhang\n- Miles Zhang\n','\n',char(10)),'["meta","supporters"]',1,NULL,NULL,'2026-01-26T22:14:08','2026-01-26T22:14:08');
INSERT INTO articles VALUES(3,'populusmidgekey','Populus Midge Gall Key','Adam Kranz',replace('This key is largely based on original categorizations of iNaturalist observations, with some remarks on the limited prior literature. Even moreso than many gall-inducer taxa, midge galls on native North American poplars seem to map very closely onto midges known from Europe; these similarities are noted below. \n\n## The Key\n\n1. Leaf edge roll: [Prodiplosis morrisi](https://www.gallformers.org/gall/2166) (can be confused with [Aceria dispar](https://www.gallformers.org/gall/4004), which causes ragged leaf edge rolling but also shortens the petiole and occurs in bunched clusters)\n2. Concentric circular spot with raised papilla and exposed larva below\n1. A green spot on Populus balsamifera: [p-balsamifera-leaf-gall](https://www.gallformers.org/gall/3987)\n2. A green spot on Populus tristis (= trichocarpa): [p-tristis-leaf-spot](https://www.gallformers.org/gall/4027) (this and the previous are indistinguishable without host ID and may be sympatric where the hosts both occur. They may be conspecific.)\n3. A reddish blister on Populus grandidentata: [?Harmandiola stebbinsae](https://www.gallformers.org/gall/3985) (It’s ambiguous whether H stebbinsae fits in this group. Gagne 1989’s drawing matches this description, but no observations of this gall type have been reported from the host or range given for that species. It also seems unlikely that none of the sources would note that the gall has an exposed larva if it did. The text descriptions suggest something like [p-tremuloides-like-globuli](https://www.gallformers.org/gall/4033) but that gall looks very different from Gagne’s drawing. No galls matching this description have been observed on Populus grandidentata so far.)\n3. Larva concealed within galled tissue, protruding at least slightly at least one side of the leaf\n 1. Gall entirely on the upper side of the leaf, with only a flat opening on the lower side\n    1. A relatively large, spherical, thick-walled pea gall on a leaf vein: [p-tremuloides-like-tremulae](https://www.gallformers.org/gall/4028) (Similar to [Harmandiola tremulae](https://bladmineerders.nl/parasites/animalia/arthropoda/insecta/diptera/nematocera/cecidomyiidae/cecidomyiinae/cecidomyiidi/cecidomyiidi-unplaced/harmandiola/harmandiola-tremulae/) in Europe. [Russo’s species B](https://www.gallformers.org/gall/3999) might key here but it has an opening above.)\n    2. A relatively small, capsule-shaped, thin-walled gall anywhere on the upper leaf: [p-tremuloides-like-globuli](https://www.gallformers.org/gall/4033) (Similar to [Harmandiola globuli](https://bladmineerders.nl/parasites/animalia/arthropoda/insecta/diptera/nematocera/cecidomyiidae/cecidomyiinae/cecidomyiidi/cecidomyiidi-unplaced/harmandiola/harmandiola-globuli/) in Europe. Easily confused with [H helena](https://www.gallformers.org/gall/4005) from above)\n 2. Gall largely on the lower side or evenly protruding from both sides\n    1. Circular to ovate openings typically on the upper side but sometimes on the lower or even on both sides of the leaf. \n        1. Circles often visible before inducers emerge. Gall protruding more or less but typically to the same degree on either side of the leaf. Variable in size, shape, and number but often confluent with each other and with nearby veins, glossy and succulent, often but not always clustering in large confluent masses at the leaf base though never on the petiole: [p-tremuloides-like-populnea](https://www.gallformers.org/gall/4030) (Similar to [Lasioptera populnea](https://bladmineerders.nl/parasites/animalia/arthropoda/insecta/diptera/nematocera/cecidomyiidae/cecidomyiinae/lasiopteridi/lasiopterini/lasioptera/lasioptera-populnea/)/Contarinia populi in Europe. Galls with confluent and thus linear/elongated slits can be confused with [p-tremuloides-lips-gall](https://www.gallformers.org/gall/4029). Seems to be Russo’s sp A. His [species B](https://www.gallformers.org/gall/3999) might key here as well but I haven’t seen anything matching that description yet. This is a highly variable gall and is perhaps the morphotype most likely to represent multiple species?)\n    2. Linear slit openings on one or the other side of the leaf\n        1. Linear slits on the lower side of the leaf (based on Gagne’s drawing; opposite of the original Felt description) \n            1. Numerous small globular galls in loose rows along the midrib, protruding equally on both sides of the leaf, with a hole on the lower side: [Harmandiola helena](https://www.gallformers.org/gall/4005) (Similar to [Harmandiola pustulans](https://bladmineerders.nl/parasites/animalia/arthropoda/insecta/diptera/nematocera/cecidomyiidae/cecidomyiinae/cecidomyiidi/cecidomyiidi-unplaced/harmandiola/harmandiola-pustulans/) in Europe. Easily confused with [p-tremuloides-like-globuli](https://www.gallformers.org/gall/4033) from above. All of my IDs of H helena are made based on Gagne’s figure, which is listed as “possibly helena,” contradicts the original description, and are essentially all on Populus grandidentata rather than the type host, Populus tremuloides.)\n            2. Pocked, globular galls with a hairy slit on the lower side. Apparently unique in having globular galls that expand toward the base: [Russo’s species C](https://www.gallformers.org/gall/4000) \n        2. Linear slits on the upper side of the leaf\n            1. Small, numerous, thin-walled pouch galls in rows on either side of the midrib or lateral veins, only a small protrusion if any on the upper side around the opening: [p-tremuloides-pouch-gall](https://www.gallformers.org/gall/4031) (Similar to [Harmandiola populi](https://bladmineerders.nl/parasites/animalia/arthropoda/insecta/diptera/nematocera/cecidomyiidae/cecidomyiinae/cecidomyiidi/cecidomyiidi-unplaced/harmandiola/harmandiola-populi/) in Europe)\n            2. Large, thick-walled, globular galls singly or in clusters on the lamina, often with wide succulent lips protruding slightly on the upper side of the leaf: [p-tremuloides-lips-gall](https://www.gallformers.org/gall/4029) (Similar to [Harmandiola cavernosa](https://bladmineerders.nl/parasites/animalia/arthropoda/insecta/diptera/nematocera/cecidomyiidae/cecidomyiinae/cecidomyiidi/cecidomyiidi-unplaced/harmandiola/harmandiola-cavernosa/) in Europe. Can be confused with galls of [p-tremuloides-like-populnea](https://www.gallformers.org/gall/4030) with confluent, elongate openings on the upper side)\n','\n',char(10)),'["identification","keys","midges","populus"]',1,NULL,NULL,'2026-01-26T22:14:08','2026-01-26T22:14:08');
INSERT INTO articles VALUES(4,'idguide','Gall Identification Guide','Adam Kranz',replace('A gall is a novel organ grown by a plant when another organism alters the way the plant expresses its genes. Gall-inducers are found in a wide range of taxa. Insects, mites, and fungi are the most common, but nematodes, bacteria, and even plants can also induce galls.\n\nBecause gall induction is a biochemical alteration of the growth pattern of a plant, galls are highly targeted, usually specific to a single part of one or several closely related{'' ''} host species. Some gall-inducing species form distinct galls on different hosts or, in different portions of their lifecycle, on different parts of the same host. These galls are listed separately in the database.\n\nGalls typically have unique, recognizable exterior features that are distinct from galls formed by their close relatives. This means that identifying a gall-inducer to species requires no taxon-specific anatomical knowledge and is generally much easier than identifying other fungi or arthropods.\n\nGalls are created to feed and protect their inducers, and these conditions are attractive to other organisms. Many galls are targeted by predators, parasitoids, and inquilines that live within the gall, some of which do not harm the gall-inducer. In most cases this database does not include these organisms, but a few inquilines modify developing galls and create distinct galls, and in these cases the gall is listed as a separate entry in the database.\n\n## Using our ID tool\n\nThe most important step in gall ID is the correct identification of the host plant. If you’re not sure what your plant is, you can take a photo and make an observation on iNaturalist. The site’s computer vision algorithm will give you a plausible suggestion, which you can confirm yourself with other resources and will likely be confirmed or corrected by other users. There are many plant ID resources available online:\n\n- [New England](https://gobotany.nativeplanttrust.org/advanced/)\n- [Michigan](https://michiganflora.net/)\n- [North America](http://efloras.org/flora_page.aspx?flora_id=1)\n- [California (willows only)](http://tchester.org/plants/analysis/salix/key.html#picture)\n\nFor plants with few galls, host ID alone will likely filter the possibilities enough that your gall is recognizable. However, most galls are found on plant species with many galls. In those cases, select additional traits, starting with location and detachable, until the results are manageable. See the gall{'' ''} filter term guide for more info on what these selections mean.\n\nOnce you find a plausible set of options, you may want to confirm your ID by checking the original descriptions of the gall, available on its page. Additional information about taxonomic shifts and ID tips is also available on each gall page.\n\nBe aware that this database is a work in progress and many galls may not be added yet. The database is complete for plants and galls marked as such. However, many gall-inducing species are not yet described, and if you find a gall that is not listed on a host that is marked complete, please contact us at gallformers@gmail.com.\n\n## ID Tips and Troubleshooting\n\nIf you’re not finding a match, try using only host, location, and detachable before you give up. Common issues using these filters include\n\n- Wrong host ID (try moving up to the genus level or checking your second or third guesses)\n- Host not included in the database. Many hybrids or rare species, especially among highly speciose host groups like oaks or goldenrods, may not appear in the database at all or may not have comprehensive gall associations. Try searching a close relative or hybrid parent instead, or the section for Quercus or Carya.\n- Whether a gall is “Between veins” or “on leaf veins” can occasionally be ambiguous or misleading; try choosing the opposite or avoiding these terms entirely\n- Bud galls are often mistaken for stem galls\n- Acorn galls on red oaks can be mistaken for bud galls (red-group oaks have small overwintering acorns with similar size and placement as their buds)\n- A gall looks detachable but is not (or vice versa); check the results for the opposite option\n- If your gall is only found on the leaf midrib, it may be a species that could theoretically be found on any of the leaf veins; check “on leaf veins” instead\n- Gall-inducers, especially cynipid wasps, occasionally form galls on the opposite side of the leaf from their normal habit; check the results for the opposite option\n- Wrong season selected. Galls often persist long after their season of appearance. Only use this filter if the gall is obviously fresh\n\nGenerally speaking, it’s a good idea to try sequentially removing filters to make sure you’re not missing relevant possibilities.\n\nOther traits, including color, walls, cells, alignment, shape, and texture, may not be added comprehensively or at all. Check the gall filter term guide to make sure you’re applying the terms consistently with our usage.\n\nNote that if you search by host at the section or genus level, you are likely to encounter galls from other parts of the country than your observation. Be sure to confirm the range makes sense before making an ID.\n','\n',char(10)),'["identification","guide"]',1,NULL,NULL,'2026-01-26T22:14:08','2026-01-26T22:14:08');
INSERT INTO articles VALUES(5,'vitisgallkey','Key to Galls on Grapes (Vitis)','Adam Kranz',replace('## The Key\n\n1. Integral\n1. On main stem, a slight swelling typically directly adjacent to a node. Contains beetle larva and frass: [Ampeloglypter sesostris](https://www.gallformers.org/gall/3111)\n2. Swollen buds containing gall midge larvae: [Contarinia johnsoni](https://www.gallformers.org/gall/3109)\n3. On petiole or tendrils; tapered swellings with matte green exterior when fresh, brown and often splitting longitudinally with age: [Neolasioptera vitinea](https://www.gallformers.org/gall/1408)\n4. On leaves, petioles, inflorescences, and tendrils; abrupt swellings, either densely clustered across many tissues or scattered in globules on leaves, exterior pink-red, succulent and glossy, developing small egress holes on the upper side later in the season: [Vitisiella brevicauda](https://www.gallformers.org/gall/1407)\n5. Exclusively on leaves\n    1. Blistering above with corresponding patches of white, red, or brown erineum below: [Colomerus vitis](https://www.gallformers.org/gall/689)\n    2. Numerous globular pockets on the lower side of the leaf with hairy tufts above. Extremely common: [Daktulosphaira vitifoliae](https://www.gallformers.org/gall/1406)\n    3. Broad, flat, light yellow-green swellings on both sides of the leaf, thick-walled in spring but hollow with large opening holes by early summer: [Heliozela aesella](https://www.gallformers.org/gall/1419)\n    4. Many small globular swellings, often pink-red and succulent and resembling Vitisiella brevicauda but differing in the presence of\n        1. a tuft or covering of hairs. Highly variable; may represent multiple species: [Vitisiella vitis-tuft-gall](https://www.gallformers.org/gall/2687)\n        2. a narrow, hairy, sometimes curved protrusion on the lower side: [Dasineura v-cinerea-hook-gall](https://www.gallformers.org/gall/1748)\n2. Detachable\n1. On stem at nodes (replacing buds)\n    1. One (sometimes several) large, globular, polythalamous gall(s). May be hairy or glabrous, ribbed or smooth: [Ampelomyia vitispomum](https://www.gallformers.org/gall/1405)\n    2. A cluster of typically 10 or more pointed-globular monothalamous galls. May be hairy or glabrous: [Ampelomyia vitiscoryloides](https://www.gallformers.org/gall/1404)\n2. On leaves\n    1. Numerous elongate, conical galls scattered on either the upper or lower side of the leaf (typically not both). Yellow, turning red with exposure to the sun. May be hairy or glabrous: [Ampelomyia viticola](https://www.gallformers.org/gall/1403)\n        1. Nearly identical galls on Vitis tilifolia in Mexico may or may not be a distinct species: [Ampelomyia v-tiliifolia-pubescent-conical-gall](https://www.gallformers.org/gall/3355)\n    2. Numerous abruptly truncated cylindrical hairless yellow galls scattered on the lower side of the leaf. Common on Vitis mustangensis but similar galls have been observed on other Vitis species: [Ampelomyia v-mustangensis-lower-tube-gall](https://www.gallformers.org/gall/1357)\n    3. One or two wide ovate-conical galls causing a bunching of leaf tissue beyond the location of the gall. Green, turning red in the sun. May be hairy or glabrous. [Ampelomyia vitis-large-cone-gall](https://www.gallformers.org/gall/2265)\n','\n',char(10)),'["identification","keys","vitis"]',1,NULL,NULL,'2026-01-26T22:14:08','2026-01-26T22:14:08');
INSERT INTO articles VALUES(6,'contributing','Contributing to the Gallformers Reference Library','Jeff Clark',replace('If you would like to contribute to the Gallformers Reference Library it is quite easy. This article will describe the type of articles that we are looking for as well as the steps needed to get your article published.\n\n## Types of Reference Material We Publish\n\nWe are primarily interested in publishing articles about galls. The types of content that we are currently looking for are:\n\n- Guides to rearing adults from galls\n- Beginners guide to finding galls\n- Guides for host identifications\n- Keys for complex groups\n- Any original gall related research or findings\n\n## Understanding How Your Article Will Be Licensed\n\nCurrently all original content that is published on the site is released under a [Creative Commons 4.0 Attribution License](https://creativecommons.org/licenses/by/4.0/). Attribution will refer to gallformers generally but most folks citing information want to give credit where credit is due and will include the specific author.\n\nIf you want to publish an article under a different license, [get in touch with us](mailto:gallformers@gmail.com) and we will see what we can do.\n\n## Writing Your Article and Getting it Published\n\nFirst you will need 2 things:\n\n1. A [Github](https://github.com/) account\n1. An understanding of [Markdown](https://www.markdownguide.org/getting-started)\n\n### Writing\n\nWith these two steps complete you are ready to write! Write your article in whatever editor you choose. It is helpful, but not necessary, to use an editor that is markdown aware. You can also write it in another format, like MS Word or Google Docs, and then use one of the many online tools that will covert that format to markdown. Generally it is a good idea to stick to simple markdown as some of the various extensions to markdown will likely not render properly. If you are looking for a basic template you can view [this article''s markdown source](https://github.com/jeffdc/gallformers/blob/main/ref/contributing.md).\n\n#### Required Metadata\n\nAt the top of your article you must create a required metadata section that will contain the title, publishing date, author, and other info. I suggest copying this from this [article''s source](https://github.com/jeffdc/gallformers/blob/main/ref/contributing.md). The metadata section must look like this:\n```\n---\ntitle: ''The Title of Your Awesome Article''\ndate: ''2022-02-27''\ndescription: ''A short one sentence description of this article.''\nauthor:\nname: Your Name\n---\n```\n\n#### Limitations\n\nCurrently it is not possible to add hosted images to the article. You can link to images that are already published on the web, but please use this sparingly. We will eventually have the ability to publish images along with articles.\n\n### Publishing\n\nTo get your article published you will open a Pull Request against the gallformers repository on Github. To do this, follow these steps:\n\n1. Navigate to the [gallformers repository](https://github.com/jeffdc/gallformers) on Github\n1. Make sure that you are logged in to Github\n1. Click on the "Add File" button\n1. Select "Create a New File"\n1. This will create a fork of the repository under your account and allow you to open a pull request\n1. Name your file. This should be a short but descriptive title for your article. Please use all lowercase letters with no spaces or punctuation\n1. Copy the source of your article and paste it into the "Edit New File" box\n1. Click "Propose New File" at the bottom of the page\n1. On the next screen click on "Create pull request"\n1. In the comment section write any details that you want. These will seen by the reviewer and might be useful to describe why you think the article should be published on Gallformers\n1. Click on "Create pull request"\n\nAt this point a Pull Request has been created. One of our reviewers will review the article. We may request changes to the article. We will do this via Github''s review mechanism. You will be notified by email so make sure you have added Github to your address book so the messages do not end up lost in your spam folder.\n\nOnce the review process is done the article will go live on the site within a couple of hours.\n\n### Future Edits\n\nIf for whatever reason in the future you want to update the article the process is straight-forward. \n\n1. Navigate to the article on Github. They are all in the [`ref`](https://github.com/jeffdc/gallformers/tree/main/ref) directory 1. Once you have clicked on the article you want to edit, find the pencil icon in the toolbar above the article content and click on it\n1. This will take you into an editor where you can make the changes\n1. Once the changes are complete fill in a comment as to the nature of the changes that you made\n1. Click on "Propose Changes"\n1. On the next screen click on "Create pull request"\n\nThis will then trigger the review process which is the same as with the Publish step above.\n\n## Closing Thoughts\n\nWe thank you for the articles that you write. The gallformers site would not exist without the hundreds of hours of volunteer time from our band of gall nerds.\n','\n',char(10)),'["meta","contributing"]',1,NULL,NULL,'2026-01-26T22:14:08','2026-01-26T22:14:08');
INSERT INTO articles VALUES(7,'populusaphidkey','Populus Aphid Gall Key','Adam Kranz',replace('*This key is a synthesis of gall descriptions given in the literature. There is reason to believe that these gall descriptions may not map perfectly onto monophyletic aphid taxa; cases where this is known to be true will be noted but the full extent of variation for all species is likely not known, and cryptic species likely await description.*\n\n## Table of Contents\n\n1. [Populus Sections](#populus-sections)\n2. [Notes](#notes)\n3. [The Key](#the-key)\n- [1. Leaves folded into loose “nest.”](#1-leaves-folded-into-loose-nest)\n- [2. Gall on stem, dropping late in the season leaving a flat circular scar](#2-gall-on-stem-dropping-late-in-the-season-leaving-a-flat-circular-scar)\n- [3. Full or most of leaf galls](#3-full-or-most-of-leaf-galls)\n- [4. Pouch or pocket galls on leaf](#4-pouch-or-pocket-galls-on-leaf)\n- [5. Globular to conical galls on petiole at or below leaf base](#5-globular-to-conical-galls-on-petiole-at-or-below-leaf-base)\n\n## Populus Sections\n\n| **Section**     | **Species**                                                   |\n|-----------------|---------------------------------------------------------------|\n| **Aigeiros**    | *deltoides*, *fremontii*, *nigra*                             |\n| **Populus**     | *alba*, *tremula*, *tremuloides*, *grandidentata*              |\n| **Tacamahaca**  | *angustifolia*, *balsamifera*, *tristis* (= *trichocarpa*)    |\n\n## Notes\n\n> **Note:** *Populus tremula*, *alba*, and *nigra* are non-native species found in cultivated settings.\n\n> **Caution:** Some galls may require DNA or anatomical evidence to distinguish between closely related species.\n\n## The Key\n\n### 1. Leaves folded into loose “nest.”\n\nNo galled tissue, leaves often not even curled, aphids exposed along the petioles causing them to shorten and bend together. Only on *Populus tremuloides*:\n\n[Pachypappa rosettei](https://www.gallformers.org/gall/4012)\n\n---\n\n### 2. Gall on stem, dropping late in the season leaving a flat circular scar\n\nSlit opening usually aligned with stem rather than perpendicular to it. On Sect. Tacamahaca and Aigeiros:\n\n[Pemphigus populiramulorum](https://www.gallformers.org/gall/3459)\n\n---\n\n### 3. Full or most of leaf galls\n\n<details>\n<summary>Expand for details</summary>\n\n1. **Galling of all or part of leaf**\n\n <details>\n   <summary>Expand for options</summary>\n   \n   - **Entire leaf with walnut-like corrugations**  \n     Wax-glossy, only on *Populus deltoides*:\n     [Mordwilkoja vagabunda](https://www.gallformers.org/gall/3678)\n   \n   - **Large, broadly wrinkled sacks**  \n     Dull in texture, only on *Populus tremuloides*:\n     [Pachypappa sacculi](https://www.gallformers.org/gall/4013)\n </details>\n\n2. **No galling, leaf folded to varying extents**\n\n <details>\n   <summary>Expand for options</summary>\n   \n   - **Tight folding, blistering, or convolution**\n     \n     <details>\n       <summary>Expand for specifics</summary>\n       \n       - **Native poplars**:  \n         [Thecabius gravicornis](https://www.gallformers.org/gall/4010)  \n         [Thecabius populiconduplifolius](https://www.gallformers.org/gall/4034)\n       \n       - **Non-native poplars**:  \n         [Thecabius lysimachiae](https://www.gallformers.org/gall/4011)  \n         [Thecabius affinis](https://www.gallformers.org/gall/3989)\n     </details>\n   \n   - **Loose bending at midrib without discoloration**  \n     [Pachypappa pseudobyrsa](https://www.gallformers.org/gall/3677)\n </details>\n\n</details>\n\n---\n\n### 4. Pouch or pocket galls on leaf\n\n<details>\n<summary>Expand for details</summary>\n\n1. **Leaf edge fold**\n\n <details>\n   <summary>Expand for options</summary>\n   \n   - **A thick, crescent shaped gall containing many aphids.**  \n     On *Populus angustifolia*:\n     [Cornaphis populi](https://www.gallformers.org/gall/4057)\n   \n   - **A globular, near spherical, pouch bulging out of a leaf edge fold.**  \n     On *Populus tremuloides*:\n     [p-tremuloides-cherry-gall](https://www.gallformers.org/gall/4058)  \n     *(only tentatively thought to be induced by an aphid)*\n   \n   - **A simple ungalled leaf edge fold**\n     \n     <details>\n       <summary>Expand for specifics</summary>\n       \n       - On *Populus deltoides* or *balsamifera*: stem mother  \n         [Thecabius populiconduplifolius](https://www.gallformers.org/gall/4034)  \n         *(some sources state this is also known from *Populus nigra* but these reports may be *T. affinis*; broadly this seems to be a native species found on native hosts)*\n       \n       - On *Populus nigra*: stem mother  \n         [Thecabius affinis](https://www.gallformers.org/gall/3989)  \n         *(a European species present in NA but likely only found on non-native *Populus* like *P. nigra*; similar observations on native poplars are presumably *T. populiconduplifolius*. The species are closely related but have different chromosome counts.)*\n     </details>\n   \n </details>\n\n2. **Linear or ovate pocket(s) on lamina or along edge, often parallel to midrib**\n\n <details>\n   <summary>Expand for options</summary>\n   \n   - **Large, smooth, flat-sided cockscomb gall.**  \n     On *Populus deltoides*:\n     [Pemphigus longicornis](https://www.gallformers.org/gall/3451)\n   \n   - **Pseudogall pocket/pouch**\n     \n     <details>\n       <summary>Expand for specifics</summary>\n       \n       - **A single long, narrow, pseudogall parallel to the midrib, barely raised above the leaf, containing one apterous aphid.**  \n         In spring. Typically on Sect. Tacamahaca; apparently the same species on *Populus fremontii*: stem mother  \n         [Thecabius populimonilis](https://www.gallformers.org/gall/4009)\n       \n       - **Apparently similar, on Sect. Tacamahaca:** stem mother  \n         [Thecabius gravicornis](https://www.gallformers.org/gall/4010)  \n         *(disagreement in the literature whether this is on the midrib, adjacent to the midrib, or halfway between the midrib and the leaf edge)*\n       \n       - **One to four rows of bead-like galls parallel to midrib or (on *Populus fremontii*) along the edge of the leaf, each containing a single winged or apterous aphid.**  \n         In summer. Often in numbers, overtaking the whole leaf and causing it to spiral. Typically on Sect. Tacamahaca.  \n         Apparently the same species forms similar galls on *Populus fremontii* but this may be worth confirming:  \n         [Thecabius populimonilis](https://www.gallformers.org/gall/4009)\n     </details>\n   \n   - **Pseudogall pocket on midrib.**  \n     Typically on *Populus deltoides*: stem mother  \n     [Pachypappa pseudobyrsa](https://www.gallformers.org/gall/3677)\n   \n   - **Gall on midrib**  \n     *(many of these aphids occur on the same hosts and cause similar or overlapping symptoms; DNA or anatomical evidence is likely necessary to distinguish them)*\n     \n     <details>\n       <summary>Expand for specifics</summary>\n       \n       1. **Lower midrib**\n          \n          <details>\n            <summary>Expand for options</summary>\n            \n            - **An elongate-globular or triangular pocket gall, typically near the base of the leaf.**  \n              Only on Sect. Tacamahaca:\n              [Pemphigus betae](https://www.gallformers.org/gall/3461)\n            \n            - **Similar, only known from *Populus angustifolia* in Utah:**  \n              [Pemphigus knowltoni](https://www.gallformers.org/gall/3462)\n            \n            - **Similar, typically found on the upper leaf per early lit but Foottit et al 2010 state that this aphid was found predominantly in galls on the lower side. A third, undescribed taxon was also reported on similar galls:**  \n              [Pemphigus populivenae](https://www.gallformers.org/gall/3456)\n            \n            - **Irregularly globular, twisted galls on the lower midrib, opening with a thick slit on the upper midrib.**  \n              On *Populus fremontii*:\n              [Pemphigus p-fremontii-midrib-gall](https://www.gallformers.org/gall/3996)\n          </details>\n       \n       2. **Upper midrib**  \n          *(these three galls all occur chiefly on Sect. Tacamahaca and their galls may overlap morphologically especially when populations are high)*\n          \n          <details>\n            <summary>Expand for options</summary>\n            \n            1. **Localized at the base of the leaf**\n               \n               <details>\n                 <summary>Expand for specifics</summary>\n                 \n                 - **A single or sometimes two large irregularly globose galls. Narrow to a small thickening of the midrib where they connect to the leaf base.**  \n                   Alate aphids emerge in mid-July. Only on Sect. Tacamahaca:  \n                   [Pemphigus populiglobuli](https://www.gallformers.org/gall/3458)\n               </details>\n            \n            2. **Along the length of the leaf**\n               \n               <details>\n                 <summary>Expand for specifics</summary>\n                 \n                 - **Leathery, slightly sinuous thickening of the midrib with sometimes one but typically at least 2 globular galls, often confluent in irregular cockscomb divided by saddle-like furrows, typically with a roughened surface.**  \n                   Alate aphids emerge in late August-September. Only on Sect. Tacamahaca:  \n                   [Pemphigus monophagus](https://www.gallformers.org/gall/3457)\n                 \n                 - **An elongate-globular or triangular pocket gall, typically near the base of the leaf.**  \n                   Typically on Sect. Tacamahaca:  \n                   [Pemphigus populivenae](https://www.gallformers.org/gall/3456)\n               </details>\n            \n          </details>\n       \n       3. **Clusters of yellow-red globular galls on the lower side of the leaf of *Populus tremuloides***  \n          [Pemphigus rileyi](https://www.gallformers.org/gall/3990)  \n          *(unclear if this is in fact an aphid species; no sources mention the aphid past Stebbins)*\n     </details>\n   \n </details>\n\n</details>\n\n---\n\n### 5. Globular to conical galls on petiole at or below leaf base\n\n<details>\n<summary>Expand for details</summary>\n\n1. **Not twisted (occasionally bending the petiole), not incorporating any leaf tissue**\n\n <details>\n   <summary>Expand for options</summary>\n   \n   - **Opening with a round ostiole. Conical, often squatly triangular but sometimes elongate and narrow.**  \n     Only on *Populus nigra var italica*:\n     [Pemphigus bursarius](https://www.gallformers.org/gall/3450)  \n     *(reported from North America in the literature but apparently not observed on iNaturalist yet?)*\n   \n   - **Opening with a simple linear slit, sometimes with protruding lips**\n     \n     <details>\n       <summary>Expand for specifics</summary>\n       \n       - **Slit oriented parallel to petiole, a stem gall rarely found on only petiole:**  \n         [Pemphigus populiramulorum](https://www.gallformers.org/gall/3459)\n       \n       - **Slit oriented nearly perpendicular to petiole**\n         \n         <details>\n           <summary>Expand for specifics</summary>\n           \n           - **Globular (some galls in CA almost laterally compressed), near junction with leaf (though not incorporating leaf midrib), slit has protruding, sometimes almost conical, lips. May cause petiole to bend slightly but never twist.**  \n             Aphids in galls from May to October (longer in CA?). On *Populus fremontii* and *deltoides*:  \n             [Pemphigus obesinymphae](https://www.gallformers.org/gall/3453)  \n             *(eastern galls of this species were formerly considered a morph of *P. populitransversus*)*\n           \n           - **Elongate, near center of petiole, opens via slit.**  \n             Aphids in galls from March to July. On *Populus deltoides* only:  \n             [Pemphigus populitransversus](https://www.gallformers.org/gall/3460)\n         </details>\n       \n     </details>\n   \n </details>\n\n2. **Twisted, with a long winding groove or slit (which may or may not ever open), gall sometimes including base of midrib**\n\n <details>\n   <summary>Expand for options</summary>\n   \n   - **Only at junction of petiole and leaf**  \n     *(these aphids apparently have at least some host overlap and cause nearly indistinguishable symptoms; DNA or anatomical evidence is likely necessary to distinguish them)*\n     \n     <details>\n       <summary>Expand for specifics</summary>\n       \n       1. **Almost entirely above upper surface of leaf; on Sect. Tacamahaca**\n          \n          - **A single or sometimes two large irregularly globose galls. Narrow to a small thickening of the midrib where they connect to the leaf base.**  \n            Alate aphids emerge in mid-July. Only on Sect. Tacamahaca:  \n            [Pemphigus populiglobuli](https://www.gallformers.org/gall/3458)\n       \n       2. **To either side of the leaf; on Sect. Aigeiros**\n          \n          <details>\n            <summary>Expand for options</summary>\n            \n            - **Large, near leaf base but almost entirely on petiole. Opening with a slit.**  \n              On *Populus deltoides* and *fremontii*:  \n              [Pemphigus nortonii](https://www.gallformers.org/gall/3452)  \n              *(Russo notes that uncited DNA evidence suggests the CA galls that key to this species are more closely related to *populiramulorum*; this key leaves them together pending further information)*\n            \n            - **Galls with a visible exit hole or fully on the leaf lamina can be identified as *populicaulis*; those with no hole and found equally on the petiole are apparently indistinguishable from *tartareus*.**  \n              On leaf base with some of the petiole twisted into the gall. On *Populus deltoides*  \n              [Pemphigus populicaulis](https://www.gallformers.org/gall/3454)\n            \n            - **Principally on the petiole but with enough of the gall on the blade that the leaf margin can be traced along the edge.**  \n              On *Populus deltoides*:  \n              [Pemphigus tartareus](https://www.gallformers.org/gall/4014)\n          </details>\n       \n     </details>\n   \n   - **Typically below junction of leaf along the petiole, though some galls may be near the junction**\n      \n      - **Twisted petioles maturing to large, irregularly globular, rough-textured galls.**  \n        Only on *Populus nigra var italica*:  \n        [Pemphigus spyrothecae](https://www.gallformers.org/gall/3994)\n   \n </details>\n\n</details>\n\n---\n','\n',char(10)),'["identification","keys","aphids","populus"]',1,NULL,NULL,'2026-01-26T22:14:08','2026-01-26T22:14:08');
INSERT INTO articles VALUES(9,'link-undescribed-inat','Using Gallformers Codes on iNaturalist','Gallformers Team',replace('# What is a Gallformers Code?\n\nMany galls are caused by species that haven''t been formally described by scientists yet. While we can recognize these galls by their distinctive appearance on specific host plants, we can''t assign them to a named species because the inducing organism hasn''t been studied and published in the scientific literature.\n\nTo track observations of these undescribed galls, Gallformers assigns each one a unique **Gallformers Code**. This code is typically based on the host plant and a descriptive element of the gall (for example, `q-lobata-integral-leaf-gall` for an integral leaf gall on *Quercus lobata*).\n\n# The Gallformers Code Observation Field on iNaturalist\n\n[iNaturalist](https://www.inaturalist.org) allows users to add custom observation fields to their observations. The **Gallformers Code** observation field lets you tag your gall observations with the corresponding code from our database.\n\n**Why use it?**\n\n- **Track undescribed galls**: Since these galls can''t be identified to a species on iNaturalist, adding the Gallformers Code creates a way to search for and aggregate observations of the same gall type\n- **Build phenology data**: More observations with codes help us understand when and where these galls appear\n- **Aid future research**: When a taxonomist eventually describes the species, having a corpus of linked observations provides valuable data on distribution, phenology, and host associations\n- **Connect the community**: Other gall enthusiasts can find your observations when researching specific undescribed galls\n\n# How to Add a Gallformers Code to Your Observation\n\n## Step 1: Find the Code\n\nOn any undescribed gall page on Gallformers, you''ll see an amber-colored box with the Gallformers Code displayed. You can click the code to copy it to your clipboard.\n\n## Step 2: Go to Your iNaturalist Observation\n\nNavigate to the observation you want to tag. You can do this from your observations page or directly after uploading a new observation.\n\n## Step 3: Add the Observation Field\n\n1. Scroll down to the **Observation Fields** section (below the Data Quality Assessment)\n2. Click **Add a Field...**\n3. Search for "Gallformers Code"\n4. Select the field from the dropdown\n5. Paste or type the code in the value field\n6. Click the checkmark or press Enter to save\n\nThat''s it! Your observation is now linked to this specific gall type in the Gallformers system.\n\n# Finding Observations with a Specific Code\n\nFrom any undescribed gall page on Gallformers, click the **"View observations collected with this code on iNaturalist"** link to see all observations that have been tagged with that Gallformers Code.\n\nYou can also search directly on iNaturalist by using the observation field filter in the Explore or Identify pages.\n\n# Tips for Best Results\n\n- **Copy the code exactly**: The field value must match exactly, including hyphens and lowercase letters\n- **Use it for undescribed galls only**: Described species should be identified to species level on iNaturalist when possible\n- **Include quality photos**: Clear photos of the gall, any cross-sections, and the host plant help others confirm your identification\n- **Add host plant info**: If you''re not certain of the host plant species, make a separate observation of the plant for identification\n\n# Learn More\n\n- [FAQ About Undescribed Galls](/articles/undescribedfaq) — comprehensive guide to collecting, rearing, and preserving specimens from undescribed galls\n- [Gall Identification Guide](/articles/idguide) — tips for identifying galls using the Gallformers ID tool\n- [iNaturalist Observation Fields](https://www.inaturalist.org/pages/observation_fields) — iNaturalist documentation on observation fields\n','\n',char(10)),'["guide","inat","undescribed"]',1,NULL,NULL,'2026-01-30T00:03:46','2026-01-30T00:03:46');

-- ---------------------------------------------------------------------------
-- Create users table
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id INTEGER PRIMARY KEY NOT NULL,
  auth0_id TEXT NOT NULL,
  display_name TEXT,
  nickname TEXT,
  inaturalist_url TEXT,
  social_url TEXT,
  personal_url TEXT,
  show_on_about BOOLEAN DEFAULT 0 NOT NULL,
  about_me TEXT,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX users_auth0_id_index ON users(auth0_id);

-- ---------------------------------------------------------------------------
-- Add image.sort_order
-- ---------------------------------------------------------------------------
ALTER TABLE image ADD COLUMN sort_order INTEGER DEFAULT 0 NOT NULL;

UPDATE image
SET sort_order = (
  SELECT row_num FROM (
    SELECT
      i.id,
      ROW_NUMBER() OVER (
        PARTITION BY i.species_id
        ORDER BY i."default" DESC, i.id ASC
      ) - 1 as row_num
    FROM image i
  ) ranked
  WHERE ranked.id = image.id
);

CREATE INDEX image_species_id_sort_order_index ON image(species_id, sort_order);

-- ---------------------------------------------------------------------------
-- Fix place CHECK constraint (change quotes)
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

CREATE TABLE place_new (
  id INTEGER PRIMARY KEY NOT NULL,
  name TEXT UNIQUE NOT NULL,
  code TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('continent', 'country', 'region', 'state', 'province', 'county', 'city'))
);

INSERT INTO place_new SELECT * FROM place;
DROP TABLE place;
ALTER TABLE place_new RENAME TO place;

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Change image.source_id FK to SET NULL
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

CREATE TABLE image_new (
  id INTEGER PRIMARY KEY NOT NULL,
  species_id INTEGER NOT NULL,
  source_id INTEGER,
  path TEXT UNIQUE NOT NULL,
  "default" INTEGER DEFAULT 0 NOT NULL,
  small TEXT,
  medium TEXT,
  large TEXT,
  creator TEXT,
  attribution TEXT,
  sourcelink TEXT,
  license TEXT,
  licenselink TEXT,
  uploader TEXT,
  lastchangedby TEXT,
  caption TEXT DEFAULT '',
  sort_order INTEGER DEFAULT 0 NOT NULL,
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (source_id) REFERENCES source(id) ON DELETE SET NULL
);

INSERT INTO image_new (id, species_id, source_id, path, "default", creator, attribution, sourcelink, license, licenselink, uploader, lastchangedby, caption, sort_order)
SELECT id, species_id, source_id, path, "default", creator, attribution, sourcelink, license, licenselink, uploader, lastchangedby, caption, sort_order
FROM image;
DROP TABLE image;
ALTER TABLE image_new RENAME TO image;

CREATE INDEX image_species_id_sort_order_index ON image(species_id, sort_order);

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Add NOT NULL to host foreign keys
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

CREATE TABLE host_new (
  id INTEGER PRIMARY KEY NOT NULL,
  host_species_id INTEGER NOT NULL,
  gall_species_id INTEGER NOT NULL,
  inserted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (host_species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (gall_species_id) REFERENCES species(id) ON DELETE CASCADE
);

INSERT INTO host_new SELECT * FROM host;
DROP TABLE host;
ALTER TABLE host_new RENAME TO host;

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Create page_views table (direct port from V1 schema)
-- ---------------------------------------------------------------------------
CREATE TABLE page_views (
  id INTEGER PRIMARY KEY NOT NULL,
  path TEXT NOT NULL,
  referrer_host TEXT,
  browser TEXT,
  device_type TEXT,
  visitor_hash TEXT NOT NULL,
  inserted_at TEXT NOT NULL
);

CREATE INDEX page_views_inserted_at_index ON page_views(inserted_at);
CREATE INDEX page_views_path_index ON page_views(path);
CREATE INDEX page_views_visitor_hash_inserted_at_index ON page_views(visitor_hash, inserted_at);

-- ============================================================================
-- PART 2: New Restructuring (to match structure_target.sql)
-- ============================================================================

-- NOTE: Unknown genera backfill moved to Part 2 after is_placeholder column added

-- ---------------------------------------------------------------------------
-- Add placeholder support to taxonomy
-- ---------------------------------------------------------------------------
ALTER TABLE taxonomy ADD COLUMN is_placeholder BOOLEAN DEFAULT 0 NOT NULL;

-- Mark existing "Unknown" genera and families as placeholders
UPDATE taxonomy
SET is_placeholder = 1
WHERE (name = 'Unknown' OR name LIKE 'Unknown-%') AND type IN ('genus', 'family');

-- Delete empty "Unknown" under Cecidomyiidae (conflicts with Unknown-cecid)
DELETE FROM taxonomy
WHERE type = 'genus'
  AND name = 'Unknown'
  AND parent_id = (SELECT id FROM taxonomy WHERE name = 'Cecidomyiidae' AND type = 'family')
  AND id NOT IN (SELECT DISTINCT taxonomy_id FROM speciestaxonomy);

-- Rename existing "Unknown" and "Unknown-*" genera to "Unknown (Family)" format
UPDATE taxonomy
SET name = 'Unknown (' || (
  SELECT name FROM taxonomy f WHERE f.id = taxonomy.parent_id
) || ')'
WHERE type = 'genus'
  AND (name = 'Unknown' OR name LIKE 'Unknown-%')
  AND parent_id IN (SELECT id FROM taxonomy WHERE type = 'family');

-- Create "Unknown (Family)" for families that don't have one yet
INSERT INTO taxonomy (name, description, type, parent_id, is_placeholder, inserted_at, updated_at)
SELECT
  'Unknown (' || f.name || ')',
  'Placeholder genus for undescribed species',
  'genus',
  f.id,
  1,
  datetime('now'),
  datetime('now')
FROM taxonomy f
WHERE f.type = 'family'
  AND NOT EXISTS (
    SELECT 1 FROM taxonomy g
    WHERE g.type = 'genus'
      AND g.name = 'Unknown (' || f.name || ')'
      AND g.parent_id = f.id
  );

-- ---------------------------------------------------------------------------
-- Create versions table (audit trail)
-- ---------------------------------------------------------------------------
CREATE TABLE versions (
  id INTEGER PRIMARY KEY NOT NULL,
  entity_schema TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  action TEXT NOT NULL,
  user_id INTEGER,
  recorded_at TEXT NOT NULL,
  changes TEXT
);

CREATE INDEX versions_entity_schema_entity_id_index ON versions(entity_schema, entity_id);
CREATE INDEX versions_user_id_index ON versions(user_id);
CREATE INDEX versions_recorded_at_index ON versions(recorded_at);
CREATE INDEX versions_action_index ON versions(action);

-- ---------------------------------------------------------------------------
-- Delete taxonomytaxonomy table (redundant - using taxonomy.parent_id)
-- ---------------------------------------------------------------------------
DROP TABLE taxonomytaxonomy;

-- ---------------------------------------------------------------------------
-- Split speciesplace into host_range and gall_range_exclusion
-- ---------------------------------------------------------------------------
-- Create host_range for plant species (where speciesplace means "host exists here")
CREATE TABLE host_range (
  species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, place_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place(id) ON DELETE CASCADE
);

INSERT INTO host_range (species_id, place_id)
SELECT sp.species_id, sp.place_id
FROM speciesplace sp
JOIN species s ON s.id = sp.species_id
WHERE s.taxoncode = 'plant';

-- Create gall_range_exclusion for gall species (where speciesplace means "excluded from range")
CREATE TABLE gall_range_exclusion (
  species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, place_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place(id) ON DELETE CASCADE
);

INSERT INTO gall_range_exclusion (species_id, place_id)
SELECT sp.species_id, sp.place_id
FROM speciesplace sp
JOIN species s ON s.id = sp.species_id
WHERE s.taxoncode = 'gall';

-- Drop old table
DROP TABLE speciesplace;

-- ---------------------------------------------------------------------------
-- Delete taxontype table and update species
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

-- Create new species table without taxontype FK, with taxonomy_id FK
CREATE TABLE species_new (
  id INTEGER PRIMARY KEY NOT NULL,
  taxoncode TEXT NOT NULL CHECK (taxoncode IN ('gall', 'plant', 'undetermined')),
  name TEXT UNIQUE NOT NULL,
  datacomplete BOOLEAN DEFAULT 0 NOT NULL,
  abundance_id INTEGER,
  taxonomy_id INTEGER,
  inserted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (abundance_id) REFERENCES abundance(id) ON DELETE SET NULL,
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id)
);

-- Copy data (taxonomy_id will be NULL for now)
INSERT INTO species_new (id, taxoncode, name, datacomplete, abundance_id, inserted_at, updated_at)
SELECT id, taxoncode, name, datacomplete, abundance_id, inserted_at, updated_at
FROM species;

-- Drop old species and rename
DROP TABLE species;
CREATE TABLE species (
  id INTEGER PRIMARY KEY NOT NULL,
  taxoncode TEXT NOT NULL CHECK (taxoncode IN ('gall', 'plant', 'undetermined')),
  name TEXT UNIQUE NOT NULL,
  datacomplete BOOLEAN DEFAULT 0 NOT NULL,
  abundance_id INTEGER,
  taxonomy_id INTEGER,
  inserted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (abundance_id) REFERENCES abundance(id) ON DELETE SET NULL,
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id)
);

INSERT INTO species SELECT * FROM species_new;
DROP TABLE species_new;

-- Drop taxontype table
DROP TABLE taxontype;

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Restructure gall traits (major transformation)
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

-- Step 1: Add new column to gall table for species_id
-- Note: color, walls, cells remain as junction tables (multi-value traits)
ALTER TABLE gall ADD COLUMN species_id INTEGER;

-- Step 2: Populate species_id from gallspecies
UPDATE gall
SET species_id = (
  SELECT species_id
  FROM gallspecies
  WHERE gallspecies.gall_id = gall.id
  LIMIT 1
);

-- Step 3: Create new gall_traits table with correct structure
-- Note: color, walls, cells are junction tables (not FKs in gall_traits)
CREATE TABLE gall_traits (
  species_id INTEGER PRIMARY KEY NOT NULL,
  detachable TEXT CHECK (detachable IN ('unknown', 'integral', 'detachable', 'both')),
  undescribed BOOLEAN NOT NULL DEFAULT 0,
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE
);

-- Step 4: Migrate data with detachable conversion (INTEGER → TEXT)
INSERT INTO gall_traits (species_id, detachable, undescribed)
SELECT
  species_id,
  CASE detachable
    WHEN 0 THEN 'unknown'
    WHEN 1 THEN 'integral'
    WHEN 2 THEN 'detachable'
    WHEN 3 THEN 'both'
    ELSE 'unknown'
  END,
  undescribed
FROM gall
WHERE species_id IS NOT NULL;

-- Step 5: Create mapping table for multi-value trait transformations
CREATE TEMP TABLE gall_species_mapping AS
SELECT gall_id, species_id FROM gallspecies;

-- Step 6: Transform multi-value trait tables (gall_id → species_id)
-- Transform gallcolor → gall_color
CREATE TABLE gall_color (
  species_id INTEGER NOT NULL,
  color_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, color_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (color_id) REFERENCES color(id) ON DELETE CASCADE
);

INSERT INTO gall_color (species_id, color_id)
SELECT DISTINCT m.species_id, gc.color_id
FROM gallcolor gc
JOIN gall_species_mapping m ON m.gall_id = gc.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE gallcolor;

-- Transform gallwalls → gall_walls
CREATE TABLE gall_walls (
  species_id INTEGER NOT NULL,
  walls_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, walls_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (walls_id) REFERENCES walls(id) ON DELETE CASCADE
);

INSERT INTO gall_walls (species_id, walls_id)
SELECT DISTINCT m.species_id, gw.walls_id
FROM gallwalls gw
JOIN gall_species_mapping m ON m.gall_id = gw.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE gallwalls;

-- Transform gallcells → gall_cells
CREATE TABLE gall_cells (
  species_id INTEGER NOT NULL,
  cells_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, cells_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (cells_id) REFERENCES cells(id) ON DELETE CASCADE
);

INSERT INTO gall_cells (species_id, cells_id)
SELECT DISTINCT m.species_id, gc.cells_id
FROM gallcells gc
JOIN gall_species_mapping m ON m.gall_id = gc.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE gallcells;

-- Transform gallseason
CREATE TABLE gall_season (
  species_id INTEGER NOT NULL,
  season_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, season_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (season_id) REFERENCES season(id) ON DELETE CASCADE
);

INSERT INTO gall_season (species_id, season_id)
SELECT DISTINCT m.species_id, gs.season_id
FROM gallseason gs
JOIN gall_species_mapping m ON m.gall_id = gs.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE gallseason;

-- Transform gallshape
CREATE TABLE gall_shape (
  species_id INTEGER NOT NULL,
  shape_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, shape_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (shape_id) REFERENCES shape(id) ON DELETE CASCADE
);

INSERT INTO gall_shape (species_id, shape_id)
SELECT DISTINCT m.species_id, gs.shape_id
FROM gallshape gs
JOIN gall_species_mapping m ON m.gall_id = gs.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE gallshape;

-- Transform galltexture
CREATE TABLE gall_texture (
  species_id INTEGER NOT NULL,
  texture_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, texture_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (texture_id) REFERENCES texture(id) ON DELETE CASCADE
);

INSERT INTO gall_texture (species_id, texture_id)
SELECT DISTINCT m.species_id, gt.texture_id
FROM galltexture gt
JOIN gall_species_mapping m ON m.gall_id = gt.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE galltexture;

-- Transform gallalignment
CREATE TABLE gall_alignment (
  species_id INTEGER NOT NULL,
  alignment_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, alignment_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (alignment_id) REFERENCES alignment(id) ON DELETE CASCADE
);

INSERT INTO gall_alignment (species_id, alignment_id)
SELECT DISTINCT m.species_id, ga.alignment_id
FROM gallalignment ga
JOIN gall_species_mapping m ON m.gall_id = ga.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE gallalignment;

-- Transform galllocation → gall_plant_part
CREATE TABLE gall_plant_part (
  species_id INTEGER NOT NULL,
  plant_part_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, plant_part_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (plant_part_id) REFERENCES location(id) ON DELETE CASCADE
);

INSERT INTO gall_plant_part (species_id, plant_part_id)
SELECT DISTINCT m.species_id, gl.location_id
FROM galllocation gl
JOIN gall_species_mapping m ON m.gall_id = gl.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE galllocation;

-- Transform gallform
CREATE TABLE gall_form (
  species_id INTEGER NOT NULL,
  form_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, form_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (form_id) REFERENCES form(id) ON DELETE CASCADE
);

INSERT INTO gall_form (species_id, form_id)
SELECT DISTINCT m.species_id, gf.form_id
FROM gallform gf
JOIN gall_species_mapping m ON m.gall_id = gf.gall_id
WHERE m.species_id IS NOT NULL;

DROP TABLE gallform;

-- Step 7: Drop obsolete tables
-- Note: gallcolor, gallwalls, gallcells already dropped after transformation
DROP TABLE gall;
DROP TABLE gallspecies;

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Rename tables to snake_case
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

-- Rename location → plant_part (also rename location column → part)
CREATE TABLE plant_part (
  id INTEGER PRIMARY KEY NOT NULL,
  part TEXT UNIQUE NOT NULL,
  description TEXT
);

INSERT INTO plant_part (id, part, description)
SELECT id, location, description
FROM location;

DROP TABLE location;

-- Update gall_plant_part FK reference
CREATE TABLE gall_plant_part_new (
  species_id INTEGER NOT NULL,
  plant_part_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, plant_part_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (plant_part_id) REFERENCES plant_part(id) ON DELETE CASCADE
);

INSERT INTO gall_plant_part_new SELECT * FROM gall_plant_part;
DROP TABLE gall_plant_part;
CREATE TABLE gall_plant_part (
  species_id INTEGER NOT NULL,
  plant_part_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, plant_part_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (plant_part_id) REFERENCES plant_part(id) ON DELETE CASCADE
);
INSERT INTO gall_plant_part SELECT * FROM gall_plant_part_new;
DROP TABLE gall_plant_part_new;

-- Rename host → gallhost
CREATE TABLE gallhost (
  id INTEGER PRIMARY KEY NOT NULL,
  host_species_id INTEGER NOT NULL,
  gall_species_id INTEGER NOT NULL,
  inserted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (host_species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (gall_species_id) REFERENCES species(id) ON DELETE CASCADE
);

INSERT INTO gallhost SELECT * FROM host;
DROP TABLE host;

-- Rename junction tables
CREATE TABLE species_source (
  id INTEGER PRIMARY KEY NOT NULL,
  species_id INTEGER NOT NULL,
  source_id INTEGER NOT NULL,
  description TEXT DEFAULT '' NOT NULL,
  useasdefault INTEGER DEFAULT 0 NOT NULL,
  externallink TEXT DEFAULT '' NOT NULL,
  alias_id INTEGER,
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (source_id) REFERENCES source(id) ON DELETE CASCADE,
  FOREIGN KEY (alias_id) REFERENCES alias(id)
);

INSERT INTO species_source SELECT * FROM speciessource;
DROP TABLE speciessource;

CREATE TABLE species_taxonomy (
  species_id INTEGER NOT NULL,
  taxonomy_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, taxonomy_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id) ON DELETE CASCADE
);

INSERT INTO species_taxonomy SELECT * FROM speciestaxonomy;
DROP TABLE speciestaxonomy;

CREATE TABLE alias_species (
  species_id INTEGER NOT NULL,
  alias_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, alias_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (alias_id) REFERENCES alias(id) ON DELETE CASCADE
);

INSERT INTO alias_species SELECT * FROM aliasspecies;
DROP TABLE aliasspecies;

CREATE TABLE taxonomy_alias (
  taxonomy_id INTEGER NOT NULL,
  alias_id INTEGER NOT NULL,
  PRIMARY KEY (taxonomy_id, alias_id),
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id) ON DELETE CASCADE,
  FOREIGN KEY (alias_id) REFERENCES alias(id) ON DELETE CASCADE
);

INSERT INTO taxonomy_alias SELECT * FROM taxonomyalias;
DROP TABLE taxonomyalias;

CREATE TABLE place_hierarchy (
  place_id INTEGER NOT NULL,
  parent_id INTEGER NOT NULL,
  PRIMARY KEY (place_id, parent_id),
  FOREIGN KEY (place_id) REFERENCES place(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES place(id) ON DELETE CASCADE
);

INSERT INTO place_hierarchy SELECT * FROM placeplace;
DROP TABLE placeplace;

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Remove redundant image columns (small, medium, large)
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

CREATE TABLE image_final (
  id INTEGER PRIMARY KEY NOT NULL,
  species_id INTEGER NOT NULL,
  source_id INTEGER,
  path TEXT UNIQUE NOT NULL,
  creator TEXT,
  attribution TEXT,
  sourcelink TEXT,
  license TEXT,
  licenselink TEXT,
  uploader TEXT,
  lastchangedby TEXT,
  caption TEXT DEFAULT '',
  sort_order INTEGER DEFAULT 0 NOT NULL,
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (source_id) REFERENCES source(id) ON DELETE SET NULL
);

INSERT INTO image_final (id, species_id, source_id, path, creator, attribution, sourcelink, license, licenselink, uploader, lastchangedby, caption, sort_order)
SELECT id, species_id, source_id, path, creator, attribution, sourcelink, license, licenselink, uploader, lastchangedby, caption, sort_order
FROM image;

DROP TABLE image;
CREATE TABLE image (
  id INTEGER PRIMARY KEY NOT NULL,
  species_id INTEGER NOT NULL,
  source_id INTEGER,
  path TEXT UNIQUE NOT NULL,
  creator TEXT,
  attribution TEXT,
  sourcelink TEXT,
  license TEXT,
  licenselink TEXT,
  uploader TEXT,
  lastchangedby TEXT,
  caption TEXT DEFAULT '',
  sort_order INTEGER DEFAULT 0 NOT NULL,
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (source_id) REFERENCES source(id) ON DELETE SET NULL
);

INSERT INTO image SELECT * FROM image_final;
DROP TABLE image_final;

CREATE INDEX image_species_id_sort_order_index ON image(species_id, sort_order);

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Add unique constraints
-- ---------------------------------------------------------------------------
-- Clean up duplicate taxonomy records (remap references first)
-- Find duplicates and remap all references to the lowest ID
UPDATE species_taxonomy
SET taxonomy_id = (
  SELECT MIN(t2.id)
  FROM taxonomy t2
  WHERE t2.name = (SELECT name FROM taxonomy WHERE id = species_taxonomy.taxonomy_id)
    AND t2.parent_id IS (SELECT parent_id FROM taxonomy WHERE id = species_taxonomy.taxonomy_id)
    AND t2.is_placeholder = 0
)
WHERE taxonomy_id IN (
  SELECT id FROM taxonomy
  WHERE id NOT IN (
    SELECT MIN(id)
    FROM taxonomy
    WHERE is_placeholder = 0
    GROUP BY name, parent_id
  )
  AND is_placeholder = 0
);

-- Now safe to delete duplicates
DELETE FROM taxonomy
WHERE id NOT IN (
  SELECT MIN(id)
  FROM taxonomy
  WHERE is_placeholder = 0
  GROUP BY name, parent_id
)
AND is_placeholder = 0;

CREATE UNIQUE INDEX idx_taxonomy_name_parent
  ON taxonomy(name, parent_id)
  WHERE NOT is_placeholder;

-- ---------------------------------------------------------------------------
-- Update cascade behavior
-- ---------------------------------------------------------------------------
PRAGMA foreign_keys = OFF;

-- Update taxonomy.parent_id FK to RESTRICT
CREATE TABLE taxonomy_final (
  id INTEGER PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL,
  parent_id INTEGER,
  is_placeholder BOOLEAN DEFAULT 0 NOT NULL,
  inserted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (parent_id) REFERENCES taxonomy(id) ON DELETE RESTRICT
);

INSERT INTO taxonomy_final (id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at)
SELECT id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at
FROM taxonomy;
DROP INDEX idx_taxonomy_name_parent;
DROP TABLE taxonomy;
CREATE TABLE taxonomy (
  id INTEGER PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL,
  parent_id INTEGER,
  is_placeholder BOOLEAN DEFAULT 0 NOT NULL,
  inserted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (parent_id) REFERENCES taxonomy(id) ON DELETE RESTRICT
);
INSERT INTO taxonomy (id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at)
SELECT id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at
FROM taxonomy_final;
DROP TABLE taxonomy_final;

CREATE UNIQUE INDEX idx_taxonomy_name_parent
  ON taxonomy(name, parent_id)
  WHERE NOT is_placeholder;

-- Update species_taxonomy.taxonomy_id FK to RESTRICT
CREATE TABLE species_taxonomy_final (
  species_id INTEGER NOT NULL,
  taxonomy_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, taxonomy_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id) ON DELETE RESTRICT
);

INSERT INTO species_taxonomy_final SELECT * FROM species_taxonomy;
DROP TABLE species_taxonomy;
CREATE TABLE species_taxonomy (
  species_id INTEGER NOT NULL,
  taxonomy_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, taxonomy_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id) ON DELETE RESTRICT
);
INSERT INTO species_taxonomy SELECT * FROM species_taxonomy_final;
DROP TABLE species_taxonomy_final;

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Add foreign key indexes for performance
-- ---------------------------------------------------------------------------
CREATE INDEX idx_species_abundance_id ON species(abundance_id);
CREATE INDEX idx_species_taxonomy_id ON species(taxonomy_id);
CREATE INDEX idx_taxonomy_parent_id ON taxonomy(parent_id);
CREATE INDEX idx_gallhost_host_species_id ON gallhost(host_species_id);
CREATE INDEX idx_gallhost_gall_species_id ON gallhost(gall_species_id);
CREATE INDEX idx_species_source_species_id ON species_source(species_id);
CREATE INDEX idx_species_source_source_id ON species_source(source_id);
CREATE INDEX idx_species_taxonomy_species_id ON species_taxonomy(species_id);
CREATE INDEX idx_species_taxonomy_taxonomy_id ON species_taxonomy(taxonomy_id);
CREATE INDEX idx_alias_species_species_id ON alias_species(species_id);
CREATE INDEX idx_alias_species_alias_id ON alias_species(alias_id);
CREATE INDEX idx_taxonomy_alias_taxonomy_id ON taxonomy_alias(taxonomy_id);
CREATE INDEX idx_taxonomy_alias_alias_id ON taxonomy_alias(alias_id);
CREATE INDEX idx_place_hierarchy_place_id ON place_hierarchy(place_id);
CREATE INDEX idx_place_hierarchy_parent_id ON place_hierarchy(parent_id);
CREATE INDEX idx_host_range_species_id ON host_range(species_id);
CREATE INDEX idx_host_range_place_id ON host_range(place_id);
CREATE INDEX idx_gall_range_exclusion_species_id ON gall_range_exclusion(species_id);
CREATE INDEX idx_gall_range_exclusion_place_id ON gall_range_exclusion(place_id);
CREATE INDEX idx_gall_color_species_id ON gall_color(species_id);
CREATE INDEX idx_gall_color_color_id ON gall_color(color_id);
CREATE INDEX idx_gall_walls_species_id ON gall_walls(species_id);
CREATE INDEX idx_gall_walls_walls_id ON gall_walls(walls_id);
CREATE INDEX idx_gall_cells_species_id ON gall_cells(species_id);
CREATE INDEX idx_gall_cells_cells_id ON gall_cells(cells_id);
CREATE INDEX idx_gall_season_species_id ON gall_season(species_id);
CREATE INDEX idx_gall_season_season_id ON gall_season(season_id);
CREATE INDEX idx_gall_shape_species_id ON gall_shape(species_id);
CREATE INDEX idx_gall_shape_shape_id ON gall_shape(shape_id);
CREATE INDEX idx_gall_texture_species_id ON gall_texture(species_id);
CREATE INDEX idx_gall_texture_texture_id ON gall_texture(texture_id);
CREATE INDEX idx_gall_alignment_species_id ON gall_alignment(species_id);
CREATE INDEX idx_gall_alignment_alignment_id ON gall_alignment(alignment_id);
CREATE INDEX idx_gall_plant_part_species_id ON gall_plant_part(species_id);
CREATE INDEX idx_gall_plant_part_plant_part_id ON gall_plant_part(plant_part_id);
CREATE INDEX idx_gall_form_species_id ON gall_form(species_id);
CREATE INDEX idx_gall_form_form_id ON gall_form(form_id);
CREATE INDEX idx_image_species_id ON image(species_id);
CREATE INDEX idx_image_source_id ON image(source_id);

COMMIT;
