defmodule Gallformers.Catalog.TaxonListener do
  @moduledoc """
  The Catalog's "taxon changed" listener (`8567` rule 6), registered in
  `config/config.exs` and called by `Gallformers.Taxa` inside the
  transaction that changes a taxon.

  For now it accepts every change:

    * `:move` — nothing in the Catalog stores ancestry; the read models
      (potential range, summaries, flags) are computed on read from current
      Facts and `Gallformers.Taxa`, so they follow the move. Generation-group
      checks for Inducers carried out of their group's subtree are reported
      by `Gallformers.Catalog.ReadModels.Flags`; whether such a move should
      fail instead is open (`8567` *Generation groups*).
    * `:rename` — derived Gall names (Inducer name plus qualifiers, `8567`
      rule 9) and keeping the old name as a Gall alias are later work, with
      name derivation; until then a rename changes nothing here. This is
      where a derived-name collision will reject the rename.
    * `:merge`, `:split` — not emitted in phase 1; re-pointing Relationship
      endpoints and curator tasks come with the operations that emit them.
  """
  @behaviour Gallformers.Taxa.Events

  alias Gallformers.Taxa.Event

  @impl true
  def taxon_changed(%Event{}), do: :ok
end
