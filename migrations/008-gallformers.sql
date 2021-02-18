-- Up

PRAGMA foreign_keys=OFF;

-- Simple changes adding gall descriptors per #75
INSERT INTO location (id, location, description) VALUES (NULL, 'leaf edge', '');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'erineum', '');
INSERT INTO color (id, color) VALUES (NULL, 'green');
INSERT INTO color (id, color) VALUES (NULL, 'black');
INSERT INTO color (id, color) VALUES (NULL, 'purple');
INSERT INTO color (id, color) VALUES (NULL, 'tan');
INSERT INTO alignment (id, alignment) VALUES (NULL, 'leaning', '');

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;

DELETE FROM location WHERE location = 'leaf edge';
DELETE FROM texture WHERE texture = 'erineum';
DELETE FROM color WHERE color = 'green';
DELETE FROM color WHERE color = 'black';
DELETE FROM color WHERE color = 'purple';
DELETE FROM color WHERE color = 'tan';
DELETE FROM alignment WHERE alignment = 'leaning';

PRAGMA foreign_keys=ON;
