-- Up

-- Add in the glossary table and all of the data that we have so far.
PRAGMA foreign_keys=OFF;

CREATE TABLE glossary (
    id INTEGER PRIMARY KEY NOT NULL,
    word TEXT UNIQUE NOT NULL,
    definition TEXT NOT NULL,
    urls TEXT NOT NULL -- Tab separated list of URLs (tabs since commas can occur in URLs but tabs cannot)
);

INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'binomial nomenclature', '("two-term naming system"), also called binominal nomenclature ("two-name naming system") or binary nomenclature, is a formal system of naming species of living things by giving each a name composed of two parts, both of which use Latin grammatical forms, although they can be based on words from other languages. Such a name is called a binomial name (which may be shortened to just "binomial"), a binomen, binominal name or a scientific name; more informally it is also called a Latin name. The first part of the name – the generic name – identifies the genus to which the species belongs, while the second part – the specific name or specific epithet – identifies the species within the genus.', 'https://en.wikipedia.org/wiki/Binomial_nomenclature');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'catkin', 'A slim, cylindrical flower cluster (a spike), with inconspicuous or no petals.', 'https://en.wikipedia.org/wiki/Catkin');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'cecidiology', 'A branch of biology that is concerned with the galls produced on plants by insects, mites, and fungi.', 'https://www.merriam-webster.com/dictionary/cecodiology');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'fusiform', 'Spindle-like shape that is wide in the middle and tapers at both ends.', 'https://en.wikipedia.org/wiki/Fusiform');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'gall', 'Plant galls are abnormal outgrowths[1] of plant tissues, similar to benign tumors or warts in animals. They can be caused by various parasites, from viruses, fungi and bacteria, to other plants, insects and mites. Plant galls are often highly organized structures so that the cause of the gall can often be determined without the actual agent being identified. This applies particularly to some insect and mite plant galls.', 'https://en.wikipedia.org/wiki/Gall	https://www.merriam-webster.com/dictionary/gall');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'genus', '(plural genera) is a taxonomic rank used in the biological classification of living and fossil organisms, as well as viruses,[1] in biology. In the hierarchy of biological classification, genus comes above species and below family. In binomial nomenclature, the genus name forms the first part of the binomial species name for each species within the genus.', 'https://en.wikipedia.org/wiki/Genus');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'host', 'A plant on which a gall is formed.', 'https://www.merriam-webster.com/dictionary/host');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'inquiline', 'Specialized moths, weevils, beetles, wasps, and other insects that feed on gall tissue.', 'https://en.wikisource.org/wiki/The_Encyclopedia_Americana_(1920)/Inquiline	https://en.wikipedia.org/wiki/Inquiline	https://www.merriam-webster.com/dictionary/inquiline');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'monothalamous', 'Single-chambered.', 'https://www.thefreedictionary.com/monothalamous');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'papilla', 'A small projecting body part similar to a nipple in form.', 'https://www.merriam-webster.com/dictionary/papilla');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'papillose', 'Full of papilla.', 'https://en.wikipedia.org/wiki/Parasitism');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'parasitism', 'A symbiotic relationship between species, where one organism, the parasite, lives on or inside another organism, the host, causing it some harm, and is adapted structurally to this way of life.', 'https://en.wikipedia.org/wiki/Parasitism	https://biologydictionary.net/parasitism/');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'pedicel', 'A narrow attachment point for a gall to its host.', 'https://www.merriam-webster.com/dictionary/pedicel');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'peduncle', 'A narrow part by which some larger part or the whole body of an organism is attached.', 'https://www.merriam-webster.com/dictionary/peduncle	https://en.wikipedia.org/wiki/Peduncle_(anatomy)');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'petiole', 'The stalk that attaches the leaf blade to the stem.', 'https://en.wikipedia.org/wiki/Petiole_(botany)');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'prolate', 'A shape where the distance between the poles is longer than the equatorial diameter.', 'https://www.thefreedictionary.com/prolate');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'pubescent', 'Covered with short hairs or soft down.', 'https://www.thefreedictionary.com/pubescent');
INSERT INTO glossary (id, word, definition, urls) VALUES (NULL, 'sessile', 'Attached directly by the base : not raised upon a stalk or peduncle.', 'https://www.merriam-webster.com/dictionary/sessile	https://en.wikipedia.org/wiki/Sessility_%28botany%29');


PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;

DROP TABLE glossary;

PRAGMA foreign_keys=ON;
