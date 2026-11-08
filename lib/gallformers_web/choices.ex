defmodule GallformersWeb.Choices do
  @moduledoc """
  The shared pickers' results as a `typeahead` takes them
  (`%{id, name, meta, group}`, grouped by `group`; matter `87a1`): one
  place that words them, for every page that picks a Host or a Fact's
  place.

    * `hosts/2`: the plants a Gall's Host may be
      (`Gallformers.Taxa.host_choices/2`): "Plants" (species and below),
      then "Genera and sections", each with its rank and up to three
      aliases ("species · also Quercus borealis");
    * `places/3`: the places a Fact may name
      (`Gallformers.Places.search_fact_places/3`), each with the place it is
      in ("Alberta", "Canada").
  """
  alias Gallformers.Places
  alias Gallformers.Taxa

  @min_letters 2

  @doc "The Host choices matching `query` (at least two letters), up to `limit` of each group."
  @spec hosts(String.t(), pos_integer()) :: [map()]
  def hosts(query, limit) when is_binary(query) do
    if String.length(String.trim(query)) < @min_letters do
      []
    else
      for c <- Taxa.host_choices(query, limit),
          do: %{id: c.id, name: c.name, meta: meta(c.rank, c.aliases), group: group(c.group)}
    end
  end

  @doc """
  The places matching `query` that a Fact of `kind` (`:occurrence`,
  `:range`) may name, up to `limit`.
  """
  @spec places(String.t(), :occurrence | :range, pos_integer()) :: [map()]
  def places(query, kind, limit) when is_binary(query) do
    if String.length(String.trim(query)) < @min_letters do
      []
    else
      for p <- Places.search_fact_places(query, kind, limit),
          do: %{id: p.id, name: p.name, meta: p.parent_name, group: p.group}
    end
  end

  defp group(:plants), do: "Plants"
  defp group(:genera_and_sections), do: "Genera and sections"

  defp meta(rank, aliases) do
    [rank && to_string(rank), aliases != [] && "also " <> Enum.join(Enum.take(aliases, 3), ", ")]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end
end
