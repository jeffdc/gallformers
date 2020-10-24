PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
-- CREATE TABLE "Location" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "loc" TEXT NOT NULL,
--     "description" TEXT NOT NULL
-- )

INSERT INTO Location VALUES(1,'bud','');
INSERT INTO Location VALUES(2,'petiole','');
INSERT INTO Location VALUES(3,'root','');
INSERT INTO Location VALUES(4,'upper leaf','');
INSERT INTO Location VALUES(5,'lower leaf','');
INSERT INTO Location VALUES(6,'leaf midrib','');
INSERT INTO Location VALUES(7,'on leaf veins','');
INSERT INTO Location VALUES(8,'between leaf veins','');
INSERT INTO Location VALUES(9,'at leaf vein angles','');
INSERT INTO Location VALUES(10,'flower','');
INSERT INTO Location VALUES(11,'fruit','');

-- CREATE TABLE "Texture" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "texture" TEXT NOT NULL,
--     "description" TEXT NOT NULL
-- )
INSERT INTO Texture VALUES(1,'felt','');
INSERT INTO Texture VALUES(2,'pubescent','');
INSERT INTO Texture VALUES(3,'stiff','');
INSERT INTO Texture VALUES(4,'wooly','');
INSERT INTO Texture VALUES(5,'sticky','');
INSERT INTO Texture VALUES(6,'bumpy','');
INSERT INTO Texture VALUES(7,'waxy','');
INSERT INTO Texture VALUES(8,'areola','');
INSERT INTO Texture VALUES(9,'glaucous','');
INSERT INTO Texture VALUES(10,'hairy','');
INSERT INTO Texture VALUES(11,'hairless','');
INSERT INTO Texture VALUES(12,'resinous dots','');

-- CREATE TABLE "Color" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "color" TEXT NOT NULL
-- )
INSERT INTO Color VALUES(1,'brown');
INSERT INTO Color VALUES(2,'gray');
INSERT INTO Color VALUES(3,'orange');
INSERT INTO Color VALUES(4,'pink');
INSERT INTO Color VALUES(5,'red');
INSERT INTO Color VALUES(6,'white');
INSERT INTO Color VALUES(7,'yellow');

-- CREATE TABLE "Walls" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "walls" TEXT NOT NULL,
--     "description" TEXT NOT NULL
-- )
INSERT INTO Walls VALUES(1,'thin','');
INSERT INTO Walls VALUES(2,'thick','');
INSERT INTO Walls VALUES(3,'broken','');
INSERT INTO Walls VALUES(4,'false chamber','');

-- CREATE TABLE "Cells" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "cells" TEXT NOT NULL,
--     "description" TEXT NOT NULL
-- )
INSERT INTO Cells VALUES(1,'single','');
INSERT INTO Cells VALUES(2,'cluster','');
INSERT INTO Cells VALUES(3,'scattered','');
INSERT INTO Cells VALUES(4,'2-10','');

-- CREATE TABLE "Alignment" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "alignment" TEXT NOT NULL,
--     "description" TEXT NOT NULL
-- )
INSERT INTO Alignment VALUES(1,'erect','');
INSERT INTO Alignment VALUES(2,'drooping','');
INSERT INTO Alignment VALUES(3,'supine','');
INSERT INTO Alignment VALUES(4,'integral','');

-- CREATE TABLE "Shape" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "shape" TEXT NOT NULL,
--     "description" TEXT NOT NULL
-- )
INSERT INTO Shape VALUES(1,'compact','');
INSERT INTO Shape VALUES(2,'conical','');
INSERT INTO Shape VALUES(3,'globular','');
INSERT INTO Shape VALUES(4,'linear','');
INSERT INTO Shape VALUES(5,'sphere','');
INSERT INTO Shape VALUES(6,'tuft','');

-- CREATE TABLE "Abundance" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "abundance" TEXT NOT NULL,
--     "description" TEXT NOT NULL,
--     "reference" TEXT
-- )

-- CREATE TABLE "Family" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "name" TEXT NOT NULL,
--     "description" TEXT NOT NULL
-- )
INSERT INTO Family VALUES(1,'Apocynaceae','Plant');
INSERT INTO Family VALUES(2,'Sapotaceae','Plant');
INSERT INTO Family VALUES(3,'Onagraceae','Plant');
INSERT INTO Family VALUES(4,'Cecidomyiidae','Midge');
INSERT INTO Family VALUES(5,'Rhamnaceae','Plant');
INSERT INTO Family VALUES(6,'Theaceae','Plant');
INSERT INTO Family VALUES(7,'Asphodelaceae','Plant');
INSERT INTO Family VALUES(8,'Altingiaceae','Plant');
INSERT INTO Family VALUES(9,'Salicaceae','Plant');
INSERT INTO Family VALUES(10,'Hamamelidaceae','Plant');
INSERT INTO Family VALUES(11,'Pinaceae','Plant');
INSERT INTO Family VALUES(12,'Boraginaceae','Plant');
INSERT INTO Family VALUES(13,'Malvaceae','Plant');
INSERT INTO Family VALUES(14,'Ranunculaceae','Plant');
INSERT INTO Family VALUES(15,'Amaranthaceae','Plant');
INSERT INTO Family VALUES(16,'Buxaceae','Plant');
INSERT INTO Family VALUES(17,'Meliaceae','Plant');
INSERT INTO Family VALUES(18,'Santalaceae','Plant');
INSERT INTO Family VALUES(19,'Rosaceae','Plant');
INSERT INTO Family VALUES(20,'Euphorbiaceae','Plant');
INSERT INTO Family VALUES(21,'Acanthaceae','Plant');
INSERT INTO Family VALUES(22,'Solanaceae','Plant');
INSERT INTO Family VALUES(23,'Nyssaceae','Plant');
INSERT INTO Family VALUES(24,'Cannabaceae','Plant');
INSERT INTO Family VALUES(25,'Asteraceae','Plant');
INSERT INTO Family VALUES(26,'Oleaceae','Plant');
INSERT INTO Family VALUES(27,'Rhytismataceae','Fungus');
INSERT INTO Family VALUES(28,'Sesiidae','Moth');
INSERT INTO Family VALUES(29,'Cupressaceae','Plant');
INSERT INTO Family VALUES(30,'Lamiaceae','Plant');
INSERT INTO Family VALUES(31,'Sapindaceae','Plant');
INSERT INTO Family VALUES(32,'Cynipidae','Wasp');
INSERT INTO Family VALUES(33,'Styracaceae','Plant');
INSERT INTO Family VALUES(34,'Calycanthaceae','Plant');
INSERT INTO Family VALUES(35,'Convolvulaceae','Plant');
INSERT INTO Family VALUES(36,'Lauraceae','Plant');
INSERT INTO Family VALUES(37,'Cerambycidae','Beetle');
INSERT INTO Family VALUES(38,'Rubiaceae','Plant');
INSERT INTO Family VALUES(39,'Juglandaceae','Plant');
INSERT INTO Family VALUES(40,'Scrophulariaceae','Plant');
INSERT INTO Family VALUES(41,'Caprifoliaceae','Plant');
INSERT INTO Family VALUES(42,'Elaeagnaceae','Plant');
INSERT INTO Family VALUES(43,'Plantaginaceae','Plant');
INSERT INTO Family VALUES(44,'Simaroubaceae','Plant');
INSERT INTO Family VALUES(45,'Verbenaceae','Plant');
INSERT INTO Family VALUES(46,'Eriophyidae','Mite');
INSERT INTO Family VALUES(47,'Magnoliaceae','Plant');
INSERT INTO Family VALUES(48,'Ebenaceae','Plant');
INSERT INTO Family VALUES(49,'Aceraceae','Plant');
INSERT INTO Family VALUES(50,'Ulmaceae','Plant');
INSERT INTO Family VALUES(51,'Betulaceae','Plant');
INSERT INTO Family VALUES(52,'Tortricidae','Moth');
INSERT INTO Family VALUES(53,'Celastraceae','Plant');
INSERT INTO Family VALUES(54,'Cucurbitaceae','Plant');
INSERT INTO Family VALUES(55,'Vitaceae','Plant');
INSERT INTO Family VALUES(56,'Dennstaedtiaceae','Plant');
INSERT INTO Family VALUES(57,'Urticaceae','Plant');
INSERT INTO Family VALUES(58,'Fagaceae','Plant');
INSERT INTO Family VALUES(59,'Ericaceae','Plant');
INSERT INTO Family VALUES(60,'Myricaceae','Plant');
INSERT INTO Family VALUES(61,'Aquifoliaceae','Plant');
INSERT INTO Family VALUES(62,'Anacardiaceae','Plant');
INSERT INTO Family VALUES(63,'Adoxaceae','Plant');
INSERT INTO Family VALUES(64,'Geraniaceae','Plant');
INSERT INTO Family VALUES(65,'Diaspididae','Scale');
INSERT INTO Family VALUES(66,'Fabaceae','Plant');

-- CREATE TABLE "Species" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "name" TEXT NOT NULL,
--     "synonyms" TEXT,
--     "commonnames" TEXT,
--     "genus" TEXT NOT NULL,
--     "familyId" INTEGER NOT NULL,
--     "description" TEXT,
--     "abundanceId" INTEGER,

--     FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
--     FOREIGN KEY ("abundanceId") REFERENCES "Abundance"("id") ON DELETE SET NULL ON UPDATE CASCADE
-- )
INSERT INTO species VALUES(1,'Acalypha rhomboidea',NULL,NULL,'Acalypha',20,NULL,NULL);
INSERT INTO species VALUES(2,'Acer campestre',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(3,'Acer circinatum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(4,'Acer floridanum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(5,'Acer ginnala',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(6,'Acer glabrum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(7,'Acer heldreichii',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(8,'Acer leucoderme',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(9,'Acer macrophyllum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(10,'Acer negundo',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(11,'Acer nigrum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(12,'Acer pensylvanicum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(13,'Acer platanoides',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(14,'Acer pseudoplatanus',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(15,'Acer rubrum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(16,'Acer saccharinum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(17,'Acer saccharum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(18,'Acer spicatum',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(19,'Acer xfreemanii',NULL,NULL,'Acer',49,NULL,NULL);
INSERT INTO species VALUES(20,'Achillea millefolium',NULL,NULL,'Achillea',25,NULL,NULL);
INSERT INTO species VALUES(21,'Achillea ptamica',NULL,NULL,'Achillea',25,NULL,NULL);
INSERT INTO species VALUES(22,'Adenostoma fasciculatum',NULL,NULL,'Adenostoma',19,NULL,NULL);
INSERT INTO species VALUES(23,'Aesculus californica',NULL,NULL,'Aesculus',31,NULL,NULL);
INSERT INTO species VALUES(24,'Agalinis heterophylla',NULL,NULL,'Agalinis',40,NULL,NULL);
INSERT INTO species VALUES(25,'Ageratina altissima',NULL,NULL,'Ageratina',25,NULL,NULL);
INSERT INTO species VALUES(26,'Ailanthus altissima',NULL,NULL,'Ailanthus',44,NULL,NULL);
INSERT INTO species VALUES(27,'Alnus cordata',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(28,'Alnus glutinosa',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(29,'Alnus incana',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(30,'Alnus pubescens',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(31,'Alnus rhombifolia',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(32,'Alnus rubra',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(33,'Alnus rugosa',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(34,'Alnus serrulata',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(35,'Alnus tenuifolia',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(36,'Alnus viridis',NULL,NULL,'Alnus',51,NULL,NULL);
INSERT INTO species VALUES(37,'Aloe spinosissima',NULL,NULL,'Aloe',7,NULL,NULL);
INSERT INTO species VALUES(38,'Aloe striata',NULL,NULL,'Aloe',7,NULL,NULL);
INSERT INTO species VALUES(39,'Aloe nobilis',NULL,NULL,'Aloe',7,NULL,NULL);
INSERT INTO species VALUES(40,'Ambrosia ambrosioides',NULL,NULL,'Ambrosia',25,NULL,NULL);
INSERT INTO species VALUES(41,'Ambrosia artemisiifolia',NULL,NULL,'Ambrosia',25,NULL,NULL);
INSERT INTO species VALUES(42,'Ambrosia chenopodiifolia',NULL,NULL,'Ambrosia',25,NULL,NULL);
INSERT INTO species VALUES(43,'Ambrosia deltoides',NULL,NULL,'Ambrosia',25,NULL,NULL);
INSERT INTO species VALUES(44,'Ambrosia psilostachya',NULL,NULL,'Ambrosia',25,NULL,NULL);
INSERT INTO species VALUES(45,'Ambrosia trifida',NULL,NULL,'Ambrosia',25,NULL,NULL);
INSERT INTO species VALUES(46,'Ambrosia trifida',NULL,NULL,'Ambrosia',25,NULL,NULL);
INSERT INTO species VALUES(47,'Amelanchier canadensis',NULL,NULL,'Amelanchier',19,NULL,NULL);
INSERT INTO species VALUES(48,'Amelanchier ovalis',NULL,NULL,'Amelanchier',19,NULL,NULL);
INSERT INTO species VALUES(49,'Amelanchier vulgaris',NULL,NULL,'Amelanchier',19,NULL,NULL);
INSERT INTO species VALUES(50,'Amorpha canescens',NULL,NULL,'Amorpha',66,NULL,NULL);
INSERT INTO species VALUES(51,'Amorpha fruticosa',NULL,NULL,'Amorpha',66,NULL,NULL);
INSERT INTO species VALUES(52,'Amsinckia menziesii',NULL,NULL,'Amsinckia',12,NULL,NULL);
INSERT INTO species VALUES(53,'Andromeda polifolia',NULL,NULL,'Andromeda',59,NULL,NULL);
INSERT INTO species VALUES(54,'Apocynum androsaemifolium',NULL,NULL,'Apocynum',1,NULL,NULL);
INSERT INTO species VALUES(55,'Aronia rotundifolia',NULL,NULL,'Aronia',19,NULL,NULL);
INSERT INTO species VALUES(56,'Artemisia californica',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(57,'Artemisia campestris',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(58,'Artemisia douglasiana',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(59,'Artemisia dracunculus',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(60,'Artemisia eriantha',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(61,'Artemisia frigida',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(62,'Artemisia furcata',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(63,'Artemisia tridentata',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(64,'Artemisia vulgaris',NULL,NULL,'Artemisia',25,NULL,NULL);
INSERT INTO species VALUES(65,'Atriplex canescens',NULL,NULL,'Atriplex',15,NULL,NULL);
INSERT INTO species VALUES(66,'Baccharis glutinosa',NULL,NULL,'Baccharis',25,NULL,NULL);
INSERT INTO species VALUES(67,'Baccharis halimifolia',NULL,NULL,'Baccharis',25,NULL,NULL);
INSERT INTO species VALUES(68,'Baccharis neglecta',NULL,NULL,'Baccharis',25,NULL,NULL);
INSERT INTO species VALUES(69,'Baccharis pilularis',NULL,NULL,'Baccharis',25,NULL,NULL);
INSERT INTO species VALUES(70,'Baccharis salicifolia',NULL,NULL,'Baccharis',25,NULL,NULL);
INSERT INTO species VALUES(71,'Baccharis sarothroides',NULL,NULL,'Baccharis',25,NULL,NULL);
INSERT INTO species VALUES(72,'Betula albosinensis',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(73,'Betula alleghaniensis',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(74,'Betula americana',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(75,'Betula concinna',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(76,'Betula cordifolia',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(77,'Betula coriacea',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(78,'Betula humilis',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(79,'Betula lenta',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(80,'Betula nana',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(81,'Betula neoalaskana',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(82,'Betula nigra',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(83,'Betula occidentalis',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(84,'Betula odorata',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(85,'Betula papyrifera',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(86,'Betula pendula',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(87,'Betula populifolia',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(88,'Betula pubescens',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(89,'Betula pumila',NULL,NULL,'Betula',51,NULL,NULL);
INSERT INTO species VALUES(90,'Borrichia frutescens',NULL,NULL,'Borrichia',25,NULL,NULL);
INSERT INTO species VALUES(91,'Buxus koreana',NULL,NULL,'Buxus',16,NULL,NULL);
INSERT INTO species VALUES(92,'Buxus microphylla',NULL,NULL,'Buxus',16,NULL,NULL);
INSERT INTO species VALUES(93,'Buxus sempervirens',NULL,NULL,'Buxus',16,NULL,NULL);
INSERT INTO species VALUES(94,'Buxus wallichiana',NULL,NULL,'Buxus',16,NULL,NULL);
INSERT INTO species VALUES(95,'Calycanthus floridus',NULL,NULL,'Calycanthus',34,NULL,NULL);
INSERT INTO species VALUES(96,'Camellia sinensis',NULL,NULL,'Camellia',6,NULL,NULL);
INSERT INTO species VALUES(97,'Cannabis sativa',NULL,NULL,'Cannabis',24,NULL,NULL);
INSERT INTO species VALUES(98,'Carpinus caroliniana',NULL,NULL,'Carpinus',51,NULL,NULL);
INSERT INTO species VALUES(99,'Carya illinoinensis',NULL,NULL,'Carya',39,NULL,NULL);
INSERT INTO species VALUES(100,'Carya ovata',NULL,NULL,'Carya',39,NULL,NULL);
INSERT INTO species VALUES(101,'Castanea dentata',NULL,NULL,'Castanea',58,NULL,NULL);
INSERT INTO species VALUES(102,'Ceanothus americanus',NULL,NULL,'Ceanothus',5,NULL,NULL);
INSERT INTO species VALUES(103,'Ceanothus cuneatus',NULL,NULL,'Ceanothus',5,NULL,NULL);
INSERT INTO species VALUES(104,'Ceanothus spinosus',NULL,NULL,'Ceanothus',5,NULL,NULL);
INSERT INTO species VALUES(105,'Ceanothus velutinus',NULL,NULL,'Ceanothus',5,NULL,NULL);
INSERT INTO species VALUES(106,'Celtis laevigata',NULL,NULL,'Celtis',24,NULL,NULL);
INSERT INTO species VALUES(107,'Celtis occidentalis',NULL,NULL,'Celtis',24,NULL,NULL);
INSERT INTO species VALUES(108,'Celtis pallida',NULL,NULL,'Celtis',24,NULL,NULL);
INSERT INTO species VALUES(109,'Celtis reticulata',NULL,NULL,'Celtis',24,NULL,NULL);
INSERT INTO species VALUES(110,'Celtis tenuifolia',NULL,NULL,'Celtis',24,NULL,NULL);
INSERT INTO species VALUES(111,'Cephalanthus occidentalis',NULL,NULL,'Cephalanthus',38,NULL,NULL);
INSERT INTO species VALUES(112,'Chondrilla juncea',NULL,NULL,'Chondrilla',25,NULL,NULL);
INSERT INTO species VALUES(113,'Corylus americana',NULL,NULL,'Corylus',51,NULL,NULL);
INSERT INTO species VALUES(114,'Corylus avellana',NULL,NULL,'Corylus',51,NULL,NULL);
INSERT INTO species VALUES(115,'Corylus columa',NULL,NULL,'Corylus',51,NULL,NULL);
INSERT INTO species VALUES(116,'Corylus cornuta',NULL,NULL,'Corylus',51,NULL,NULL);
INSERT INTO species VALUES(117,'Corylus maxima',NULL,NULL,'Corylus',51,NULL,NULL);
INSERT INTO species VALUES(118,'Corylus tubulosa',NULL,NULL,'Corylus',51,NULL,NULL);
INSERT INTO species VALUES(119,'Cotoneaster integerrimus',NULL,NULL,'Cotoneaster',19,NULL,NULL);
INSERT INTO species VALUES(120,'Cotoneaster nebrodensis',NULL,NULL,'Cotoneaster',19,NULL,NULL);
INSERT INTO species VALUES(121,'Cotoneaster nummularia',NULL,NULL,'Cotoneaster',19,NULL,NULL);
INSERT INTO species VALUES(122,'Cotoneaster racemiflorus',NULL,NULL,'Cotoneaster',19,NULL,NULL);
INSERT INTO species VALUES(123,'Crataegus calpodendron',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(124,'Crataegus crus-galli',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(125,'Crataegus erythropoda',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(126,'Crataegus laevigata',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(127,'Crataegus monogyna',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(128,'Crataegus nigra',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(129,'Crataegus pruinosa',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(130,'Crataegus punctata',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(131,'Crataegus rhipidophylla',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(132,'Crataegus tomentosa',NULL,NULL,'Crataegus',19,NULL,NULL);
INSERT INTO species VALUES(133,'Cucurbita foetidissima',NULL,NULL,'Cucurbita',54,NULL,NULL);
INSERT INTO species VALUES(134,'Cydonia oblonga',NULL,NULL,'Cydonia',19,NULL,NULL);
INSERT INTO species VALUES(135,'Cytisus scoparius',NULL,NULL,'Cytisus',66,NULL,NULL);
INSERT INTO species VALUES(136,'Diospyros texana',NULL,NULL,'Diospyros',48,NULL,NULL);
INSERT INTO species VALUES(137,'Diospyros virginiana',NULL,NULL,'Diospyros',48,NULL,NULL);
INSERT INTO species VALUES(138,'Elaeagnus commutata',NULL,NULL,'Elaeagnus',42,NULL,NULL);
INSERT INTO species VALUES(139,'Ericameria laricifolia',NULL,NULL,'Ericameria',25,NULL,NULL);
INSERT INTO species VALUES(140,'Ericameria palmeri',NULL,NULL,'Ericameria',25,NULL,NULL);
INSERT INTO species VALUES(141,'Erigeron canadensis',NULL,NULL,'Erigeron',25,NULL,NULL);
INSERT INTO species VALUES(142,'Erodium texanum',NULL,NULL,'Erodium',64,NULL,NULL);
INSERT INTO species VALUES(143,'Euonymus occidentalis',NULL,NULL,'Euonymus',53,NULL,NULL);
INSERT INTO species VALUES(144,'Euthamia caroliniana',NULL,NULL,'Euthamia',25,NULL,NULL);
INSERT INTO species VALUES(145,'Euthamia graminifolia',NULL,NULL,'Euthamia',25,NULL,NULL);
INSERT INTO species VALUES(146,'Euthamia leptocephala',NULL,NULL,'Euthamia',25,NULL,NULL);
INSERT INTO species VALUES(147,'Euthamia minor',NULL,NULL,'Euthamia',25,NULL,NULL);
INSERT INTO species VALUES(148,'Euthamia tenuifolia',NULL,NULL,'Euthamia',25,NULL,NULL);
INSERT INTO species VALUES(149,'Fagus grandifolia',NULL,NULL,'Fagus',58,NULL,NULL);
INSERT INTO species VALUES(150,'Frangula alnus',NULL,NULL,'Frangula',5,NULL,NULL);
INSERT INTO species VALUES(151,'Fraxinus americana',NULL,NULL,'Fraxinus',26,NULL,NULL);
INSERT INTO species VALUES(152,'Fraxinus angustifolia',NULL,NULL,'Fraxinus',26,NULL,NULL);
INSERT INTO species VALUES(153,'Fraxinus dipetala',NULL,NULL,'Fraxinus',26,NULL,NULL);
INSERT INTO species VALUES(154,'Fraxinus excelsior',NULL,NULL,'Fraxinus',26,NULL,NULL);
INSERT INTO species VALUES(155,'Fraxinus latifolia',NULL,NULL,'Fraxinus',26,NULL,NULL);
INSERT INTO species VALUES(156,'Fraxinus nigra',NULL,NULL,'Fraxinus',26,NULL,NULL);
INSERT INTO species VALUES(157,'Fraxinus pennsylvanica',NULL,NULL,'Fraxinus',26,NULL,NULL);
INSERT INTO species VALUES(158,'Gaylussacia frondosa',NULL,NULL,'Gaylussacia',59,NULL,NULL);
INSERT INTO species VALUES(159,'Geranium carolinianum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(160,'Geranium dissectum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(161,'Geranium lucidum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(162,'Geranium multiflorum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(163,'Geranium palustre',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(164,'Geranium pratense',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(165,'Geranium pusillum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(166,'Geranium sanguineum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(167,'Geranium sylvaticum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(168,'Geranium villosum',NULL,NULL,'Geranium',64,NULL,NULL);
INSERT INTO species VALUES(169,'Glechoma hederacea',NULL,NULL,'Glechoma',30,NULL,NULL);
INSERT INTO species VALUES(170,'Guara biennis',NULL,NULL,'Guara',3,NULL,NULL);
INSERT INTO species VALUES(171,'Guazuma ulmifolia',NULL,NULL,'Guazuma',13,NULL,NULL);
INSERT INTO species VALUES(172,'Halesia carolina',NULL,NULL,'Halesia',33,NULL,NULL);
INSERT INTO species VALUES(173,'Hamamelis virginiana',NULL,NULL,'Hamamelis',10,NULL,NULL);
INSERT INTO species VALUES(174,'Haworthia retusa',NULL,NULL,'Haworthia',7,NULL,NULL);
INSERT INTO species VALUES(175,'Heterotheca subaxillaris',NULL,NULL,'Heterotheca',25,NULL,NULL);
INSERT INTO species VALUES(176,'Hieracium canadense',NULL,NULL,'Hieracium',25,NULL,NULL);
INSERT INTO species VALUES(177,'Hippophae rhamnoides',NULL,NULL,'Hippophae',42,NULL,NULL);
INSERT INTO species VALUES(178,'Holodiscus discolor',NULL,NULL,'Holodiscus',19,NULL,NULL);
INSERT INTO species VALUES(179,'Ilex dubia',NULL,NULL,'Ilex',61,NULL,NULL);
INSERT INTO species VALUES(180,'Ilex longipes',NULL,NULL,'Ilex',61,NULL,NULL);
INSERT INTO species VALUES(181,'Ilex montana',NULL,NULL,'Ilex',61,NULL,NULL);
INSERT INTO species VALUES(182,'Ilex serrata',NULL,NULL,'Ilex',61,NULL,NULL);
INSERT INTO species VALUES(183,'Ilex verticillata',NULL,NULL,'Ilex',61,NULL,NULL);
INSERT INTO species VALUES(184,'Ilex vomitoria',NULL,NULL,'Ilex',61,NULL,NULL);
INSERT INTO species VALUES(185,'Ipomoea carnea',NULL,NULL,'Ipomoea',35,NULL,NULL);
INSERT INTO species VALUES(186,'Iva frutescens',NULL,NULL,'Iva',25,NULL,NULL);
INSERT INTO species VALUES(187,'Juglans ailantifolia',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(188,'Juglans californica',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(189,'Juglans cinerea',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(190,'Juglans hindsii',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(191,'Juglans major',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(192,'Juglans microcarpa',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(193,'Juglans nigra',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(194,'Juglans regia',NULL,NULL,'Juglans',39,NULL,NULL);
INSERT INTO species VALUES(195,'Juniperus ashei',NULL,NULL,'Juniperus',29,NULL,NULL);
INSERT INTO species VALUES(196,'Lactuca canadensis',NULL,NULL,'Lactuca',25,NULL,NULL);
INSERT INTO species VALUES(197,'Lantana camara',NULL,NULL,'Lantana',45,NULL,NULL);
INSERT INTO species VALUES(198,'Laportea canadensis',NULL,NULL,'Laportea',57,NULL,NULL);
INSERT INTO species VALUES(199,'Lepidospartum squamatum',NULL,NULL,'Lepidospartum',25,NULL,NULL);
INSERT INTO species VALUES(200,'Liquidambar styracifolia',NULL,NULL,'Liquidambar',8,NULL,NULL);
INSERT INTO species VALUES(201,'Liriodendron tulipifera',NULL,NULL,'Liriodendron',47,NULL,NULL);
INSERT INTO species VALUES(202,'Lycium afrum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(203,'Lycium andersonii',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(204,'Lycium arabicum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(205,'Lycium barbarum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(206,'Lycium carolinianum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(207,'Lycium chinense',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(208,'Lycium cooperi',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(209,'Lycium europaeum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(210,'Lycium intricatum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(211,'Lycium macrodon',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(212,'Lycium mediterraneum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(213,'Lycium pallidum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(214,'Lycium ruthenicum',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(215,'Lycium shawii',NULL,NULL,'Lycium',22,NULL,NULL);
INSERT INTO species VALUES(216,'Lygodesmia juncea',NULL,NULL,'Lygodesmia',25,NULL,NULL);
INSERT INTO species VALUES(217,'Lyonia ferruginea',NULL,NULL,'Lyonia',59,NULL,NULL);
INSERT INTO species VALUES(218,'Malus fusca',NULL,NULL,'Malus',19,NULL,NULL);
INSERT INTO species VALUES(219,'Malus sylvestris',NULL,NULL,'Malus',19,NULL,NULL);
INSERT INTO species VALUES(220,'Malus xdomestica',NULL,NULL,'Malus',19,NULL,NULL);
INSERT INTO species VALUES(221,'Malvaviscus arboreus',NULL,NULL,'Malvaviscus',13,NULL,NULL);
INSERT INTO species VALUES(222,'Mespilus coccinea',NULL,NULL,'Mespilus',19,NULL,NULL);
INSERT INTO species VALUES(223,'Mespilus germanica',NULL,NULL,'Mespilus',19,NULL,NULL);
INSERT INTO species VALUES(224,'Myoporum laetum',NULL,NULL,'Myoporum',40,NULL,NULL);
INSERT INTO species VALUES(225,'Myrica pensylvanica',NULL,NULL,'Myrica',60,NULL,NULL);
INSERT INTO species VALUES(226,'Nyssa sylvatica',NULL,NULL,'Nyssa',23,NULL,NULL);
INSERT INTO species VALUES(227,'Ostrya virginiana',NULL,NULL,'Ostrya',51,NULL,NULL);
INSERT INTO species VALUES(228,'Parthenium integrifolium',NULL,NULL,'Parthenium',25,NULL,NULL);
INSERT INTO species VALUES(229,'Parthenocissus quinquefolia',NULL,NULL,'Parthenocissus',55,NULL,NULL);
INSERT INTO species VALUES(230,'Pectocarya linearis',NULL,NULL,'Pectocarya',12,NULL,NULL);
INSERT INTO species VALUES(231,'Persea borbonia',NULL,NULL,'Persea',36,NULL,NULL);
INSERT INTO species VALUES(232,'Persea palustris',NULL,NULL,'Persea',36,NULL,NULL);
INSERT INTO species VALUES(233,'Phoradendron villosum',NULL,NULL,'Phoradendron',18,NULL,NULL);
INSERT INTO species VALUES(234,'Picea abies',NULL,NULL,'Picea',11,NULL,NULL);
INSERT INTO species VALUES(235,'Picea glauca',NULL,NULL,'Picea',11,NULL,NULL);
INSERT INTO species VALUES(236,'Pinus contorta',NULL,NULL,'Pinus',11,NULL,NULL);
INSERT INTO species VALUES(237,'Pinus virginiana',NULL,NULL,'Pinus',11,NULL,NULL);
INSERT INTO species VALUES(238,'Plantago lanceolata',NULL,NULL,'Plantago',43,NULL,NULL);
INSERT INTO species VALUES(239,'Populus alba',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(240,'Populus angustifolia',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(241,'Populus balsamifera',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(242,'Populus deltoides',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(243,'Populus fremontii',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(244,'Populus grandidentata',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(245,'Populus nigra',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(246,'Populus tomentosa',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(247,'Populus tremula',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(248,'Populus tremuloides',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(249,'Populus trichocarpa',NULL,NULL,'Populus',9,NULL,NULL);
INSERT INTO species VALUES(250,'Prosopis glandulosa',NULL,NULL,'Prosopis',66,NULL,NULL);
INSERT INTO species VALUES(251,'Prosopis velutina',NULL,NULL,'Prosopis',66,NULL,NULL);
INSERT INTO species VALUES(252,'Prunus americana',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(253,'Prunus andersonii',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(254,'Prunus armeniaca',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(255,'Prunus avium',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(256,'Prunus cerasifera',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(257,'Prunus cerasus',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(258,'Prunus communis',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(259,'Prunus divaricata',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(260,'Prunus domestica',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(261,'Prunus dulcis',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(262,'Prunus emarginata',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(263,'Prunus fruticosa',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(264,'Prunus granatum',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(265,'Prunus hortulana',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(266,'Prunus ilicifolia',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(267,'Prunus insititia',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(268,'Prunus mahaleb',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(269,'Prunus maritima',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(270,'Prunus mume',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(271,'Prunus munsoniana',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(272,'Prunus nigra',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(273,'Prunus padus',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(274,'Prunus persica',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(275,'Prunus prostrata',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(276,'Prunus pseudocerasus',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(277,'Prunus ramburei',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(278,'Prunus salicina',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(279,'Prunus serotina',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(280,'Prunus serrulata',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(281,'Prunus spinosa',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(282,'Prunus subcordata',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(283,'Prunus triloba',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(284,'Prunus virginiana',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(285,'Prunus yedoensis',NULL,NULL,'Prunus',19,NULL,NULL);
INSERT INTO species VALUES(286,'Pteridium aquilinum',NULL,NULL,'Pteridium',56,NULL,NULL);
INSERT INTO species VALUES(287,'Purshia tridentata',NULL,NULL,'Purshia',19,NULL,NULL);
INSERT INTO species VALUES(288,'Pyracantha coccinea',NULL,NULL,'Pyracantha',19,NULL,NULL);
INSERT INTO species VALUES(289,'Pyrus aria',NULL,NULL,'Pyrus',19,NULL,NULL);
INSERT INTO species VALUES(290,'Pyrus calleryana',NULL,NULL,'Pyrus',19,NULL,NULL);
INSERT INTO species VALUES(291,'Pyrus communis',NULL,NULL,'Pyrus',19,NULL,NULL);
INSERT INTO species VALUES(292,'Pyrus salicifolia',NULL,NULL,'Pyrus',19,NULL,NULL);
INSERT INTO species VALUES(293,'Pyrus spinosa',NULL,NULL,'Pyrus',19,NULL,NULL);
INSERT INTO species VALUES(294,'Pyrus ussuriensis',NULL,NULL,'Pyrus',19,NULL,NULL);
INSERT INTO species VALUES(295,'Quercus agrifolia',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(296,'Quercus alba',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(297,'Quercus arizonica',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(298,'Quercus berberidifolia',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(299,'Quercus bicolor',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(300,'Quercus breviloba',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(301,'Quercus cerris',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(302,'Quercus chapmanii',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(303,'Quercus chrysolepis',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(304,'Quercus coccifera',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(305,'Quercus coccinea',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(306,'Quercus douglasii',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(307,'Quercus emoryi',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(308,'Quercus falcata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(309,'Quercus fusiformis',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(310,'Quercus garryana',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(311,'Quercus geminata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(312,'Quercus glauca',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(313,'Quercus grisea',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(314,'Quercus hemisphaerica',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(315,'Quercus hypoleucoides',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(316,'Quercus ilex',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(317,'Quercus ilicifolia',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(318,'Quercus ilicis',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(319,'Quercus imbricaria',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(320,'Quercus incana',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(321,'Quercus ithaburensis',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(322,'Quercus laceyi',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(323,'Quercus laevis',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(324,'Quercus laurifolia',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(325,'Quercus lobata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(326,'Quercus lyrata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(327,'Quercus macrocarpa',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(328,'Quercus macrolepis',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(329,'Quercus margarettae',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(330,'Quercus marilandica',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(331,'Quercus michauxii',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(332,'Quercus montana',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(333,'Quercus muehlenbergii',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(334,'Quercus myrtifolia',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(335,'Quercus nigra',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(336,'Quercus oblongifolia',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(337,'Quercus palustris',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(338,'Quercus parvula',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(339,'Quercus phellos',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(340,'Quercus prinoides',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(341,'Quercus pubescens',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(342,'Quercus pumila',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(343,'Quercus pungens',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(344,'Quercus reticulata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(345,'Quercus robur',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(346,'Quercus rubra',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(347,'Quercus shumardii',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(348,'Quercus sinuata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(349,'Quercus stellata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(350,'Quercus suber',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(351,'Quercus texana',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(352,'Quercus turbinella',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(353,'Quercus undulata',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(354,'Quercus vaccinifolia',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(355,'Quercus velutina',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(356,'Quercus virginiana',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(357,'Quercus wislizensii',NULL,NULL,'Quercus',58,NULL,NULL);
INSERT INTO species VALUES(358,'Rhamnus cathartica',NULL,NULL,'Rhamnus',5,NULL,NULL);
INSERT INTO species VALUES(359,'Rhododendron menziesii',NULL,NULL,'Rhododendron',59,NULL,NULL);
INSERT INTO species VALUES(360,'Rhus aromatica',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(361,'Rhus coppalinum',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(362,'Rhus glabra',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(363,'Rhus integrifolia',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(364,'Rhus microphylla',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(365,'Rhus trilobata',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(366,'Rhus trilobata',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(367,'Rhus typhina',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(368,'Rhus virens',NULL,NULL,'Rhus',62,NULL,NULL);
INSERT INTO species VALUES(369,'Rubus armeniacus',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(370,'Rubus caesius',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(371,'Rubus fruticosus',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(372,'Rubus idaeus',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(373,'Rubus laciniatus',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(374,'Rubus leucodermis',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(375,'Rubus pubescens',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(376,'Rubus thyrsanthus',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(377,'Rubus ursinus',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(378,'Rubus vitifolius',NULL,NULL,'Rubus',19,NULL,NULL);
INSERT INTO species VALUES(379,'Ruellia patula',NULL,NULL,'Ruellia',21,NULL,NULL);
INSERT INTO species VALUES(380,'Ruellia tuberosa',NULL,NULL,'Ruellia',21,NULL,NULL);
INSERT INTO species VALUES(381,'Salix acutifolia',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(382,'Salix aegyptica',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(383,'Salix alba',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(384,'Salix amygdalina',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(385,'Salix amygdaloides',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(386,'Salix appendiculata',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(387,'Salix arbuscula',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(388,'Salix aurita',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(389,'Salix babylonica',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(390,'Salix bebbiana',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(391,'Salix brachycarpa',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(392,'Salix caprea',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(393,'Salix cinerea',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(394,'Salix daphnoides',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(395,'Salix discolor',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(396,'Salix eleagnos',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(397,'Salix exigua',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(398,'Salix fragilis',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(399,'Salix glauca',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(400,'Salix gooddingii',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(401,'Salix grandifolia',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(402,'Salix groenlandica',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(403,'Salix hastata',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(404,'Salix herbacea',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(405,'Salix hookeriana',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(406,'Salix incana',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(407,'Salix integra',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(408,'Salix interior',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(409,'Salix koreensis',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(410,'Salix laevigata',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(411,'Salix lanata',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(412,'Salix lapponica',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(413,'Salix lapponum',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(414,'Salix livida',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(415,'Salix matsudana',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(416,'Salix melanopsis',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(417,'Salix myrsinifolia',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(418,'Salix myrsinites',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(419,'Salix myrsinitis',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(420,'Salix myrtilloides',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(421,'Salix nigra',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(422,'Salix nigricans',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(423,'Salix orestera',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(424,'Salix pentandra',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(425,'Salix phylicifolia',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(426,'Salix polaris',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(427,'Salix purpurea',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(428,'Salix pyrifolia',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(429,'Salix reticulata',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(430,'Salix retusa',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(431,'Salix rosmarinifolia',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(432,'Salix rotundifolia',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(433,'Salix scouleriana',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(434,'Salix starkeana',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(435,'Salix triandra',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(436,'Salix viminalis',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(437,'Salix viridis',NULL,NULL,'Salix',9,NULL,NULL);
INSERT INTO species VALUES(438,'Salvia mellifera',NULL,NULL,'Salvia',30,NULL,NULL);
INSERT INTO species VALUES(439,'Salvia verbenaca',NULL,NULL,'Salvia',30,NULL,NULL);
INSERT INTO species VALUES(440,'Sambucus caerulea',NULL,NULL,'Sambucus',63,NULL,NULL);
INSERT INTO species VALUES(441,'Sambucus canadensis',NULL,NULL,'Sambucus',63,NULL,NULL);
INSERT INTO species VALUES(442,'Sambucus nigra',NULL,NULL,'Sambucus',63,NULL,NULL);
INSERT INTO species VALUES(443,'Sambucus racemosus',NULL,NULL,'Sambucus',63,NULL,NULL);
INSERT INTO species VALUES(444,'Sandoricum koetjape',NULL,NULL,'Sandoricum',17,NULL,NULL);
INSERT INTO species VALUES(445,'Senegalia greggii',NULL,NULL,'Senegalia',66,NULL,NULL);
INSERT INTO species VALUES(446,'Sideroxylon lanuginosum',NULL,NULL,'Sideroxylon',2,NULL,NULL);
INSERT INTO species VALUES(447,'Silphium laciniatum',NULL,NULL,'Silphium',25,NULL,NULL);
INSERT INTO species VALUES(448,'Solidago altissima',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(449,'Solidago bicolor',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(450,'Solidago caesia',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(451,'Solidago californica',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(452,'Solidago canadensis',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(453,'Solidago chapmanii',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(454,'Solidago erecta',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(455,'Solidago fistulosa',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(456,'Solidago gigantea',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(457,'Solidago juncea',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(458,'Solidago leavenworthii',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(459,'Solidago missouriensis',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(460,'Solidago nemoralis',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(461,'Solidago odora',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(462,'Solidago patula',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(463,'Solidago rugosa',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(464,'Solidago sempervirens',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(465,'Solidago spathulata',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(466,'Solidago tortifolia',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(467,'Solidago uliginosa',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(468,'Solidago velutina',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(469,'Solidago flexicaulis',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(470,'Solidago macrophylla',NULL,NULL,'Solidago',25,NULL,NULL);
INSERT INTO species VALUES(471,'Sorbus aria',NULL,NULL,'Sorbus',19,NULL,NULL);
INSERT INTO species VALUES(472,'Sorbus aucuparia',NULL,NULL,'Sorbus',19,NULL,NULL);
INSERT INTO species VALUES(473,'Sorbus californica',NULL,NULL,'Sorbus',19,NULL,NULL);
INSERT INTO species VALUES(474,'Sorbus commixta',NULL,NULL,'Sorbus',19,NULL,NULL);
INSERT INTO species VALUES(475,'Sorbus pohuashanensis',NULL,NULL,'Sorbus',19,NULL,NULL);
INSERT INTO species VALUES(476,'Sorbus scopulina',NULL,NULL,'Sorbus',19,NULL,NULL);
INSERT INTO species VALUES(477,'Sorbus torminalis',NULL,NULL,'Sorbus',19,NULL,NULL);
INSERT INTO species VALUES(478,'Spiraea douglasii',NULL,NULL,'Spiraea',19,NULL,NULL);
INSERT INTO species VALUES(479,'Spiraea splendens',NULL,NULL,'Spiraea',19,NULL,NULL);
INSERT INTO species VALUES(480,'Symphoricarpos albus',NULL,NULL,'Symphoricarpos',41,NULL,NULL);
INSERT INTO species VALUES(481,'Syringa vulgaris',NULL,NULL,'Syringa',26,NULL,NULL);
INSERT INTO species VALUES(482,'Tanacetum abrotanifolium',NULL,NULL,'Tanacetum',25,NULL,NULL);
INSERT INTO species VALUES(483,'Tanacetum parthenium',NULL,NULL,'Tanacetum',25,NULL,NULL);
INSERT INTO species VALUES(484,'Tanacetum vulgare',NULL,NULL,'Tanacetum',25,NULL,NULL);
INSERT INTO species VALUES(485,'Taxodium ascendens',NULL,NULL,'Taxodium',29,NULL,NULL);
INSERT INTO species VALUES(486,'Taxodium distichum',NULL,NULL,'Taxodium',29,NULL,NULL);
INSERT INTO species VALUES(487,'Tilia americana',NULL,NULL,'Tilia',13,NULL,NULL);
INSERT INTO species VALUES(488,'Tilia cordata',NULL,NULL,'Tilia',13,NULL,NULL);
INSERT INTO species VALUES(489,'Tilia platyphyllos',NULL,NULL,'Tilia',13,NULL,NULL);
INSERT INTO species VALUES(490,'Tilia tomentosa',NULL,NULL,'Tilia',13,NULL,NULL);
INSERT INTO species VALUES(491,'Toxicodendron diversilobum',NULL,NULL,'Toxicodendron',62,NULL,NULL);
INSERT INTO species VALUES(492,'Toxicodendron radicans',NULL,NULL,'Toxicodendron',62,NULL,NULL);
INSERT INTO species VALUES(493,'Toxicodendron vernix',NULL,NULL,'Toxicodendron',62,NULL,NULL);
INSERT INTO species VALUES(494,'Tsuga canadensis',NULL,NULL,'Tsuga',11,NULL,NULL);
INSERT INTO species VALUES(495,'Ulmus alata',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(496,'Ulmus americana',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(497,'Ulmus crassifolia',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(498,'Ulmus glabra',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(499,'Ulmus laevis',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(500,'Ulmus minor',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(501,'Ulmus parvifolia',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(502,'Ulmus procera',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(503,'Ulmus rubra',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(504,'Ulmus thomasii',NULL,NULL,'Ulmus',50,NULL,NULL);
INSERT INTO species VALUES(505,'Urtica dioica',NULL,NULL,'Urtica',57,NULL,NULL);
INSERT INTO species VALUES(506,'Vaccinium angustifolium',NULL,NULL,'Vaccinium',59,NULL,NULL);
INSERT INTO species VALUES(507,'Vaccinium canadense',NULL,NULL,'Vaccinium',59,NULL,NULL);
INSERT INTO species VALUES(508,'Vaccinium corymbosum',NULL,NULL,'Vaccinium',59,NULL,NULL);
INSERT INTO species VALUES(509,'Vaccinium pennsylvanicum',NULL,NULL,'Vaccinium',59,NULL,NULL);
INSERT INTO species VALUES(510,'Vaccinium stamineum',NULL,NULL,'Vaccinium',59,NULL,NULL);
INSERT INTO species VALUES(511,'Vernonia baldwini',NULL,NULL,'Vernonia',25,NULL,NULL);
INSERT INTO species VALUES(512,'Vernonia gigantea',NULL,NULL,'Vernonia',25,NULL,NULL);
INSERT INTO species VALUES(513,'Vernonia novaboracensis',NULL,NULL,'Vernonia',25,NULL,NULL);
INSERT INTO species VALUES(514,'Viburnum dentatum',NULL,NULL,'Viburnum',63,NULL,NULL);
INSERT INTO species VALUES(515,'Viburnum lantana',NULL,NULL,'Viburnum',63,NULL,NULL);
INSERT INTO species VALUES(516,'Viburnum opulus',NULL,NULL,'Viburnum',63,NULL,NULL);
INSERT INTO species VALUES(517,'Viburnum rafinesquianum',NULL,NULL,'Viburnum',63,NULL,NULL);
INSERT INTO species VALUES(518,'Vitis aestivalis',NULL,NULL,'Vitis',55,NULL,NULL);
INSERT INTO species VALUES(519,'Vitis labrusca',NULL,NULL,'Vitis',55,NULL,NULL);
INSERT INTO species VALUES(520,'Vitis riparia',NULL,NULL,'Vitis',55,NULL,NULL);
INSERT INTO species VALUES(521,'Vitis vinifera',NULL,NULL,'Vitis',55,NULL,NULL);
INSERT INTO species VALUES(522,'Vitis vulpina',NULL,NULL,'Vitis',55,NULL,NULL);
INSERT INTO species VALUES(523,'Zelkova serrata',NULL,NULL,'Zelkova',50,NULL,NULL);
INSERT INTO species VALUES(524,''Aceria calaceris',NULL,NULL,'Aceria',46,'"These mites are found in and probably cause the red erineum on leaf tips [upper surface]"; produce bright red erineum on upper leaf surfaces.',NULL);
INSERT INTO species VALUES(525,''Aceria elongata',NULL,NULL,'Aceria',46,'Red erineum patches on the upper surfaces of leaves., Described from individuals found among red erineum galls on the upper surfaces of leaves of the sugar maple, Acer saccharum L., Described from individuals found among red erineum galls on the upper surfaces of leaves of the sugar maple, Acer saccharum L.',NULL);
INSERT INTO species VALUES(526,''Aceria modesta',NULL,NULL,'Aceria',46,'Described from individuals found among greenish erineum galls on the under surface of leaves of the sugar maple, Acer saccharum L., Whitish or greenish erineum patches on the lower surfaces of leaves or along the veins.',NULL);
INSERT INTO species VALUES(527,''Eriophyes aceris',NULL,NULL,'Eriophyes',46,'Elongate red carmine galls, filled with hairs, with large open aperture on underside of leaf; hairs protruding from aperture., In erineum on leaves of silver maple, E. aceris Hodgkiss is abundant. The erineum patches, which are on the undersurface of the leaves, are pale greenish or greenish yellow, often with a reddish tint, and later red. In July most of the erineum turns brown and becomes dry. ',NULL);
INSERT INTO species VALUES(528,''Aceria major',NULL,NULL,'Aceria',46,'Described from individuals found among galls of pinkish erineum on the under surface of leaves of the red maple, Acer rubrum L., Described from individuals found among pinkish erineum galls on the under surfaces of leaves of the red maple, Acer rubrum L., Pale-greenish or greenish-yellow lower surface, leaf erineum often with a reddish tint, later becoming red, then brown and dry.',NULL);
INSERT INTO species VALUES(529,''Aculus minutissimus',NULL,NULL,'Aculus',46,'Described from individuals found among red erineum galls on the upper surfaces of leaves of the red maple, Acer rubrum L., White or red erineum consisting of large capitate multicellular processes on the upper surfaces of leaves. It may be an inquiline.',NULL);
INSERT INTO species VALUES(530,''Aculus quinquilobus',NULL,NULL,'Aculus',46,'Described from individuals found among pinkish erineum galls on the under surfaces of leaves of the red maple, Acer rubrum L., Causes whitish or pinkish erineum galls on the lower surfaces of leaves.',NULL);
INSERT INTO species VALUES(531,''Aceria negundi',NULL,NULL,'Aceria',46,replace('Described from individuals found in wart-like swellings of leaves of the black maple, Acer negundo L.\n, Wart-like swellings or pouch galls on leaves, lower surface erineum., The galls are large, rounded, and peculiarly pouchtype. They develop on the underside of the leaf blade as thickened cavities filled with a dense mass of felty, whitish, unicellular hairs. They protrude on the upper side and have slightly wrinkled domes. Their dimensions are variable. The galls are solitary and widespread on the leaf blade but are not on the veins. \nSpecimens were collected in galls on box elder in New York, Illinois, and Canada and recently in Ohio. Hodgkiss {1930) reported two species of Phyllocoptes in galls of box elder in New York; they should not be confused with E. negundi. ','\n',char(10)),NULL);
INSERT INTO species VALUES(532,''Vasates quadripedes',NULL,NULL,'Vasates',46,replace('Described from individuals found associated with P quadripes Shimer in bladder galls on the leaves of the soft maple, Acer saccharinum., Bladder galls on leaf upper surface., The mite causes a pouch gall type known as bladder gall, which is periodically common and abundant on the upper leaf surface of red and silver maples. The galls on the latter are variable in shape, rounded or elongate. Each has a slender short stem or neck. The length varies from 1.5 to 5 mm. They are solitary and are usually crowded and numerous at the basal part of the leaf blade in the angles between the larger veins. The exterior of the galls appears wrinkled and glossy. They change from yellowish green or dark green to pink, to brown, to black. The interior is hollow, and the exit hole, which is on the underside of the leaf, is lined with unicellular whitish hairs. In heavy infestations, the leaves become curled, form cylindrical rolls, and drop prematurely. The galls on red maple differ in size and form. They are smaller, I to 2 mm, somewhat beadlike, and without a basal constriction or neck. \nVasates quadripedes is found on red and silver maples in the United States and Canada.','\n',char(10)),NULL);
INSERT INTO species VALUES(533,''Vasates aceriscrumena',NULL,NULL,'Vasates',46,replace('Upper surface, leaf finger galls with lower surface opening., Another common and abundant pouch gall that develops on the upper surface of sugar maple leaves is the spindle or finger gall, which is caused by Vasates aceriscrumena. The gall is distinguished from that of V. quadripedes Shimer by its form, position, color, and texture. The galls are solitary, elongate, with pointed or truncate apices, or spindle shaped. They are variable in size, up to 5 mm in length, and tend to crowd at the apical half of the leaf blade. They vary from greenish tinged with yellow to pink, to crimson. The exit hole on the underside of the leaf has a tuft of unicellular hairs, but the interior of the gall is thin walled and lacks hairs. \nVasates aceriscrumena is similar to V. quadripedes. It is recognized by having two spinules on the anterior lobe of the dorsal shield, by the forward-centrad direction of the dorsal setae, and by the well pronounced design of the dorsal shield. \nSpecimens are found in galls through July on sugar maple in the Eastern United States and Canada. \n','\n',char(10)),NULL);
INSERT INTO species VALUES(534,''Aceria myriadeum',NULL,NULL,'Aceria',46,'Numerous cephaloneon galls on leaf surface, Cephaloneon myriadeum Bremi',NULL);
INSERT INTO species VALUES(535,''Aceria spicati',NULL,NULL,'Aceria',46,'Described from individuals found in a whitish erineum on the under surfaces of leaves of the mountain maple, Acer spicatum L., Small white "frost" (= erineum) galls on leaf underside at vein angles; cylindrical galls on leaf surface on Acer insulare.',NULL);
INSERT INTO species VALUES(536,''Cecidophyes naulti',NULL,NULL,'Cecidophyes',46,'The mites were found on the lower surface of leaf curling.',NULL);
INSERT INTO species VALUES(537,''Acericecis ocellaris',NULL,NULL,'Acericecis',4,'',NULL);
INSERT INTO species VALUES(538,''Dasineura communis',NULL,NULL,'Dasineura',4,'',NULL);
INSERT INTO species VALUES(539,''Proteoteras willingana',NULL,NULL,'Proteoteras',52,'',NULL);
INSERT INTO species VALUES(540,''Contarinia negundinis',NULL,NULL,'Contarinia',4,'',NULL);
INSERT INTO species VALUES(541,''Contarinia (undescribed)',NULL,NULL,'Contarinia',4,'',NULL);
INSERT INTO species VALUES(542,''Rhytisma acerinum',NULL,NULL,'Rhytisma',27,'',NULL);
INSERT INTO species VALUES(543,''Rhytisma americanum',NULL,NULL,'Rhytisma',27,'',NULL);
INSERT INTO species VALUES(544,''Rhytisma punctatum',NULL,NULL,'Rhytisma',27,'',NULL);
INSERT INTO species VALUES(545,''Xylotrechus aceris',NULL,NULL,'Xylotrechus',37,'',NULL);
INSERT INTO species VALUES(546,''Synanthedon acerni',NULL,NULL,'Synanthedon',28,'',NULL);
INSERT INTO species VALUES(547,''Proteoteras aesculana',NULL,NULL,'Proteoteras',52,'',NULL);
INSERT INTO species VALUES(548,''Synanthedon acerrubri',NULL,NULL,'Synanthedon',28,'',NULL);
INSERT INTO species VALUES(549,''Cryptophyllaspis liquidambaris',NULL,NULL,'Cryptophyllaspis',65,'',NULL);
INSERT INTO species VALUES(550,''Dasineura rileyana',NULL,NULL,'Dasineura',4,'',NULL);
INSERT INTO species VALUES(551,''Dasineura aceris',NULL,NULL,'Dasineura',4,'',NULL);
INSERT INTO species VALUES(552,''Rhyncaphytoptus magnificus',NULL,NULL,'Rhyncaphytoptus',46,'Described from individuals found in epidermal hairy growths which occur in the axils of the veins on the under surfaces of leaves of the Norway maple, Acer platanoides L., Epidermal hairy growths which occur in the axils of the veins on the under surfaces of leaves.',NULL);
INSERT INTO species VALUES(553,''Caryomyia tubicola',NULL,NULL,'Caryomyia',4,'',NULL);
INSERT INTO species VALUES(554,''Aculops rhois',NULL,NULL,'Aculops',46,replace('Infestation is common and typical of the leaf galls. It consists of puckered, irregular, rounded, or wartlike pouches affecting both upper and lower surfaces of the leaves. The galls are usually scattered about indiscriminately on the leaf blade. They range from green to pinkish, to red brown. Poison oak leaves are often so heavily attacked that they become visibly crinkled and distorted. \nSpecimens were collected on poison oak in Oregon and California and on poison ivy in Ohio and Maryland. It has also been found on poison sumac (Rhus vernix L.) in Ohio. The mite is probably present throughout its host range. , "Corrugations [galls] on upper and lower surfaces of leaf with numerous, whitish hairs or erinea"; leaf deformation; stunting of plant? [5041]. Flowers of large vines sometimes become deformed producing numerous long narrow filaments that are narrow rolled leaves; mites deveop in large numbers within the rolls; in some cases the filaments are somewhat more leaflike [West Virginia: Monongalia, Nicholas, Preston and Tucker counties; Maryland: near mouth of Susquehanna River]. Are these a different species?','\n',char(10)),NULL);
INSERT INTO species VALUES(555,''Eriophyes laevis',NULL,NULL,'Eriophyes',46,'These beadlike galls are particularly striking because they appear on both surfaces of the leaves. They are small, hemispherical, of variable size and are scattered singly or crowded alongside the midrib. The galls are firmly attached, with the exit holes on the underside. They are shiny externally and the interior contains fleshy tissue. They range from green to yellowish, to red, to reddish brown as they mature. A single leaf may carry numerous galls so that it becomes distorted and its growth inhibited. Although P. laevis is a common species on alder, little is known of its seasonal history and habits. Specimens were abundant in August. The hosts are Oregon or red alder, white alder, and mountain alder in California and hazel alder in Ohio and Georgia. , Numerous cephaloneon galls of various sizes, on both leaf surfaces [mostly upper]; Cephaloneon pustulatum Bremi.',NULL);
INSERT INTO species VALUES(556,''Aceria baccharipha',NULL,NULL,'Aceria',46,'This gall is known as Baccharis leaf blister, a pimplelike swelling that develops on both sides of the leaf blade, with the exit hole on the underside. Generally an infestation gives the leaf a pimply, blistered appearance. The galls vary in size and from greenish to yellow, to brown. The mites occur among the fleshy tissue in the galls and presumably leave the galls and migrate to the buds during unfavorable weather. The host plant is locally known as chaparral broom, a spreading evergreen shrub that occurs in coastal and inland hills in California and southern Oregon. The mite specimens were first collected in California in April. Eriophyes baccharipha should not be confused with two other eriophyids that infest Baccharis in California. They are Eriophyes calibaccharis Keifer, which occurs in the terminal buds of chaparral broom, and E. baccharices (Keifer), which causes irregular, wartlike, rough-looking galls on the upper surface of the leaves of seep willow (Baccharis glutinosa Pers.) and mule-fat (B. viminea D. C.). , Leaf blisters.',NULL);
INSERT INTO species VALUES(557,''Aceria brachytarsa',NULL,NULL,'Aceria',46,'The pouch galls induced by this mite on the upper surface of the leaves invariably appear at random between the lateral veins and on the midrib. The galls are often solitary, 3.6 mm in dimension, irregularly globular, and shiny with roughened surface. They range from green to yellowish green with red-dish or brown tinge. The interior of the gall, which becomes red as it matures, consists of multicellular structures, as shown in plate 6, E. Galls at times are numerous on some trees, causing considerable distortion to the foliage. , Undersurface purse galls; purse galls filled with parenchymatous tissue and sparse hairs, with channels for mite development. The leaf gall on Juglans nigra is mostly on the upper surface and hollow with hairs; nothing like this gall. ',NULL);
INSERT INTO species VALUES(558,''Aceria caulis',NULL,NULL,'Aceria',46,'This is an exceptionally interesting and beautiful pubescent gall, often brightly colored, passing from greenish through pink and crimson to reddish brown. The gall most frequently develops as an irregular, solid, hard mass on the leaf petiole. It is often solitary and variable in size. The exterior is covered with a dense mass of silky, unicellular, erineumlike hairs (see pl. 7, A). The gall tends to be large and to spread to and partly envelop the stem and leaf. The affected structure is greatly distorted and twisted, and leaflets fail to develop. This mite was found infesting black walnut in New Jersey and Pennsylvania in July-August. It is probably distributed throughout the range of its host from Ontario to Massachusetts and south to Florida and eastern Texas. , The mites produce the Petiole Gall, peculiar reddish to purplish erineum-covered wooden swellings on the petioles; leaves often distorted and shortened; may be many galls per leaf.',NULL);
INSERT INTO species VALUES(559,''Aceria aloinis',NULL,NULL,'Aceria',46,'An affected plant shows a remarkable proliferation of unsightly, irregular outgrowth, clustered densely on the surface of the leaf blades or in leaf axils. The infestation may be con-fined to the base in the leaf axils as bunched, greenish, tiny-to-large globular sprouts or as a lumpy, rough-looking thickening in the form of wartlike growths from the base of the leaf blade extending to the tip. The longitudinal pattern of growth follows that of the lanceolate shape of the leaf. It ranges from yellowish to brownish, to green tinged with yellow. The mites also attack the inflorescence and cause galled blooms. This eriophyid attacks golden-tooth aloe, spider aloe, and star cactus or wart plant in southern California and Florida. It is probably found wherever these plants are grown. , The mites cause severe deformation on the inner sides of leaf axils and on inflorescences.',NULL);
INSERT INTO species VALUES(560,''Aceria sandorici',NULL,NULL,'Aceria',46,'This is an unsightly pouch gall that develops on the underside of the leaf blade as a concavity filled with erineum and on the upper side as a rounded outpocketing with irregular puckered domes. The pouch is greenish, becoming blackish, and the erineum turns brownish at maturity. The galls are variable in size and are frequently coalesced and crowded, giving a lumpy appearance to the leaf blade. Eriophyes sandorici has been found only on santol of the mahogany family Meliaceae, a tropical tree with edible fruit from the lndomalayan region and Mauritius. , Erineum pockets on upper and lower sides of leaves, the pockets protruding out of both surfaces.',NULL);
INSERT INTO species VALUES(561,''Aceria fraxini',NULL,NULL,'Aceria',46,'The galls on the upper surface of ash leaves are unmistakable and often particularly numerous on the terminal leaves. They are small and solitary, somewhat reniform in shape, and gen-erally scattered at random on the lateral veins. Their greenish-yellow color and shape give a striking effect on an infested leaf. Specimens were found in galls on leaves of white, Oregon, and green or red ash in California, Wisconsin, Virginia, New York, Vermont, and Canada. In Europe, Eriophyes fraxinicola (Nalepa), a closely related species of E. chondriphora, makes similar galls on leaves of European ash (Fraxinus excelsior L.). , Masses of bead galls on leaves, with most openings on the lower surface of the leaf; [deformed flowers [892], error, symptoms of Aceria fraxiniflora (Felt, 1906)].',NULL);
INSERT INTO species VALUES(562,''Callirhytis furva',NULL,NULL,'Callirhytis',32,'Small, somewhat globular galls, 3-4 mm in diameter covered with short, straight, stiff brown hairs, scattered along midrib or main veins on upper side of leaf in the fall and dropping off singly when mature. The hairs do not weather away during winter. Similar to galls of C infuscata on Quercus laevis in Florida., On Quercus catesbaei [laevis], coccinea, falcata, ilicifolia, imbricaria, laurifolia, marilandica, myrtifolia, nigra, palustris, phellos, velutina: Small cluster of globular galls, 3-4 mm in dia., each covered with short, straight brown hairs, on upper side of leaf in fall.',NULL);
INSERT INTO species VALUES(563,''Callirhytis infuscata',NULL,NULL,'Callirhytis',32,replace('A globular, fleshy gall, densely covered with yellow wool; diameter .23 to .25 inch. It is attached by a slight point to the upper surface of the leaf and when mature is in reality nothing but a hard, tough, larval cell, covered with wool; the wooly covering is easily detached. It is monothalamous; occasionally several galls occur together on the leaf compressing one another into odd shapes but the galls fall to the ground, separate and renew their globular form, and the fly reaches maturity in the damp earth. Described from several specimens reared in March., Globular, fleshy, monothalamous leaf gall with dense, yellow wool, diameter 5 to 6 mm, on upper surface, on Q catesbaei [laevis]., On Quercus catesbaei [laevis]: Woolly midrib cluster on under side in fall dropping in late Nov. When wool weathers away each element is white and flat-topped. [contradicts original description, which states that this gall is found on the upper side of the leaf on this host]\nOn Quercus cinerea [incana]: Globular, fleshy, densely covered with yellow wool, on upper surface in fall, dropping when mature.\nOn Quercus laurifolia: Globular, fleshy, densely covered with yellowish wool, single or cluster on midrib on  upper surface in fall, dropping when mature, then the wool coming away clean.\nOn Quercus marilandica: Globular, fleshy, densely covered with yellow wool, on upper surface in fall, dropping when mature.\nOn Quercus myrtifolia: Globular, fleshy, densely covered with yellow hairs, on upper surface in fall, dropping when mature.\nOn Quercus phellos: Globular, densely covered with yellow wool, on midrib on upper surface in fall, dropping when mature.\nOn Quercus pumila: Globular, densely covered with yellow wool, in cluster on midrib in upper surface in fall, dropping when mature and becoming plump on ground, the wool easily detached.','\n',char(10)),NULL);
INSERT INTO species VALUES(564,''Callirhytis piperoides',NULL,NULL,'Callirhytis',32,'Galls from one-eighth to three-eighths of an inch in diameter, in dense clusters along the mid-vein of full grown red oak leaves (Quercus rubra). They are found only on the largest leaves of the thriftiest shoots of young oaks. The clusters contain from one or two dozen galls up to a hundred or more, and extend along the vein two, three or even four inches. The vein is considerably enlarged, and is often split by the crowding of the galls as they increase in size. The blade of the leaf is often torn by the same force and the galls appear on both surfaces. When on the tree they are covered with a dense, coarse pubescence which is, in color, a dusky drab, or when exposed to the sun a brownish red. They are round except a very slight elongation at the point of attachment to the leaf. After falling to the ground they soon turn black, and after losing their pubescence they resemble quite closely small black pepper corns. At this time they are a solid mass of vegetable cells with a minute jelly-like center, which is the undeveloped larva. The growing larva devours the gall till at maturity nothing remains but a thin shell. , These galls are found in clusters of one to five dozen along the midrib, looking as if they had burst out from the inside of the leaf or vein. Each is smooth, spherical, attached by a small stem, 3.8 mm in diameter, monothalamous, grayish or tinged with red. They fall to the ground, where the larva completes its metamorphosis, which sometimes requires two years. Insects in second summer. Leaves of red oak Q rubra. Not rare., Similar in size and shape [to Andricus dimorphus] but red in color, in an elongated less compact cluster on upper or lower side of large leaves on thrifty shoots of Q rubra, dropping in October. Pubescent under lens. Adults emerged April-May the second spring and some hang over to emerge still later., Fuzzy, globular. Red oaks., Clustered, pubescent, globular, drab or brownish red midvein galls, frequently splitting and extending along the vein 4 to 8 cm, diameter 3 to 9 mm, occur in clusters of 10 to 100 or more on a leaf, on Q rubra. , Galls of this species were noted on the leaves of Q maxima [rubra] in IL, NY, and VA. Some specimens sent from Maine were determined by the writer as those of this species. Galls collected in IL in October contained both pupae and larvae in September and adults and larvae in November. Adults emerged April to May. The emergence is evidently distributed over at least two seasons. Beutenmueller notes that the galls were very common in the fall of 1916 and again in 1918, but none were noticed in 1917. , On Quercus coccinea, ilicifolia, rubra, velutina: Cluster on upper or lower side of leaf, each spherical, red, pubescent, 1-4 mm in dia, dropping in fall.',NULL);
INSERT INTO species VALUES(565,''Callirhytis lanata',NULL,NULL,'Callirhytis',32,'During late summer and autumn the galls of this species are found on the under side of leaves of Quercus rubra and Q coccinea, appearing externally as little bunches of compact brown wool and hardly distinguishable in outward appearance from the galls of Andricus flocci Walsh. The galls seldom occur singly, but usually in clusters of from four to eight. A cluster of eight galls when fully grown will measure about 3/8 of an inch in width by 5/8 of an inch in length. An individual gall when denuded of its covering is in the form of an irregularly shaped cone with a bulging base, the diameter of the base being three or four sixteenths of an inch, which is nearly twice the height. The galls fall to the ground in the autumn in advance of the leaves, and the flies emerge the following summer. , Bunches of pale brown wool on under surface of leaf, each with 2 to 8 triangular or irregularly conical cells, diameter 5 to 15 mm, on Q rubra, coccinea, velutina, marilandica, phellos, nana., This species is here recorded from two new host oaks, Q rubra and Q texana from IL, MN, WI, PA, NY, VA, MO, OK, TX, and AL. Galls collected in fall of 1916 contained pupae and larvae in September and adults and larvae in November. Adults issued in April. Brodie found the galls common about Toronto on red and black oak, forest trees as well as second growth. They appear in August, mature in October dropping before the leaves, the producers emerging May and June from galls collected on the ground under the trees the previous fall. , A cluster of several light brown, wooly galls, sometimes pink-tinted, found on the under side of the leaf. Individual galls cone-shaped, monothalamous, attached by tip of cone to common center. About 5 mm wide, 5-7 mm high. The galls fall from the leaf in early autumn. The flies emerge the following spring. Common on Q coccinea., Hemispherical brownish woolly mass on midrib on underside of leaf of Q rubra and velutina. Made up of a cluster of easily detached separate angular galls which drop to the group in the fall in Oct before the leaves, each covered with a dense coating of wool. They are then fleshy and apparently solid as the larval cavity is very minute. Adults emerge the second and third springs in April., This gall, which occurs as a woolly mass on the under side of the leaves of several species of the red oak group, is composed of angular galls closely joined. When young the galls are covered with a whitish wool which later turns brown., On Quercus coccinea, falcata, ilicifolia, marilandica, rubra, texana, velutina: Woolly midrib cluster on under side of leaf in fall, dropping before the leaves.',NULL);
INSERT INTO species VALUES(566,''Neuroterus laurifoliae',NULL,NULL,'Neuroterus',32,'An oblong, wooly gall on the upper or lower surface of the leaves; the wool is fawn colored, long and fine, covering three or four, sometimes more irregularly rounded, flattened disks, in the centre of which live the flies; they are attached to the midrib by a nipple-like point; the disk or cell is concave above and measures .08 to .10 inch in diameter. , Woolly midrib cluster on under side of leaf in fall. Wool comes off clean leaving a conical gall with a sunken crenate top., Globose, kernel-like leaf galls occurring singly or in clusters and covered with long, loose, fawn-colored wool, diameter of kernel 2 to 2.5 mm, on Q laurifolia, Q imbricaria.',NULL);
INSERT INTO species VALUES(567,''Disholcaspis bassetti',NULL,NULL,'Disholcaspis',32,replace('The gall occurs, sometimes singly, but usually in clusters about the twigs. The cluster represented at Fig. 2 was composed of 30 of these galls closely crowded together. The galls resemble very much the galls of Holcaspis duricoria Bass (Cynips mamma Wal) (Fig 3). The galls are very much the shape that a thick waxy material would take if dropped on the twigs and then suddenly congealed, leaved stout, test-like projections standing out from each drop. The central cell is placed low in the gall and can usually be seen protruding when the latter is broken off. Some entomologists have thought this gall to be identical with Walsh''s C. mamma, but I have examined a large number of both forms and find the following points of difference, which convince me that this, if not a new species, is certainly a well marked variety:\nH bassetti as compared with H duricoria, is rather larger and more irregular in outline. The teat-like projection is much heavier and longer in proportion to the size of the gall and appears to be a drawn-out portion of the substance of the gall, while in duricoria it is a small, hard pointed projection much resembling a spine in many cases, and often almost entirely wanting. In bassetti the substance of the gall is more corky and easy to cut. The central cell, as before stated, is at the base of the gall, and when the latter is removed the point of the cell can usually be seen protruding below. Before the gall is detached the central cell is situated with its greatest diameter perpendicular to the limb at the point of attachment of the gall. In duricoria the cell is situated at the center of the gall; it never protrudes from below when the gall is detached; and it always has its greatest diameter parallel with the limb at the point of attachment of the gall. The central or larval cells are also differently shaped. In duricoria the cell is egg-shaped, while in bassetti the end towards the twig is somewhat pointed, so that the cell is very much the shape of a plump apple seed with the point rounded off. , A monothalamous gall occurring singly or in clusters around the stems of the host. When grouped the galls often cover completely 4 to 5 inches of the stem.\nWhen the gall is not deformed by crowding, it is irregularly circular in outline at the base, gradually tapering to a distinct point that is recurved in most cases. The gall is attached to the host by a small stalk at the centre of the base. Colour green, often tinged with pink when young; becoming brown when more mature. The larval chamber resembles closely that found in the former species [Disholcaspis quercusglobulus] in being oval and free at maturity, but it differs in being placed nearer the base of the gall and in tapering to a point at the end nearer the twig. \nDiameter at base, average, 16 mm.\n, Globose, usually with a produced, curved apex, single or clustered twig gall, green turning to brown, on Q platanoides [bicolor], Q imbricaria [mistake? confused with Callirhytis ventricosa?], Bassett''s bullet gall. Broadest at the clasping sessile base and tapering gradually above, the apex often lop-sided, 15-20 mm high, the larval cell basal. Single or in crowded clusters on twigs of trees of Q bicolor in fall. Adults emerge in early Oct.','\n',char(10)),NULL);
INSERT INTO species VALUES(568,''Disholcaspis quercusmamma',NULL,NULL,'Disholcaspis',32,replace('The galls are very common on the twigs of Quercus bicolor and macrocarpa. They may appear singly but are usually crowded in the cluster, are sub-globular in outline with a small teat-like projection. The fly, which much resembles Holcaspis globulus, rugosa, and bassetti, began to appear in the breeding cages Oct 27. Fig 3 is a full size representation of a cluster of these galls., Twig gall. Light tan globular woody gall with a rough surface, found in groups of 3 or more. Bur oak. Summer. Oak bullet gall, Globose, obscurely pointed, green, bright red, turning to brown or dark red, diameter 6 to 18 mm, on Q platanoides [bicolor] Q macrocarpa. , This gall may be confused easily with the preceding [Disholcaspis quercusglobulus]. The distinguishing characters are a velvety surface and pointed apex. It usually occurs in large numbers and in variable sizes on the branches of the burr oak, Quercus macrocarpa. Color: green, turning brown., These round, nipple-tipped galls are found on several species of oaks. They are colored green and red when young, velvety to touch, later becoming red or dark brown. In winter the galls are very hard and may be cut with difficulty. Rough Bullet Galls are generally found on young shoots of oak., In the Chicago area the galls start about the middle or end of July and some are full grown by end of August, adults emerging in different years from October 20 to November 10. \n, Pointed bullet gall. Similar [to Disholcaspis quercusglobulus] but pointed at the apex, subclasping at base, often distorted by crowding and extending along the stem for several inches sometimes. Frequently on sprouts from stumps or on small trees in large numbers in the fall. On Q macrocarpa and bicolor. Adults emerge Oct 20-Nov 10.','\n',char(10)),NULL);
INSERT INTO species VALUES(569,''Andricus apiarium',NULL,NULL,'Andricus',32,'Solitary, sessile, on underside of leaf close to edge in October, shaped like an old-fashioned straw beehive, white or pinkish, measuring up to 4.6 mm broad by 4.0 mm high. Inside is a large cavity with a transverse larval cell at very base. During the winter on the ground the outer fleshy layer shrivels and the gall becomes more cylindrical. Not common. ',NULL);
INSERT INTO species VALUES(570,''Callirhytis tubicola',NULL,NULL,'Callirhytis',32,replace('On Quercus obtusiloba [stellata] Clusters of yellow, tubular galls with red spines, on the underside of the leaves. The gall is a perpendicular tube 0.3 to 0.4 [no unit given] long, slightly narrowed at its point of attachment, open at the other end, yellowish and covered on its outer surface with numerous red spines. If cut open longitudinally, its inside appears divided into three compartments like so many floors, by two horizontal partitions; the compartment nearest to the base is empty, the intermediate one contains the insect and the third one is open at the top. \nIf the red spines are removed with a knife and the surface of the gall examined under a strong lens, it shows dense longitudinal fibres and numerous little pale yellow crystals. The substance of the gall itself is hard, as if crystalline. From 30 to 40 of these galls are found sometimes on the underside of a single leaf. I frequently found them near Washington, in October and obtained the fly soon afterwards, each tube containing a single fly., On Quercus stellata: Cluster of yellow tubular galls bearing red spines, erect on under side of leaf in fall, 12 mm. high.\nGalls stand erect in a group on under side of leaf. Adults May 11-28 the next spring.','\n',char(10)),NULL);
INSERT INTO species VALUES(571,''Neuroterus saltarius',NULL,NULL,'Neuroterus',32,'Small, seed-like bodies, inserted in cup-like depressions on the under surface of leaf and causing a prominent light-colored bulging on the upper side of the leaf opposite, often two or three hundred on a leaf, less numerous on the basal part of leaf blade. When growing the galls are greenish-white, somewhat globular, flattened above with a papilla in center and a raised rim, not pubescent. They start to develop in June and in July or August drop to the ground where they exhibit the phenomenon of bouncing about until the lodge in some crevice in the soil where they pass the winter. When detached a large scar is left on base of gall. During the winter the galls become tan-colored and somewhat compressed laterally, one measured 1.2 mm long by .9 mm thick and 1.1 mm high. ',NULL);
INSERT INTO species VALUES(572,''Andricus pattoni',NULL,NULL,'Andricus',32,'Galls, clusters of larval cells along the midvein of the leaves of Quercus obtusiloba [stellata], on the under side, and standing perpendicular to its surface. The cells are completely hidden in a short, dense brownish wool. The largest clusters often extend along the midvein more than half the length of the leaf. They are found on young trees, and usually on the leaves near the top of the stronger growing shoots. The insects live over winter in the galls. My specimens gathered in October were kept in a warm room and the insects came out in the February following. The galls resemble in their woolly covering those of C. flocci [Andricus quercusflocci] of Walsh, but the latter are round and the woolly hairs are longer, and the species is only found on Quercus alba. ',NULL);
INSERT INTO species VALUES(573,''Andricus ignotus',NULL,NULL,'Andricus',32,replace('Small oval cells, found singly or in small clusters of from two to eight together on the under side of the leaves of Q. bicolor. They are sessile on the midrib and principal veins, and usually lie in a position nearly horizontal to the surface of the leaf They are at first covered with short woolly hairs, but when ripe become more or less denuded. The naked surface when examined with a microscope shows numerous minute papillae, and between these a fine and regular reticulation. They are .10 of an inch in length and . 05 in diameter, and might easily be mistaken for the cocoons of some species of Microgaster. \nAbout fifteen years ago I found a few of these galls on the fallen leaves of a large oak and also on a small tree a few rods distant. The next year the greater part of the leaves on the large tree were covered with galls, a hundred or more being sometimes found on a single leaf I gathered a large quantity after the leaves fell, and the flies came out the next spring. I have examined this tree every year since and have never found any of these galls, nor have I ever seen them on other trees. \nThere are some specimens of this species in the Museum at Cambridge, which Dr. Hagen informs me were found on oaks in the University grounds. I examined some oaks of the same species in the borders of the Botanical Garden at Cambridge last fall, and found several species of galls, but none of these. Can it be that the species has disappeared entirely ?','\n',char(10)),NULL);
INSERT INTO species VALUES(574,''Andricus quercusstrobilanus',NULL,NULL,'Andricus',32,replace('On Quercus prinos, var bicolor [Quercus bicolor]. Large gall, at the tip of twigs, consisting of a number of wedge-shaped bodies, fastened by their poitned ends to a common centre. Diameter about an inch and a half. C q. stobilana [sic] (as yet not reared)\nThese specimens measure rather more than an inch and a half in diameter and look somewhat like the cones of some kinds of pine, for instance, of the scrub-pine, as they consist of a number from 20 to 25 or more of wedge-shaped bodies, closely packed together, with their pointed ends attached to a common centre. These wedges are hard and corky and break off very easily when the gall is dry. Each of them contains a hollow kernel with a plump, large larva inside. This gall is evidently produced by the sting of the insect on the single leaves of a bud, each leaf growing into the shape of a wedge.','\n',char(10)),NULL);
INSERT INTO species VALUES(575,''Callirhytis vaccinii',NULL,NULL,'Callirhytis',32,replace('On Quercus obtusiloba [stellata] Post oak. Clusters of small, somewhat bell-shaped, petiolate, greenish galls on the under side of the leaves, along the midrib. Their shape may be compared to that of the flowers of vaccinium. They are attenuated at the basis into a short petiole, fastened to the midrib of the leaf; the opposite end is truncated the truncature being excavated; the length, from the foot of the petiole to the truncated end, is from 0.12 to 0.15. They grow in numbers, sometimes of ten or more together, so that six, for instance, form a row on one side of the midrib and four or five on the opposite. When found by me on the tree in October 1861, these galls were pale green; the dry specimens are brownish. Inside of each was a small whitish larva, probably of a cynips., [Ashmead quotes the entire Osten Sacken original description]\nThis gall is common; begins developing in August, but does not reach maturity until last of December. I have found the same gall on the Post Oak at Asheville, N. C. , In clusters on the midrib on the under side of the leaves of post oak (Quercus minor [stellata]) in autumn. They grow in numbers on the opposite sides of the rib. Monothalamous, somewhat bell shaped and greenish in color gradually becoming reddish late in the season. They are attenuated at the base into a short petiole, fastened to the rib, and at the opposite end they are truncated, and excavated, making their shape somewhat like that of a huckleberry blossom. Length 3 to 4 mm., The gall and male are not known., On the under sides of the leaves of post oak (Quercus minor [stellata]) in clusters from about 4-40 individuals closely packed together, on the mid-rib and lateral veins, September to November. Monothalamous. Green, sometimes tinged with red. Elongate, rounded at the sides, narrow at the point of attachment and concave at the apex with a small central nipple. Outside it is rather densely covered with small pustules. When young, the gall is almost solid, but as it grows older the larval chamber gradually occupies the entire interior. After it drops to the ground, late in the fall, the gall gradually changes its shape to almost globular (berry-like) with the concave apex flattened and the surrounding rim less prominent. The crystal-like pustules change, the gall becoming evenly rugose. The point of attachment becomes long, narrow, and sharply pointed. The entire inside becomes hollow with the outer wall thin and brittle. Length 2.5 to 5 mm, width 2 to 4 mm, length of clusters 5 to 35 mm., These galls occur as midrib clusters on under side of leaves of Quercus stellata in the fall, dropping when mature. When fresh the individual galls are shaped like huckleberry flowers, somewhat cylindrical with the end distinctly truncate and depressed, but during the winter on the ground they become globular except for a short pedical, and the depressed end becomes a flattened circular scar at apex with a slightly raised rim, and the greenish or reddish color changes to brown., Clustered, seed-like leaf galls. Each gall monothalamous, elongate, rather cylindrical, urn-shape, broadest at the middle, less broad apically, flattened at the end, taper pointed basally, up to 4 mm in diameter by 6 mm in length; colored dark green when young, becoming a dark red or purplish red when old. Mostly solid and fleshy when young, becoming hard, thin -walled, and hollow when old, without a distinct larval cell lining. In compact clusters of up to 30 galls, attached to the midrib, on the under sides of leaves of Quercus stellata (and Q breviloba?)\nThis gall is very common on the post oaks in Texas. Patterson states that the punctures from which the galls will arise may be detected about the first of May, that the galls do not develop from the scars until about the middle of July, that the galls are fully grown in size by the first of October, and in a couple of weeks most of them fall to the ground. I have collected them in late November and December, but the larva are then still so small that they do not mature after becoming dry. Evidently they need to be kept moist, as they are when lying on the ground, to allow the insect to develop. Patterson secured over a hundred adults which emerged from February 12, 1922, to March 8. Inasmuch as the breeding of the insect is difficult unless carefully handled on the field, we are considerably indebted to Dr. Patterson for successfully rearing the adult. I collected the galls, but did not obtain the insects from the other Texas localities listed. It is possible but not prob-able that other varieties occur at some of those points. The gall occurs on Q. breviloba at Leander, and Patterson reports it as occasionally on breviloba at Austin. It is not unlikely that the breviloba insect is a distinct variety with a range centering about Burnett County, Texas. \n, On Quercus breviloba: Midrib cluster like Callirhytis lustrans\nOn Quercus stellata: Midrib cluster on under side in fall, each with a short stalk, end truncate and depressed.\nFigure caption: There is a similar gall on Q margarettae and on Q chapmanii which has never been reared., On Quercus stellata: Galls shaped like those of C lustrans, in numbers in rows on either side of the midrib in the fall. Turn black in drying. Entered from literature.','\n',char(10)),NULL);
INSERT INTO species VALUES(576,''Zopheroteras hubbardi',NULL,NULL,'Zopheroteras',32,'Nothing is known regarding the habits of this species.',NULL);
INSERT INTO species VALUES(577,''Dryocosmus deciduus',NULL,NULL,'Dryocosmus',32,replace('On the midrib of the leaves of red oak (Quercus rubra) and black oak (Q velutina). Rounded or elongated swellings filled with oblong kernels from a few to about 40, all depending on the size of the gall. When young these bodies are concealed in the hard, fleshy part of the gall and as the swelling grows older the seed-like kernels gradually protrude therefrom and when fully grown late in September and early in October the swelling bursts open completely and the kernels are whitish, yellowish, sometimes tinged after they become exposed., Rounded or elongate midrib swellings filled with oblong or elongate kernels, a few to 40, when young concealed in the tissues and bursting open in October on Q rubra, Q velutina., Clusters of seedlike bodies, often 30 to 40 together, occur on the under side of the midvein of red oak leaves, the larger cells smooth, greenish white with an enlarged apex and about the size of grains of wheat, on Q bicolor, Q ilicifolia, Q rubra, and Q coccinea., Clusters of seed-like bodies, often thirty or forty together growing on the midvein on the under side of the leaves of Q rubra. The larger cells are about the size of a grain of wheat. They are smooth, greenish-white, the apex enlarged, and would remind a botanist of the sessile stigmas of some flowers., Black oak wheat. Individual galls about size and shape of a kernel of wheat with a fleshy knob at upper end, greenish, smooth, bare. When young concealed in the swelling midrib but later bursting out of a crack in a compact cluster of from a few to 40 galls often rupturing the leaf blade so as to be visible from above, dropping in Oct. On Q rubra and velutina. Galls collected Oct 1916 gave adults Mar 23-Apr 22 1918.  , On Quercus coccinea, falcata, ilicifolia, imbricaria, marilandica, rubra, velutina: Black Oak Wheat. Cluster of up to 40 bursting out of midrib in early Oct, dropping when mature.\n','\n',char(10)),NULL);
INSERT INTO species VALUES(578,''Andricus robustus',NULL,NULL,'Andricus',32,replace('A midrib cluster on under side of leaf in fall, the galls dropping to the ground when mature. The individual galls are somewhat globular, tapering to a pedicel at base and pointed with a slight scar at apex, greenish and mottled with white when fresh turning brown during winter on ground. \nThe type material was collected at Arlington, Texas, November 3. 1917, when the galls were still dropping to the ground. On December 1.1919. living flies (that would probably have emerged in spring of 1930) were cut from the galls. Some of the same lot of fresh galls were sent to William Benteninueller, who reared adults January 10. February 11. 15. 20, 21. 1919, and more in February. 19211. Paratype flies were cut out December 1, 1919. from galls collected Texarkana, Ark.. in October. 1917. The galls have been collected also at Webster Groves. Poplar Bluff. and Ironton. Mo. Hoxie,. Little Rork. and Hot Springs. Ark:: Palestine. Cuero. and Austin, Tex.: Cottondale. Fla.: Washington. D. Falls Church. Va. Galls collected at Washington in late October. 1923. gave adults February 22 March 1. 14. 17. 1925. and these have been included among the paratypes. , In clusters on the midrib of post oak (Quercus minor [stellata]). Monothalamous and moderately thick-walled with a large round larval chamber. Globular and almost like a huckleberry or fruit of hackberry (Celtis occidentalis) with a more or less distinct nipple at the apex and long petiole or stem at the base by means of which it is attached to the leaf. Brown when old and probably green when fresh. The outer surface is slightly roughened or almost smooth. Diameter 4-7 mm; petiole 1-2.5 mm long. The gall somewhat resembles that of C dimorphus, but is larger and more globose. It occurs in clusters like dimorphus, but the galls as less closely together and not pressed out of shape, each individual gall retains its globose shape. The male is not known., Globose, clustered, monothalamous, midrib gall with a more or less distinct nipple apically and a long stem basally, brown when old, probably green when fresh, diameter 4 to 7 mm, stem 1 to 2.5 mm, resembles a huckleberry, on post oak., On Quercus stellata: Midrib cluster of thick-walled, one-celled galls shaped like a huckleberry or hackberry fruit, with nipple at apex, stalk 1-2.5 mm long, gall 4-7 mm in dia. Entered from lit., On Quercus stellata: Midrib cluster on under side of leaf in fall, each pointed at apex, dropping when mature.','\n',char(10)),NULL);
INSERT INTO species VALUES(579,''Andricus flavohirtus',NULL,NULL,'Andricus',32,'On the terminal twigs of swamp white oak (Quercus platanoides [bicolor]) early in June. Monothalamous, globular, and thin-shelled, containing no separated larval chamber. Green when fresh, brown or gray when old. It is embedded in a cluster of short, lanceolate, aborted leaflets, more or less concealing the gall. When mature it drops to the ground, leaving the bunch of leaflets on the twig. Diameter 3 mm. ',NULL);
INSERT INTO species VALUES(580,''Amphibolips quercusspongifica',NULL,NULL,'Amphibolips',32,replace('On the leaves usually from a vein or the petiole on red oak (Quercus rubra), scarlet oak (Quercus coccinea), quercitron or yellow oak (Quercus velutina) in May and June. Globular or nearly so, smooth, shining or opaque with a thin outer shell. Internally filled with a juicy white spongy substance and with a large, hard, central larval cell. When fresh the gall is green, and light brown when old and dry, with the internal spongy substance dark brown. Diameter, 25 to 50 mm.\nThis well-known gall is very common and hundreds may often be found upon a single tree. It makes its appearance early in may, as soon as the leaves put forth, on different kinds of oaks belonging to the red oak group, and is fully grown in a few weeks. It is popularly known as "oak-apple" or May-apple, owing to its superficial resemblance to a small apple. , Attached to the midrib near the base of a leaf and prevents its development beyond the point of attachment. It occurs on a species of oak probably, Quercus minor [Quercus stellata--this is incorrect]. Resembles the galls of Amphibolips spongifica and Amphibolips cinerea, but the surface is more coarsely reticulated and less glossy. Internally the spongy mass surrounding the larval cell is of a much darker color. The outer shell is thinner and in dried specimens is irregularly shrunken and depressed. The gall very much resembles that of Amphibolips longicornis., Allied to A spongifica, and probably found in similar situations on the leaves and young twigs of oak. Monothalamous and very thin shelled. Internally it is of a soft, light and spongy consistency not unlike that of A spongifica. Length 35 mm, Width 30 mm. The species of oak upon which the galls of this species occur is not known. , Globose, monothalamous, very thin-shelled leaf and twig gall, internally soft, light, spongy, not unlike A confluens form spongifica, diameters 3.5 and 3 cm., A large "oak-apple" with a very thin shell and a single larval cell in the middle of a soft, light and spongy mass, not unlike that of A spongifica OS. It is an inch and a half long and an inch and a quarter thick. Species of oak unknown., The galls belong to the oak-apple family, and much resemble those of A spongifica OS and A coccinae OS, but the surface is more coarsely reticulated and less glossy, and internally the spongy mass surrounding the larval cell is of a much darker color. The shell is also much thinner, and, in my dried specimens, is irregularly shrunken and depressed, until they look like pressed figs. I am not sure as to the species of oak on which they grew, but the few immature leaves that came with the galls seem to be those of Q obtusiloba [Quercus stellata--a mistaken guess]. The galls are attached to the midvein near the base of the leaf and prevent its development beyond the point of attachment; they are as large as those of A spongifica, and differ widely from A cinerea described by Mr. Ashmead., Globular leaf gall resembling that of A confluens, form spongifica, and A cinerea, but the surface is more coarsely reticulated and less glossy and the larval cell much darker in color, diameter 2.5 cm on midrib near base of leaf on Q ?minor [Quercus stellata; incorrect], Quercus rubra. Red Oak. Large, smooth, globular gall on the leaves, filled, when ripe, with a brown, spongy mass. Diameter about 1.5.These galls are more than one inch, sometimes almost two inches in diameter. "They are green and somewhat pulpy at first, says Dr. Harris, but when ripe, they consist of a thin and brittle shell, of a dirty drab color, enclosing a quantity of brown, spongy matter in the middle of which is a woody kernel about as big as a pea. A single grub live sin the kernel, becomes a chrysalis in the autumn, when the oak-apple falls from the tree, changes to a fly in the spring and makes its escape out of a small round hole which it gnaws through the kernel and shell. This is probably the usual course, but I have known the fly to come out in October."I am more inclined to agree with Dr Fitch who supposes that there are annually two generations of this fly. They are not rare around Washington, but I have never found them so abundantly as they seem to occur in other localities. On the first of June I found balls of this kind already ripened, measuring one inch and a half in diameter, of the usual drab color and somewhat greenish only at its base. One of them, which I opened contained a larva. On the 13th of June another gall was opened, it contained the perfect insect, but with wings yet wet and folded and evidently not quite ready to escape. , The external appearance of this gall is very like that of the gall of C. q. inanis. It is more or less globular (although irregular specimens of both frequently occur), that is, not narrowed towards the basis; its surface is glossy. Internally, it is easily distinguished by the spongy mass which fills it. It seems to reach a larger size than the former gall, as among six specimens now before me, one measures an inch and a half in diameter and two others are but little smaller, whereas among eight specimens of the gall of C q inanis the largest does not much exceed an inch. From the following gall [Cynips quercus spongifica] it is distinguished by its glossy surface, its less dense and more whitish spongy internal matter, its much thinner and brittle shell and by its shape, which is more rounded on the top. , Quercus tinctoria [velutina]. Black Oak. Large, round gall, somewhat attenuated and pointed at the top; surface more or less opaque, as if powdered or dusted; shell thick, inside, a dense, spongy, brownish substance, surrounding the kernel. Diameter about an inch and a half. \nOn the 25th of May last I found four full-grown specimens of this gall on the leaves of a large black oak and have obtained, on June 15, three female specimens of the gall-fly. They look exactly like C. q. inanis, only they are a little larger (the gall also being larger). . . Of these galls three, taken from a high branch of the tree, can be considered as typical specimens. They are slightly oblong, that is, somewhat extended into a point at the end, although not narrowed at the basis. Their diameter is about an inch and a half. Their color is drab, sometimes spotted with brown on one side; the surface is more or less opaque, as if powdered or sericeous, and shows very little gloss. The shell is much thicker than that of the two previous species [Cynips quercus coccineae and Cynips quercus inanis]; the spongy mass is more dense and brownish.\nA fourth specimen, found on the same tree, is more irregular in its shape; its surface is without any gloss and altogether drab, without brown spots. Specimens of this kind are frequently found on young shrubs of Q tinctoria [velutina], the leaves of which are very rusty-puberelent beneath., The Fibrous Oak-apple. Amphibolips coccineae. There are several large, spherical galls, common on oaks, which have received the name of oak-apples. These galls resemble each other quite closely in their external appearance, but differ much in their internal structure. The one which we name the Fibrous Oak-apple is represented by Figure 746. In the centre of the gall there is a small, hollow kernel, in the cavity of which the gall-fly is developed. The space between this kernel and the dense outer layer of the gall is filled with many fibres, which radiate from the kernel. This gall is found on the scarlet oak, and varies in size from three fourths inch to two inches in diameter., The Spongy Oak-apple, is most common on red oak, but it occurs also on the black oak. In this gall the space between the kernel and the outer layer is quite densely filled with a porous mass, which suggests the name spongy., Large spongy oak apple. Galls appear with the leaves in spring, becoming 40 mm in diameter, green until full grown early in May, turning brown about the time the flies, males and females, emerge the latter half of June. On Q velutina., A globular gall found attached to leaf by small portion. Monothalamous; larval cell surrounded by brown spongy mass, and that by a rather smooth thickened wall. Pale green and soft while fresh, turning brown and brittle. 2-4 cm in diameter. Common on black, red, and scarlet oaks. Begins growth about May. Males and females emerge in June. Some females remain until October (C aciculata OS) A good example of dimorphism., Leaf-gall, globular, suppressing part or all of leaf, at first green, soon becoming light brown, with shiny, paper wall, containing a spongy mass of radiating fibres covered with down, which hold in place the oblong central larval chamber. 3-5 cm in diameter. Common at Huron. , On Quercus palustris: Spongy Oak Apple.\n[Figure caption section--no figure] Gall similar in size and appearance to [A confluenta] on Q velutina, coccinea, ilicifolia, palustris, rubra, falcata [why doesn''t he list these host associations in the main text?] Galls appear with the leaves in spring. Adults of both sexes emerged June, all out by July.','\n',char(10)),NULL);
INSERT INTO species VALUES(581,''Amphibolips confluenta',NULL,NULL,'Amphibolips',32,replace('The largest galls in this country [Massachusetts] are commonly called oak-apples. They grow on the leaves of the red oak, are round and smooth, and measure from an inch and a half to two inches in diameter. This kind of gall is green and somewhat pulpy at first, but, when ripe, it consists of a thin and brittle shell, of a dirty drab color, enclosing a quantity of brown spongy matter, in the middle of which is a woody kernel about as big as a pea. A single grub lives in the kernel, becomes a chrysalis in the autumn, when the oak-apple falls from the tree, changes to a fly in the spring, and makes its escape out of a small round hole which it gnaws through the kernel and shell. This is probably the usual course, but I have known this gall-fly to come out in October. , Globular, smooth, shining or opaque leaf gall, internally a juicy, white, spongy substance and a large central larval cell, green, turning with age to light brown, diameter 2.5 to 5 cm, usually on a vein or petiole, on Q rubra, Q coccinea, and Q velutina in May and June., Quercus tinctoria [velutina]. Black Oak. Large, round gall, broad and rounded at the top; surface smooth and glossy; shell thick, inside, a dense, brown, spongy substance, surrounding the kernel. Diameter upwards to an inch and a half. \nThe specimens . . . can be distinguished at once from the gall of C q spongifica, by their smooth, glossy surface and their subglobular or short-oval form, their basis being slightly attenuated, their top, on the contrary, being broad and rounded. Otherwise, their thick shell and their dense, brownish spongy substance reminds of C q spongifica. , Similar [to Amphibolips spongifica] but the adults, all females, emerge in Nov. Probably an alternating generation of the above but the life history needs further study., A monothalamous gall attached to the petiole or midrib of the leaf. The midrib is never continued beyond the point of origin of the gall.\nGlobular to prolate spheroidal in shape and invariably terminating in a minute point. The thick walled larval cell at the centre of the gall is surrounded by a sponge-like mass of fibres that is at first white but becomes dark brown when the gall is dry. At a very early stage of development the epidermis of the gall is pubescent but later it becomes smooth. The colour is at first green but this changes to a lustrous light brown when the gall is old. Dimensions:—Average diameter 4o mm. \n(a) Stage in which the gall is 2 mm. in diameter. Almost the entire gall consists of a compact tissue, which is composed of small uniform cells. Lines of narrow elongated cells, however, pass in a radial direction throughout this tissue. These cells do not extend into the gall cavity nor out to the epidermis, they traverse about two-thirds of the gall radius. As they approach the epidermis the lines curve around and run parallel to its surface. Spiral vessels are in some cases differentiated in these rays and the elements are more numerous near the point of attachment of the gall. \n(b) Older stage 9 mm. in diameter. The gall wall can now be divided roughly into three sections. That part lying next the larval cell resembles closely the compact tissue described in the preceding stage, except that immediately adjoining the cavity a typical nutritive layer has been formed by the elongation of the cells in a radial direction. In the centre zone the lines of cells containing the vessels are much more apparent at this stage, since the intervening tissue has become loose and skeleton-like. The cells composing it are long, very narrow and frequently branched. In many cases a branch is attached to the main cell without the formation of an intersecting partition between the two. The outside zone of the three is composed of somewhat elliptical cells. These form a fairly firm tissue constituting the rind of the gall. \n(c) Mature stage. The protective zone is now the most characteristic feature of the anatomical structure. The part of the protective sheath adjoining the larval cavity consists of a few layers of elliptical cells arranged in tangential rows. The sclerenchymatous deposits on the outside walls of these cells are much heavier than those on the inside. Further out the protective cells are formed in radial rows and their walls are uniformly thickened. This protective strengthening of the cell walls extends even into the loosely arranged filament-like cells, some of which are heavily sclerified.\n, Thin walled and globular, about 4 cm in diameter. Exterior surface smooth (not pubescent) and somewhat irregular. Interior filled with a spongy mass of fibres, very loosely attached to the exterior but tightly attached to an interior woody cell in which the larva lives. Green in the early part of the season, later turning brown and brittle. Generally produced on the upper part of the leaf from the end of one of the veins. Occurs on Red Oak and other closely related species. Common., This is one of our common oak galls. It is nearly globular in shape, greenish or brown in color dependent on its age, and its interior is filled with a spongy mass in the center of which is a single larval cell. This species is occasionally quite abundant on trees, as may be seen by reference to plate 50, figure 1, though it cannot be considered injurious. [The figure in Felt''s plate seems to be what we would now call Amphibolips quercusinanis], Large, globular, more or less smooth outside and filled with a spongy substance in the center of which is a hard woody kernel containing the larval cell. From 1 to 2 in in diameter. When fresh, it is pale green, soft and succulent, with the contents whitish. Later in the season the shell becomes brown, hard and brittle, with the kernel woody and the spongy substance dark brown, but remaining soft. Confined to the leaves of the trees belonging to the red oak group. Common., The Large Oak Apple gall, occurs from southern Canada to Virginia. It produces galls on the leaves or leaf petioles of various oaks, principally red, black, and scarlet. These galls are quite large, from 12 to 50 mm in diameter, and greenish to brownish in color, depending on age., The mature insects are small, gall wasps which appear early in the spring; the eggs are laid in the tissues of the leaves or the petioles. The globose galls are 0.5 to 2 inches in diameter and are conspicuous. As they develop, they change from green to brown. One larval cell is in the center of the gall, which is filled with a spongy mass of fibers.\n, This is the largest of our common oak apples, measuring from 1 to 2 inches in diameter. It occurs on several species of oak and is usually attached to a vein or the petiole of a leaf. the space between the larval cell and the outer wall of the gall is filled with a spongy mass of tissue, in which some of the galls there are many radiating fibers, as shown in the figure above, but in other galls these fibers are indistinct, the space being filled with an amorphous mass of tissue., On Quercus falcata, ilicifolia, marilandica, rubra: Spongy Oak Apple. Aborts the development of the leaf. Agamic females emerge in October.\n[Figure caption] Spongy Oak Apple. On Q velutina. Also on Q coccinea, rubra, falcata, marilandica, texana. Galls in NY contained pupae Aug and adults Sept. Adults emerged Nov--all females.','\n',char(10)),NULL);
INSERT INTO species VALUES(582,''Amphibolips quercusinanis',NULL,NULL,'Amphibolips',32,replace('Quercus rubra. Red oak. Large, smooth, globular brownish-yellow gall, attached to the underside of the leaves, inside with whitish, delicate filaments radiating from the kernel to the shell. Diam about an inch.\nVery like gall No. 1 [Cynips confluens] at first glance, but smaller, the specimens in my possession measuring an inch or a little more in diameter. It is also fastened to the leaf by a small point on its surface. The outside of this gall shows no other difference from the oak-apple of the red oak but the size. The inside on the contrary distinguishes them at once; instead of the spongy, brown mass with which the other gall is filled, this one is almost empty, the kernel being kept in its central position by a certain number of whitish filaments which radiate from it to the shell. , Q coccinea. Scarlet oak? Large, more or less round gall, not attenuated towards the basis; surface glossy; shell thin and brittle; on the inside whitish filaments radiating from the kernel to the shell. Diameter about an inch.\nAmong the specimens of my collection, I find a number of galls, collected in one locality and somewhat different in shape from the typical specimens of C q inanis. The latter are more or less globular, the leaf being, so to say, the tangent of the globe. There is no distinct point or nipple on the top. The other gall, on the contrary, is somewhat lemon-shaped, being attenuated at its basis with a corresponding elongation, ending in a minute nipple, at the opposite end. Its color is more brownish than that of C q inanis; on the inside, I did not detect any difference between both galls. The tree is also either the red or the scarlet oak. , The Larger Empty Oak-apple. There are two oak apples which are very similar in structure, and which may be termed the empty oak apples. In these the space between the central kernel and the outer shell contains only a few, very slender, silky filaments, which hold the kernel in place. The larger of these two galls measures an inch or more in diameter, and is found on the scarlet oak and the red oak., This is a spherical gall with thin walls from which many fibers extend towards the center, these holding in place the cell in which the larva develops. The gall is between 15 and 30 mm in diameter, light yellow-green changing to light brown. Common on leaves of scarlet and red oak. Matures in june., Resembles the preceding species [A confluenta] in external appearance and in its attachment to the midrib or the petiole of the leaf. In shape it is more nearly spherical than A. confluens Harr. and it has a much thinner rind than is found in that species. The epidermis of the gall, which is at first green with dark spots, becomes light brown with darker patches at a later stage. The larval cell in this case is held in position by a number of fine radiating fibres. Dimensions:—Average diameter 35 mm. In the earlier stages the anatomical structure of this gall is practically the same as A. confluens Harr. The vascular strands surrounded by elongated cells are present, but as the gall becomes older the connecting tissue from between the strands disappears. In the mature gall the protective zone is very apparent. It consists of 8 to to rows of comparatively small elliptical cells. The walls of these cells are uniformly thickened, constituting a porous sclerenchyma. ','\n',char(10)),NULL);
INSERT INTO species VALUES(583,''Atrusca quercuscentricola',NULL,NULL,'Atrusca',32,'The Smaller Empty Oak-apple is found on the post-oak and measures three fourths of an inch or less in diameter. It also differs from the preceding in that the outer shell is mottled.',NULL);
INSERT INTO species VALUES(584,''Amphibolips quercusostensackenii',NULL,NULL,'Amphibolips',32,'Smaller oak apple. Diameter 14 mm a third of the sphere projecting from the upper surface of the leaf, the rest on the under side, seldom more than one on a leaf, green, not spotted. On Q rubra in May and June, the adults emerging early in July., Similar [to Andricus singularis] but smaller, diameter about 8 mm, on Q coccinea in June. Adults emerged July 8-15.',NULL);
INSERT INTO species VALUES(585,''Disholcaspis globosa',NULL,NULL,'Disholcaspis',32,'Similar to those of Disholscapis globulus (Fitch) in appearance, but less regular in shape and dark red or sometimes yellowish. They occur in clusters at base of 2-3 year old sprouts from stumps and are almost always hidden by debris. Scattering small ones are sometimes seen exposed a few inches above the surface. They are closely crowded together about the base of sprougs and there may be from two or three to as many as forty in the cluster. Each is 8-12 mm in diameter, the interior spongy, with a distinct thin inner shell., On Quercus alba, prinus [montana/michauxii]: Cluster of 3-40 reddish bullet galls, 8-12 mm in dia., at base of sprouts, usually hidden by debris. Adults emerge in late Oct and early Nov., Individual galls averaging over 7 mm in diameter. Globular bullet galls with a distinct inner cell often free in an irregular cavity within. Up to 40 in a cluster at base of sprouts from stumps of Q alba. Adults emerge in late Oct and early Nov.',NULL);
INSERT INTO species VALUES(586,''Callirhytis gemmiformis',NULL,NULL,'Callirhytis',32,replace('On the trunk of the white oak (Quercus alba), May-October. Monothalamous. Green, sometimes tinged with red. Bud-shaped, elongate, pointed at the apex, thin-walled when mature and hollow inside and containing no separate larval chamber. When young it is more solid. Length 3-4 mm.\nThe gall is found on the trunk of large, white oak, where the same is gnarly and young shoots sprout forth. It is imbedded in a cavity and may be easily removed. The gall looks exactly like the bud of a young sprout, and may be readily mistaken for such and overlooked. I have found fully developed galls May and June and also late in October., Bud-shaped, elongate, pointed apically, thin-walled and hollow. Length 3 to 4 mm, on trunk of white oak. , Galls of this species have been collected on Q alba in IL and on Q bicolor in IL. Galls collected in Oct contained pupae in Sept the following year and adults in Nov. These would probably have emerged in the spring after., Conical, greenish becoming brown when mature, 3-4 mm high, from weak dormant buds on limbs or from adventitious buds on trunk of large trees of Q alba in Sept and Oct. Deciduous. Adults emerge the second spring, transforming the fall before.','\n',char(10)),NULL);
INSERT INTO species VALUES(587,''Andricus weldi',NULL,NULL,'Andricus',32,'On the underside of the petiole of the leaf of white oak (Quercus alba) at the junction of the leaf blade, July to October. A rounded ball-like cluster of bright red or brownish galls closely pressed together and out of shape. The individual gall is rounded or tuberculated on the summit, flattened at the sides and pointed at the place of attachment. It is solid when fresh with a single barely visible larval chamber in the center. Late in September and in October the galls become detached, drop to the ground and the larvae continue to feed therein. The gall gradually changes its shape and becomes subtriangular or polyhedral and may be taken for that of another species. The outer shell becomes thin, soft, darker in color, and the inner part is eaten away until only a hard and woody shell remains. Diameter of clusters 8-20 mm. Individual galls 5-10 mm., A globular cluster, 8-20 mm in diameter, on under side of petiole at its junction with the leaf blade, consisting of a dozen or more reddish brown galls, closely pressed together, tuberculate at the distal end, flattened at the sides, tapering to the point of attachment, dropping to the ground in late Sept or Oct before the leaves. On trees of Q alba. The emergence of the flies is in March or early April and distributed over a period of five or six years, none probably appearing until the second spring., On Quercus alba and prinoides: Cluster of 6-10 brown galls, 10 mm in dia. closely pressed together at junction of petiole and leaf blade in fall, dropping singly when mature. Galls drop in Oct. Emergence is distributed over three seasons beginning the second spring.',NULL);
INSERT INTO species VALUES(588,''Asteromyia euthamiae',NULL,NULL,'Asteromyia',4,'Black blister on leaf or stem. Galls are occasionally bordered with purple. Leaf galls may dehisce separately from the leaves. A euthamiae has several generations per year and presumably overwinters as full-grown larvae in the last generation of galls. ',NULL);
INSERT INTO species VALUES(589,''Asteromyia carbonifera',NULL,NULL,'Asteromyia',4,'Leaf blister gall. Galls contain a symbiotic fungus that apparently is not eaten by the larva. The fungus turns hard and black and becomes incorporated with the plant tissue as the larva matures. This species is found on most goldenrods and is widely distributed across North America. As the season progresses, galls develop on leaves progressively farther up the stem. The color of the galls is characteristic of the host species. The size is variable also, 5-15 mm in diameter on S canadensis with one to several larvae, 3-4 mm in diam on S juncea with one larva. Hosts: most species of Solidago.',NULL);
INSERT INTO species VALUES(590,''Asteromyia modesta',NULL,NULL,'Asteromyia',4,'This species is less common on goldenrod than A carbonifera and, unlike the latter, does not have a fungus associted with it but lives simply in the mesophyll layer of the leaf and forms only a single convexity on the leaf. Hosts Erigeron spp., Conyza spp, Grindelia spp.',NULL);
INSERT INTO species VALUES(591,''Amphibolips globulus',NULL,NULL,'Amphibolips',32,'On the twigs of black jack oak (Quercus marylandica [marilandica]) in September. Globular, thick-shelled, with a small nipple at the apex. Filled with a very dense mass of radiating spongy substance. Green when fresh, brown when dry. Diameter 14 to 17 mm. The gall very much resembles that of Holcaspis globulus [Disholcaspis quercusglobulus] externally, but the internal structure is very different. , Globular, thick-shelled, slightly nippled twig gall, green, becoming brown, diameter 14 to 17 mm, on Q marilandica., On Quercus cinerea [incana], falcata, marilandica, phellos: Globular, thick-walled with a slight nipple at apex, 14-17 mm in dia. Sept. Described from NJ.',NULL);
INSERT INTO species VALUES(592,''Rabdophaga rosacea',NULL,NULL,'Rabdophaga',4,'',NULL);
INSERT INTO species VALUES(593,''Amphibolips quercuscoelebs',NULL,NULL,'Amphibolips',32,replace('Quercus rubra. Red Oak. Elongated, fusiform, pale green gall, with a pedicel, inserted on the edge of the leaf and being the prolongation of a leaf-vein. Length about an inch. \nThe pedicel is about 0.15-0.2 long; the gall itself is an elongated, subcylindrical body, tapering on both sides, 0.6 or 0.7 long; its apex is slender, about 0.1 or 0.15 long. I have found three specimens of this gall near Washington, in June; two are inserted on the margin of the leaf, not far from the stalk; the third is on the leaf-stalk itself, but so that on the side of the gall the leaf originates about half an inch above its place of insertion, whereas on the other side the beginning of the leaf corresponds exactly to the place of insertion of the gall-stalk. In all the three cases, the gall is the prolongation of a vein; in the latter case, the vein, in consequence of the growth of the leaf, has become entirely independent of the blade and appears to be growing out of the leaf-stalk. \nThe inside of these galls is hollow; each contains a brownish, oblong nucleus, kept in position by woody fibers. ','\n',char(10)),NULL);
INSERT INTO species VALUES(594,''Callirhytis seminosa',NULL,NULL,'Callirhytis',32,'On Quercus palustris, rubra: Abrupt, surface very irregular, cells very numerous., Hard, woody knots, sometimes terminating the shoots in a clump of oak sprouts (Q castanea?), but oftener an enlargement of the base of the small lateral branches. In my specimens the terminal galls are an inch in diameter and shaped like a strawberry. The others are about half as large, and of the same shape. All are more or less uneven on the surface. These are all old galls and the outer bark has mostly fallen off, and the entire surface is dotted as thickly as possible with very small, open larval cells. The larger galls must contain, each, several hundreds of these tenantless cells. The cells are distinct from the woody fibre in which they are imbedded, but cannot be separated from it. The galls are easily taken for those of A scitula Bass. and such I took them to be until I found that the insects were very different.  ',NULL);
INSERT INTO species VALUES(595,''Callirhytis quercuspunctata',NULL,NULL,'Callirhytis',32,replace('On Quercus cinereae [incana], coccinea, imbricaria, nigra, palustris, rubra, velutina\nOak Knot Gall. Abrupt, completely encircling branch, covered with normal bark. Immature galls cut like cheese. Twig beyond gall usually dies and this has been known to kill isolated trees. Adults emerged Apr. 16. The alternating generation is a small blister on main veins about May 12., Quercus rubra. A smoothish club-shaped, woody knot, four inches long, and an inch and a half in diameter at the upper and largest end, completely encircling a branch half an inch in diameter. \nThis gall was cut from a very young and thrifty oak, April 11. The flies were then fully grown and began to appear in less than a week. No other galls were noticed at the time, but now (Oct) there are several of this year''s growth,--some larger and others much smaller than the one described. The new galls were fully grown the middle of June, but no larvae could be detected then. The larvae are now, however, well developed. There are hundreds of other oak trees of the same species near this one, but I have no been able to find any similar galls upon them.','\n',char(10)),NULL);
INSERT INTO species VALUES(596,''Acraspis quercushirta',NULL,NULL,'Acraspis',32,replace('Quercus montana. Hard, round galls, .25 of an inch in diameter with a finely papillose surface and a solid radiated cellular structure; growing sometimes on the upper, but as often on the under side of the leaf; attached to the larger veins by a very short pedicel. \nThese galls are rarely met with, and I have seldom found more than one on a leaf. In a single instance there were three on the same leaf, two on the under side and one on the upper. My specimens were found in October and contained perfect insects. Through the gall of several, gathered October 20th, the insect had eaten a passage but they still remain in the galls. , Galls agreeing with the Bassett types on rock chestnut oak were collected on Q montana in NY and VA. They are found in September and October. No adults reared. Probably emerge in the fall., Quite spheroidal, moderately large, up to 6 mm in diameter; the faceted surface without projecting spines and consequently smooth in appearance; on leaves of Quercus montana (=Q prinus = Q. monticola), Q michauxii, and probably related chestnut oaks.\nThis is the chestnut oak variety of the species, originally described from Q prinus and now recorded from Q michauxii. Most of the Cynipidae do not make distinctions between the several species of Middle-Western chestnut oaks. Beutenmuller''s 1900 record and Viereck''s 1916 records of Q ilicifolia as the host are certainly errors, while the Q macrocarpa records should apply to variety macrescens [Acraspis macrocarpae]. \n, On Quercus muehlenbergii, prinus [montana and michauxii]: Globular, 4-6 mm in dia, on under side of leaf on a secondary vein, one to three on a leaf, one-celled.\nAn adult was cut out Sept 12 and 21. Normal emergence probably in late fall. An adult was captured on snow Dec 20.','\n',char(10)),NULL);
INSERT INTO species VALUES(597,''Xanthoteras ornatum',NULL,NULL,'Xanthoteras',32,'Spindle-shaped, covered with a golden brown mass of short filaments; 6 mm wide by 11 mm long, widest slightly above the middle, distinctly tipped apically. Covered with a dense compacted mass of filaments, each filament short, wholly flattened with a slender, narrow blade 2 mm long, the tips purplish when fresh. The central stem is swollen to form a thin-walled, empty larval chamber, apparently monothalamous. A bud gall, or on leaves, attached to the end of the mid-rib, on Quercus breviloba.',NULL);

-- CREATE TABLE gall(
--     species_id INTEGER NOT NULL,
--     taxoncode TEXT NOT NULL CHECK (taxoncode = 'gall'),
--     detachable INTEGER, -- boolean: 0 = false; 1 = true, standard sqlite
--     texture_id INTEGER,
--     alignment_id INTEGER,
--     walls_id INTEGER,
--     cells_id INTEGER,
--     color_id INTEGER,
--     shape_id INTEGER,
--     loc_id INTEGER,
--     FOREIGN KEY(species_id) REFERENCES species(species_id)
--     FOREIGN KEY(taxonCode) REFERENCES taxontype(taxonCode)
--     FOREIGN KEY(loc_id) REFERENCES location(loc_id)
--     FOREIGN KEY(walls_id) REFERENCES walls(walls_id)
--     FOREIGN KEY(cells_id) REFERENCES walls(cells_id)
--     FOREIGN KEY(color_id) REFERENCES color(color_id)
--     FOREIGN KEY(loc_id) REFERENCES shape(shape_id)
--     FOREIGN KEY(loc_id) REFERENCES alignment(alignment_id)
-- );
-- CREATE TABLE "Gall" (
--     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
--     "speciesId" INTEGER NOT NULL,
--     "detachable" INTEGER,
--     "colorId" INTEGER,
--     "wallsId" INTEGER,
--     "cellsId" INTEGER,
--     "alignmentId" INTEGER,
--     "shapeId" INTEGER,

--     FOREIGN KEY ("speciesId") REFERENCES "Species"("id") ON DELETE CASCADE ON UPDATE CASCADE,
--     FOREIGN KEY ("shapeId") REFERENCES "Shape"("id") ON DELETE SET NULL ON UPDATE CASCADE,
--     FOREIGN KEY ("colorId") REFERENCES "Color"("id") ON DELETE SET NULL ON UPDATE CASCADE,
--     FOREIGN KEY ("wallsId") REFERENCES "Walls"("id") ON DELETE SET NULL ON UPDATE CASCADE,
--     FOREIGN KEY ("cellsId") REFERENCES "Cells"("id") ON DELETE SET NULL ON UPDATE CASCADE,
--     FOREIGN KEY ("alignmentId") REFERENCES "Alignment"("id") ON DELETE SET NULL ON UPDATE CASCADE
-- )
INSERT INTO gall VALUES(NULL,524,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,525,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,526,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,527,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,528,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,529,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,530,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,531,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,532,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,533,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,534,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,535,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,536,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,537,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,538,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,539,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,540,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,541,'yes',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,542,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,543,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,544,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,545,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,546,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,547,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,548,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,549,'yes',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,550,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,551,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,552,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,553,'yes,no',NULL,'Erect','thin',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,554,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,555,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,556,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,557,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,558,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,559,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,560,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,561,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,562,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,563,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,564,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,565,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,566,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,567,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,568,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,569,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,570,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,571,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,572,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,573,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,574,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,575,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,576,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,577,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,578,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,579,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,580,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,581,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,582,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,583,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,584,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,585,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,586,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,587,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,588,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,589,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,590,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,591,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,592,'no',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,593,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,594,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,595,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,596,'',NULL,'','',NULL,0,NULL,NULL);
INSERT INTO gall VALUES(NULL,597,'',NULL,'','',NULL,0,NULL,NULL);
CREATE TABLE host(
    host_species_id INTEGER,
    species_id INTEGER,
    FOREIGN KEY(host_species_id) REFERENCES species(species_id),
    FOREIGN KEY(species_id) REFERENCES species(species_id)
);
INSERT INTO host VALUES(6,524);
INSERT INTO host VALUES(7,524);
INSERT INTO host VALUES(9,524);
INSERT INTO host VALUES(17,525);
INSERT INTO host VALUES(17,526);
INSERT INTO host VALUES(4,526);
INSERT INTO host VALUES(16,527);
INSERT INTO host VALUES(9,528);
INSERT INTO host VALUES(3,528);
INSERT INTO host VALUES(15,528);
INSERT INTO host VALUES(19,529);
INSERT INTO host VALUES(15,529);
INSERT INTO host VALUES(15,530);
INSERT INTO host VALUES(10,531);
INSERT INTO host VALUES(16,532);
INSERT INTO host VALUES(15,532);
INSERT INTO host VALUES(14,532);
INSERT INTO host VALUES(4,533);
INSERT INTO host VALUES(8,533);
INSERT INTO host VALUES(17,533);
INSERT INTO host VALUES(11,533);
INSERT INTO host VALUES(2,534);
INSERT INTO host VALUES(14,534);
INSERT INTO host VALUES(18,535);
INSERT INTO host VALUES(15,536);
INSERT INTO host VALUES(17,537);
INSERT INTO host VALUES(11,537);
INSERT INTO host VALUES(15,537);
INSERT INTO host VALUES(17,538);
INSERT INTO host VALUES(15,538);
INSERT INTO host VALUES(10,539);
INSERT INTO host VALUES(15,539);
INSERT INTO host VALUES(10,540);
INSERT INTO host VALUES(10,541);
INSERT INTO host VALUES(13,542);
INSERT INTO host VALUES(10,542);
INSERT INTO host VALUES(18,542);
INSERT INTO host VALUES(17,542);
INSERT INTO host VALUES(16,542);
INSERT INTO host VALUES(3,542);
INSERT INTO host VALUES(15,542);
INSERT INTO host VALUES(5,542);
INSERT INTO host VALUES(2,542);
INSERT INTO host VALUES(14,542);
INSERT INTO host VALUES(10,543);
INSERT INTO host VALUES(18,543);
INSERT INTO host VALUES(17,543);
INSERT INTO host VALUES(16,543);
INSERT INTO host VALUES(15,543);
INSERT INTO host VALUES(6,543);
INSERT INTO host VALUES(9,543);
INSERT INTO host VALUES(14,543);
INSERT INTO host VALUES(12,544);
INSERT INTO host VALUES(10,544);
INSERT INTO host VALUES(18,544);
INSERT INTO host VALUES(17,544);
INSERT INTO host VALUES(16,544);
INSERT INTO host VALUES(3,544);
INSERT INTO host VALUES(15,544);
INSERT INTO host VALUES(6,544);
INSERT INTO host VALUES(9,544);
INSERT INTO host VALUES(14,544);
INSERT INTO host VALUES(15,545);
INSERT INTO host VALUES(17,546);
INSERT INTO host VALUES(16,546);
INSERT INTO host VALUES(15,546);
INSERT INTO host VALUES(15,549);
INSERT INTO host VALUES(15,550);
INSERT INTO host VALUES(16,551);
INSERT INTO host VALUES(13,552);
INSERT INTO host VALUES(15,552);
INSERT INTO host VALUES(100,553);
INSERT INTO host VALUES(493,554);
INSERT INTO host VALUES(492,554);
INSERT INTO host VALUES(491,554);
INSERT INTO host VALUES(28,555);
INSERT INTO host VALUES(31,555);
INSERT INTO host VALUES(36,555);
INSERT INTO host VALUES(33,555);
INSERT INTO host VALUES(29,555);
INSERT INTO host VALUES(32,555);
INSERT INTO host VALUES(35,555);
INSERT INTO host VALUES(30,555);
INSERT INTO host VALUES(69,556);
INSERT INTO host VALUES(190,557);
INSERT INTO host VALUES(188,557);
INSERT INTO host VALUES(193,558);
INSERT INTO host VALUES(174,559);
INSERT INTO host VALUES(39,559);
INSERT INTO host VALUES(38,559);
INSERT INTO host VALUES(37,559);
INSERT INTO host VALUES(444,560);
INSERT INTO host VALUES(155,561);
INSERT INTO host VALUES(157,561);
INSERT INTO host VALUES(151,561);
INSERT INTO host VALUES(156,561);
INSERT INTO host VALUES(330,562);
INSERT INTO host VALUES(305,562);
INSERT INTO host VALUES(319,562);
INSERT INTO host VALUES(317,562);
INSERT INTO host VALUES(337,562);
INSERT INTO host VALUES(339,562);
INSERT INTO host VALUES(308,562);
INSERT INTO host VALUES(334,562);
INSERT INTO host VALUES(355,562);
INSERT INTO host VALUES(335,562);
INSERT INTO host VALUES(323,562);
INSERT INTO host VALUES(324,562);
INSERT INTO host VALUES(330,563);
INSERT INTO host VALUES(342,563);
INSERT INTO host VALUES(320,563);
INSERT INTO host VALUES(323,563);
INSERT INTO host VALUES(339,563);
INSERT INTO host VALUES(334,563);
INSERT INTO host VALUES(324,563);
INSERT INTO host VALUES(317,564);
INSERT INTO host VALUES(305,564);
INSERT INTO host VALUES(346,564);
INSERT INTO host VALUES(355,564);
INSERT INTO host VALUES(330,565);
INSERT INTO host VALUES(305,565);
INSERT INTO host VALUES(351,565);
INSERT INTO host VALUES(317,565);
INSERT INTO host VALUES(339,565);
INSERT INTO host VALUES(308,565);
INSERT INTO host VALUES(355,565);
INSERT INTO host VALUES(346,565);
INSERT INTO host VALUES(319,566);
INSERT INTO host VALUES(324,566);
INSERT INTO host VALUES(319,567);
INSERT INTO host VALUES(299,567);
INSERT INTO host VALUES(327,567);
INSERT INTO host VALUES(299,568);
INSERT INTO host VALUES(327,568);
INSERT INTO host VALUES(326,568);
INSERT INTO host VALUES(296,569);
INSERT INTO host VALUES(349,570);
INSERT INTO host VALUES(299,571);
INSERT INTO host VALUES(327,571);
INSERT INTO host VALUES(349,572);
INSERT INTO host VALUES(299,573);
INSERT INTO host VALUES(299,574);
INSERT INTO host VALUES(300,575);
INSERT INTO host VALUES(349,575);
INSERT INTO host VALUES(330,577);
INSERT INTO host VALUES(305,577);
INSERT INTO host VALUES(319,577);
INSERT INTO host VALUES(317,577);
INSERT INTO host VALUES(308,577);
INSERT INTO host VALUES(355,577);
INSERT INTO host VALUES(299,577);
INSERT INTO host VALUES(346,577);
INSERT INTO host VALUES(349,578);
INSERT INTO host VALUES(299,579);
INSERT INTO host VALUES(349,580);
INSERT INTO host VALUES(305,580);
INSERT INTO host VALUES(346,580);
INSERT INTO host VALUES(317,580);
INSERT INTO host VALUES(337,580);
INSERT INTO host VALUES(308,580);
INSERT INTO host VALUES(355,580);
INSERT INTO host VALUES(330,581);
INSERT INTO host VALUES(305,581);
INSERT INTO host VALUES(346,581);
INSERT INTO host VALUES(351,581);
INSERT INTO host VALUES(317,581);
INSERT INTO host VALUES(308,581);
INSERT INTO host VALUES(355,581);
INSERT INTO host VALUES(305,582);
INSERT INTO host VALUES(346,582);
INSERT INTO host VALUES(349,583);
INSERT INTO host VALUES(305,584);
INSERT INTO host VALUES(346,584);
INSERT INTO host VALUES(296,585);
INSERT INTO host VALUES(331,585);
INSERT INTO host VALUES(332,585);
INSERT INTO host VALUES(296,586);
INSERT INTO host VALUES(299,586);
INSERT INTO host VALUES(296,587);
INSERT INTO host VALUES(340,587);
INSERT INTO host VALUES(146,588);
INSERT INTO host VALUES(147,588);
INSERT INTO host VALUES(148,588);
INSERT INTO host VALUES(145,588);
INSERT INTO host VALUES(469,590);
INSERT INTO host VALUES(470,590);
INSERT INTO host VALUES(330,591);
INSERT INTO host VALUES(339,591);
INSERT INTO host VALUES(308,591);
INSERT INTO host VALUES(320,591);
INSERT INTO host VALUES(346,593);
INSERT INTO host VALUES(337,594);
INSERT INTO host VALUES(346,594);
INSERT INTO host VALUES(305,595);
INSERT INTO host VALUES(319,595);
INSERT INTO host VALUES(320,595);
INSERT INTO host VALUES(337,595);
INSERT INTO host VALUES(346,595);
INSERT INTO host VALUES(355,595);
INSERT INTO host VALUES(335,595);
INSERT INTO host VALUES(331,596);
INSERT INTO host VALUES(332,596);
INSERT INTO host VALUES(333,596);
INSERT INTO host VALUES(300,597);
CREATE TABLE source(
    source_id INTEGER PRIMARY KEY NOT NULL,
    title TEXT UNIQUE NOT NULL , 
    author TEXT,
    pubyear TEXT,
    link TEXT,
    citation TEXT
);
INSERT INTO source VALUES(1,'Amrine Catalog','James Amrine','','','Private communication');
INSERT INTO source VALUES(2,'New Species of Maple Mites','HE Hodgkiss','1913','https://academic.oup.com/jee/article-abstract/6/5/420/919472','Hodgkiss, H. E. "New species of maple mites." Journal of Economic Entomology 6.5 (1913): 420-424.');
INSERT INTO source VALUES(3,'An Illustrated Guide to Plant Abnormalities Caused by Eriophyid Mites in North America','Hartford Keifer,Edward Baker,Tokuwo Kono,Mercedes Delfinado,William Styer','1982','https://naldc.nal.usda.gov/download/CAT87208955/PDF','Keifer, Hartford H. An Illustrated Guide to Plant Abnormalities Casued by Eriophyid Mites in North America. No. 573. US Department of Agriculture, 1982.');
INSERT INTO source VALUES(4,'New American Cynipid Wasps From Galls','LH Weld','1952','https://www.biodiversitylibrary.org/page/15672479#page/372/mode/1up','Weld, Lewis H. "New American cynipid wasps from galls." Proceedings of the United States National Museum (1952).');
INSERT INTO source VALUES(5,'On The Cynipidous Galls of Florida','William Ashmead','1887','https://www.biodiversitylibrary.org/item/32293#page/135/mode/1up','Ashmead, William H. "On the cynipidous galls of Florida, with descriptions of new species and synopses of the described species of North America." Transactions of the American Entomological Society and Proceedings of the Entomological Section of the Academy of Natural Sciences 14 (1887): 125-158.');
INSERT INTO source VALUES(6,'New Species of North American Cynipidae (1900)','HF Bassett','1900','https://www.biodiversitylibrary.org/page/7522373#page/334/mode/1up','Bassett, H. F. "New species of North American Cynipidae." Transactions of the American Entomological Society (1890-) 26.4 (1899): 310-336.');
INSERT INTO source VALUES(7,'Key to American Insect Galls','EP Felt','1917','https://www.biodiversitylibrary.org/page/8635512#page/5/mode/1up','Felt, Ephraim Porter. Key to American insect galls. No. 200. University of the State of New York, 1917.');
INSERT INTO source VALUES(8,'Descriptions of new Cynipidae in the Collection of the Illinois State Laboratory of Natural History','CP Gillette','1891','https://www.biodiversitylibrary.org/page/8571764#page/197/mode/1up','Gillette, Clarence Preston. "Descriptions of new Cynipidae in the collection of the Illinois State Laboratory of Natural History." Illinois Natural History Survey Bulletin; v. 003, no. 11 (1891).');
INSERT INTO source VALUES(9,'Field notes on gall-inhabiting cynipid wasps with descriptions of new species','LH Weld','1926','https://www.biodiversitylibrary.org/page/7610635#page/269/mode/1up','Weld, Lewis H. "Field notes on gall-inhabiting cynipid wasps with descriptions of new species." Proceedings of the United States National Museum (1926).');
INSERT INTO source VALUES(10,'Insect galls of Springfield, Massachusetts, and vicinity','FA Stebbins','1910','https://www.biodiversitylibrary.org/item/71437','Stebbins, Fannie Adelle. Insect galls of Springfield, Massachusetts, and vicinity. No. 2. The Museum, 1910.');
INSERT INTO source VALUES(11,'Cynipid Galls of the Chicago Area','LH Weld','1928','https://www.biodiversitylibrary.org/page/57505981#page/174/mode/1up','Weld, Lewis H. "Cynipid galls of the Chicago area." Trans. Ill. St. Acad. Sci. 20 (1928): 142-177.');
INSERT INTO source VALUES(12,'50 common plant galls of the Chicago area','Carl Gronemann','1930','https://www.biodiversitylibrary.org/item/25182#page/5/mode/1up','Gronemann, Carl Fredrick. "50 common plant galls of the Chicago area." (1930).');
INSERT INTO source VALUES(13,'An illustrated catalogue of American insect galls','MT Thompson','1915','https://www.biodiversitylibrary.org/item/37925#page/5/mode/1up','Thompson, Millett Taylor. An illustrated catalogue of American insect galls. Published and distributed by Rhode Island Hospital Trust Company, 1915.');
INSERT INTO source VALUES(14,'Cynipid galls of the eastern United States','LH Weld','1959','https://www.biodiversitylibrary.org/item/273718#page/7/mode/1up','Weld, Lewis Hart. "Cynipid galls of the eastern United States." (1959).');
INSERT INTO source VALUES(15,'A Study of the Cynipidae','CP Gillette','1888','https://babel.hathitrust.org/cgi/pt?id=msu.31293101462541&view=1up&seq=502','Gillette, C. P. "Astudy OF THE OYNIPIDAE." (1888).');
INSERT INTO source VALUES(16,'A contribution to the morphology and biology of insect galls ','A Cosens','1912','https://www.biodiversitylibrary.org/item/99818#page/3/mode/1up','Cosens, A. "A contribution to the morphology and biology of insect galls: University of Toronto studies: Biological series." (1912).');
INSERT INTO source VALUES(17,'Key to shelterbelt insects in the northern great plains','John Stein,Patrick Kennedy','1972','https://www.biodiversitylibrary.org/item/177444#page/3/mode/1up','Stein, John D., and Patrick C. Kennedy. Key to shelterbelt insects in the northern Great Plains. Vol. 85. Rocky Mountain Forest and Range Experiment Station, Forest Service, US Department of Agriculture, 1972.');
INSERT INTO source VALUES(18,'Some plant galls of Illinois','Glen Spelman Winterringer','1961','https://www.biodiversitylibrary.org/item/56067#page/3/mode/1up','Winterringer, Glen Spelman. "Some plant galls of Illinois." (1961).');
INSERT INTO source VALUES(19,'On the Cynipidae of the North American Oaks and their Galls','Baron Osten Sacken','1861','https://www.biodiversitylibrary.org/item/22852#page/67/mode/1up','Osten-Sacken, Carl Robert. On the Cynipidae of the North American oaks, and their galls. 1861.');
INSERT INTO source VALUES(20,'New Cynipidae','HF Bassett','1881','https://www.biodiversitylibrary.org/item/22092#page/102/mode/1up','Bassett, H. F. "New species of Cynipidae." The Canadian Entomologist 13.3 (1881): 51-57.');
INSERT INTO source VALUES(21,'Additions and corrections to the paper entitled "On the Cynipidae of the North American Oaks and their Galls"','Baron Osten Sacken','1862','https://www.biodiversitylibrary.org/item/22852#page/283/mode/1up','');
INSERT INTO source VALUES(22,'The species of Biorhiza, Philonix and allied genera, and their galls','William Beutenmuller','1909','http://digitallibrary.amnh.org/bitstream/handle/2246/660//v2/dspace/ingest/pdfSource/bul/B026a18.pdf?sequence=1&isAllowed=y','Beutenmüller, William. "species of Biorhiza, Philonix and allied genera, and their galls." Bulletin of the American Museum of Natural History; v. 26, article 18 (1909).');
INSERT INTO source VALUES(23,'Descriptions of New Cynipidae','William Beutenmuller','1913','https://www.jstor.org/stable/pdf/25076912.pdf','Beutenmuller, William. "Descriptions of new Cynipidae." Transactions of the American Entomological Society (1890-) 39.3/4 (1913): 243-248.');
INSERT INTO source VALUES(24,'Notes on Cynipidae, with description of a new species (Hym.)','William Beutenmuller','1918','https://www.biodiversitylibrary.org/page/2570776#page/409/mode/1up','Beutenmüller, W. "Notes on Cynipidae, with description of a new species (Hym.)." Entomological News 29 (1918): 327-330.');
INSERT INTO source VALUES(25,'Studies of some new and described Cynipidae (Hymenoptera)','Charles Alfred Kinsey','1922','https://www.biodiversitylibrary.org/page/45387508#page/65/mode/1up','Kinsey, Alfred Charles, and Kenneth D. Ayres. Studies of some new and described Cynipidae (Hymenoptera). Vol. 9. No. 53. University of Indiana, 1922.');
INSERT INTO source VALUES(26,'Descriptions of Five New Genera in the Family Cynipidae','William Ashmead','1897','https://www.biodiversitylibrary.org/item/88720#page/285/mode/1up','Ashmead, William H. "Descriptions of five new genera in the family Cynipidae." The Canadian Entomologist 29.11 (1897): 260-263.');
INSERT INTO source VALUES(27,'A New Andricus from New Jersey','William Beutenmuller','1913','https://www.biodiversitylibrary.org/item/36243#page/172/mode/1up','');
INSERT INTO source VALUES(28,'Description of a New Gallfly (Andricus decidua)','William Beutenmuller','1913','https://www.biodiversitylibrary.org/item/36243#page/179/mode/1up','');
INSERT INTO source VALUES(29,'Descriptions of several new species of Cynips and a new species of Diastrophus','HF Bassett','1864','https://www.biodiversitylibrary.org/item/23810#page/699/mode/1up','Bassett, Homer Franklin. Descriptions of several new species of Cynips, and a new species of Diastrophus. The Society, 1864.');
INSERT INTO source VALUES(30,'A Report on the Insects of Massachusetts, Injurious to Vegetation','TW Harris','1841','https://www.biodiversitylibrary.org/item/27609#page/5/mode/1up','Harris, Thaddeus William. A report on the insects of Massachusetts, injurious to vegetation: Publ.... by the commissioners on the Zoological and Botanical Survey of the State. Folsom, Wells, and Thurston, 1841.');
INSERT INTO source VALUES(31,'The species of Amphibolips and their 'William Beutenmuller','1909','http://digitallibrary.amnh.org/bitstream/handle/2246/656//v2/dspace/ingest/pdfSource/bul/B026a06.pdf?sequence=1&isAllowed=y','Beutenmuller, Wm. "The species of Amphibolips and their Galls." Amer. Mus. Nat. Hist 26: 47-66.');
INSERT INTO source VALUES(32,'New Species of North American Cynipidae (1890)','HF Bassett','1890','https://www.biodiversitylibrary.org/item/32322#page/67/mode/1up','Bassett, H. F. "New species of North American Cynipidae." Transactions of the American Entomological Society (1890-) 17.1 (1890): 59-92.');
INSERT INTO source VALUES(33,'A manual for the study of insects','JH Comstock,AB Comstock','1904','https://www.biodiversitylibrary.org/item/266410#page/11/mode/1up','Comstock, John Henry, and Anna Botsford Comstock. A Manual for the Study of Insects. Comstock Publishing Company, 1904.');
INSERT INTO source VALUES(34,'Review of the world genera of oak cynipid wasps (Hymenoptera: Cynipidae: Cynipini)','G Melika,WG Abrahamson','','https://www.researchgate.net/profile/Warren_Abrahamson/publication/254570300_Review_of_the_world_genera_of_oak_cynipid_wasps_Hymenoptera_Cynipidae_Cynipini/links/0deec52b85f3e817a3000000/Review-of-the-world-genera-of-oak-cynipid-wasps-Hymenoptera-Cynipidae-Cynipini.pdf','MELIKA, George, and Warren G. ABRAHAMSON. "REVIEW OF THE WORLD GENERA OF OAK CYNIPID WASPS."');
INSERT INTO source VALUES(35,'Current state of knowledge of heterogony in Cynipidae (Hymenoptera, Cynipoidea)','J Pujade-Villar,D Bellido,G Segu,G Melika','1999','https://www.researchgate.net/profile/J_Pujade-Villar/publication/39095093_Current_state_of_knowledge_of_heterogony_in_Cynipidae_Hymenoptera_Cynipoidea/links/02e7e53b6c35e8cc3d000000.pdf','Melika, George, et al. "Current state of knowledge of heterogony in Cynipidae (Hymenoptera, Cynipoidea)." Sessió Conjunta d''Entomologia (2001): 87-107.');
INSERT INTO source VALUES(36,'Insect Galls of Ontario','TD Jarvis','1906','https://www.biodiversitylibrary.org/page/40931581#page/308/mode/1up','Jarvis, T. D. "Insect Galls of Ontario." Rep. Ent. Soc. Ont 37 (1906): 56-72.');
INSERT INTO source VALUES(37,'Insects affecting park and woodland trees','EP Felt','1906','https://www.biodiversitylibrary.org/page/58122706#page/5/mode/1up','Felt, Ephraim Porter. Insects affecting park and woodland trees. New York state education department, 1906.');
INSERT INTO source VALUES(38,'A catalogue of the gall insects of Ontario','TD Jarvis','1909','https://www.biodiversitylibrary.org/page/27900549#page/502/mode/1up','Jarvis, T. "A catalogue of the gall insects of Ontario." Thirty-Ninth Annual Report of the Entomological Society of Ontario 1908 (1909): 70-98.');
INSERT INTO source VALUES(39,'Insect-galls of the vicinity of New York City','William Beutenmuller','1904','https://www.biodiversitylibrary.org/page/12267172#page/241/mode/1up','Beutenmüller, Willliam. "insect-galls of the vicinity of New York City." (1904).');
INSERT INTO source VALUES(40,'Insect galls of Cedar Point and vicinity','PB Sears','1914','https://www.biodiversitylibrary.org/page/50337404#page/455/mode/1up','Sears, Paul B. "The insect galls of Cedar Point and vicinity." (1914).');
INSERT INTO source VALUES(41,'Life histories of American Cynipidae','Charles Alfred Kinsey','1920','https://www.biodiversitylibrary.org/item/213997#page/1/mode/1up','Kinsey, Alfred Charles. Life histories of American Cynipidae. American Museum of Natural History, 1920.');
INSERT INTO source VALUES(42,'Eastern forest insects','WL Baker','1972','https://www.biodiversitylibrary.org/item/132738#page/7/mode/1up','Baker, Whiteford Lee. Eastern forest insects. Vol. 1166. US Forest Service, 1972.');
INSERT INTO source VALUES(43,'Identification of hardwood insects by type of tree injury, North-Central Region','HJ MacAloney,HG Ewan','1964','https://www.biodiversitylibrary.org/item/159223#page/3/mode/1up','MacAloney, Harvey John, and Herbert George Ewan. Identification of hardwood insects by type of tree injury, North-Central Region. Vol. 11. Lake States Forest Experiment Station, 1964.');
INSERT INTO source VALUES(44,'Insect enemies of Eastern Forests','FC Craighead','1950','https://www.biodiversitylibrary.org/item/132361#page/7/mode/1up','Craighead, Frank Cooper, ed. Insect enemies of eastern forests. No. 657. US Government Printing Office, 1950.');
INSERT INTO source VALUES(45,'American gallflies of the family Cynipidae producing subterranean galls on oak','LH Weld','1921','https://www.biodiversitylibrary.org/page/7562993#page/241/mode/1up','Weld, Lewis Hart. American gallflies of the family Cynipidae producing subterranean galls on oak. Vol. 59. US Government Printing Office, 1921.');
INSERT INTO source VALUES(46,'Descriptions of new Cynipidae (1917)','William Beutenmuller','1917','https://www.biodiversitylibrary.org/page/28154038#page/831/mode/1up','Beutenmuller, Wm. "Descriptions of new Cynipidae." The Canadian Entomologist 49.10 (1917): 345-349.');
INSERT INTO source VALUES(47,'Two New Cynipidae','William Beutenmuller','1918','https://www.biodiversitylibrary.org/item/95656#page/168/mode/1up','');
INSERT INTO source VALUES(48,'Hymenoptera of American north of Mexico: Synoptic catalog (1951)','Karl Krombein,CF Muesebeck,Henry Townes','1951','https://www.biodiversitylibrary.org/page/41966767#page/9/mode/1up','');
INSERT INTO source VALUES(49,'The plant-feeding gall midges of North America','Raymond J. Gagne','1989','','Gagné, Raymond J. The plant-feeding gall midges of North America. Comstock Pub. Associates, 1989.');
INSERT INTO source VALUES(50,'The Gall Wasp Genus Cynips','Charles Alfred Kinsey','1929','https://www.biodiversitylibrary.org/page/53516882#page/7/mode/1up','Kinsey, Alfred C. "The gall wasp genus Cynips." A study in the origin of species. Indiana University Studies 16.84-86 (1930): 1-577.');
CREATE TABLE speciessource(
    species_id INTEGER,
    source_id INTEGER,
    FOREIGN KEY(species_id) REFERENCES species(species_id),
    FOREIGN KEY(source_id) REFERENCES source(source_id)
);
INSERT INTO speciessource VALUES(524,1);
INSERT INTO speciessource VALUES(525,1);
INSERT INTO speciessource VALUES(525,2);
INSERT INTO speciessource VALUES(525,2);
INSERT INTO speciessource VALUES(526,2);
INSERT INTO speciessource VALUES(526,1);
INSERT INTO speciessource VALUES(527,1);
INSERT INTO speciessource VALUES(527,3);
INSERT INTO speciessource VALUES(528,2);
INSERT INTO speciessource VALUES(528,2);
INSERT INTO speciessource VALUES(528,1);
INSERT INTO speciessource VALUES(529,2);
INSERT INTO speciessource VALUES(529,1);
INSERT INTO speciessource VALUES(530,2);
INSERT INTO speciessource VALUES(530,1);
INSERT INTO speciessource VALUES(531,2);
INSERT INTO speciessource VALUES(531,1);
INSERT INTO speciessource VALUES(531,3);
INSERT INTO speciessource VALUES(532,2);
INSERT INTO speciessource VALUES(532,1);
INSERT INTO speciessource VALUES(532,3);
INSERT INTO speciessource VALUES(533,1);
INSERT INTO speciessource VALUES(533,3);
INSERT INTO speciessource VALUES(534,1);
INSERT INTO speciessource VALUES(535,2);
INSERT INTO speciessource VALUES(535,1);
INSERT INTO speciessource VALUES(536,1);
INSERT INTO speciessource VALUES(552,2);
INSERT INTO speciessource VALUES(552,1);
INSERT INTO speciessource VALUES(554,3);
INSERT INTO speciessource VALUES(554,1);
INSERT INTO speciessource VALUES(555,3);
INSERT INTO speciessource VALUES(555,1);
INSERT INTO speciessource VALUES(556,3);
INSERT INTO speciessource VALUES(556,1);
INSERT INTO speciessource VALUES(557,3);
INSERT INTO speciessource VALUES(557,1);
INSERT INTO speciessource VALUES(558,3);
INSERT INTO speciessource VALUES(558,1);
INSERT INTO speciessource VALUES(559,3);
INSERT INTO speciessource VALUES(559,1);
INSERT INTO speciessource VALUES(560,3);
INSERT INTO speciessource VALUES(560,1);
INSERT INTO speciessource VALUES(561,3);
INSERT INTO speciessource VALUES(561,1);
INSERT INTO speciessource VALUES(562,4);
INSERT INTO speciessource VALUES(562,14);
INSERT INTO speciessource VALUES(563,5);
INSERT INTO speciessource VALUES(563,7);
INSERT INTO speciessource VALUES(563,14);
INSERT INTO speciessource VALUES(563,9);
INSERT INTO speciessource VALUES(564,6);
INSERT INTO speciessource VALUES(564,10);
INSERT INTO speciessource VALUES(564,11);
INSERT INTO speciessource VALUES(564,13);
INSERT INTO speciessource VALUES(564,7);
INSERT INTO speciessource VALUES(564,9);
INSERT INTO speciessource VALUES(564,14);
INSERT INTO speciessource VALUES(565,8);
INSERT INTO speciessource VALUES(565,7);
INSERT INTO speciessource VALUES(565,9);
INSERT INTO speciessource VALUES(565,10);
INSERT INTO speciessource VALUES(565,11);
INSERT INTO speciessource VALUES(565,12);
INSERT INTO speciessource VALUES(565,14);
INSERT INTO speciessource VALUES(566,5);
INSERT INTO speciessource VALUES(566,14);
INSERT INTO speciessource VALUES(566,7);
INSERT INTO speciessource VALUES(567,15);
INSERT INTO speciessource VALUES(567,13);
INSERT INTO speciessource VALUES(567,16);
INSERT INTO speciessource VALUES(567,7);
INSERT INTO speciessource VALUES(567,11);
INSERT INTO speciessource VALUES(567,9);
INSERT INTO speciessource VALUES(568,15);
INSERT INTO speciessource VALUES(568,17);
INSERT INTO speciessource VALUES(568,7);
INSERT INTO speciessource VALUES(568,12);
INSERT INTO speciessource VALUES(568,18);
INSERT INTO speciessource VALUES(568,9);
INSERT INTO speciessource VALUES(568,11);
INSERT INTO speciessource VALUES(569,4);
INSERT INTO speciessource VALUES(570,19);
INSERT INTO speciessource VALUES(570,14);
INSERT INTO speciessource VALUES(571,9);
INSERT INTO speciessource VALUES(572,20);
INSERT INTO speciessource VALUES(573,20);
INSERT INTO speciessource VALUES(574,21);
INSERT INTO speciessource VALUES(575,21);
INSERT INTO speciessource VALUES(575,5);
INSERT INTO speciessource VALUES(575,22);
INSERT INTO speciessource VALUES(575,23);
INSERT INTO speciessource VALUES(575,24);
INSERT INTO speciessource VALUES(575,9);
INSERT INTO speciessource VALUES(575,25);
INSERT INTO speciessource VALUES(575,26);
INSERT INTO speciessource VALUES(575,14);
INSERT INTO speciessource VALUES(575,14);
INSERT INTO speciessource VALUES(576,22);
INSERT INTO speciessource VALUES(577,9);
INSERT INTO speciessource VALUES(577,28);
INSERT INTO speciessource VALUES(577,7);
INSERT INTO speciessource VALUES(577,7);
INSERT INTO speciessource VALUES(577,29);
INSERT INTO speciessource VALUES(577,11);
INSERT INTO speciessource VALUES(577,14);
INSERT INTO speciessource VALUES(578,9);
INSERT INTO speciessource VALUES(578,23);
INSERT INTO speciessource VALUES(578,7);
INSERT INTO speciessource VALUES(578,14);
INSERT INTO speciessource VALUES(578,14);
INSERT INTO speciessource VALUES(579,27);
INSERT INTO speciessource VALUES(580,31);
INSERT INTO speciessource VALUES(580,31);
INSERT INTO speciessource VALUES(580,31);
INSERT INTO speciessource VALUES(580,7);
INSERT INTO speciessource VALUES(580,6);
INSERT INTO speciessource VALUES(580,32);
INSERT INTO speciessource VALUES(580,7);
INSERT INTO speciessource VALUES(580,19);
INSERT INTO speciessource VALUES(580,21);
INSERT INTO speciessource VALUES(580,21);
INSERT INTO speciessource VALUES(580,33);
INSERT INTO speciessource VALUES(580,33);
INSERT INTO speciessource VALUES(580,11);
INSERT INTO speciessource VALUES(580,10);
INSERT INTO speciessource VALUES(580,40);
INSERT INTO speciessource VALUES(580,14);
INSERT INTO speciessource VALUES(581,30);
INSERT INTO speciessource VALUES(581,7);
INSERT INTO speciessource VALUES(581,31);
INSERT INTO speciessource VALUES(581,19);
INSERT INTO speciessource VALUES(581,21);
INSERT INTO speciessource VALUES(581,11);
INSERT INTO speciessource VALUES(581,35);
INSERT INTO speciessource VALUES(581,16);
INSERT INTO speciessource VALUES(581,36);
INSERT INTO speciessource VALUES(581,37);
INSERT INTO speciessource VALUES(581,38);
INSERT INTO speciessource VALUES(581,39);
INSERT INTO speciessource VALUES(581,41);
INSERT INTO speciessource VALUES(581,42);
INSERT INTO speciessource VALUES(581,43);
INSERT INTO speciessource VALUES(581,33);
INSERT INTO speciessource VALUES(581,14);
INSERT INTO speciessource VALUES(582,19);
INSERT INTO speciessource VALUES(582,21);
INSERT INTO speciessource VALUES(582,33);
INSERT INTO speciessource VALUES(582,10);
INSERT INTO speciessource VALUES(582,16);
INSERT INTO speciessource VALUES(583,33);
INSERT INTO speciessource VALUES(584,11);
INSERT INTO speciessource VALUES(584,11);
INSERT INTO speciessource VALUES(584,34);
INSERT INTO speciessource VALUES(585,45);
INSERT INTO speciessource VALUES(585,14);
INSERT INTO speciessource VALUES(585,11);
INSERT INTO speciessource VALUES(586,46);
INSERT INTO speciessource VALUES(586,7);
INSERT INTO speciessource VALUES(586,9);
INSERT INTO speciessource VALUES(586,11);
INSERT INTO speciessource VALUES(587,47);
INSERT INTO speciessource VALUES(587,11);
INSERT INTO speciessource VALUES(587,48);
INSERT INTO speciessource VALUES(587,14);
INSERT INTO speciessource VALUES(588,49);
INSERT INTO speciessource VALUES(589,49);
INSERT INTO speciessource VALUES(590,49);
INSERT INTO speciessource VALUES(591,31);
INSERT INTO speciessource VALUES(591,13);
INSERT INTO speciessource VALUES(591,7);
INSERT INTO speciessource VALUES(591,14);
INSERT INTO speciessource VALUES(593,19);
INSERT INTO speciessource VALUES(594,14);
INSERT INTO speciessource VALUES(594,32);
INSERT INTO speciessource VALUES(595,14);
INSERT INTO speciessource VALUES(595,29);
INSERT INTO speciessource VALUES(596,29);
INSERT INTO speciessource VALUES(596,9);
INSERT INTO speciessource VALUES(596,50);
INSERT INTO speciessource VALUES(596,14);
INSERT INTO speciessource VALUES(597,48);
INSERT INTO speciessource VALUES(597,25);
CREATE VIEW v_gall
AS
SELECT DISTINCT
    gall.*,
    location.loc,
    walls.walls,
    color.color,
    alignment.alignment,
    texture.texture,
    shape.shape,
    cells.cells,
    species.name,
    species.synonyms,
    species.commonnames,
    species.genus,
    species.description,
    abundance.abundance, 
    family.name as family
FROM
    gall
INNER JOIN species ON (species.species_id = gall.species_id)
INNER JOIN family ON (species.family_id = family.family_id)
LEFT JOIN location ON (location.loc_id = gall.loc_id)
LEFT JOIN walls ON (walls.walls_id = gall.walls_id)
LEFT JOIN color ON (color.color_id = gall.color_id)
LEFT JOIN alignment ON (alignment.alignment_id = gall.alignment_id)
LEFT JOIN texture ON (texture.texture_id = gall.texture_id)
LEFT JOIN shape ON (shape.shape_id = gall.shape_id)
LEFT JOIN cells ON (cells.cells_id = gall.cells_id)
LEFT JOIN abundance ON (abundance.abundance_id = species.abundance_id);
COMMIT;
