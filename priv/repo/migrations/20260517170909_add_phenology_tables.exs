defmodule Gallformers.Repo.Migrations.AddPhenologyTables do
  @moduledoc """
  Storage for manually curated phenology evidence and rejected iNaturalist IDs.
  Creates empty tables; does not fetch, import, relabel or overwrite evidence.
  """
  use Ecto.Migration

  def change do
    create table(:phenology_observations) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :host_species_id, references(:species, on_delete: :nilify_all)
      add :source_type, :string, null: false
      add :inat_id, :integer

      # Original source values, retained for provenance.
      add :raw_phenophase, :string
      add :raw_date, :date
      add :raw_latitude, :float
      add :raw_longitude, :float

      # Validated fields used for display and predictions.
      add :phenophase, :string
      add :date, :date, null: false
      add :doy, :integer, null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :site, :string
      add :state, :string
      add :country, :string

      # Insect stage and rearing outcome are independent of gall phenophase.
      add :lifestage, :string
      add :viability, :string

      # Retained for legacy selection lenses, not seasonal-landmark predictions.
      add :seasind, :float
      add :acchours, :float
      add :source_url, :text
      add :page_url, :text
      timestamps(type: :utc_datetime)
    end

    create index(:phenology_observations, [:species_id],
             name: :idx_phenology_observations_species_id
           )

    create index(:phenology_observations, [:species_id, :date],
             name: :idx_phenology_observations_species_date
           )

    create index(:phenology_observations, [:host_species_id],
             name: :idx_phenology_observations_host_species_id
           )

    create index(:phenology_observations, [:source_type],
             name: :idx_phenology_observations_source_type
           )

    create unique_index(:phenology_observations, [:inat_id],
             where: "inat_id IS NOT NULL",
             name: :idx_phenology_observations_inat_id_unique
           )

    create constraint(:phenology_observations, :phenology_observations_source_type_check,
             check: "source_type IN ('literature', 'inat')"
           )

    create constraint(
             :phenology_observations,
             :phenology_observations_inat_id_matches_source_type,
             check:
               "(source_type = 'inat' AND inat_id IS NOT NULL) OR (source_type = 'literature' AND inat_id IS NULL)"
           )

    create constraint(:phenology_observations, :phenology_observations_doy_check,
             check: "doy BETWEEN 1 AND 366"
           )

    create constraint(:phenology_observations, :phenology_observations_latitude_check,
             check: "latitude BETWEEN -90.0 AND 90.0"
           )

    create constraint(:phenology_observations, :phenology_observations_longitude_check,
             check: "longitude BETWEEN -180.0 AND 180.0"
           )

    create table(:phenology_blacklist) do
      add :inat_id, :integer, null: false
      add :species_id, references(:species, on_delete: :delete_all)
      add :reason, :text
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:phenology_blacklist, [:inat_id],
             name: :idx_phenology_blacklist_inat_id_unique
           )

    create index(:phenology_blacklist, [:species_id], name: :idx_phenology_blacklist_species_id)
  end
end
