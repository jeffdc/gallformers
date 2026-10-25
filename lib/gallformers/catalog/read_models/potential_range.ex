defmodule Gallformers.Catalog.ReadModels.PotentialRange do
  @moduledoc """
  A Gall's potential range (`9449` §4; `8567` rule 10): where it could
  occur.

    1. The union of the ranges (`host_range`, native and introduced) of the
       plant taxa that are its current Hosts (`host_of`), read by
       `host_range.taxon_id`. A genus Host contributes its own range rows:
       the data migration re-keys a genus placeholder's rows to the genus
       taxon (`Gallformers.CatalogMigration`).
    2. Then its current range adjustments: `only` restricts it to those
       places, `exclude` removes places, `include` adds places.

  **Missing data is not absence.** A Gall with no Host range data (no Host,
  or Hosts without range rows) appears in every region, as today
  (`search.ex`, "Galls with no range data should appear in every region"),
  so its range is `:everywhere`, never an empty list. Adjustments still
  apply to it: `only` gives it that range, and `exclude` leaves every other
  selectable place (`Gallformers.Places.list_places/0`). Following the plan,
  any computation that ends empty is `:everywhere` too.

  Places are compared as leaves: a country-level host-range row, or an
  adjustment naming a country, stands for the country's subdivisions (as
  `Gallformers.Ranges` expands country precision); a place with no
  subdivisions stands for itself. The result is a list of leaf places by
  code. The exact-versus-inherited distinction maps draw is left to the
  pages, which still use `Gallformers.Ranges`.

  Computed on read from current Facts; see `Gallformers.Catalog` for why it
  is not materialized yet.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Repo

  @type place :: %{place_id: integer(), code: String.t()}

  @type t :: :everywhere | [place(), ...]

  @doc "A Gall's potential range: `:everywhere`, or its leaf places by code."
  @spec for_gall(integer()) :: t()
  def for_gall(gall_id) when is_integer(gall_id) do
    adjustments =
      from(r in Current.range_adjustments(gall_id), select: {r.adjustment, r.place_id})
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    case host_leaf_ids(gall_id) do
      [] -> :everywhere
      ids -> ids
    end
    |> restrict(leaves(adjustments[:only]))
    |> exclude(leaves(adjustments[:exclude]))
    |> include(leaves(adjustments[:include]))
    |> places()
  end

  defp host_leaf_ids(gall_id) do
    host_ids =
      Repo.all(
        from(r in Current.relationships("host_of"),
          where: r.object_gall_id == ^gall_id,
          select: r.subject_taxon_id
        )
      )

    from(hr in "host_range",
      where: hr.taxon_id in ^host_ids,
      distinct: true,
      select: hr.place_id
    )
    |> Repo.all()
    |> leaves()
  end

  defp leaves(nil), do: []
  defp leaves([]), do: []
  defp leaves(place_ids), do: place_ids |> Enum.uniq() |> Places.batch_leaf_descendant_ids()

  # Ranges are lists of leaf place IDs, or :everywhere.

  defp restrict(range, []), do: range
  defp restrict(:everywhere, only), do: only
  defp restrict(range, only), do: Enum.filter(range, &(&1 in only))

  defp exclude(range, []), do: range

  defp exclude(:everywhere, excluded),
    do: exclude(Enum.map(Places.list_places(), & &1.id), excluded)

  defp exclude(range, excluded), do: Enum.reject(range, &(&1 in excluded))

  defp include(:everywhere, _included), do: :everywhere
  defp include(range, included), do: Enum.uniq(range ++ included)

  defp places(:everywhere), do: :everywhere

  defp places(ids) do
    case Repo.all(
           from(p in Place,
             where: p.id in ^ids,
             order_by: p.code,
             select: %{place_id: p.id, code: p.code}
           )
         ) do
      [] -> :everywhere
      places -> places
    end
  end
end
