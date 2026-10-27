defmodule Gallformers.Catalog.TaxonListener do
  @moduledoc """
  The Catalog's "taxon changed" listener (`8567` rule 6), registered in
  `config/config.exs` and called by `Gallformers.Taxa` inside the
  transaction that changes a taxon.

  It accepts every change:

    * `:move` — the ID tool's lookup table
      (`Gallformers.Catalog.ReadModels.GallIndex`) stores the lineages of
      Inducers and Hosts, so the Galls whose current Inducer or Host is in
      the moved subtree get a refresh enqueued, and so do the Galls whose
      Host is above the moved taxon, before or after the move: a Host above
      species rank stores its subtree's range (`803b` decision 8). The
      other read models
      (potential range, summaries, flags) are computed on read, so they
      follow the move. Generation-group checks for Inducers carried out of
      their group's subtree are reported by
      `Gallformers.Catalog.ReadModels.Flags`; whether such a move should
      fail instead is open (`8567` *Generation groups*).
    * `:rename` — the same refresh, for the taxon's subtree. Derived Gall
      names (Inducer name plus qualifiers, `8567` rule 9) and keeping the
      old name as a Gall alias are later work, with name derivation; this
      is where a derived-name collision will reject the rename.
    * `:merge`, `:split` — not emitted in phase 1; re-pointing Relationship
      endpoints and curator tasks come with the operations that emit them.
  """
  @behaviour Gallformers.Taxa.Events

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Event

  @impl true
  def taxon_changed(%Event{type: type, taxon_id: taxon_id} = event)
      when type in [:move, :rename] do
    subtree = taxon_id |> List.wrap() |> Taxa.subtree_ids() |> Map.get(taxon_id, [taxon_id])
    hosts = subtree ++ range_hosts(event)

    from(r in Current.relationships("inducer_of"),
      where: r.subject_taxon_id in ^subtree,
      select: r.object_gall_id
    )
    |> Ecto.Query.union(
      ^from(r in Current.relationships("host_of"),
        where: r.subject_taxon_id in ^hosts,
        select: r.object_gall_id
      )
    )
    |> Repo.all()
    |> GallIndex.enqueue_refresh()
  end

  def taxon_changed(%Event{}), do: :ok

  # A move changes the range of every Host above the moved taxon, before and
  # after: a genus Host's range is its subtree's
  # (`Gallformers.Catalog.ReadModels.PotentialRange`).
  defp range_hosts(%Event{type: :move} = event) do
    for parent <- [event.from_parent_id, event.to_parent_id],
        parent != nil,
        id <- [parent | Enum.map(Taxa.ancestors(parent), & &1.id)],
        uniq: true,
        do: id
  end

  defp range_hosts(%Event{}), do: []
end
