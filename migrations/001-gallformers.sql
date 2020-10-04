-- Up
CREATE TABLE gall(
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT UNIQUE NOT NULL , 
    commonname TEXT,
    genus TEXT NOT NULL ,
    family TEXT NOT NULL,
    description TEXT,
    location TEXT,
    detachable INTEGER,
    texture TEXT,
    alignment TEXT,
    walls TEXT,
    abundance TEXT
);

CREATE TABLE host(
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT UNIQUE NOT NULL , 
    commonname TEXT,
    genus TEXT NOT NULL ,
    family TEXT NOT NULL 
    );

CREATE TABLE gallhost(
    gallid INTEGER,
    hostid INTEGER,
    FOREIGN KEY(gallid) REFERENCES gall(id),
    FOREIGN KEY(hostid) REFERENCES host(id)
);

CREATE TABLE source(
    id INTEGER PRIMARY KEY NOT NULL,
    title TEXT UNIQUE NOT NULL , 
    author TEXT,
    pubdate TEXT, -- ISO8601 strings ("YYYY-MM-DD HH:MM:SS.SSS")
    link TEXT,
    citation TEXT
);

CREATE TABLE gallsource(
    gallid INTEGER,
    sourceid INTEGER,
    FOREIGN KEY(gallid) REFERENCES gall(id),
    FOREIGN KEY(sourceid) REFERENCES source(id)
);

INSERT INTO "gall" VALUES(NULL, 'Andricus apiarium', NULL, 'Andricus', 'Cynipidae', 
                           'Solitary, sessile, on underside of leaf close to edge in October, shaped like an old-fashioned straw beehive, white or pinkish, measuring up to 4.6 mm broad by 4.0 mm high. Inside is a large cavity with a transverse larval cell at very base. During the winter on the ground the outer fleshy layer shrivels and the gall becomes more cylindrical.',
                           'leaf', '1', 'waxy', '', '', 'uncommon');
                           
INSERT INTO "host" VALUES(NULL, 'Quercus alba', 'White Oak', 'Quercus', 'Fagaceae');
INSERT INTO "host" VALUES(NULL, 'Quercus phellos', 'Willow Oak', 'Quercus', 'Fagaceae');
INSERT INTO "host" VALUES(NULL, 'Quercus stellata', 'Post Oak', 'Quercus', 'Fagaceae');

INSERT INTO "gallhost" VALUES((SELECT id FROM host WHERE name = 'Quercus alba'), 
                              (SELECT id from gall WHERE name = 'Andricus apiarium')
                             );

INSERT INTO "source" VALUES(NULL, 'New American Cynipid Wasps From Galls', 'Weld, L.H.', '1952-01-01 00:00;00.000', 
                             'https://www.biodiversitylibrary.org/page/15672479#page/372/mode/1up',
                             'Weld, Lewis H. "New American cynipid wasps from galls." Proceedings of the United States National Museum (1952).');
INSERT INTO "gallsource" VALUES((SELECT id from gall WHERE name = 'Andricus apiarium'),
                                (SELECT id from source WHERE title = 'New American Cynipid Wasps From Galls')
                               );

-- Down
DROP TABLE gallsource;
DROP TABLE source;
DROP TABLE gallhost;
DROP TABLE host;
DROP TABLE gall;