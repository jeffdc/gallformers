defmodule Gallformers.Repo.Migrations.CreateLegacyCitations do
  @moduledoc """
  Creates `legacy_citations` (`9449` §6, Task 16), owned by
  `Gallformers.Catalog`: today's record-level citations (`species_source`
  rows of any Source but the Gallformers Source) carried over per Gall —
  the Source, its narrative (`description`), `useasdefault` and the deep
  link (`externallink`) — so the Gall page can show them as today until the
  backscan replaces them with attributed Facts. They are not Facts.

  `legacy_id` is the `species_source` row's ID. Audited, as every new
  table is; filled only by the data migration.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:legacy_citations) do
      add :gall_id, references(:galls, type: :bigint, on_delete: :restrict), null: false
      add :source_id, references(:source, on_delete: :restrict), null: false
      add :description, :text, null: false, default: ""
      add :useasdefault, :boolean, null: false, default: false
      add :externallink, :text, null: false, default: ""
      add :legacy_id, :bigint
    end

    create unique_index(:legacy_citations, [:gall_id, :source_id])
    create index(:legacy_citations, [:source_id])

    Audit.track_table("legacy_citations")
  end

  def down do
    Audit.untrack_table("legacy_citations")
    drop table(:legacy_citations)
  end
end
