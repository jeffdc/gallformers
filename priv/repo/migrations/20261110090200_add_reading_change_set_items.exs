defmodule Gallformers.Repo.Migrations.AddReadingChangeSetItems do
  @moduledoc """
  A tray item may fix how Gallformers read a Source (matter `87a1`, task
  9): a `reading` item, about one Fact and one Source. One item per Fact
  key and Source: two Sources' readings of one Fact are two items, so the
  unique index takes the Source too (null for every other kind).
  """
  use Ecto.Migration

  @columns [:change_set_id, :kind, :subject_type, :subject_id, :key]

  def up do
    alter table(:change_set_items) do
      add :source_id, references(:source, on_delete: :delete_all)
    end

    drop constraint(:change_set_items, :change_set_items_kind_check)

    create constraint(:change_set_items, :change_set_items_kind_check,
             check: "kind IN ('fact', 'note', 'editorial', 'photo', 'reading')"
           )

    drop unique_index(:change_set_items, @columns)

    create unique_index(:change_set_items, @columns ++ [:source_id],
             name: :change_set_items_one_per_key_index,
             nulls_distinct: false
           )
  end

  def down do
    execute "DELETE FROM change_set_items WHERE kind = 'reading'"
    drop index(:change_set_items, @columns ++ [:source_id], name: :change_set_items_one_per_key_index)
    create unique_index(:change_set_items, @columns)
    drop constraint(:change_set_items, :change_set_items_kind_check)

    create constraint(:change_set_items, :change_set_items_kind_check,
             check: "kind IN ('fact', 'note', 'editorial', 'photo')"
           )

    alter table(:change_set_items) do
      remove :source_id
    end
  end
end
