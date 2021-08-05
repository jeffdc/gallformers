-- Up

-- fix typo
UPDATE form SET form='leaf edge fold' WHERE form = 'lead edge fold';

-- new terms for #231
INSERT INTO texture (id, texture, description) VALUES (NULL, 'ruptured/split', 'Galls emerge from the host plant through a visible rupture in the tissue they form in. Typically observed in stem and occasionally midrib galls. Split edges may not be apparent if galls are large.');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'mealy', 'Galls appear to be coated in a coarse, granular texture, like flour or cornmeal. This appearance may be caused by a fine bumpiness of the solid exterior of the gall or a layer of short hairs, such that the mealiness may or may not be removable.');
INSERT INTO form (id, form, description) VALUES (NULL, 'modified capitulum', 'Flowers in Asteraceae are clustered into tight structures called "capitula", which themselves resemble a flower at first glance. Developing capitula have the overall appearance of flower buds, and are sometimes called "flower buds" or "inflorescence buds" in technical and popular literature. Several gall-formers develop within developing capitula. These occupied capitula are referred to as galls, even when there is not an obvious external difference. There are usually at least some external clues (arrested development vs. nearby capitula, color change, change in texture, swelling, etc.), however.');
INSERT INTO walls (id, walls, description) VALUES (NULL, 'mycelium lining', 'Some galls, sometimes called "ambrosia" type galls, have walls with a fungal inner lining. Examples include those produced by Asteromyia and some Asphondylia species. In some cases the developing midge larva feeds on the fungus; in other cases the role of the fungus is unknown. It may be important for inducing the gall.');
INSERT INTO form (id, form, description) VALUES (NULL, 'leaf snap', 'Two distinct, otherwise typical host leaves are joined together around a gall cell');

-- add defintions for locations and textures so that we can generate the FilterGuide page rather than manually keep it in synch
UPDATE location SET description = 'Galls located exclusively in the inside of the intersection between the lateral veins and main veins of the leaf.' WHERE location = 'at leaf vein angles';
UPDATE location SET description = 'Galls are not specifically located only on leaf veins. Galls with this term may sometimes incidentally appear close to veins.' WHERE location = 'between leaf veins';
UPDATE location SET description = 'Galls are located in buds (often found where branches intersect the stem, can be mistaken for stem galls).' WHERE location = 'bud';
UPDATE location SET description = 'Galls are located in flowers. Note this is a botanical term referring to reproductive structures, and some flowers (eg oak catkins) may not be obviously recognizable as such.' WHERE location = 'flower';
UPDATE location SET description = 'Galls are located in fruit. This is a botanical term referring to seed-bearing structures, and some fruit (eg maple samaras) may not be obviously recognizable as such.' WHERE location = 'fruit';
UPDATE location SET description = 'Galls are located exclusively on the thickest, central vein of the leaf.' WHERE location = 'leaf midrib';
UPDATE location SET description = 'Galls are located on the lower (abaxial) side of the leaf.' WHERE location = 'lower leaf';
UPDATE location SET description = 'Galls are located exclusively on or very close to the veins of the leaf, including but not limited to the midrib.' WHERE location = 'on leaf veins';
UPDATE location SET description = 'Galls are located on the part of the midrib between the leaf and the stem.' WHERE location = 'petiole';
UPDATE location SET description = 'Galls are located on the roots of the plant or near the base of the stem.' WHERE location = 'root';
UPDATE location SET description = 'Galls are located anywhere in or on the stem (except within buds, which are occasionally deformed by gall inducers enough to appear as stem galls).' WHERE location = 'stem';
UPDATE location SET description = 'Galls are located on the upper (adaxial) side of the leaf.' WHERE location = 'upper leaf';
UPDATE location SET description = 'Galls are exclusively located around the edge of the leaf, often curled or folded.' WHERE location = 'leaf edge';

UPDATE texture SET description = 'The upper tip of the gall has a ring, often raised and sometimes containing a central umbo, scar, or nipple.' WHERE texture = 'areola';        
UPDATE texture SET description = 'The surface of the gall is covered with some kind of slight protrusions.' WHERE texture = 'bumpy';         
UPDATE texture SET description = 'The distinctive “sugary” crystalline texture formed by many eriophyid mites.' WHERE texture = 'erineum';       
UPDATE texture SET description = 'Covered in a whitish layer of fine powder or wax that can be easily rubbed off.' WHERE texture = 'glaucous';      
UPDATE texture SET description = 'The gall has no visible hairs at all. Note that late in hte season, hairs may wear off some galls.' WHERE texture = 'hairless';      
UPDATE texture SET description = 'The gall has some hairs, whether that is only a sparse pubescence of short hairs or a dense coat of long wool that obscures the gall or stiff bristles (as in Acraspis erinacei).' WHERE texture = 'hairy';         
UPDATE texture SET description = 'Galls releasing sugary solution. Often visible as a shiny wetness, but can be more apparent in the ants and wasps it attracts.' WHERE texture = 'honeydew';      
UPDATE texture SET description = 'The gall is surrounded by or composed of a profusion of altered leaves, bud scales, or similar structures.' WHERE texture = 'leafy';         
UPDATE texture SET description = 'Multiple colors on the surface of the gall mix irregularly.' WHERE texture = 'mottled';       
UPDATE texture SET description = 'The hair covering the gall is short, soft, and dense. May or may not obscure the color and texture of the surface, but not concealing its shape.' WHERE texture = 'pubescent';     
UPDATE texture SET description = 'The surface of the gall is covered in dots, often red, that secret sticky resin.' WHERE texture = 'resinous dots'; 
UPDATE texture SET description = 'The external surface has linear grooves and ridges, typically running from the bottom to the top of the gall.' WHERE texture = 'ribbed';        
UPDATE texture SET description = 'The gall is covered in sharp spines, prickles, etc.' WHERE texture = 'spiky/thorny';  
UPDATE texture SET description = 'The gall contains distinct spots of a different color than its primary surface.' WHERE texture = 'spotted';       
UPDATE texture SET description = 'The gall is hard and incompressable to the touch, generally because they are woody, thick-walled, but sometimes with an almost plastic-like texture.' WHERE texture = 'stiff';         
UPDATE texture SET description = 'The walls of the gall (when fresh) are juicy if cut.' WHERE texture = 'succulent';     
UPDATE texture SET description = 'The hair covering the gall is long, soft, and thick, often concealing the surface and structure of the gall completely.' WHERE texture = 'woolly';        
UPDATE texture SET description = 'The surface of the gall is often irregular or sunken into folds.' WHERE texture = 'wrinkly';       

-- add FR-PM as a region. It is included in Canadian plant data.
INSERT INTO place (type, code, name) VALUES ("province", "PM", "Saint Pierre and Miquelon");

VACUUM;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
