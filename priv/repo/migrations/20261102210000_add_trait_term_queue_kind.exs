defmodule Gallformers.Repo.Migrations.AddTraitTermQueueKind do
  @moduledoc """
  Questions about a Source's Trait terms (matter d213, Task C): a
  `trait_term` item asks a curator to settle a term the import could not
  place on its own — an ambiguous term's use the readers didn't agree on,
  or a new term they placed differently (`Gallformers.Import.TraitTerms`).
  One per term within a package, covering its Galls. It never holds
  approval.

  `set_aside_term` stays allowed for the rows made before it replaced
  them; no new ones are made.
  """
  use Ecto.Migration

  @kinds ~w(ambiguous_match unresolved_name unresolved_host undescribed_gall dispute
            same_date_conflict taxonomy_disagreement generation_outside_group gall_rename
            set_aside_term set_aside_statement)

  @new ~w(trait_term)

  def up do
    drop constraint(:queue_items, :queue_items_kind_check)

    create constraint(:queue_items, :queue_items_kind_check,
             check: "kind IN (#{list(@kinds ++ @new)})"
           )
  end

  def down do
    # `queue_items` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_trait_term_queue_kind")
    execute "DELETE FROM queue_items WHERE kind IN (#{list(@new)})"

    drop constraint(:queue_items, :queue_items_kind_check)
    create constraint(:queue_items, :queue_items_kind_check, check: "kind IN (#{list(@kinds)})")
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
