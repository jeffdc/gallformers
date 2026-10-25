defmodule Gallformers.Repo.Migrations.CreateGalls do
  @moduledoc """
  Creates `galls` (`9449` §4, Task 9), owned by `Gallformers.Catalog`, and
  gives `source_documents.gall_id` (a Gall's note versions, Task 3) its
  foreign key.

  A Gall's ID comes from `entity_id_seq`, shared with taxa (`8567` rule 4);
  migrated Galls insert their species IDs explicitly. Its generation
  identifies it (not a Fact). `name` is the derived name (`8567` rule 9) and
  `name_override` replaces it where set; the name shown — the override, else
  the derived name — is unique. `abundance_id` and `datacomplete` are
  editorial carry-overs from today's `species` rows.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:galls, primary_key: false) do
      add :id, :bigint, primary_key: true, default: fragment("nextval('entity_id_seq')")
      add :gallformers_code, :text
      add :generation_value_id, references(:generation_values, on_delete: :restrict)
      add :name, :text, null: false
      add :name_override, :text
      add :abundance_id, references(:abundance, on_delete: :restrict)
      add :datacomplete, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:galls, ["COALESCE(name_override, name)"], name: :galls_display_name_index)

    create unique_index(:galls, [:gallformers_code],
             where: "gallformers_code IS NOT NULL",
             name: :galls_gallformers_code_index
           )

    create index(:galls, [:generation_value_id])
    create constraint(:galls, :galls_name_present, check: "name <> ''")

    create constraint(:galls, :galls_name_override_present,
             check: "name_override IS NULL OR name_override <> ''"
           )

    Audit.track_table("galls")

    alter table(:source_documents) do
      modify :gall_id, references(:galls, type: :bigint, on_delete: :restrict),
        from: :bigint
    end
  end

  def down do
    alter table(:source_documents) do
      modify :gall_id, :bigint, from: references(:galls, type: :bigint, on_delete: :restrict)
    end

    Audit.untrack_table("galls")
    drop table(:galls)
  end
end
