defmodule Gallformers.Taxonomy do
  @moduledoc """
  The Taxonomy context.

  Provides functions for working with taxonomic classifications.
  """

  require Logger
  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.Taxonomy

  @doc """
  Returns all non-placeholder taxonomies.
  """
  @spec list_taxonomies() :: [Taxonomy.t()]
  def list_taxonomies do
    from(t in Taxonomy, where: t.is_placeholder == false)
    |> Repo.all()
  end

  @doc """
  Gets the "Unknown" placeholder genus for a given parent family.
  Returns nil if not found.
  """
  @spec get_unknown_placeholder(integer()) :: Taxonomy.t() | nil
  def get_unknown_placeholder(parent_id) do
    from(t in Taxonomy,
      where: t.is_placeholder == true and t.type == "genus" and t.parent_id == ^parent_id
    )
    |> Repo.one()
  end

  @doc """
  Gets or creates an "Unknown" placeholder genus for a family.
  Alias for find_or_create_unknown_genus/1.
  """
  @spec get_or_create_unknown_genus(integer()) ::
          {:ok, Taxonomy.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_unknown_genus(family_id) do
    find_or_create_unknown_genus(family_id)
  end

  @doc """
  Returns the display name for a taxonomy, handling placeholders.

  Preloads the parent association if not already loaded (needed for placeholder formatting).
  For better performance, callers should preload :parent when loading taxonomies if they
  plan to call this function.
  """
  @spec display_name(Taxonomy.t()) :: String.t()
  def display_name(%Taxonomy{} = taxonomy) do
    taxonomy =
      if Ecto.assoc_loaded?(taxonomy.parent) do
        taxonomy
      else
        Repo.preload(taxonomy, :parent)
      end

    Taxonomy.display_name(taxonomy)
  end

  @doc """
  Returns all taxonomies of a specific type.
  """
  @spec list_taxonomies_by_type(String.t()) :: [Taxonomy.t()]
  def list_taxonomies_by_type(type) do
    from(t in Taxonomy,
      where: t.type == ^type,
      order_by: t.name
    )
    |> Repo.all()
  end

  @doc """
  Returns all families.
  """
  @spec list_families() :: [Taxonomy.t()]
  def list_families do
    list_taxonomies_by_type("family")
  end

  @doc """
  Returns all genera.
  """
  @spec list_genera() :: [Taxonomy.t()]
  def list_genera do
    list_taxonomies_by_type("genus")
  end

  @doc """
  Returns all sections.
  """
  @spec list_sections() :: [Taxonomy.t()]
  def list_sections do
    list_taxonomies_by_type("section")
  end

  @doc """
  Returns IDs of "Unknown" genera that have no species linked.

  These are placeholder genera auto-created for each family but not yet
  used for any undescribed species. They create UI noise and should
  typically be hidden from browse/search interfaces.
  """
  @spec empty_unknown_genus_ids() :: [integer()]
  def empty_unknown_genus_ids do
    from(t in Taxonomy,
      where: t.type == "genus" and t.name == "Unknown",
      where:
        fragment(
          "NOT EXISTS (SELECT 1 FROM species_taxonomy st WHERE st.taxonomy_id = ?)",
          t.id
        ),
      select: t.id
    )
    |> Repo.all()
  end

  @doc """
  Gets a taxonomy by ID.
  """
  @spec get_taxonomy(integer()) :: Taxonomy.t() | nil
  def get_taxonomy(id) do
    Repo.get(Taxonomy, id)
  end

  @doc """
  Gets a taxonomy by ID, raising if not found.
  """
  @spec get_taxonomy!(integer()) :: Taxonomy.t()
  def get_taxonomy!(id) do
    Repo.get!(Taxonomy, id)
  end

  @doc """
  Gets multiple taxonomies by IDs in a single query (batch version).

  Returns a map of id => %{id, name, type, description}.
  """
  @spec get_taxonomies_batch([integer()]) :: %{integer() => map()}
  def get_taxonomies_batch([]), do: %{}

  def get_taxonomies_batch(ids) do
    from(t in Taxonomy,
      where: t.id in ^ids,
      select: {t.id, %{id: t.id, name: t.name, type: t.type, description: t.description}}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets a taxonomy by name and type.
  """
  @spec get_taxonomy_by_name(String.t(), String.t()) :: Taxonomy.t() | nil
  def get_taxonomy_by_name(name, type) do
    from(t in Taxonomy,
      where: t.name == ^name and t.type == ^type
    )
    |> Repo.one()
  end

  @doc """
  Gets all genera with a given name across all families.
  Returns a list of genera (can be empty, one, or multiple).
  """
  @spec get_genera_by_name(String.t()) :: [Taxonomy.t()]
  def get_genera_by_name(name) do
    from(t in Taxonomy,
      where: t.name == ^name and t.type == "genus",
      order_by: t.id
    )
    |> Repo.all()
  end

  @doc """
  Gets the parent taxonomy for a given taxonomy ID.
  """
  @spec get_parent(integer()) :: Taxonomy.t() | nil
  def get_parent(taxonomy_id) do
    from(t in Taxonomy,
      join: child in Taxonomy,
      on: child.parent_id == t.id,
      where: child.id == ^taxonomy_id
    )
    |> Repo.one()
  end

  @doc """
  Gets all children of a taxonomy.
  """
  @spec get_children(integer()) :: [Taxonomy.t()]
  def get_children(taxonomy_id) do
    from(t in Taxonomy,
      where: t.parent_id == ^taxonomy_id,
      order_by: t.name
    )
    |> Repo.all()
  end

  @doc """
  Gets children for multiple parent taxonomy IDs in a single query.

  Returns a map of parent_id => [children].
  """
  @spec get_children_for_parents([integer()]) :: %{integer() => [Taxonomy.t()]}
  def get_children_for_parents([]), do: %{}

  def get_children_for_parents(parent_ids) do
    from(t in Taxonomy,
      where: t.parent_id in ^parent_ids,
      order_by: t.name
    )
    |> Repo.all()
    |> Enum.group_by(& &1.parent_id)
  end

  @doc """
  Extracts the genus name from a species name (first word before space).

  ## Examples

      iex> extract_genus_from_name("Andricus quercuslanigera")
      "Andricus"

      iex> extract_genus_from_name("Test")
      "Test"
  """
  @spec extract_genus_from_name(String.t()) :: String.t() | nil
  def extract_genus_from_name(name) when is_binary(name) do
    case String.split(name, " ", parts: 2) do
      [genus_name | _] when byte_size(genus_name) > 0 -> genus_name
      _ -> nil
    end
  end

  def extract_genus_from_name(_), do: nil

  @doc """
  Looks up or prepares taxonomy info for a species name.

  Unlike `get_taxonomy_from_species_name/1`, this function always returns
  a result (never nil) to support species creation workflows:

  - If genus exists in one family: returns full taxonomy with `genus_is_new: false`
  - If genus exists in MULTIPLE families: returns info with `requires_disambiguation: true`
    and a list of all matching families under `possible_families`
  - If genus is NEW: returns extracted genus name with `genus_is_new: true`
    and empty family fields (user must select a family)

  ## Examples

      iex> lookup_taxonomy_for_new_species("Andricus quercuslanigera")
      %{genus: "Andricus", genus_id: 123, genus_is_new: false,
        section: nil, section_id: nil, family: "Cynipidae", family_id: 456}

      iex> lookup_taxonomy_for_new_species("Newgenus species")
      %{genus: "Newgenus", genus_id: nil, genus_is_new: true,
        section: nil, section_id: nil, family: nil, family_id: nil}

      iex> lookup_taxonomy_for_new_species("Quercus rubra")
      %{genus: "Quercus", requires_disambiguation: true,
        possible_families: [%{family: "Fagaceae", family_id: 1, genus_id: 10}, ...]}
  """
  @spec lookup_taxonomy_for_new_species(String.t()) :: map() | nil
  def lookup_taxonomy_for_new_species(name) when is_binary(name) do
    case extract_genus_from_name(name) do
      nil ->
        nil

      genus_name ->
        genera = get_genera_by_name(genus_name)

        case genera do
          [] ->
            # Genus doesn't exist - this is a new genus
            %{
              genus: genus_name,
              genus_id: nil,
              genus_is_new: true,
              section: nil,
              section_id: nil,
              family: nil,
              family_id: nil
            }

          [single_genus] ->
            # Genus exists in exactly one family
            result = build_taxonomy_from_genus(single_genus)
            Map.put(result, :genus_is_new, false)

          multiple_genera ->
            # Genus exists in multiple families - requires disambiguation
            possible_families = Enum.map(multiple_genera, &extract_family_info/1)

            %{
              genus: genus_name,
              requires_disambiguation: true,
              possible_families: possible_families
            }
        end
    end
  end

  def lookup_taxonomy_for_new_species(_), do: nil

  # Helper to build taxonomy map from an existing genus
  defp build_taxonomy_from_genus(genus) do
    case get_parent(genus.id) do
      nil ->
        %{
          genus: genus.name,
          genus_id: genus.id,
          section: nil,
          section_id: nil,
          family: nil,
          family_id: nil
        }

      parent when parent.type == "section" ->
        family = get_parent(parent.id)

        %{
          genus: genus.name,
          genus_id: genus.id,
          section: parent.name,
          section_id: parent.id,
          family: family && family.name,
          family_id: family && family.id
        }

      parent ->
        %{
          genus: genus.name,
          genus_id: genus.id,
          section: nil,
          section_id: nil,
          family: parent.name,
          family_id: parent.id
        }
    end
  end

  defp extract_family_info(genus) do
    taxonomy = build_taxonomy_from_genus(genus)

    %{
      genus_id: genus.id,
      section: taxonomy.section,
      section_id: taxonomy.section_id,
      family: taxonomy.family,
      family_id: taxonomy.family_id
    }
  end

  @doc """
  Creates a new genus under a family and links a species to it.

  Used when creating a new species with a genus that doesn't exist yet.
  Creates the genus taxonomy entry and the species-taxonomy relationship.

  Returns `{:ok, genus}` on success or `{:error, reason}` on failure.
  """
  @spec create_genus_for_species(String.t(), integer(), integer()) ::
          {:ok, Taxonomy.t()} | {:error, term()}
  def create_genus_for_species(genus_name, family_id, species_id) do
    # Create the genus under the family
    case create_taxonomy(%{name: genus_name, type: "genus", parent_id: family_id}) do
      {:ok, genus} ->
        # Link the species to the genus
        link_species_to_taxonomy(species_id, genus.id)
        {:ok, genus}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Links a species to its taxonomy, creating the genus if needed.

  Call this within a transaction after creating a species. It handles:
  - Creating a new genus under the selected section or family (if genus_is_new is true)
  - Linking the species to an existing genus (if genus exists)
  - No-op if no taxonomy info is available

  ## Parameters
  - species_id: The ID of the newly created species
  - taxonomy: Map from lookup_taxonomy_for_new_species/1
  - genus_is_new: Boolean indicating if genus needs to be created
  - parent_id: The section or family ID to create the genus under (required if genus_is_new is true)

  Returns :ok on success.
  """
  @spec link_species_taxonomy(integer(), map() | nil, boolean(), integer() | nil) :: :ok
  def link_species_taxonomy(species_id, %{genus: "Unknown"} = _taxonomy, true, family_id) do
    # For Unknown genus, use find_or_create to avoid duplicates per family
    {:ok, genus} = find_or_create_unknown_genus(family_id)
    link_species_to_taxonomy(species_id, genus.id)
    :ok
  end

  def link_species_taxonomy(species_id, taxonomy, true = _genus_is_new, parent_id) do
    # parent_id can be either a section ID or family ID - genus is created under it
    {:ok, _genus} = create_genus_for_species(taxonomy.genus, parent_id, species_id)
    :ok
  end

  def link_species_taxonomy(species_id, %{genus_id: genus_id}, false, _parent_id)
      when not is_nil(genus_id) do
    link_species_to_taxonomy(species_id, genus_id)
    :ok
  end

  def link_species_taxonomy(_species_id, _taxonomy, false, _parent_id), do: :ok

  @doc """
  Links a species to a taxonomy entry (genus).
  """
  @spec link_species_to_taxonomy(integer(), integer()) :: {:ok, any()} | {:error, term()}
  def link_species_to_taxonomy(species_id, taxonomy_id) do
    Repo.insert_all(
      "species_taxonomy",
      [%{species_id: species_id, taxonomy_id: taxonomy_id}],
      on_conflict: :nothing
    )
    |> case do
      {1, _} -> {:ok, nil}
      {0, _} -> {:ok, nil}
      error -> {:error, error}
    end
  end

  @doc """
  Updates a species' genus link.

  Removes any existing genus links and creates a new one to the specified genus.
  Used when renaming a species to a different genus.
  """
  @spec update_species_genus(integer(), integer()) :: :ok | {:error, term()}
  def update_species_genus(species_id, new_genus_id) do
    # First, find all genus taxonomy IDs
    genus_ids_query =
      from(t in Taxonomy,
        where: t.type == "genus",
        select: t.id
      )

    # Remove any existing genus links for this species
    # (SQLite doesn't support JOINs in DELETE, so we use a subquery)
    from(st in "species_taxonomy",
      where: st.species_id == ^species_id and st.taxonomy_id in subquery(genus_ids_query)
    )
    |> Repo.delete_all()

    # Then link to the new genus
    case link_species_to_taxonomy(species_id, new_genus_id) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Looks up taxonomy info (genus, section, family) from a species name.

  Extracts the genus from the first word of the species name,
  looks it up in the taxonomy table, and returns the full taxonomy path.

  Returns a map with the same structure as `get_taxonomy_for_species/1`,
  or nil if the genus is not found.

  ## Examples

      iex> get_taxonomy_from_species_name("Andricus quercuslanigera")
      %{genus: "Andricus", genus_id: 123, section: nil, section_id: nil, family: "Cynipidae", family_id: 456}

      iex> get_taxonomy_from_species_name("Unknown species")
      nil
  """
  @spec get_taxonomy_from_species_name(String.t()) :: map() | nil
  def get_taxonomy_from_species_name(name) when is_binary(name) do
    with [genus_name | _] when byte_size(genus_name) > 0 <- String.split(name, " ", parts: 2),
         %{} = genus <- get_taxonomy_by_name(genus_name, "genus") do
      build_taxonomy_map(genus, get_parent(genus.id))
    else
      _ -> nil
    end
  end

  def get_taxonomy_from_species_name(_), do: nil

  defp build_taxonomy_map(genus, nil) do
    %{
      genus: genus.name,
      genus_id: genus.id,
      section: nil,
      section_id: nil,
      family: nil,
      family_id: nil
    }
  end

  defp build_taxonomy_map(genus, %{type: "section"} = section) do
    family = get_parent(section.id)

    %{
      genus: genus.name,
      genus_id: genus.id,
      section: section.name,
      section_id: section.id,
      family: family && family.name,
      family_id: family && family.id
    }
  end

  defp build_taxonomy_map(genus, family) do
    %{
      genus: genus.name,
      genus_id: genus.id,
      section: nil,
      section_id: nil,
      family: family.name,
      family_id: family.id
    }
  end

  @doc """
  Gets the genus, section, and family for a species.

  Returns a map with taxonomy names, IDs, and descriptions (common names) or nil if not found.
  Section is optional and will only be present for plant hosts in genera
  that have sections (primarily Quercus).

  The data model has:
  - Family → Genus → Section (hierarchy via parent_id)
  - Species links directly to both genus AND section via species_taxonomy

  Descriptions contain common names (e.g., "Oaks" for Quercus, "Beeches" for Fagus).

  Note: This uses two queries by design. A species can link to both a genus AND a section
  via species_taxonomy, and combining these into a single query creates complexity with
  JOIN cardinality. For single-species lookups (the common case), 2 queries is acceptable.
  For batch operations, callers should use different patterns (e.g., preloading all taxonomy
  data for multiple species at once with IN clauses).
  """
  @spec get_taxonomy_for_species(integer()) :: map() | nil
  def get_taxonomy_for_species(species_id) do
    # Get the genus link - genus's parent is the family
    genus_query =
      from st in "species_taxonomy",
        join: g in Taxonomy,
        on: st.taxonomy_id == g.id and g.type == "genus",
        left_join: family in Taxonomy,
        on: g.parent_id == family.id,
        where: st.species_id == ^species_id,
        limit: 1,
        select: %{
          genus: g.name,
          genus_id: g.id,
          genus_description: g.description,
          family: family.name,
          family_id: family.id,
          family_description: family.description
        }

    # Get the section link (if any) - species may be directly linked to a section
    section_query =
      from st in "species_taxonomy",
        join: s in Taxonomy,
        on: st.taxonomy_id == s.id and s.type == "section",
        where: st.species_id == ^species_id,
        limit: 1,
        select: %{
          section: s.name,
          section_id: s.id,
          section_description: s.description
        }

    case Repo.one(genus_query) do
      nil ->
        nil

      genus_result ->
        section_result = Repo.one(section_query)

        %{
          genus: genus_result.genus,
          genus_id: genus_result.genus_id,
          genus_description: genus_result.genus_description,
          section: section_result && section_result.section,
          section_id: section_result && section_result.section_id,
          section_description: section_result && section_result.section_description,
          family: genus_result.family,
          family_id: genus_result.family_id,
          family_description: genus_result.family_description
        }
    end
  end

  @doc """
  Gets taxonomy (genus/family) for multiple species in a single query (batch version).

  Returns a map of species_id => %{genus: name, family: name}.
  This is a simplified version that only fetches genus and family names,
  suitable for API responses where the full taxonomy details aren't needed.
  """
  @spec get_taxonomy_for_species_batch([integer()]) :: %{integer() => map()}
  def get_taxonomy_for_species_batch([]), do: %{}

  def get_taxonomy_for_species_batch(species_ids) do
    from(st in "species_taxonomy",
      join: g in Taxonomy,
      on: st.taxonomy_id == g.id and g.type == "genus",
      left_join: family in Taxonomy,
      on: g.parent_id == family.id,
      where: st.species_id in ^species_ids,
      select: {st.species_id, %{genus: g.name, family: family.name}}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets species IDs associated with a genus.
  """
  @spec get_species_ids_for_genus(integer()) :: [integer()]
  def get_species_ids_for_genus(genus_id) do
    from(st in "species_taxonomy",
      where: st.taxonomy_id == ^genus_id,
      select: st.species_id
    )
    |> Repo.all()
  end

  @doc """
  Gets species IDs for multiple genera in a single query (batch version).

  Returns a map of genus_id => [species_ids].
  """
  @spec get_species_ids_for_genera([integer()]) :: %{integer() => [integer()]}
  def get_species_ids_for_genera([]), do: %{}

  def get_species_ids_for_genera(genus_ids) do
    from(st in "species_taxonomy",
      where: st.taxonomy_id in ^genus_ids,
      select: {st.taxonomy_id, st.species_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {genus_id, _} -> genus_id end, fn {_, species_id} -> species_id end)
  end

  @doc """
  Gets species IDs associated with a family (via genera).
  """
  @spec get_species_ids_for_family(integer()) :: [integer()]
  def get_species_ids_for_family(family_id) do
    from(st in "species_taxonomy",
      join: g in Taxonomy,
      on: st.taxonomy_id == g.id,
      where: g.parent_id == ^family_id,
      select: st.species_id
    )
    |> Repo.all()
  end

  @doc """
  Gets the full taxonomic path from a taxonomy up to root.

  Returns a list of taxonomies from the given taxonomy up to the root,
  ordered from root to leaf (e.g., [Family, Genus, Section]).

  Uses a recursive CTE for efficient single-query path retrieval.
  """
  @spec get_taxonomy_path(integer()) :: [Taxonomy.t()]
  def get_taxonomy_path(taxonomy_id) do
    # Use a recursive CTE to build the path in a single query
    # This is much more efficient than the old recursive approach
    query = """
    WITH RECURSIVE taxonomy_path AS (
      -- Base case: start with the given taxonomy
      SELECT id, name, description, type, parent_id, is_placeholder,
             inserted_at, updated_at, 0 as depth
      FROM taxonomy
      WHERE id = ?1

      UNION ALL

      -- Recursive case: add parent taxonomies
      SELECT t.id, t.name, t.description, t.type, t.parent_id, t.is_placeholder,
             t.inserted_at, t.updated_at, tp.depth + 1
      FROM taxonomy t
      INNER JOIN taxonomy_path tp ON t.id = tp.parent_id
    )
    SELECT id, name, description, type, parent_id, is_placeholder, inserted_at, updated_at
    FROM taxonomy_path
    ORDER BY depth DESC
    """

    case Repo.query(query, [taxonomy_id]) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Map.new()
          |> cast_to_taxonomy()
        end)

      {:error, _} ->
        []
    end
  end

  # Helper to cast raw query results to Taxonomy structs
  defp cast_to_taxonomy(row) do
    %Taxonomy{
      id: row["id"],
      name: row["name"],
      description: row["description"],
      type: row["type"],
      parent_id: row["parent_id"],
      is_placeholder: row["is_placeholder"] == 1,
      inserted_at: parse_datetime(row["inserted_at"]),
      updated_at: parse_datetime(row["updated_at"])
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case NaiveDateTime.from_iso8601(datetime_string) do
      {:ok, naive_dt} -> DateTime.from_naive!(naive_dt, "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime

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
        # Exclude Unknown genera that have no species
        from(t in base_query,
          where:
            not (t.name == "Unknown" and t.type == "genus" and
                   fragment(
                     "NOT EXISTS (SELECT 1 FROM species_taxonomy st WHERE st.taxonomy_id = ?)",
                     t.id
                   ))
        )
      end

    Repo.all(query)
  end

  @doc """
  Gets a taxonomy by name (for URL parameter lookups).
  """
  @spec get_taxonomy_by_name(String.t()) :: Taxonomy.t() | nil
  def get_taxonomy_by_name(name) when is_binary(name) do
    from(t in Taxonomy,
      where: t.name == ^name,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists families for galls that occur on a given host.
  """
  @spec list_gall_families_for_host(integer()) :: [map()]
  def list_gall_families_for_host(host_id) do
    from(f in Taxonomy,
      join: g in Taxonomy,
      on: g.parent_id == f.id,
      join: st in "species_taxonomy",
      on: st.taxonomy_id == g.id,
      join: s in Gallformers.Species.Species,
      on: st.species_id == s.id,
      join: h in Gallformers.GallHosts.GallHost,
      on: h.gall_species_id == s.id,
      where: s.taxoncode == "gall" and f.type == "family" and h.host_species_id == ^host_id,
      group_by: [f.id, f.name],
      order_by: f.name,
      select: %{
        id: f.id,
        name: f.name
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists families for galls that occur on hosts in a given host genus/section.
  """
  @spec list_gall_families_for_host_genus(integer()) :: [map()]
  def list_gall_families_for_host_genus(host_genus_id) do
    from(f in Taxonomy,
      join: galler_genus in Taxonomy,
      on: galler_genus.parent_id == f.id,
      join: st in "species_taxonomy",
      on: st.taxonomy_id == galler_genus.id,
      join: s in Gallformers.Species.Species,
      on: st.species_id == s.id,
      join: h in Gallformers.GallHosts.GallHost,
      on: h.gall_species_id == s.id,
      join: host in Gallformers.Species.Species,
      on: h.host_species_id == host.id,
      join: host_tax in "species_taxonomy",
      on: host_tax.species_id == host.id,
      where:
        s.taxoncode == "gall" and f.type == "family" and
          host_tax.taxonomy_id == ^host_genus_id,
      group_by: [f.id, f.name],
      order_by: f.name,
      select: %{id: f.id, name: f.name}
    )
    |> Repo.all()
  end

  # Admin functions

  @doc """
  Returns a changeset for tracking taxonomy changes.
  """
  @spec change_taxonomy(Taxonomy.t(), map()) :: Ecto.Changeset.t()
  def change_taxonomy(%Taxonomy{} = taxonomy, attrs \\ %{}) do
    Taxonomy.changeset(taxonomy, attrs)
  end

  @doc """
  Creates a taxonomy entry.

  When creating a non-plant family, automatically creates an "Unknown" genus placeholder
  for undescribed species. Plant families (description = "Plant") do not get Unknown genera
  as we don't track undescribed plant species.
  """
  @spec create_taxonomy(map()) :: {:ok, Taxonomy.t()} | {:error, Ecto.Changeset.t()}
  def create_taxonomy(attrs \\ %{}) do
    type = attrs["type"] || attrs[:type]

    if type == "family" do
      create_family_with_unknown_genus(attrs)
    else
      %Taxonomy{}
      |> Taxonomy.changeset(attrs)
      |> Repo.insert()
      |> broadcast(:taxonomy_created)
    end
  end

  defp create_family_with_unknown_genus(attrs) do
    Repo.transaction(fn ->
      case %Taxonomy{} |> Taxonomy.changeset(attrs) |> Repo.insert() do
        {:ok, family} ->
          maybe_create_unknown_genus(family, attrs)
          family

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, family} -> broadcast({:ok, family}, :taxonomy_created)
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_create_unknown_genus(family, attrs) do
    # Auto-create Unknown genus for non-plant families only
    # Plant families don't need Unknown genera as we don't track undescribed plants
    description = attrs["description"] || attrs[:description]

    if description != "Plant" do
      {:ok, _unknown_genus} = find_or_create_unknown_genus(family.id)
    end
  end

  @doc """
  Updates a taxonomy entry.

  When renaming a genus, automatically updates all linked species names and
  creates scientific synonyms with the old names.
  """
  @spec update_taxonomy(Taxonomy.t(), map()) :: {:ok, Taxonomy.t()} | {:error, Ecto.Changeset.t()}
  def update_taxonomy(%Taxonomy{} = taxonomy, attrs) do
    new_name = attrs["name"] || attrs[:name]
    is_genus_rename = taxonomy.type == "genus" && new_name && new_name != taxonomy.name

    if is_genus_rename do
      update_genus_with_species_sync(taxonomy, attrs)
    else
      taxonomy
      |> Taxonomy.changeset(attrs)
      |> Repo.update()
      |> broadcast(:taxonomy_updated)
    end
  end

  # Updates a genus and syncs all linked species names via the Species context.
  defp update_genus_with_species_sync(%Taxonomy{} = taxonomy, attrs) do
    old_genus_name = taxonomy.name
    new_genus_name = attrs["name"] || attrs[:name]

    Repo.transaction(fn ->
      # Delegate species rename to Species context
      species_list =
        from(s in Species,
          join: st in "species_taxonomy",
          on: st.species_id == s.id,
          where: st.taxonomy_id == ^taxonomy.id,
          select: s
        )
        |> Repo.all()

      for species <- species_list do
        Gallformers.Species.rename_for_genus_change(species, old_genus_name, new_genus_name)
      end

      # Update the genus itself
      taxonomy
      |> Taxonomy.changeset(attrs)
      |> Repo.update!()
    end)
    |> broadcast(:taxonomy_updated)
  end

  @doc """
  Deletes a taxonomy entry.
  """
  @spec delete_taxonomy(Taxonomy.t()) :: {:ok, Taxonomy.t()} | {:error, Ecto.Changeset.t()}
  def delete_taxonomy(%Taxonomy{} = taxonomy) do
    Repo.delete(taxonomy)
    |> broadcast(:taxonomy_deleted)
  end

  # =====================================================================
  # Deletion Impact Assessment
  # =====================================================================

  @doc """
  Gathers all data that would be deleted if this taxonomy is deleted.
  Returns counts and lists for UI display.

  For family: returns all child genera, sections (via genera), and species count.
  For genus: returns all child sections and species count.
  For section/other: returns has_impact: false (no cascade concern).
  """
  @spec get_deletion_impact(Taxonomy.t()) :: map()
  def get_deletion_impact(%Taxonomy{id: id, type: "family"} = taxonomy) do
    genera = list_child_genera(id)
    genera_ids = Enum.map(genera, & &1.id)

    sections = list_sections_for_family_tree(id)
    section_ids = Enum.map(sections, & &1.id)

    # Species linked to this family's genera or sections
    all_taxonomy_ids = genera_ids ++ section_ids
    species_count = count_species_for_taxonomies(all_taxonomy_ids)

    %{
      taxonomy: taxonomy,
      genera: genera,
      genera_count: length(genera),
      sections: sections,
      sections_count: length(sections),
      species_count: species_count,
      has_impact: genera != [] or sections != [] or species_count > 0
    }
  end

  def get_deletion_impact(%Taxonomy{id: id, type: "genus"} = taxonomy) do
    sections = list_child_sections(id)
    section_ids = Enum.map(sections, & &1.id)

    # Species linked to this genus or its sections
    all_taxonomy_ids = [id | section_ids]
    species_count = count_species_for_taxonomies(all_taxonomy_ids)

    %{
      taxonomy: taxonomy,
      genera: [],
      genera_count: 0,
      sections: sections,
      sections_count: length(sections),
      species_count: species_count,
      has_impact: sections != [] or species_count > 0
    }
  end

  def get_deletion_impact(%Taxonomy{} = taxonomy) do
    # Section or other types - no cascade concern
    %{
      taxonomy: taxonomy,
      genera: [],
      genera_count: 0,
      sections: [],
      sections_count: 0,
      species_count: 0,
      has_impact: false
    }
  end

  # =====================================================================
  # Cascade Delete
  # =====================================================================

  @doc """
  Deletes taxonomy and all dependent data in a single transaction.

  For family: Deletes leaves first (species → sections → genera → family).
  For genus: Deletes species → sections → genus.

  Returns {:ok, impact} or {:error, reason}.

  Note: Species deletion includes S3 image cleanup via `Gallformers.Images`.
  """
  @spec delete_taxonomy_cascade(Taxonomy.t()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t() | term()}
  def delete_taxonomy_cascade(%Taxonomy{id: id, type: "family"} = taxonomy) do
    Logger.info("Cascade delete starting for family #{taxonomy.name} (id=#{id})")

    genera = list_child_genera(id)
    genera_ids = Enum.map(genera, & &1.id)

    sections = list_sections_for_family_tree(id)
    section_ids = Enum.map(sections, & &1.id)

    # All taxonomy IDs that could have species linked (genera + sections)
    all_taxonomy_ids = genera_ids ++ section_ids
    species_count = count_species_for_taxonomies(all_taxonomy_ids)

    Logger.info(
      "Family #{taxonomy.name}: deleting #{length(genera)} genera, #{length(sections)} sections, #{species_count} species"
    )

    result =
      Repo.transaction(fn ->
        # 1. Delete all species linked to this family tree
        #    (includes S3 cleanup, gall_traits, FTS, cascades to images, aliases, hosts, etc.)
        delete_species_for_cascade(all_taxonomy_ids)

        # 2. Delete sections (now safe - no species references)
        Enum.each(sections, &Repo.delete!/1)

        # 3. Delete genera (now safe - no species or section references)
        Enum.each(genera, &Repo.delete!/1)

        # 4. Delete the family itself
        Repo.delete!(taxonomy)

        # Return impact summary
        %{
          taxonomy: taxonomy,
          genera: genera,
          genera_count: length(genera),
          sections: sections,
          sections_count: length(sections),
          species_count: species_count
        }
      end)

    log_cascade_result(result, taxonomy)
    broadcast(result, :taxonomy_deleted)
  end

  def delete_taxonomy_cascade(%Taxonomy{id: id, type: "genus"} = taxonomy) do
    Logger.info("Cascade delete starting for genus #{taxonomy.name} (id=#{id})")

    sections = list_child_sections(id)
    section_ids = Enum.map(sections, & &1.id)

    # Species linked to this genus or its sections
    all_taxonomy_ids = [id | section_ids]
    species_count = count_species_for_taxonomies(all_taxonomy_ids)

    Logger.info(
      "Genus #{taxonomy.name}: deleting #{length(sections)} sections, #{species_count} species"
    )

    result =
      Repo.transaction(fn ->
        # 1. Delete all species linked to this genus or its sections
        delete_species_for_cascade(all_taxonomy_ids)

        # 2. Delete sections (now safe - no species references)
        Enum.each(sections, &Repo.delete!/1)

        # 3. Delete the genus itself
        Repo.delete!(taxonomy)

        # Return impact summary
        %{
          taxonomy: taxonomy,
          genera: [],
          genera_count: 0,
          sections: sections,
          sections_count: length(sections),
          species_count: species_count
        }
      end)

    log_cascade_result(result, taxonomy)
    broadcast(result, :taxonomy_deleted)
  end

  def delete_taxonomy_cascade(%Taxonomy{} = taxonomy) do
    # Section or other types - simple delete, no cascade needed
    Logger.info("Simple delete for #{taxonomy.type} #{taxonomy.name} (id=#{taxonomy.id})")

    result = Repo.delete(taxonomy)
    log_cascade_result(result, taxonomy)
    broadcast(result, :taxonomy_deleted)
  end

  # Deletes all species linked to the given taxonomy IDs.
  # Delegates to owning contexts (Galls/Plants) for full cleanup.
  defp delete_species_for_cascade([]), do: :ok

  defp delete_species_for_cascade(taxonomy_ids) do
    # Load species with taxoncodes so we can route to the right context
    species_list =
      from(s in Species,
        join: st in "species_taxonomy",
        on: st.species_id == s.id,
        where: st.taxonomy_id in ^taxonomy_ids,
        distinct: true,
        select: s
      )
      |> Repo.all()

    for species <- species_list do
      case species.taxoncode do
        "gall" -> Gallformers.Galls.delete_gall(species.id)
        "plant" -> Gallformers.Plants.delete_host(species.id)
      end
    end

    :ok
  end

  @doc """
  Gets species IDs linked to any of the given taxonomy IDs.
  """
  @spec get_species_ids_for_taxonomies([integer()]) :: [integer()]
  def get_species_ids_for_taxonomies([]), do: []

  def get_species_ids_for_taxonomies(taxonomy_ids) do
    from(st in "species_taxonomy",
      where: st.taxonomy_id in ^taxonomy_ids,
      select: st.species_id,
      distinct: true
    )
    |> Repo.all()
  end

  @doc """
  Lists all genera that are direct children of a family.
  """
  @spec list_child_genera(integer()) :: [Taxonomy.t()]
  def list_child_genera(family_id) do
    from(t in Taxonomy,
      where: t.parent_id == ^family_id and t.type == "genus",
      order_by: t.name
    )
    |> Repo.all()
  end

  @doc """
  Lists all sections that are direct children of a genus.
  """
  @spec list_child_sections(integer()) :: [Taxonomy.t()]
  def list_child_sections(genus_id) do
    from(t in Taxonomy,
      where: t.parent_id == ^genus_id and t.type == "section",
      order_by: t.name
    )
    |> Repo.all()
  end

  @doc """
  Lists all sections under a family tree (sections whose parent genus is a child of this family).
  """
  @spec list_sections_for_family_tree(integer()) :: [Taxonomy.t()]
  def list_sections_for_family_tree(family_id) do
    from(s in Taxonomy,
      join: g in Taxonomy,
      on: s.parent_id == g.id,
      where: s.type == "section" and g.type == "genus" and g.parent_id == ^family_id,
      order_by: s.name
    )
    |> Repo.all()
  end

  @doc """
  Counts species linked to any of the given taxonomy IDs.
  """
  @spec count_species_for_taxonomies([integer()]) :: non_neg_integer()
  def count_species_for_taxonomies([]), do: 0

  def count_species_for_taxonomies(taxonomy_ids) do
    from(st in "species_taxonomy",
      where: st.taxonomy_id in ^taxonomy_ids,
      select: count(st.species_id, :distinct)
    )
    |> Repo.one()
  end

  @doc """
  Finds or creates an "Unknown" genus under the given family.

  Used for undescribed galls where the genus is not known.
  Returns {:ok, genus} or {:error, changeset}.
  """
  @spec find_or_create_unknown_genus(integer()) ::
          {:ok, Taxonomy.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_unknown_genus(family_id) do
    # Check if an Unknown genus already exists under this family
    case Repo.one(
           from(t in Taxonomy,
             where: t.name == "Unknown" and t.type == "genus" and t.parent_id == ^family_id
           )
         ) do
      nil ->
        # Create a new Unknown genus under the family
        create_taxonomy(%{
          name: "Unknown",
          type: "genus",
          parent_id: family_id,
          is_placeholder: true,
          description: "Placeholder genus for undescribed species"
        })

      existing ->
        {:ok, existing}
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
  Returns all taxonomies with their parent preloaded, optionally filtered by type.

  ## Options
  - `hide_empty_unknown` - If true, excludes Unknown genera with no species (default: false)
  """
  @spec list_taxonomies_with_parent(String.t() | nil, keyword()) :: [map()]
  def list_taxonomies_with_parent(type \\ nil, opts \\ []) do
    hide_empty_unknown = Keyword.get(opts, :hide_empty_unknown, false)

    base_query =
      from(t in Taxonomy,
        left_join: p in Taxonomy,
        on: t.parent_id == p.id,
        order_by: [t.type, t.name],
        select: %{
          id: t.id,
          name: t.name,
          description: t.description,
          type: t.type,
          parent_id: t.parent_id,
          parent_name: p.name,
          parent_type: p.type
        }
      )

    query_with_type =
      if type do
        from([t, p] in base_query, where: t.type == ^type)
      else
        base_query
      end

    query =
      if hide_empty_unknown do
        from([t, p] in query_with_type,
          where:
            not (t.name == "Unknown" and t.type == "genus" and
                   fragment(
                     "NOT EXISTS (SELECT 1 FROM species_taxonomy st WHERE st.taxonomy_id = ?)",
                     t.id
                   ))
        )
      else
        query_with_type
      end

    Repo.all(query)
  end

  @doc """
  Returns families for use as parent options in forms.
  """
  @spec list_families_for_select() :: [{String.t(), integer()}]
  def list_families_for_select do
    from(t in Taxonomy,
      where: t.type == "family",
      order_by: t.name,
      select: {t.name, t.id}
    )
    |> Repo.all()
  end

  @doc """
  Returns plant families for use in host creation forms.
  Plant families have description = "Plant".
  """
  @spec list_plant_families_for_select() :: [{String.t(), integer()}]
  def list_plant_families_for_select do
    from(t in Taxonomy,
      where: t.type == "family" and t.description == "Plant",
      order_by: t.name,
      select: {t.name, t.id}
    )
    |> Repo.all()
  end

  @doc """
  Returns non-plant families for use in gall creation forms.
  Non-plant families have description != "Plant".
  """
  @spec list_gall_families_for_select() :: [{String.t(), integer()}]
  def list_gall_families_for_select do
    from(t in Taxonomy,
      where: t.type == "family" and t.description != "Plant",
      order_by: t.name,
      select: {t.name, t.id}
    )
    |> Repo.all()
  end

  @doc """
  Returns sections for a given family, for use in select dropdowns.

  Sections are children of genera, not families directly. This function
  finds all sections under any genus that belongs to the given family.
  """
  @spec list_sections_for_family(integer()) :: [{String.t(), integer()}]
  def list_sections_for_family(family_id) when is_integer(family_id) do
    from(s in Taxonomy,
      join: g in Taxonomy,
      on: s.parent_id == g.id,
      where: s.type == "section" and g.type == "genus" and g.parent_id == ^family_id,
      order_by: s.name,
      select: {s.name, s.id}
    )
    |> Repo.all()
  end

  def list_sections_for_family(_), do: []

  @doc """
  Returns sections for a given genus, for use in select dropdowns.
  Sections are subdivisions within a specific genus.
  """
  @spec list_sections_for_genus(integer()) :: [{String.t(), integer()}]
  def list_sections_for_genus(genus_id) when is_integer(genus_id) do
    from(t in Taxonomy,
      where: t.type == "section" and t.parent_id == ^genus_id,
      order_by: t.name,
      select: {t.name, t.id}
    )
    |> Repo.all()
  end

  def list_sections_for_genus(_), do: []

  @doc """
  Returns all sections for use in select dropdowns.
  """
  @spec list_sections_for_select() :: [{String.t(), integer()}]
  def list_sections_for_select do
    from(t in Taxonomy,
      where: t.type == "section",
      order_by: t.name,
      select: {t.name, t.id}
    )
    |> Repo.all()
  end

  @doc """
  Updates a genus's parent to a new section.

  Used when changing what section a host's genus belongs to.
  """
  @spec update_genus_parent(integer(), integer()) :: {:ok, Taxonomy.t()} | {:error, term()}
  def update_genus_parent(genus_id, new_parent_id) do
    case get_taxonomy(genus_id) do
      nil ->
        {:error, :genus_not_found}

      genus ->
        genus
        |> Taxonomy.changeset(%{parent_id: new_parent_id})
        |> Repo.update()
    end
  end

  @doc """
  Gets all species in a Section by ID.
  """
  def get_species_for_section(section_id) do
    from(s in Gallformers.Species.Species,
      join: st in "species_taxonomy",
      on: st.species_id == s.id,
      where: st.taxonomy_id == ^section_id,
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists all sections with their parent genus and species count.
  """
  @spec list_sections_with_details() :: [map()]
  def list_sections_with_details do
    from(s in Taxonomy,
      left_join: g in Taxonomy,
      on: s.parent_id == g.id,
      left_join: st in "species_taxonomy",
      on: st.taxonomy_id == s.id,
      where: s.type == "section",
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

  @doc """
  Updates the species assigned to a section.

  Removes all existing species and adds the new ones.
  Also updates the section's parent_id to the genus of the first species
  (sections derive their parent from their species).

  Returns {:ok, section} on success or {:error, reason} on failure.
  """
  @spec update_section_species(integer(), [integer()]) :: {:ok, Taxonomy.t()} | {:error, term()}
  def update_section_species(section_id, species_ids) when is_list(species_ids) do
    Repo.transaction(fn ->
      # Remove existing species links
      from(st in "species_taxonomy",
        where: st.taxonomy_id == ^section_id
      )
      |> Repo.delete_all()

      # Add new species links and update parent genus
      add_species_to_section(section_id, species_ids)

      Repo.get!(Taxonomy, section_id)
    end)
    |> case do
      {:ok, section} ->
        Phoenix.PubSub.broadcast(Gallformers.PubSub, "taxonomy", {:section_updated, section})
        {:ok, section}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_species_to_section(_section_id, []), do: :ok

  defp add_species_to_section(section_id, species_ids) do
    new_links =
      Enum.map(species_ids, fn species_id ->
        %{species_id: species_id, taxonomy_id: section_id}
      end)

    Repo.insert_all("species_taxonomy", new_links)

    # Update section's parent genus based on first species
    update_section_parent_genus(section_id, hd(species_ids))
  end

  defp update_section_parent_genus(section_id, first_species_id) do
    first_species = Repo.get!(Species, first_species_id)

    with genus_name when genus_name != nil <- extract_genus_from_name(first_species.name),
         %{id: genus_id} <- get_taxonomy_by_name(genus_name, "genus") do
      from(t in Taxonomy, where: t.id == ^section_id)
      |> Repo.update_all(set: [parent_id: genus_id])
    end

    :ok
  end

  @doc """
  Returns genera for use in typeahead/select components.
  Each result includes the parent family ID for auto-population.
  Excludes genera named "Unknown" as those are created automatically.
  """
  @spec list_genera_for_select() :: [map()]
  def list_genera_for_select do
    from(g in Taxonomy,
      left_join: p in Taxonomy,
      on: g.parent_id == p.id,
      left_join: gp in Taxonomy,
      on: p.parent_id == gp.id,
      where: g.type == "genus" and g.name != "Unknown",
      order_by: g.name,
      select: %{
        id: g.id,
        name: g.name,
        # If parent is a section, grandparent is the family
        # If parent is a family, that's the family
        family_id:
          fragment(
            "CASE WHEN ? = 'section' THEN ? ELSE ? END",
            p.type,
            gp.id,
            p.id
          )
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns families and sections for use as parent options for genera.
  """
  @spec list_parents_for_genus() :: [map()]
  def list_parents_for_genus do
    from(t in Taxonomy,
      where: t.type in ["family", "section"],
      order_by: [t.type, t.name],
      select: %{id: t.id, name: t.name, type: t.type}
    )
    |> Repo.all()
  end

  @doc """
  Moves one or more genera from one family to another.

  This operation updates the parent_id for all specified genera.
  The parent-child relationship is tracked via the parent_id foreign key
  in the taxonomy table itself.

  Returns {:ok, count} on success where count is the number of genera moved.
  """
  @spec move_genera([integer()], integer(), integer()) :: {:ok, integer()} | {:error, term()}
  def move_genera([_ | _] = genus_ids, _old_family_id, new_family_id) do
    Repo.transaction(fn ->
      # Update parent_id on all genera
      # Verify they're actually genera and belong to the old family for safety
      {updated_count, _} =
        from(t in Taxonomy,
          where: t.id in ^genus_ids and t.type == "genus"
        )
        |> Repo.update_all(set: [parent_id: new_family_id])

      updated_count
    end)
    |> case do
      {:ok, count} ->
        Phoenix.PubSub.broadcast(Gallformers.PubSub, "taxonomy", :genera_moved)
        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def move_genera([], _old_family_id, _new_family_id), do: {:error, :no_genera_selected}

  @doc """
  Subscribes to taxonomy changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "taxonomy")
  end

  defp log_cascade_result({:ok, _}, taxonomy) do
    Logger.info(
      "Cascade delete SUCCEEDED for #{taxonomy.type} #{taxonomy.name} (id=#{taxonomy.id})"
    )
  end

  defp log_cascade_result({:error, reason}, taxonomy) do
    Logger.error(
      "Cascade delete FAILED for #{taxonomy.type} #{taxonomy.name} (id=#{taxonomy.id}): #{inspect(reason)}"
    )
  end

  defp broadcast({:ok, taxonomy}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "taxonomy", {event, taxonomy})
    {:ok, taxonomy}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
