defmodule Gallformers.Repo.Migrations.Baseline do
  @moduledoc """
  Baseline Postgres migration — creates all tables from scratch.

  Replaces the old SQLite structure.sql bootstrap and all incremental migrations.
  Table creation order respects foreign key dependencies.
  """

  use Ecto.Migration

  def up do
    # =========================================================================
    # 1. Filter field tables (no foreign keys)
    # =========================================================================

    create table(:alignment) do
      add :alignment, :string, null: false
      add :description, :text
    end

    create unique_index(:alignment, [:alignment])

    create table(:cells) do
      add :cells, :string, null: false
      add :description, :text
    end

    create unique_index(:cells, [:cells])

    create table(:color) do
      add :color, :string, null: false
    end

    create unique_index(:color, [:color])

    create table(:form) do
      add :form, :string, null: false
      add :description, :text
    end

    create unique_index(:form, [:form])

    create table(:plant_part) do
      add :part, :string, null: false
      add :description, :text
    end

    create unique_index(:plant_part, [:part])

    create table(:season) do
      add :season, :string, null: false
    end

    create unique_index(:season, [:season])

    create table(:shape) do
      add :shape, :string, null: false
      add :description, :text
    end

    create unique_index(:shape, [:shape])

    create table(:texture) do
      add :texture, :string, null: false
      add :description, :text
    end

    create unique_index(:texture, [:texture])

    create table(:walls) do
      add :walls, :string, null: false
      add :description, :text
    end

    create unique_index(:walls, [:walls])

    # =========================================================================
    # 2. Standalone reference tables (no foreign keys)
    # =========================================================================

    create table(:abundance) do
      add :abundance, :string, null: false
      add :description, :text
      add :reference, :text
    end

    create unique_index(:abundance, [:abundance])

    create table(:glossary) do
      add :word, :string, null: false
      add :definition, :text, null: false
      add :urls, :text, null: false
    end

    create unique_index(:glossary, [:word])

    create table(:place) do
      add :name, :text, null: false
      add :code, :string, null: false
      add :type, :string, null: false
    end

    create unique_index(:place, [:code])

    execute """
    ALTER TABLE place
    ADD CONSTRAINT place_type_check
    CHECK (type IN ('continent', 'country', 'region', 'state', 'province', 'county', 'city'))
    """

    # =========================================================================
    # 3. Taxonomy (self-referencing FK)
    # =========================================================================

    create table(:taxonomy) do
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false
      add :rank, :string
      add :is_placeholder, :boolean, null: false, default: false
      add :parent_id, references(:taxonomy, on_delete: :restrict)

      timestamps(type: :utc_datetime)
    end

    create index(:taxonomy, [:parent_id], name: :idx_taxonomy_parent_id)

    # Partial unique index: name+parent must be unique among non-placeholder entries
    execute """
    CREATE UNIQUE INDEX idx_taxonomy_name_parent
    ON taxonomy (name, parent_id)
    WHERE NOT is_placeholder
    """

    # =========================================================================
    # 4. Source, Users, Articles, Keys, PageViews, SiteSettings (no FK deps)
    # =========================================================================

    create table(:source) do
      add :title, :text, null: false
      add :author, :text, null: false
      add :pubyear, :text, null: false
      add :link, :text, null: false
      add :citation, :text, null: false
      add :datacomplete, :boolean, null: false, default: false
      add :license, :string, null: false, default: ""
      add :licenselink, :text, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create unique_index(:source, [:title])

    create table(:users) do
      add :auth0_id, :string, null: false
      add :display_name, :string
      add :nickname, :string
      add :about_me, :text
      add :inaturalist_url, :string
      add :social_url, :string
      add :personal_url, :string
      add :show_on_about, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:auth0_id])

    create table(:articles) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :author, :string, null: false
      add :description, :text
      add :content, :text, null: false
      add :tags, :text
      add :is_published, :boolean, null: false, default: false
      add :published_at, :utc_datetime

      timestamps()
    end

    create unique_index(:articles, [:slug])
    create index(:articles, [:is_published])

    create table(:keys) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :subtitle, :string
      add :authors, :text
      add :citation, :text
      add :citation_url, :string
      add :description, :text
      add :version, :string, null: false
      add :couplets, :text, null: false

      timestamps()
    end

    create unique_index(:keys, [:slug])

    create table(:page_views) do
      add :path, :string, null: false
      add :referrer_host, :string
      add :browser, :string
      add :device_type, :string
      add :visitor_hash, :string, null: false

      timestamps(updated_at: false)
    end

    create index(:page_views, [:inserted_at])
    create index(:page_views, [:path])
    create index(:page_views, [:visitor_hash, :inserted_at])

    create table(:site_settings) do
      add :key, :string, null: false
      add :value, :text

      timestamps()
    end

    create unique_index(:site_settings, [:key])

    # =========================================================================
    # 5. Species (FK to abundance)
    # =========================================================================

    create table(:species) do
      add :name, :string, null: false
      add :taxoncode, :string, null: false
      add :datacomplete, :boolean, null: false, default: false
      add :abundance_id, references(:abundance, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:species, [:name])
    create index(:species, [:abundance_id], name: :idx_species_abundance_id)

    execute """
    ALTER TABLE species
    ADD CONSTRAINT species_taxoncode_check
    CHECK (taxoncode IN ('gall', 'plant', 'undetermined'))
    """

    # =========================================================================
    # 6. Alias (no FKs on the table itself; junctions reference it)
    # =========================================================================

    create table(:alias) do
      add :name, :text, null: false
      add :type, :string, null: false
      add :description, :text, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    execute """
    ALTER TABLE alias
    ADD CONSTRAINT alias_type_check
    CHECK (type IN ('common', 'scientific', 'former_undescribed'))
    """

    # =========================================================================
    # 7. Gall traits (1:1 extension of species, species_id is PK+FK)
    # =========================================================================

    create table(:gall_traits, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), primary_key: true, null: false
      add :detachable, :string
      add :undescribed, :boolean, null: false, default: false
      add :gallformers_code, :string
      add :range_confirmed, :boolean, null: false, default: false
      add :range_computed_at, :utc_datetime
    end

    execute """
    ALTER TABLE gall_traits
    ADD CONSTRAINT gall_traits_detachable_check
    CHECK (detachable IN ('unknown', 'integral', 'detachable', 'both'))
    """

    # Partial unique index: gallformers_code must be unique when not null
    execute """
    CREATE UNIQUE INDEX gall_traits_gallformers_code_unique
    ON gall_traits (gallformers_code)
    WHERE gallformers_code IS NOT NULL
    """

    # =========================================================================
    # 8. Host traits (1:1 extension of species, species_id is PK+FK)
    # =========================================================================

    create table(:host_traits, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), primary_key: true, null: false
      add :wcvp_id, :string
      add :powo_id, :string
      add :range_confirmed, :boolean, null: false, default: false
      add :wcvp_synced_at, :utc_datetime
    end

    create index(:host_traits, [:wcvp_id])
    create index(:host_traits, [:powo_id])

    # =========================================================================
    # 9. Image (FK to species, source)
    # =========================================================================

    create table(:image) do
      add :path, :text, null: false
      add :sort_order, :integer, null: false, default: 0
      add :creator, :text
      add :attribution, :text
      add :license, :text
      add :licenselink, :text
      add :sourcelink, :text
      add :uploader, :text
      add :lastchangedby, :text
      add :caption, :text, default: ""
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :source_id, references(:source, on_delete: :nilify_all)
    end

    create unique_index(:image, [:path])
    create index(:image, [:species_id, :sort_order])
    create index(:image, [:species_id], name: :idx_image_species_id)
    create index(:image, [:source_id], name: :idx_image_source_id)

    # =========================================================================
    # 10. Content images (FK to articles, keys, source)
    # =========================================================================

    create table(:content_images) do
      add :path, :text, null: false
      add :sort_order, :integer, null: false, default: 0
      add :creator, :text
      add :attribution, :text
      add :license, :text
      add :licenselink, :text
      add :sourcelink, :text
      add :caption, :text
      add :uploader, :text
      add :lastchangedby, :text
      add :article_id, references(:articles, on_delete: :delete_all)
      add :key_id, references(:keys, on_delete: :delete_all)
      add :source_id, references(:source, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:content_images, [:path])
    create index(:content_images, [:article_id, :sort_order])
    create index(:content_images, [:key_id, :sort_order])

    # Exactly one owner constraint (Postgres CHECK instead of SQLite trigger)
    execute """
    ALTER TABLE content_images
    ADD CONSTRAINT content_images_exactly_one_owner
    CHECK (
      (article_id IS NOT NULL AND key_id IS NULL)
      OR (article_id IS NULL AND key_id IS NOT NULL)
    )
    """

    # =========================================================================
    # 11. Gallhost (FK to species x2)
    # =========================================================================

    create table(:gallhost) do
      add :host_species_id, references(:species, on_delete: :delete_all), null: false
      add :gall_species_id, references(:species, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gallhost, [:host_species_id, :gall_species_id])
    create index(:gallhost, [:host_species_id], name: :idx_gallhost_host_species_id)
    create index(:gallhost, [:gall_species_id], name: :idx_gallhost_gall_species_id)

    # =========================================================================
    # 12. Species source (FK to species, source, alias)
    # =========================================================================

    create table(:species_source) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :source_id, references(:source, on_delete: :delete_all), null: false
      add :description, :text, null: false, default: ""
      add :useasdefault, :boolean, null: false, default: false
      add :externallink, :text, null: false, default: ""
      add :alias_id, references(:alias, on_delete: :nothing)
    end

    create unique_index(:species_source, [:species_id, :source_id],
      name: :species_source_species_id_source_id
    )

    create index(:species_source, [:species_id], name: :idx_species_source_species_id)
    create index(:species_source, [:source_id], name: :idx_species_source_source_id)

    # =========================================================================
    # 13. Junction tables
    # =========================================================================

    # alias_species (species <-> alias)
    create table(:alias_species, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :alias_id, references(:alias, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE alias_species ADD PRIMARY KEY (species_id, alias_id)"
    create index(:alias_species, [:species_id], name: :idx_alias_species_species_id)
    create index(:alias_species, [:alias_id], name: :idx_alias_species_alias_id)

    # taxonomy_alias (taxonomy <-> alias)
    create table(:taxonomy_alias, primary_key: false) do
      add :taxonomy_id, references(:taxonomy, on_delete: :delete_all), null: false
      add :alias_id, references(:alias, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE taxonomy_alias ADD PRIMARY KEY (taxonomy_id, alias_id)"
    create index(:taxonomy_alias, [:taxonomy_id], name: :idx_taxonomy_alias_taxonomy_id)
    create index(:taxonomy_alias, [:alias_id], name: :idx_taxonomy_alias_alias_id)

    # species_taxonomy (species <-> taxonomy)
    create table(:species_taxonomy, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :taxonomy_id, references(:taxonomy, on_delete: :restrict), null: false
    end

    execute "ALTER TABLE species_taxonomy ADD PRIMARY KEY (species_id, taxonomy_id)"
    create index(:species_taxonomy, [:species_id], name: :idx_species_taxonomy_species_id)
    create index(:species_taxonomy, [:taxonomy_id], name: :idx_species_taxonomy_taxonomy_id)

    # place_hierarchy (place <-> place, parent-child)
    create table(:place_hierarchy, primary_key: false) do
      add :place_id, references(:place, on_delete: :delete_all), null: false
      add :parent_id, references(:place, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE place_hierarchy ADD PRIMARY KEY (place_id, parent_id)"
    create index(:place_hierarchy, [:place_id], name: :idx_place_hierarchy_place_id)
    create index(:place_hierarchy, [:parent_id], name: :idx_place_hierarchy_parent_id)

    # host_range (species <-> place, with precision and distribution_type)
    create table(:host_range, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :place_id, references(:place, on_delete: :delete_all), null: false
      add :precision, :string, null: false, default: "exact"
      add :distribution_type, :string, null: false, default: "native"
    end

    execute "ALTER TABLE host_range ADD PRIMARY KEY (species_id, place_id)"
    create index(:host_range, [:species_id], name: :idx_host_range_species_id)
    create index(:host_range, [:place_id], name: :idx_host_range_place_id)

    # gall_range (species <-> place, curated range)
    create table(:gall_range, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :place_id, references(:place, on_delete: :delete_all), null: false
      add :precision, :string, null: false, default: "exact"
    end

    execute "ALTER TABLE gall_range ADD PRIMARY KEY (species_id, place_id)"
    create index(:gall_range, [:species_id], name: :idx_gall_range_species_id)
    create index(:gall_range, [:place_id], name: :idx_gall_range_place_id)

    # =========================================================================
    # 14. Gall trait junction tables (gall_traits <-> filter fields)
    # =========================================================================

    create table(:gall_color, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :color_id, references(:color, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_color ADD PRIMARY KEY (species_id, color_id)"
    create index(:gall_color, [:species_id], name: :idx_gall_color_species_id)
    create index(:gall_color, [:color_id], name: :idx_gall_color_color_id)

    create table(:gall_walls, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :walls_id, references(:walls, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_walls ADD PRIMARY KEY (species_id, walls_id)"
    create index(:gall_walls, [:species_id], name: :idx_gall_walls_species_id)
    create index(:gall_walls, [:walls_id], name: :idx_gall_walls_walls_id)

    create table(:gall_cells, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :cells_id, references(:cells, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_cells ADD PRIMARY KEY (species_id, cells_id)"
    create index(:gall_cells, [:species_id], name: :idx_gall_cells_species_id)
    create index(:gall_cells, [:cells_id], name: :idx_gall_cells_cells_id)

    create table(:gall_shape, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :shape_id, references(:shape, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_shape ADD PRIMARY KEY (species_id, shape_id)"
    create index(:gall_shape, [:species_id], name: :idx_gall_shape_species_id)
    create index(:gall_shape, [:shape_id], name: :idx_gall_shape_shape_id)

    create table(:gall_texture, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :texture_id, references(:texture, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_texture ADD PRIMARY KEY (species_id, texture_id)"
    create index(:gall_texture, [:species_id], name: :idx_gall_texture_species_id)
    create index(:gall_texture, [:texture_id], name: :idx_gall_texture_texture_id)

    create table(:gall_alignment, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :alignment_id, references(:alignment, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_alignment ADD PRIMARY KEY (species_id, alignment_id)"
    create index(:gall_alignment, [:species_id], name: :idx_gall_alignment_species_id)
    create index(:gall_alignment, [:alignment_id], name: :idx_gall_alignment_alignment_id)

    create table(:gall_plant_part, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :plant_part_id, references(:plant_part, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_plant_part ADD PRIMARY KEY (species_id, plant_part_id)"
    create index(:gall_plant_part, [:species_id], name: :idx_gall_plant_part_species_id)
    create index(:gall_plant_part, [:plant_part_id], name: :idx_gall_plant_part_plant_part_id)

    create table(:gall_form, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :form_id, references(:form, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_form ADD PRIMARY KEY (species_id, form_id)"
    create index(:gall_form, [:species_id], name: :idx_gall_form_species_id)
    create index(:gall_form, [:form_id], name: :idx_gall_form_form_id)

    create table(:gall_season, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :season_id, references(:season, on_delete: :delete_all), null: false
    end

    execute "ALTER TABLE gall_season ADD PRIMARY KEY (species_id, season_id)"
    create index(:gall_season, [:species_id], name: :idx_gall_season_species_id)
    create index(:gall_season, [:season_id], name: :idx_gall_season_season_id)

    # =========================================================================
    # 15. Analytics summary tables (no FKs, used via raw SQL)
    # =========================================================================

    create table(:daily_stats) do
      add :date, :date, null: false
      add :page_views, :integer, null: false, default: 0
      add :unique_visitors, :integer, null: false, default: 0
    end

    create unique_index(:daily_stats, [:date])

    create table(:daily_page_stats) do
      add :date, :date, null: false
      add :path, :string, null: false
      add :page_views, :integer, null: false, default: 0
      add :unique_visitors, :integer, null: false, default: 0
    end

    create unique_index(:daily_page_stats, [:date, :path])
    create index(:daily_page_stats, [:date])

    create table(:daily_referrer_stats) do
      add :date, :date, null: false
      add :referrer_host, :string
      add :page_views, :integer, null: false, default: 0
    end

    create unique_index(:daily_referrer_stats, [:date, :referrer_host])
    create index(:daily_referrer_stats, [:date])

    create table(:daily_device_stats) do
      add :date, :date, null: false
      add :device_type, :string
      add :count, :integer, null: false, default: 0
    end

    create unique_index(:daily_device_stats, [:date, :device_type])
    create index(:daily_device_stats, [:date])

    create table(:daily_browser_stats) do
      add :date, :date, null: false
      add :browser, :string
      add :count, :integer, null: false, default: 0
    end

    create unique_index(:daily_browser_stats, [:date, :browser])
    create index(:daily_browser_stats, [:date])
  end

  def down do
    # Drop in reverse dependency order

    # Analytics summary tables
    drop_if_exists table(:daily_browser_stats)
    drop_if_exists table(:daily_device_stats)
    drop_if_exists table(:daily_referrer_stats)
    drop_if_exists table(:daily_page_stats)
    drop_if_exists table(:daily_stats)

    # Gall trait junction tables
    drop_if_exists table(:gall_season)
    drop_if_exists table(:gall_form)
    drop_if_exists table(:gall_plant_part)
    drop_if_exists table(:gall_alignment)
    drop_if_exists table(:gall_texture)
    drop_if_exists table(:gall_shape)
    drop_if_exists table(:gall_cells)
    drop_if_exists table(:gall_walls)
    drop_if_exists table(:gall_color)

    # Range and hierarchy junction tables
    drop_if_exists table(:gall_range)
    drop_if_exists table(:host_range)
    drop_if_exists table(:place_hierarchy)
    drop_if_exists table(:species_taxonomy)
    drop_if_exists table(:taxonomy_alias)
    drop_if_exists table(:alias_species)

    # Entity tables with FKs
    drop_if_exists table(:species_source)
    drop_if_exists table(:gallhost)
    drop_if_exists table(:content_images)
    drop_if_exists table(:image)
    drop_if_exists table(:host_traits)
    drop_if_exists table(:gall_traits)
    drop_if_exists table(:alias)
    drop_if_exists table(:species)

    # Standalone tables
    drop_if_exists table(:site_settings)
    drop_if_exists table(:page_views)
    drop_if_exists table(:keys)
    drop_if_exists table(:articles)
    drop_if_exists table(:users)
    drop_if_exists table(:source)
    drop_if_exists table(:taxonomy)
    drop_if_exists table(:place)
    drop_if_exists table(:glossary)
    drop_if_exists table(:abundance)

    # Filter field tables
    drop_if_exists table(:walls)
    drop_if_exists table(:texture)
    drop_if_exists table(:shape)
    drop_if_exists table(:season)
    drop_if_exists table(:plant_part)
    drop_if_exists table(:form)
    drop_if_exists table(:color)
    drop_if_exists table(:cells)
    drop_if_exists table(:alignment)
  end
end
