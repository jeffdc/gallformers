defmodule Gallformers.Repo.Migrations.AddPhotoChangeSetItems do
  @moduledoc """
  A tray item may be an iNaturalist observation's photo for a Gall
  (matter `87a1`, Add from observation): an editorial change, stored as
  the Gall's image when applied.
  """
  use Ecto.Migration

  def up do
    drop constraint(:change_set_items, :change_set_items_kind_check)

    create constraint(:change_set_items, :change_set_items_kind_check,
             check: "kind IN ('fact', 'note', 'editorial', 'photo')"
           )
  end

  def down do
    execute "DELETE FROM change_set_items WHERE kind = 'photo'"
    drop constraint(:change_set_items, :change_set_items_kind_check)

    create constraint(:change_set_items, :change_set_items_kind_check,
             check: "kind IN ('fact', 'note', 'editorial')"
           )
  end
end
