defmodule GallformersWeb.LineageBreadcrumb do
  @moduledoc """
  The assigns of the `taxonomy_breadcrumb` component from a taxon's lineage
  (`Gallformers.Taxa.lineage/1`, root first): its family, the ranks between
  family and genus, its genus and its section.
  """
  alias Gallformers.Taxa.Rank

  @type entry :: %{id: integer(), name: String.t()}

  @type t :: %{
          family: entry() | nil,
          intermediates: [%{id: integer(), name: String.t(), rank: String.t()}],
          genus: entry() | nil,
          section: entry() | nil
        }

  @doc "The breadcrumb of `lineage`, or nil when it has no family, intermediate, genus or section."
  @spec from_lineage([Gallformers.Taxa.lineage_entry()]) :: t() | nil
  def from_lineage(lineage) when is_list(lineage) do
    intermediates =
      for t <- lineage, Rank.below?(t.rank, :family), Rank.below?(:genus, t.rank) do
        %{id: t.taxon_id, name: t.name, rank: t.rank |> Atom.to_string() |> String.capitalize()}
      end

    case {find(lineage, :family), intermediates, find(lineage, :genus), find(lineage, :section)} do
      {nil, [], nil, nil} ->
        nil

      {family, intermediates, genus, section} ->
        %{family: family, intermediates: intermediates, genus: genus, section: section}
    end
  end

  defp find(lineage, rank) do
    Enum.find_value(lineage, fn t -> t.rank == rank && %{id: t.taxon_id, name: t.name} end)
  end
end
