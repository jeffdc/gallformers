defmodule Gallformers.Repo.Migrations.CreateGallFacts do
  @moduledoc """
  Creates the gall Fact detail tables (`9449` §4, Task 9), owned by
  `Gallformers.Catalog`. Each is keyed by `fact_id` and unique on its kind's
  natural key; all are audited.

  | Table | Natural key |
  |---|---|
  | `relationship_facts` | type + subject + object + Gall context |
  | `qualifier_facts` | Relationship + qualifier + value |
  | `trait_facts` | Gall + Trait value |
  | `range_facts` | Gall + adjustment + place |
  | `occurrence_facts` | Gall + place |
  | `alias_facts` | Gall + name (any case) |
  | `description_facts` | Gall |

  A Relationship's subject and object are each a taxon or a Gall, by its
  type's endpoint kinds (`Gallformers.Catalog.RelationshipTypes`), which the
  check constraint `relationship_facts_endpoint_kinds` enforces. The type and
  qualifier lists here are the system lists: they change only by migration,
  together with `RelationshipTypes`.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @taxon_to_gall ~w(inducer_of host_of symbiont_of inquiline_of cecidophage_in parasitoid_in
                    emerged_from feeds_on herbivore_of successor_in)
  @gall_to_gall ~w(modified_form_of alternate_generation_of)
  @taxon_to_taxon_in_gall ~w(parasitoid_of vectored_by predator_of)

  @lethality ["lethal", "non-lethal"]
  @parasitism_mode ~w(idiobiont koinobiont solitary gregarious ecto endo)

  @fact_pk ["fact_id"]

  def up do
    create table(:relationship_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :type, :text, null: false
      add :subject_taxon_id, references(:taxa, type: :bigint, on_delete: :restrict)
      add :subject_gall_id, references(:galls, type: :bigint, on_delete: :restrict)
      add :object_taxon_id, references(:taxa, type: :bigint, on_delete: :restrict)
      add :object_gall_id, references(:galls, type: :bigint, on_delete: :restrict)
      # The Gall an organism-to-organism Relationship happens in.
      add :gall_context_id, references(:galls, type: :bigint, on_delete: :restrict)
    end

    create constraint(:relationship_facts, :relationship_facts_type_check,
             check: "type IN (#{list(@taxon_to_gall ++ @gall_to_gall ++ @taxon_to_taxon_in_gall)})"
           )

    create constraint(:relationship_facts, :relationship_facts_endpoint_kinds,
             check: """
             (type IN (#{list(@taxon_to_gall)})
               AND subject_taxon_id IS NOT NULL AND subject_gall_id IS NULL
               AND object_gall_id IS NOT NULL AND object_taxon_id IS NULL
               AND gall_context_id IS NULL)
             OR (type IN (#{list(@gall_to_gall)})
               AND subject_gall_id IS NOT NULL AND subject_taxon_id IS NULL
               AND object_gall_id IS NOT NULL AND object_taxon_id IS NULL
               AND gall_context_id IS NULL)
             OR (type IN (#{list(@taxon_to_taxon_in_gall)})
               AND subject_taxon_id IS NOT NULL AND subject_gall_id IS NULL
               AND object_taxon_id IS NOT NULL AND object_gall_id IS NULL
               AND gall_context_id IS NOT NULL)
             """
           )

    create constraint(:relationship_facts, :relationship_facts_not_own_gall,
             check: "subject_gall_id IS NULL OR subject_gall_id <> object_gall_id"
           )

    # Each type fixes which of the taxon and Gall columns an endpoint uses, so
    # COALESCE never mixes the two kinds within a type.
    create unique_index(
             :relationship_facts,
             [
               "type",
               "COALESCE(subject_taxon_id, subject_gall_id)",
               "COALESCE(object_taxon_id, object_gall_id)",
               "COALESCE(gall_context_id, 0)"
             ],
             name: :relationship_facts_natural_key_index
           )

    create index(:relationship_facts, [:object_gall_id, :type])
    create index(:relationship_facts, [:subject_gall_id])
    create index(:relationship_facts, [:subject_taxon_id])
    create index(:relationship_facts, [:object_taxon_id])
    create index(:relationship_facts, [:gall_context_id])

    Audit.track_table("relationship_facts", primary_key_columns: @fact_pk)

    create table(:qualifier_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true

      add :of_fact_id,
          references(:relationship_facts, column: :fact_id, on_delete: :restrict),
          null: false

      add :qualifier, :text, null: false
      add :value, :text, null: false
    end

    create unique_index(:qualifier_facts, [:of_fact_id, :qualifier, :value])

    create constraint(:qualifier_facts, :qualifier_facts_value_check,
             check: """
             (qualifier = 'required_for_formation' AND value = 'true')
             OR (qualifier = 'lethality' AND value IN (#{list(@lethality)}))
             OR (qualifier = 'parasitism_mode' AND value IN (#{list(@parasitism_mode)}))
             """
           )

    Audit.track_table("qualifier_facts", primary_key_columns: @fact_pk)

    create table(:trait_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :gall_id, references(:galls, type: :bigint, on_delete: :restrict), null: false
      add :trait_value_id, references(:trait_values, on_delete: :restrict), null: false
    end

    create unique_index(:trait_facts, [:gall_id, :trait_value_id])
    create index(:trait_facts, [:trait_value_id])

    Audit.track_table("trait_facts", primary_key_columns: @fact_pk)

    create table(:range_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :gall_id, references(:galls, type: :bigint, on_delete: :restrict), null: false
      add :adjustment, :text, null: false
      add :place_id, references(:place, on_delete: :restrict), null: false
    end

    create unique_index(:range_facts, [:gall_id, :adjustment, :place_id])
    create index(:range_facts, [:place_id])

    create constraint(:range_facts, :range_facts_adjustment_check,
             check: "adjustment IN ('include', 'exclude', 'only')"
           )

    Audit.track_table("range_facts", primary_key_columns: @fact_pk)

    # When and at what stage live on each Source's attribution
    # (`when_as_written`, `stage_as_written`).
    create table(:occurrence_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :gall_id, references(:galls, type: :bigint, on_delete: :restrict), null: false
      add :place_id, references(:place, on_delete: :restrict), null: false
    end

    create unique_index(:occurrence_facts, [:gall_id, :place_id])
    create index(:occurrence_facts, [:place_id])

    Audit.track_table("occurrence_facts", primary_key_columns: @fact_pk)

    # A common name for the Gall; `name` keeps the form first recorded.
    create table(:alias_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :gall_id, references(:galls, type: :bigint, on_delete: :restrict), null: false
      add :name, :text, null: false
    end

    create unique_index(:alias_facts, ["gall_id", "lower(name)"],
             name: :alias_facts_gall_id_name_index
           )

    create constraint(:alias_facts, :alias_facts_name_present, check: "name <> ''")

    Audit.track_table("alias_facts", primary_key_columns: @fact_pk)

    # A Source's description of a Gall is its attribution's quotes: one Fact
    # per Gall, one attribution per Source.
    create table(:description_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :gall_id, references(:galls, type: :bigint, on_delete: :restrict), null: false
    end

    create unique_index(:description_facts, [:gall_id])

    Audit.track_table("description_facts", primary_key_columns: @fact_pk)
  end

  def down do
    for table <-
          ~w(description_facts alias_facts occurrence_facts range_facts trait_facts qualifier_facts relationship_facts) do
      Audit.untrack_table(table)
      drop table(table)
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
