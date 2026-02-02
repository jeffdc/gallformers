defmodule Gallformers.Explore do
  @moduledoc """
  The Explore context.

  Provides functions for building hierarchical tree data for browsing
  galls and hosts by taxonomic family.
  """

  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Species.{GallTraits, Species}
  alias Gallformers.Taxonomy.Taxonomy

  @type key_style :: :short | :long

  @doc """
  Returns a hierarchical tree of gall species organized by Family → Genus → Species.

  Each node has:
  - key: unique identifier (string)
  - label: display text
  - url: navigation URL
  - nodes: child nodes (for families and genera)

  ## Options
  - `:key_style` - `:short` for `f-123` format (default), `:long` for `family-123` format
  """
  @spec get_galls_tree(keyword()) :: [map()]
  def get_galls_tree(opts \\ []) do
    get_species_tree("gall", false, opts)
  end

  @doc """
  Returns a hierarchical tree of undescribed gall species.

  ## Options
  - `:key_style` - `:short` for `f-123` format (default), `:long` for `family-123` format
  """
  @spec get_undescribed_tree(keyword()) :: [map()]
  def get_undescribed_tree(opts \\ []) do
    get_species_tree("gall", true, opts)
  end

  @doc """
  Returns a hierarchical tree of host species organized by Family → Genus → Species.

  ## Options
  - `:key_style` - `:short` for `f-123` format (default), `:long` for `family-123` format
  """
  @spec get_hosts_tree(keyword()) :: [map()]
  def get_hosts_tree(opts \\ []) do
    get_species_tree("plant", false, opts)
  end

  defp get_species_tree(taxoncode, undescribed_only, opts) do
    rows = fetch_tree_data(taxoncode, undescribed_only)
    build_tree(rows, taxoncode, opts)
  end

  defp fetch_tree_data("gall", undescribed_only) do
    base_query =
      from f in Taxonomy,
        join: g in Taxonomy,
        on: g.parent_id == f.id and g.type == "genus",
        join: st in "species_taxonomy",
        on: st.taxonomy_id == g.id,
        join: s in Species,
        on: s.id == st.species_id,
        join: gt in GallTraits,
        on: gt.species_id == s.id,
        where: f.type == "family" and f.description != "Plant" and s.taxoncode == "gall",
        order_by: [f.name, g.name, s.name],
        select: %{
          family_id: f.id,
          family_name: f.name,
          family_description: f.description,
          genus_id: g.id,
          genus_name: g.name,
          genus_description: g.description,
          species_id: s.id,
          species_name: s.name,
          undescribed: gt.undescribed
        }

    query =
      if undescribed_only do
        from [f, g, st, s, gt] in base_query,
          where: gt.undescribed == true
      else
        base_query
      end

    Repo.all(query)
  end

  defp fetch_tree_data("plant", _undescribed_only) do
    from(f in Taxonomy,
      join: g in Taxonomy,
      on: g.parent_id == f.id and g.type == "genus",
      join: st in "species_taxonomy",
      on: st.taxonomy_id == g.id,
      join: s in Species,
      on: s.id == st.species_id,
      where: f.type == "family" and f.description == "Plant" and s.taxoncode == "plant",
      order_by: [f.name, g.name, s.name],
      select: %{
        family_id: f.id,
        family_name: f.name,
        family_description: f.description,
        genus_id: g.id,
        genus_name: g.name,
        genus_description: g.description,
        species_id: s.id,
        species_name: s.name,
        undescribed: false
      }
    )
    |> Repo.all()
  end

  defp build_tree(rows, taxoncode, opts) do
    url_prefix = if taxoncode == "plant", do: "/host/", else: "/gall/"
    key_style = Keyword.get(opts, :key_style, :short)

    # Group by family, then genus, then species
    # Using maps to track unique entries and maintain order
    families_map = %{}
    families_order = []

    {families_map, families_order} =
      Enum.reduce(rows, {families_map, families_order}, fn row, {fam_map, fam_order} ->
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

        # Update genera within family
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

        # Update species within genus
        genus = Map.get(genera_map, genus_key)
        species_key = row.species_id

        {species_map, species_order} =
          if Map.has_key?(genus.species, species_key) do
            {genus.species, genus.species_order}
          else
            species_entry = %{
              id: row.species_id,
              name: row.species_name
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

    # Convert to tree nodes
    Enum.map(families_order, fn family_key ->
      family = Map.get(families_map, family_key)
      genus_nodes = build_genus_nodes(family, url_prefix, key_style)

      %{
        key: format_key("family", "f", family.id, key_style),
        label: format_label(family.name, family.description),
        url: "/family/#{family.id}",
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
        url: "/genus/#{genus.id}",
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
        url: "#{url_prefix}#{species.id}"
      }
    end)
  end

  defp format_key(long, _short, id, :long), do: "#{long}-#{id}"
  defp format_key(_long, short, id, :short), do: "#{short}-#{id}"

  defp format_label(name, nil), do: name
  defp format_label(name, ""), do: name
  defp format_label(name, "Plant"), do: name
  defp format_label(name, description), do: "#{name} (#{description})"
end
