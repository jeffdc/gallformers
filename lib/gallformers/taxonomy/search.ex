defmodule Gallformers.Taxonomy.Search do
  @moduledoc """
  Search and typeahead queries for taxonomy data.
  """

  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Taxonomy.Taxonomy

  @doc """
  Searches families by name prefix (case-insensitive).

  Used by the reclassify modal family typeahead.
  Returns maps with id and name.

  ## Options

    * `:taxoncode` - when set (e.g. `"gall"` or `"plant"`), only returns
      families that contain genera with at least one species of that taxoncode.
  """
  @spec search_families(String.t(), keyword()) :: [map()]
  def search_families(query, opts \\ []) do
    name_pattern = "#{String.downcase(query)}%"
    taxoncode = Keyword.get(opts, :taxoncode)
    limit = Keyword.get(opts, :limit, 20)

    base =
      from(f in Taxonomy,
        where: f.type == "family",
        where: fragment("lower(?) LIKE ?", f.name, ^name_pattern),
        order_by: f.name,
        limit: ^limit,
        select: %{id: f.id, name: f.name}
      )

    base =
      if taxoncode do
        from(f in base,
          join: g in Taxonomy,
          on: g.parent_id == f.id and g.type == "genus",
          join: st in "species_taxonomy",
          on: st.taxonomy_id == g.id,
          join: s in Gallformers.Species.Species,
          on: st.species_id == s.id,
          where: s.taxoncode == ^taxoncode,
          distinct: true
        )
      else
        base
      end

    Repo.all(base)
  end

  @doc """
  Searches genera by name, returning genus with parent family info.

  Used by the reclassify modal typeahead. When `family_id` is provided,
  constrains results to genera within that family.

  ## Options

    * `:taxoncode` - when set (e.g. `"gall"` or `"plant"`), only returns
      genera that have at least one species of that taxoncode.
  """
  @spec search_genera(String.t(), integer() | nil, keyword()) :: [map()]
  def search_genera(query, family_id \\ nil, opts \\ []) do
    name_pattern = "#{String.downcase(query)}%"
    taxoncode = Keyword.get(opts, :taxoncode)
    limit = Keyword.get(opts, :limit, 20)

    base =
      from(g in Taxonomy,
        left_join: f in Taxonomy,
        on: g.parent_id == f.id,
        where: g.type == "genus",
        where: fragment("lower(?) LIKE ?", g.name, ^name_pattern),
        order_by: g.name,
        limit: ^limit,
        select: %{
          id: g.id,
          name: g.name,
          family_name: f.name,
          family_id: f.id,
          is_placeholder: g.is_placeholder
        }
      )

    base =
      if family_id do
        from([g, f] in base, where: g.parent_id == ^family_id)
      else
        base
      end

    base =
      if taxoncode do
        from([g, ...] in base,
          join: st in "species_taxonomy",
          on: st.taxonomy_id == g.id,
          join: s in Gallformers.Species.Species,
          on: st.species_id == s.id,
          where: s.taxoncode == ^taxoncode,
          distinct: true
        )
      else
        base
      end

    Repo.all(base)
  end

  @doc """
  Searches for genera and sections by name or common name (case-insensitive).

  Matches scientific names by prefix and common names (description field)
  by substring. Used for typeahead/autocomplete functionality in the ID tool.
  Returns up to `limit` results ordered by name.

  By default, filters out empty Unknown genera (placeholder genera with
  no species). Pass `include_empty_unknown: true` to include them.
  """
  @spec search_genera_and_sections(String.t(), integer(), keyword()) :: [map()]
  def search_genera_and_sections(query, limit \\ 20, opts \\ []) when is_binary(query) do
    name_pattern = "#{String.downcase(query)}%"
    description_pattern = "%#{String.downcase(query)}%"
    include_empty_unknown = Keyword.get(opts, :include_empty_unknown, false)
    taxoncode = Keyword.get(opts, :taxoncode)

    base_query =
      from(t in Taxonomy,
        where: t.type in ["genus", "section"],
        where:
          fragment("lower(?) LIKE ?", t.name, ^name_pattern) or
            fragment("lower(?) LIKE ?", t.description, ^description_pattern),
        order_by: [t.type, t.name],
        limit: ^limit,
        select: %{
          id: t.id,
          name: t.name,
          type: t.type,
          description: t.description
        }
      )

    # Filter by taxoncode if specified
    base_query =
      if taxoncode do
        from(t in base_query,
          join: st in "species_taxonomy",
          on: st.taxonomy_id == t.id,
          join: s in Gallformers.Species.Species,
          on: st.species_id == s.id,
          where: s.taxoncode == ^taxoncode,
          distinct: true
        )
      else
        base_query
      end

    query =
      if include_empty_unknown do
        base_query
      else
        # Exclude placeholder genera that have no species
        from(t in base_query,
          where:
            not (t.is_placeholder == true and t.type == "genus" and
                   fragment(
                     "NOT EXISTS (SELECT 1 FROM species_taxonomy st WHERE st.taxonomy_id = ?)",
                     t.id
                   ))
        )
      end

    Repo.all(query)
  end

  @doc """
  Searches taxonomies by name (case-insensitive).
  """
  @spec search_taxonomies(String.t(), String.t() | nil, integer()) :: [Taxonomy.t()]
  def search_taxonomies(query, type \\ nil, limit \\ 50) do
    search_pattern = "%#{String.downcase(query)}%"

    base_query =
      from(t in Taxonomy,
        where: fragment("lower(?) LIKE ?", t.name, ^search_pattern),
        order_by: t.name,
        limit: ^limit
      )

    query_with_type =
      if type do
        from(t in base_query, where: t.type == ^type)
      else
        base_query
      end

    Repo.all(query_with_type)
  end

  @doc """
  Searches sections by name (case-insensitive).
  """
  @spec search_sections(String.t()) :: [map()]
  def search_sections(query) do
    search_pattern = "%#{String.downcase(query)}%"

    from(s in Taxonomy,
      left_join: g in Taxonomy,
      on: s.parent_id == g.id,
      left_join: st in "species_taxonomy",
      on: st.taxonomy_id == s.id,
      where: s.type == "section",
      where: fragment("lower(?) LIKE ?", s.name, ^search_pattern),
      group_by: [s.id, s.name, s.description, g.id, g.name],
      order_by: [g.name, s.name],
      select: %{
        id: s.id,
        name: s.name,
        description: s.description,
        genus_id: g.id,
        genus_name: g.name,
        species_count: count(st.species_id)
      }
    )
    |> Repo.all()
  end
end
