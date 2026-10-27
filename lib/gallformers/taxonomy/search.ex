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
        where: ilike(f.name, ^name_pattern),
        order_by: f.name,
        limit: ^limit,
        select: %{id: f.id, name: f.name}
      )

    if taxoncode do
      search_families_by_taxoncode(query, taxoncode, limit)
    else
      Repo.all(base)
    end
  end

  defp search_families_by_taxoncode(query, taxoncode, limit) do
    name_pattern = "#{String.downcase(query)}%"

    # The description filter mirrors list_families_for_select/1:
    # gall → description != 'Plant', plant → description = 'Plant'.
    desc_filter =
      if taxoncode == "plant",
        do: "f.description = 'Plant'",
        else: "f.description != 'Plant'"

    sql = """
    WITH RECURSIVE family_descendants AS (
      SELECT f.id, f.id as family_id, f.name as family_name, f.type
      FROM taxonomy f
      WHERE f.type = 'family' AND f.name ILIKE $1::text

      UNION ALL

      SELECT t.id, fd.family_id, fd.family_name, t.type
      FROM taxonomy t
      JOIN family_descendants fd ON t.parent_id = fd.id
    ),
    -- Families that already have species with the matching taxoncode
    by_species AS (
      SELECT DISTINCT fd.family_id as id, fd.family_name as name
      FROM family_descendants fd
      JOIN species_taxonomy st ON st.taxonomy_id = fd.id AND fd.type = 'genus'
      JOIN species s ON st.species_id = s.id AND s.taxoncode = $2::text
    ),
    -- Families whose description matches the taxoncode (catches new families with no species)
    by_description AS (
      SELECT f.id, f.name
      FROM taxonomy f
      WHERE f.type = 'family' AND f.name ILIKE $1::text AND #{desc_filter}
    )
    SELECT id, name FROM by_species
    UNION
    SELECT id, name FROM by_description
    ORDER BY name
    LIMIT $3::integer
    """

    case Repo.query(sql, [name_pattern, taxoncode, limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name] -> %{id: id, name: name} end)

      {:error, _} ->
        []
    end
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

    # Build parameterized query — params are numbered $1, $2, etc.
    # $1 = name_pattern, $2 = limit, then optional $3 for taxoncode, $4 for family_id
    {taxoncode_filter, taxoncode_params, next_param} =
      if taxoncode do
        {"""
         AND (
           EXISTS (
             SELECT 1 FROM species_taxonomy st
             JOIN species s ON st.species_id = s.id AND s.taxoncode = $3::text
             WHERE st.taxonomy_id = g.id
           )
           OR NOT EXISTS (
             SELECT 1 FROM species_taxonomy st2
             WHERE st2.taxonomy_id = g.id
           )
         )
         """, [taxoncode], 4}
      else
        {"", [], 3}
      end

    {family_filter, family_params} =
      if family_id do
        {"AND ancestors.family_id = $#{next_param}::bigint", [family_id]}
      else
        {"", []}
      end

    sql = """
    WITH RECURSIVE genus_ancestors AS (
      SELECT g.id as genus_id, g.id as current_id, g.parent_id as current_parent_id, g.type as current_type
      FROM taxonomy g
      WHERE g.type = 'genus' AND g.name ILIKE $1::text
      #{taxoncode_filter}

      UNION ALL

      SELECT ga.genus_id, t.id, t.parent_id, t.type
      FROM taxonomy t
      JOIN genus_ancestors ga ON t.id = ga.current_parent_id
      WHERE ga.current_type != 'family'
    ),
    ancestors AS (
      SELECT ga.genus_id, ga.current_id as family_id
      FROM genus_ancestors ga
      WHERE ga.current_type = 'family'
    )
    SELECT g.id, g.name, f.name as family_name, f.id as family_id, g.is_placeholder
    FROM taxonomy g
    LEFT JOIN ancestors ON ancestors.genus_id = g.id
    LEFT JOIN taxonomy f ON f.id = ancestors.family_id
    WHERE g.type = 'genus' AND g.name ILIKE $1::text
    #{taxoncode_filter}
    #{family_filter}
    ORDER BY g.name
    LIMIT $2::integer
    """

    params = [name_pattern, limit] ++ taxoncode_params ++ family_params

    case Repo.query(sql, params) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, family_name, fam_id, is_placeholder] ->
          %{
            id: id,
            name: name,
            family_name: family_name,
            family_id: fam_id,
            is_placeholder: is_placeholder == true
          }
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Searches taxonomies by name (case-insensitive).
  """
  @spec search_taxonomies(String.t(), String.t() | nil, integer()) :: [Taxonomy.t()]
  def search_taxonomies(query, type \\ nil, limit \\ 50) do
    search_pattern = "%#{String.downcase(query)}%"

    base_query =
      from(t in Taxonomy,
        where: ilike(t.name, ^search_pattern),
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
      where: ilike(s.name, ^search_pattern),
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
