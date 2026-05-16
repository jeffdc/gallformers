defmodule Gallformers.Taxonomy.TreeBuilder do
  @moduledoc """
  Builds hierarchical tree structures from flat taxonomy query rows.

  Takes flat rows with family/genus/species data and produces a
  Family → Genus → Species tree for browse/explore UIs.
  """

  @type key_style :: :short | :long

  @doc """
  Builds a hierarchical tree from flat query rows.

  Each row must have: family_id, family_name, family_description,
  genus_id, genus_name, genus_description, species_id, species_name.

  ## Parameters
  - `rows` - flat query results
  - `url_prefix` - species URL prefix (e.g., "/gall/" or "/host/")
  - `opts` - keyword list with `:key_style` (`:short` or `:long`, default `:short`)
  """
  @spec build_tree([map()], String.t(), keyword()) :: [map()]
  def build_tree(rows, url_prefix, opts \\ []) do
    key_style = Keyword.get(opts, :key_style, :short)

    {families_map, families_order} =
      Enum.reduce(rows, {%{}, []}, fn row, {fam_map, fam_order} ->
        family_key = row.family_id

        {fam_map, fam_order} =
          if Map.has_key?(fam_map, family_key) do
            {fam_map, fam_order}
          else
            family_entry = %{
              id: row.family_id,
              name: row.family_name,
              description: row.family_description,
              genera: %{},
              genera_order: []
            }

            {Map.put(fam_map, family_key, family_entry), fam_order ++ [family_key]}
          end

        family = Map.get(fam_map, family_key)
        genus_key = row.genus_id

        {genera_map, genera_order} =
          if Map.has_key?(family.genera, genus_key) do
            {family.genera, family.genera_order}
          else
            genus_entry = %{
              id: row.genus_id,
              name: row.genus_name,
              description: row.genus_description,
              species: %{},
              species_order: []
            }

            {Map.put(family.genera, genus_key, genus_entry), family.genera_order ++ [genus_key]}
          end

        genus = Map.get(genera_map, genus_key)
        species_key = row.species_id

        {species_map, species_order} =
          if Map.has_key?(genus.species, species_key) do
            {genus.species, genus.species_order}
          else
            species_entry = %{
              id: row.species_id,
              name: row.species_name,
              genus_placeholder: Map.get(row, :species_genus_placeholder, false)
            }

            {Map.put(genus.species, species_key, species_entry),
             genus.species_order ++ [species_key]}
          end

        genus = %{genus | species: species_map, species_order: species_order}
        genera_map = Map.put(genera_map, genus_key, genus)
        family = %{family | genera: genera_map, genera_order: genera_order}
        fam_map = Map.put(fam_map, family_key, family)

        {fam_map, fam_order}
      end)

    Enum.map(families_order, fn family_key ->
      family = Map.get(families_map, family_key)
      genus_nodes = build_genus_nodes(family, url_prefix, key_style)

      %{
        key: format_key("family", "f", family.id, key_style),
        label: format_label(family.name, family.description),
        name: family.name,
        rank: "family",
        description: format_description(family.description),
        url: "/family/#{family.name}",
        nodes: genus_nodes
      }
    end)
  end

  defp build_genus_nodes(family, url_prefix, key_style) do
    Enum.map(family.genera_order, fn genus_key ->
      genus = Map.get(family.genera, genus_key)
      species_nodes = build_species_nodes(genus, url_prefix, key_style)

      %{
        key: format_key("genus", "g", genus.id, key_style),
        label: format_label(genus.name, genus.description),
        name: genus.name,
        rank: "genus",
        description: format_description(genus.description),
        url: "/genus/#{genus.name}",
        nodes: species_nodes
      }
    end)
  end

  defp build_species_nodes(genus, url_prefix, key_style) do
    Enum.map(genus.species_order, fn species_key ->
      species = Map.get(genus.species, species_key)

      %{
        key: format_key("species", "s", species.id, key_style),
        label: species.name,
        url: "#{url_prefix}#{species.id}",
        genus_placeholder: Map.get(species, :genus_placeholder, false)
      }
    end)
  end

  defp format_key(long, _short, id, :long), do: "#{long}-#{id}"
  defp format_key(_long, short, id, :short), do: "#{short}-#{id}"

  defp format_label(name, nil), do: name
  defp format_label(name, ""), do: name
  defp format_label(name, "Plant"), do: name
  defp format_label(name, description), do: "#{name} (#{description})"

  defp format_description(nil), do: nil
  defp format_description(""), do: nil
  defp format_description("Plant"), do: nil
  defp format_description(description), do: description
end
