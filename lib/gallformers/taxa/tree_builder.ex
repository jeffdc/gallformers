defmodule Gallformers.Taxa.TreeBuilder do
  @moduledoc """
  Builds the Family → Genus → leaf tree of the browse pages (`/galls`,
  `/hosts`) from flat rows, in the node shape `GallformersWeb.TreeComponents`
  renders. Pure: the rows come from `Gallformers.Taxa.plant_tree/0` and
  `Gallformers.Catalog.gall_tree/0`.

  Each row has `family_id`, `family_name`, `family_description`, `genus_id`,
  `genus_name`, `genus_description`, `leaf_id` and `leaf_name`, and may
  have `genus_url` (default the genus's page, `rank_path/2`) and
  `leaf_genus_placeholder`.
  Families, genera and leaves keep the rows' order; a repeated row adds
  nothing.
  """

  @type key_style :: :short | :long

  @type row :: %{
          required(:family_id) => integer(),
          required(:family_name) => String.t(),
          required(:family_description) => String.t() | nil,
          required(:genus_id) => integer(),
          required(:genus_name) => String.t(),
          required(:genus_description) => String.t() | nil,
          required(:leaf_id) => integer(),
          required(:leaf_name) => String.t(),
          optional(:genus_url) => String.t(),
          optional(:leaf_genus_placeholder) => boolean()
        }

  @doc """
  Builds the tree of `rows`; each leaf links to `url_prefix` plus its ID
  (e.g. `"/gall/"`). `opts`: `:key_style` — `:short` (`f-123`, the
  default) or `:long` (`family-123`).
  """
  @spec build_tree([row()], String.t(), keyword()) :: [map()]
  def build_tree(rows, url_prefix, opts \\ []) do
    key_style = Keyword.get(opts, :key_style, :short)

    rows
    |> group_ordered(& &1.family_id)
    |> Enum.map(fn [first | _] = family_rows ->
      %{
        key: format_key("family", "f", first.family_id, key_style),
        label: format_label(first.family_name, first.family_description),
        name: first.family_name,
        rank: "family",
        description: format_description(first.family_description),
        url: rank_path(:family, first.family_name),
        nodes: genus_nodes(family_rows, url_prefix, key_style)
      }
    end)
  end

  defp genus_nodes(rows, url_prefix, key_style) do
    rows
    |> group_ordered(& &1.genus_id)
    |> Enum.map(fn [first | _] = genus_rows ->
      %{
        key: format_key("genus", "g", first.genus_id, key_style),
        label: format_label(first.genus_name, first.genus_description),
        name: first.genus_name,
        rank: "genus",
        description: format_description(first.genus_description),
        url: Map.get(first, :genus_url) || rank_path(:genus, first.genus_name),
        nodes: leaf_nodes(genus_rows, url_prefix, key_style)
      }
    end)
  end

  defp leaf_nodes(rows, url_prefix, key_style) do
    rows
    |> Enum.uniq_by(& &1.leaf_id)
    |> Enum.map(fn row ->
      %{
        key: format_key("species", "s", row.leaf_id, key_style),
        label: row.leaf_name,
        url: "#{url_prefix}#{row.leaf_id}",
        genus_placeholder: Map.get(row, :leaf_genus_placeholder, false)
      }
    end)
  end

  @doc """
  The public page of a taxon of `rank` named `name`: `/family/<name>`,
  `/genus/<name>`, `/section/<name>`, or `/<rank>/<name>` for the ranks
  between family and genus; nil for other ranks (a plant's page is by ID).
  """
  @spec rank_path(Gallformers.Taxa.Rank.t(), String.t()) :: String.t() | nil
  def rank_path(rank, name)
      when rank in [:family, :subfamily, :tribe, :subtribe, :genus, :section],
      do: "/#{rank}/#{URI.encode(name)}"

  def rank_path(_rank, _name), do: nil

  # Groups by `key_fun`, groups and their rows in first-seen order.
  defp group_ordered(rows, key_fun) do
    {groups, order} =
      Enum.reduce(rows, {%{}, []}, fn row, {groups, order} ->
        key = key_fun.(row)

        if Map.has_key?(groups, key),
          do: {Map.update!(groups, key, &[row | &1]), order},
          else: {Map.put(groups, key, [row]), [key | order]}
      end)

    order |> Enum.reverse() |> Enum.map(&Enum.reverse(Map.fetch!(groups, &1)))
  end

  defp format_key(long, _short, id, :long), do: "#{long}-#{id}"
  defp format_key(_long, short, id, :short), do: "#{short}-#{id}"

  defp format_label(name, description) do
    case format_description(description) do
      nil -> name
      description -> "#{name} (#{description})"
    end
  end

  defp format_description(nil), do: nil
  defp format_description(""), do: nil
  defp format_description(description), do: description
end
