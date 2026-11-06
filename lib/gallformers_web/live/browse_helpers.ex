defmodule GallformersWeb.BrowseHelpers do
  @moduledoc """
  Shared helper functions for tree-browse LiveViews (galls, hosts, places).

  Provides tree filtering, smart expand logic, and branch key collection
  used by all browse pages.
  """

  # Smart expand thresholds
  @max_families_to_auto_expand 3
  @max_children_per_node 5

  @doc "The Browse pages' tabs, as `{label, path}`, for `tab_nav`."
  @spec browse_tabs() :: [{String.t(), String.t()}]
  def browse_tabs do
    [{"By what causes them", "/galls"}, {"By host plant", "/hosts"}, {"By place", "/places"}]
  end

  @doc """
  Computes the smart-expand set for a search query.

  When a search produces few matching families (<= 3), auto-expands nodes
  that have <= 5 children. Otherwise keeps the current expanded set.
  """
  @spec smart_expand([map()], String.t(), MapSet.t()) :: MapSet.t()
  def smart_expand(filtered_tree, query, current_expanded) do
    if String.trim(query) != "" do
      matching_families = length(filtered_tree)

      if matching_families <= @max_families_to_auto_expand do
        filtered_tree
        |> collect_branch_keys_with_limit(@max_children_per_node)
        |> MapSet.new()
      else
        current_expanded
      end
    else
      current_expanded
    end
  end

  @doc """
  Collects all branch node keys from a tree (nodes that have children).
  """
  @spec collect_branch_keys([map()]) :: [String.t()]
  def collect_branch_keys(nodes) do
    Enum.flat_map(nodes, fn node ->
      if Map.has_key?(node, :nodes) and node.nodes != [] do
        [node.key | collect_branch_keys(node.nodes)]
      else
        []
      end
    end)
  end

  @doc """
  Toggles a key in a MapSet (adds if absent, removes if present).

  Works with any term type — string IDs, integer IDs, tuples, etc.
  """
  @spec toggle_set(MapSet.t(), term()) :: MapSet.t()
  def toggle_set(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  @doc """
  Toggles all items in a group within a selection set.

  If all group items are selected, deselects them. Otherwise, selects all.
  Expects a group with an `:items` list where each item has an `:id` field.
  Returns the selection unchanged if the group is not found.
  """
  @spec toggle_group_selection([map()], MapSet.t(), term()) :: MapSet.t()
  def toggle_group_selection(groups, selected, group_id) do
    group = Enum.find(groups, &(to_string(&1.id) == to_string(group_id)))

    if group do
      item_ids = MapSet.new(group.items, & &1.id)
      selected_in_group = MapSet.intersection(selected, item_ids)

      if MapSet.equal?(selected_in_group, item_ids),
        do: MapSet.difference(selected, item_ids),
        else: MapSet.union(selected, item_ids)
    else
      selected
    end
  end

  @doc """
  Filters a browse tree (`/galls`, `/hosts`, `/places`) by a name: it keeps
  the nodes whose label contains the query (ignoring case) and their
  ancestors, and a node whose own label matches keeps everything under it,
  so a matched family's card still shows its genera.
  """
  @spec filter_tree([map()], String.t()) :: [map()]
  def filter_tree(nodes, ""), do: nodes

  def filter_tree(nodes, query) do
    query_lower = String.downcase(query)

    nodes
    |> Enum.map(&filter_card_node(&1, query_lower))
    |> Enum.reject(&is_nil/1)
  end

  defp filter_card_node(node, query_lower) do
    cond do
      label_matches?(node.label, query_lower) ->
        node

      branch_node?(node) ->
        case filter_tree(node.nodes, query_lower) do
          [] -> nil
          children -> %{node | nodes: children}
        end

      true ->
        nil
    end
  end

  @doc """
  A browse tree (`Gallformers.Taxa.TreeBuilder` shape) as `family_card`s:
  each family with its count, a photo and its genera (each with its count
  and leaves), genera most first, then by name.

  `counting` says what a count is:
  - `{:leaves, photos}`: the Galls under it (the Galls tree); `photos` maps
    a Gall ID to its photo URL, and a family's photo is its first Gall with
    one. Families keep the tree's order.
  - `{:taxa, counts}`: `counts` maps a genus or family taxon ID to
    `%{count:, image_url:}` (the Hosts tree: Galls on the taxon); a taxon
    absent from it counts 0. Families are most galled first, then by name.
  """
  @spec family_cards([map()], {:leaves, map()} | {:taxa, map()}) :: [map()]
  def family_cards(nodes, counting) do
    cards = Enum.map(nodes, &family_card(&1, counting))

    case counting do
      {:leaves, _} -> cards
      {:taxa, _} -> Enum.sort_by(cards, &{-&1.count, &1.name})
    end
  end

  defp family_card(node, counting) do
    genera =
      node.nodes
      |> Enum.map(&genus_card(&1, counting))
      |> Enum.sort_by(&{-&1.count, &1.name})

    {count, image_url} =
      case counting do
        {:leaves, photos} ->
          leaf_ids = Enum.flat_map(genera, fn g -> Enum.map(g.leaves, & &1.id) end)
          {length(leaf_ids), Enum.find_value(leaf_ids, &Map.get(photos, &1))}

        {:taxa, counts} ->
          taxon_count(counts, node.key)
      end

    node
    |> Map.take([:key, :name, :url, :description])
    |> Map.merge(%{count: count, image_url: image_url, genera: genera})
  end

  defp genus_card(node, counting) do
    leaves =
      Enum.map(node.nodes, &Map.put(Map.take(&1, [:key, :label, :url]), :id, key_id(&1.key)))

    count =
      case counting do
        {:leaves, _} -> length(leaves)
        {:taxa, counts} -> counts |> taxon_count(node.key) |> elem(0)
      end

    node
    |> Map.take([:key, :name, :url, :description])
    |> Map.merge(%{count: count, leaves: leaves})
  end

  defp taxon_count(counts, key) do
    case Map.get(counts, key_id(key)) do
      %{count: count, image_url: url} -> {count, url}
      nil -> {0, nil}
    end
  end

  # "f-12" -> 12
  defp key_id(key), do: key |> String.split("-") |> List.last() |> String.to_integer()

  # --- Private helpers ---

  defp branch_node?(node), do: Map.has_key?(node, :nodes) and node.nodes != []

  defp label_matches?(label, query_lower),
    do: String.contains?(String.downcase(label), query_lower)

  defp collect_branch_keys_with_limit(nodes, max_children) do
    Enum.flat_map(nodes, &collect_node_keys_with_limit(&1, max_children))
  end

  defp collect_node_keys_with_limit(%{nodes: children} = node, max_children)
       when is_list(children) and children != [] do
    child_keys = collect_branch_keys_with_limit(children, max_children)

    if length(children) <= max_children do
      [node.key | child_keys]
    else
      child_keys
    end
  end

  defp collect_node_keys_with_limit(_node, _max_children), do: []
end
