CREATE TABLE IF NOT EXISTS "migration" (
  id   INTEGER PRIMARY KEY,
  name TEXT    NOT NULL,
  up   TEXT    NOT NULL,
  down TEXT    NOT NULL
);
CREATE TABLE texture (
    id INTEGER PRIMARY KEY NOT NULL,
    texture TEXT UNIQUE NOT NULL,
    description TEXT
);
CREATE TABLE walls (
    id INTEGER PRIMARY KEY NOT NULL,
    walls TEXT UNIQUE NOT NULL,
    description TEXT
);
CREATE TABLE cells (
    id INTEGER PRIMARY KEY NOT NULL,
    cells TEXT UNIQUE NOT NULL,
    description TEXT
);
CREATE TABLE color (
    id INTEGER PRIMARY KEY NOT NULL,
    color TEXT UNIQUE NOT NULL
);
CREATE TABLE alignment (
    id INTEGER PRIMARY KEY NOT NULL,
    alignment TEXT UNIQUE NOT NULL,
    description TEXT
);
CREATE TABLE shape (
    id INTEGER PRIMARY KEY NOT NULL,
    shape TEXT UNIQUE NOT NULL,
    description TEXT
);
CREATE TABLE abundance (
    id INTEGER PRIMARY KEY NOT NULL,
    abundance TEXT UNIQUE NOT NULL,
    description TEXT,
    reference TEXT
);
CREATE TABLE glossary (
    id INTEGER PRIMARY KEY NOT NULL,
    word TEXT UNIQUE NOT NULL,
    definition TEXT NOT NULL,
    urls TEXT NOT NULL -- Tab separated list of URLs (tabs since commas can occur in URLs but tabs cannot)
);
CREATE TABLE source (
    id       INTEGER PRIMARY KEY
                     NOT NULL,
    title    TEXT    UNIQUE
                     NOT NULL,
    author   TEXT   NOT NULL, -- add NOT NULL in 004
    pubyear  TEXT NOT NULL, -- add NOT NULL in 004
    link     TEXT NOT NULL, -- add NOT NULL in 004
    citation TEXT NOT NULL -- add NOT NULL in 004
, datacomplete BOOLEAN DEFAULT 0 NOT NULL, license TEXT DEFAULT '' NOT NULL, licenselink TEXT DEFAULT '' NOT NULL, inserted_at TEXT, updated_at TEXT);
CREATE TABLE alias (
    id       INTEGER PRIMARY KEY NOT NULL,
    name     TEXT NOT NULL,
    type     TEXT NOT NULL CHECK (type = 'common' OR type = 'scientific'),
    description TEXT NOT NULL DEFAULT ''
, inserted_at TEXT, updated_at TEXT);
CREATE TABLE season (
    id INTEGER PRIMARY KEY NOT NULL,
    season TEXT UNIQUE NOT NULL
);
CREATE TABLE form (
    id          INTEGER PRIMARY KEY NOT NULL,
    form        TEXT    UNIQUE NOT NULL,
    description TEXT
);
CREATE VIRTUAL TABLE species_fts USING fts5(
  species_id UNINDEXED,
  name,
  aliases,
  tokenize='porter unicode61',
  prefix='2 3'
)
/* species_fts(species_id,name,aliases) */;
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
CREATE TABLE IF NOT EXISTS "place" (
  id INTEGER PRIMARY KEY NOT NULL,
  name TEXT UNIQUE NOT NULL,
  code TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('continent', 'country', 'region', 'state', 'province', 'county', 'city'))
);
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
CREATE TABLE host_range (
  species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, place_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place(id) ON DELETE CASCADE
);
CREATE TABLE gall_range_exclusion (
  species_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, place_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES place(id) ON DELETE CASCADE
);
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
CREATE TABLE gall_traits (
  species_id INTEGER PRIMARY KEY NOT NULL,
  detachable TEXT CHECK (detachable IN ('unknown', 'integral', 'detachable', 'both')),
  undescribed BOOLEAN NOT NULL DEFAULT 0,
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE
);
CREATE TABLE gall_color (
  species_id INTEGER NOT NULL,
  color_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, color_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (color_id) REFERENCES color(id) ON DELETE CASCADE
);
CREATE TABLE gall_walls (
  species_id INTEGER NOT NULL,
  walls_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, walls_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (walls_id) REFERENCES walls(id) ON DELETE CASCADE
);
CREATE TABLE gall_cells (
  species_id INTEGER NOT NULL,
  cells_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, cells_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (cells_id) REFERENCES cells(id) ON DELETE CASCADE
);
CREATE TABLE gall_season (
  species_id INTEGER NOT NULL,
  season_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, season_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (season_id) REFERENCES season(id) ON DELETE CASCADE
);
CREATE TABLE gall_shape (
  species_id INTEGER NOT NULL,
  shape_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, shape_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (shape_id) REFERENCES shape(id) ON DELETE CASCADE
);
CREATE TABLE gall_texture (
  species_id INTEGER NOT NULL,
  texture_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, texture_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (texture_id) REFERENCES texture(id) ON DELETE CASCADE
);
CREATE TABLE gall_alignment (
  species_id INTEGER NOT NULL,
  alignment_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, alignment_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (alignment_id) REFERENCES alignment(id) ON DELETE CASCADE
);
CREATE TABLE gall_form (
  species_id INTEGER NOT NULL,
  form_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, form_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (form_id) REFERENCES form(id) ON DELETE CASCADE
);
CREATE TABLE plant_part (
  id INTEGER PRIMARY KEY NOT NULL,
  part TEXT UNIQUE NOT NULL,
  description TEXT
);
CREATE TABLE gall_plant_part (
  species_id INTEGER NOT NULL,
  plant_part_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, plant_part_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (plant_part_id) REFERENCES plant_part(id) ON DELETE CASCADE
);
CREATE TABLE gallhost (
  id INTEGER PRIMARY KEY NOT NULL,
  host_species_id INTEGER NOT NULL,
  gall_species_id INTEGER NOT NULL,
  inserted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (host_species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (gall_species_id) REFERENCES species(id) ON DELETE CASCADE
);
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
CREATE TABLE alias_species (
  species_id INTEGER NOT NULL,
  alias_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, alias_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (alias_id) REFERENCES alias(id) ON DELETE CASCADE
);
CREATE TABLE taxonomy_alias (
  taxonomy_id INTEGER NOT NULL,
  alias_id INTEGER NOT NULL,
  PRIMARY KEY (taxonomy_id, alias_id),
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id) ON DELETE CASCADE,
  FOREIGN KEY (alias_id) REFERENCES alias(id) ON DELETE CASCADE
);
CREATE TABLE place_hierarchy (
  place_id INTEGER NOT NULL,
  parent_id INTEGER NOT NULL,
  PRIMARY KEY (place_id, parent_id),
  FOREIGN KEY (place_id) REFERENCES place(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES place(id) ON DELETE CASCADE
);
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
CREATE INDEX image_species_id_sort_order_index ON image(species_id, sort_order);
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
CREATE UNIQUE INDEX idx_taxonomy_name_parent
  ON taxonomy(name, parent_id)
  WHERE NOT is_placeholder;
CREATE TABLE species_taxonomy (
  species_id INTEGER NOT NULL,
  taxonomy_id INTEGER NOT NULL,
  PRIMARY KEY (species_id, taxonomy_id),
  FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
  FOREIGN KEY (taxonomy_id) REFERENCES taxonomy(id) ON DELETE RESTRICT
);
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
