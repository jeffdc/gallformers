-- Up

PRAGMA foreign_keys=OFF;

-- the texture and location mapping tables are missing a CASCADE DELETE, add them
CREATE TABLE galltexture__ (
    gall_id    INTEGER NOT NULL,
    texture_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (texture_id) REFERENCES texture (id) ON DELETE CASCADE,
    PRIMARY KEY (gall_id, texture_id)
);
INSERT INTO galltexture__ (gall_id, texture_id)
    SELECT gall_id, texture_id 
    FROM galltexture;
DROP TABLE galltexture;
ALTER TABLE galltexture__ RENAME TO galltexture;

CREATE TABLE galllocation__ (
    gall_id     INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (location_id) REFERENCES location (id) ON DELETE CASCADE,
    PRIMARY KEY (gall_id, location_id)
);
INSERT INTO galllocation__ (gall_id, location_id)
    SELECT gall_id, location_id 
    FROM galllocation;
DROP TABLE galllocation;
ALTER TABLE galllocation__ RENAME TO galllocation;

-- add Gall Form metadata for #160
CREATE TABLE form (
    id          INTEGER PRIMARY KEY
                        NOT NULL,
    form        TEXT    UNIQUE
                        NOT NULL,
    description TEXT
);

CREATE TABLE gallform (
    id       INTEGER PRIMARY KEY NOT NULL,
    gall_id  INTEGER,
    form_id INTEGER,
    FOREIGN KEY (gall_id) REFERENCES gall (id) ON DELETE CASCADE,
    FOREIGN KEY (form_id) REFERENCES form (id) ON DELETE CASCADE
);

PRAGMA foreign_keys=ON;

INSERT INTO form (id, form, description) VALUES (NULL, 'witches broom', 'A dense profusion of buds or shoots on woody plants.');
INSERT INTO form (id, form, description) VALUES (NULL, 'leaf edge roll', 'A tight roll of tissue only at the edge of a leaf, of varying thickness.');
INSERT INTO form (id, form, description) VALUES (NULL, 'leaf curl', 'Broad deformation of the lamina of a leaf, pulling the edges in. Typically irregular and sometimes causing entire leaves to roll up. Often accompanied by discoloration.');
INSERT INTO form (id, form, description) VALUES (NULL, 'leaf blister', 'Localized distortions of the leaf lamina, typically creating a cup opening toward the lower side of the leaf.');
INSERT INTO form (id, form, description) VALUES (NULL, 'lead edge fold', 'A single layer of the leaf edge folded back against the leaf.');
INSERT INTO form (id, form, description) VALUES (NULL, 'scale', 'An herbivorous insect of the superfamily Coccoidea. The post-reproductive females of the family Kermesidae have thin, globular, hollow shells fixed in place on their host.');
INSERT INTO form (id, form, description) VALUES (NULL, 'rust', 'Plant deformations caused by fungi in the order Pucciniales. They cause swelling and curling of stems and petioles and blisters on leaves, easily recognizable for their bright orange coloration, seen in characteristic rings.');
INSERT INTO form (id, form, description) VALUES (NULL, 'tapered swelling', 'An increase in the diameter of a stem, petiole, etc, gradual from either side of the gall.');
INSERT INTO form (id, form, description) VALUES (NULL, 'abrupt swelling', 'A significant increase in the diameter of a stem, petiole, etc, emerging directly from unaffected tissue. Sometimes encircling the stem, other times emerging only from one side.');
INSERT INTO form (id, form, description) VALUES (NULL, 'hidden cell', 'A gall making no externally visible change to the host (typically in a stem or fruit) until the inducer chews its egress hole.');
INSERT INTO form (id, form, description) VALUES (NULL, 'stem club', 'A substantial enlargement of the growing tip of a woody plant, tapering more or less gradually from normal stem width below it, blunt or rounded above.');
INSERT INTO form (id, form, description) VALUES (NULL, 'oak apple', 'A spherical or near-spherical gall with thin outer walls, a single central larval cell surrounded by either spongy tissue or fine radiating fibers.');
INSERT INTO form (id, form, description) VALUES (NULL, 'leaf spot', 'A flat (never more than slightly thicker than the normal leaf), typically circular spot on the lamina of the leaf, sometimes with distinct rings of darker and lighter coloration (eye spots). Fungal leaf spots often have small dots above; midge spots have an exposed larva below.');
INSERT INTO form (id, form, description) VALUES (NULL, 'pocket', 'A structure formed by pinching the leaf lamina together into a narrow opening (a point or line) and stretching it into various forms, from beads to sacks to spindles to long purses. The walls may or may not be thickened relative to the normal leaf.');

-- various changes for #160 updating descriptions, adding, remapping, deleting other gall metadata properties
-- shape
UPDATE shape SET description = 'Perfectly round, of equal diameter in every dimension,' WHERE shape = 'sphere';
UPDATE shape SET description = 'Elongated, round in the middle and narrowed above and below, often pointed above.' WHERE shape = 'spindle';
UPDATE shape SET description = 'Small galls with structure entirely obscured by long woolly fibers.' WHERE shape = 'tuft';
UPDATE shape SET description = 'Wide and round at the base, tapering on all sides to a point above.' WHERE shape = 'conical';
UPDATE shape SET description = 'The gall is rounded but not perfectly spherical (including ovate, ellipsoid, irregular, etc).' WHERE shape = 'globular';
UPDATE shape SET description = 'The gall is a narrow line in shape for much of its form. Often seen as extensions of leaf veins, sometimes widening at a club or spindle-like end. ' WHERE shape = 'linear';
INSERT INTO shape (id, shape, description) VALUES (NULL, 'hemispherical', 'Perfectly round or nearly so, but only in one half of a full sphere (often divided by a leaf)');
INSERT INTO shape (id, shape, description) VALUES (NULL,  'cluster', 'Individual galls nearly always found in numbers, often pressing together and flattening against each other.');
INSERT INTO shape (id, shape, description) VALUES (NULL,  'rosette', 'A layered bunch of leaves or similar.'); 
INSERT INTO shape (id, shape, description) VALUES (NULL,  'numerous', 'Typically found in large numbers (>10) scattered across every leaf or other plant part on which they occur, but not clustered together.');
INSERT INTO shape (id, shape, description) VALUES (NULL, 'spangle', 'A flat, circular disc-like structure. Often with a central umbo.');
INSERT INTO shape (id, shape, description) VALUES (NULL, 'cup', 'A circular structure with walls enclosing a volume, open from above.');
DELETE FROM shape where shape IN ('compact');

-- texture
INSERT INTO texture (id, texture, description) VALUES (NULL, 'wrinkly', 'The surface of the gall is often irregular or sunken into folds.');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'ribbed', 'The external surface has linear grooves and ridges, typically running from the bottom to top of the gall.');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'spotted', 'The gall contains distinct spots of a different color than its primary surface.');
UPDATE texture SET description = 'The hair covering the gall is short, soft, and dense. May or may not obscure the color and texture of the surface, but not concealing its shape.' WHERE texture = 'pubsecent';
UPDATE texture SET description = 'The gall has some hairs, whether that is only a sparse pubescence of short hairs (even inherited from the host plant rather than produced specifically for the gall) or a dense coat of long wool that obscures the gall or stiff bristles (as in Acraspis erinacei).' WHERE texture = 'hairy';
UPDATE texture SET description = 'The hair covering the gall is long, soft, and thick, often concealing the surface and structure of the gall completely.', texture = 'woolly' WHERE texture = 'wooly';
UPDATE texture SET description = 'The gall has no visible hairs at all. Note that late in the season, hairs may wear off some galls.' WHERE texture = 'hairless';
UPDATE texture SET description = 'The distinctive "sugary" crystalline texture formed by many eriophyid mites.' WHERE texture = 'erineum';
UPDATE texture SET description = 'The upper tip of the gall has a ring, often raised and sometimes containing a central umbo, scar, or nipple.' WHERE texture = 'areola';
UPDATE texture SET description = 'The surface of the gall is covered with some kind of slight protrusions.' WHERE texture = 'bumpy';
UPDATE texture SET description = 'The gall is surrounded by or composed of a profusion of altered leaves, bud scales, or similar structures.' WHERE texture = 'leafy';
UPDATE texture SET description = 'Multiple colors on the surface of the gall mix irregularly.' WHERE texture = 'mottled';
UPDATE texture SET description = 'The surface of the gall is covered in dots, often red, that secrete sticky resin.' WHERE texture = 'resinous dots';
UPDATE texture SET description = 'The gall is covered in sharp spines, prickles, etc.' WHERE texture = 'spiky/thorny';
UPDATE texture SET description = 'The walls of the gall (when fresh) are juicy if cut.' WHERE texture = 'succulent';
UPDATE texture SET description = 'Covered in a whitish layer of fine powder or wax that can be easily rubbed off.' WHERE texture = 'glaucous';
UPDATE texture SET description = 'Galls releasing sugary solution. Often visible as a shiny wetness, but can be more apparent in the ants and wasps it attracts.', texture = 'honeydew' WHERE texture = 'sticky'; 
UPDATE texture SET description = 'The gall is hard and incompressable to the touch, generally because they are woody, thick-walled, but sometimes with an almost plastic-like texture.' WHERE texture = 'stiff';
-- remap felt (1) to pubsecent (2)
UPDATE galltexture SET texture_id = 2 WHERE texture_id = 1;
DELETE FROM texture where texture IN ('felt', 'waxy');

-- cells
INSERT INTO cells (id, cells, description) VALUES (NULL, 'not applicable', 'Galls formed by fungi, mites, viruses, aphids, etc, do not have larval cells.');
UPDATE cells SET cells = 'monothalamous', description = 'One cell or chamber containing a larva or larvae of the inducing insect is present within the gall if single, or within each gall in a cluster. May include galls with empty false chambers.' WHERE cells = 'single';
UPDATE cells SET cells = 'polythalamous', description = 'More than one cell or chamber containing a single larva of the inducing insect is present within the gall if single, or within each gall in a cluster. Does not include galls with empty false chambers.' WHERE cells = '2-10';
UPDATE cells SET description = 'The cell containing the larva is loose within an open cavity formed by the walls of the gall, free to roll around when disturbed.' WHERE cells = 'free-rolling';
-- remap cells:cluster to the new shape:cluster (8)
INSERT INTO gallshape (gall_id, shape_id)
  SELECT gall_id, 8
    FROM gallcells AS gc
          INNER JOIN
          cells AS c ON c.id = gc.cells_id
    WHERE c.cells = 'cluster';
-- remap cells:scattered to the new shape:numerous
INSERT INTO gallshape (gall_id, shape_id)
  SELECT gall_id, s.id
    FROM gallcells AS gc
          INNER JOIN
          cells AS c ON c.id = gc.cells_id
          JOIN shape as s
    WHERE c.cells = 'scattered' AND s.shape = 'numerous';
DELETE FROM cells where cells IN ('scattered', 'cluster');

-- walls
UPDATE walls SET description = 'When the gall is cut open, it reveals an interior matching the shape of the exterior. The walls are not thick enough to conceal the shape of the chamber within.' WHERE walls = 'thin';
UPDATE walls SET description = 'When the gall is cut open, the interior is full of tissue except for the small chamber containing the larvae. The walls are thick enough that the shape of this chamber could (but may not necessarily) differ from the shape of the exterior.' WHERE walls = 'thick';
UPDATE walls SET description = 'When the gall is cut open, there are two chambers, only one of which contains larvae.' WHERE walls = 'false chamber';
UPDATE walls SET description = 'A central larval cell held in place by many thin, thread-like fibers' WHERE walls = 'radiating-fibers';
UPDATE walls SET description = 'Space between larval cell and outer walls filled by a spongy substance of a distinct composition from either.' WHERE walls = 'spongy';
DELETE FROM walls where walls IN ('broken');

-- alignment
UPDATE alignment SET description = 'The gall is at an angle from the surface it is attached to.' WHERE alignment = 'leaning';
UPDATE alignment SET description = 'The gall stands at nearly 90 degrees from the surface it is attached to. Includes the majority of detachable galls.' WHERE alignment = 'erect';
UPDATE alignment SET description = 'The gall is integral with the surface it is attached to. It may not be flat, but it does not protrude out from the surface leaving an angled gap. Includes nearly all non-detachable galls.' WHERE alignment = 'integral';
UPDATE alignment SET description = 'The gall is only attached at its base but lays nearly flat along the surface it is attached to for most of its length.' WHERE alignment = 'supine';
UPDATE alignment SET description = 'The gall may have any alignment, but its tip is conspicuously curved toward the ground from whatever the primary orientation of the gall is.' WHERE alignment = 'drooping';

-- for #154 add caption for images
ALTER TABLE image ADD COLUMN caption TEXT DEFAULT '';

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
