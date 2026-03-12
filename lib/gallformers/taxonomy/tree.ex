defmodule Gallformers.Taxonomy.Tree do
  @moduledoc """
  Tree CRUD and hierarchy query functions for the taxonomy system.

  Handles creating, reading, updating, and deleting taxonomy entries,
  querying the taxonomy hierarchy, and managing placeholder genera.
  """

  require Logger
  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.{Family, Lineage, Section, TaxonName, Taxonomy}

  # =====================================================================
  # CRUD
  # =====================================================================

  @doc """
  Returns a changeset for tracking taxonomy changes.
  """
  @spec change_taxonomy(Taxonomy.t(), map()) :: Ecto.Changeset.t()
  def change_taxonomy(%Taxonomy{} = taxonomy, attrs \\ %{}) do
    Taxonomy.changeset(taxonomy, attrs)
  end

  @doc """
  Checks if a taxonomy entry with the given name and parent already exists.

  Excludes the given `exclude_id` (for edit mode, so a record doesn't conflict with itself).
  Returns true if a duplicate exists.
  """
  @spec name_parent_exists?(String.t(), integer() | nil, integer() | nil) :: boolean()
  def name_parent_exists?(name, parent_id, exclude_id \\ nil) do
    query =
      from(t in Taxonomy,
        where: t.name == ^name and t.is_placeholder == false
      )

    query =
      if is_nil(parent_id) do
        from(t in query, where: is_nil(t.parent_id))
      else
        from(t in query, where: t.parent_id == ^parent_id)
      end

    query =
      if exclude_id do
        from(t in query, where: t.id != ^exclude_id)
      else
        query
      end

    Repo.exists?(query)
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
  Creates an intermediate taxonomy node and re-parents selected children under it.

  Requires at least one child to be selected. Atomically creates the intermediate
  and updates children's parent_id in a transaction.

  Attrs must include: name, rank, parent_id, children_ids (list of integer IDs).
  """
  @spec create_intermediate(map()) :: {:ok, Taxonomy.t()} | {:error, term()}
  def create_intermediate(attrs) do
    children_ids = attrs[:children_ids] || attrs["children_ids"] || []

    if children_ids == [] do
      {:error, :no_children_selected}
    else
      attrs
      |> do_create_intermediate(children_ids)
      |> case do
        {:ok, intermediate} -> broadcast({:ok, intermediate}, :taxonomy_created)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp do_create_intermediate(attrs, children_ids) do
    intermediate_attrs = prepare_intermediate_attrs(attrs)

    Repo.transaction(fn ->
      case %Taxonomy{} |> Taxonomy.changeset(intermediate_attrs) |> Repo.insert() do
        {:ok, intermediate} ->
          reparent_children!(children_ids, intermediate.id)
          intermediate

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp prepare_intermediate_attrs(attrs) do
    attrs
    |> Map.drop([:children_ids, "children_ids"])
    |> then(fn a ->
      if Map.has_key?(a, :name),
        do: Map.put_new(a, :type, "intermediate"),
        else: Map.put_new(a, "type", "intermediate")
    end)
  end

  defp reparent_children!(children_ids, parent_id) do
    {count, _} =
      from(t in Taxonomy, where: t.id in ^children_ids)
      |> Repo.update_all(set: [parent_id: parent_id])

    if count == 0, do: Repo.rollback(:no_children_updated)
  end

  @doc """
  Updates a taxonomy entry.

  When renaming a genus, automatically updates all linked species names and
  creates scientific synonyms with the old names.
  """
  @spec update_taxonomy(Taxonomy.t(), map()) ::
          {:ok, Taxonomy.t()}
          | {:error, Ecto.Changeset.t() | {:rename_collision, String.t(), atom()}}
  def update_taxonomy(%Taxonomy{} = taxonomy, attrs) do
    new_name = attr_value(attrs, "name")
    new_type = attr_value(attrs, "type") || taxonomy.type
    type_changing? = new_type != taxonomy.type

    genus_rename? =
      taxonomy.type == "genus" && !type_changing? && new_name && new_name != taxonomy.name

    cond do
      type_changing? && has_linked_species?(taxonomy.id) ->
        {:error,
         taxonomy
         |> Taxonomy.changeset(attrs)
         |> Ecto.Changeset.add_error(:type, "cannot change type when species are linked")}

      genus_rename? ->
        update_genus_with_species_sync(taxonomy, attrs)

      true ->
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
        case Gallformers.Species.rename_for_genus_change(
               species,
               old_genus_name,
               new_genus_name
             ) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback({:rename_collision, species.name, reason})
        end
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
  # Lookups
  # =====================================================================

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
  Returns a `%Family{}` domain struct for the given taxonomy ID, or nil.
  """
  @spec get_family(integer()) :: Family.t() | nil
  def get_family(id) do
    case Repo.get(Taxonomy, id) do
      %Taxonomy{type: "family"} = t ->
        %Family{id: t.id, name: t.name, description: t.description}

      _ ->
        nil
    end
  end

  @doc """
  Returns a `%Lineage{}` for a genus, including its parent family.
  """
  @spec get_genus_lineage(integer()) :: {:ok, Lineage.t()} | {:error, :not_found}
  def get_genus_lineage(id) do
    case Repo.get(Taxonomy, id) do
      %Taxonomy{type: "genus"} ->
        path = get_taxonomy_path(id)
        {:ok, Lineage.from_path(path)}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns a `%Lineage{}` for a section, including its parent genus and grandparent family.
  """
  @spec get_section_lineage(integer()) :: {:ok, Lineage.t()} | {:error, :not_found}
  def get_section_lineage(id) do
    case Repo.get(Taxonomy, id) do
      %Taxonomy{type: "section", parent_id: genus_id} = section when not is_nil(genus_id) ->
        # Get the full path from the genus up to the root (includes intermediates)
        genus_path = get_taxonomy_path(genus_id)
        lineage = Lineage.from_path(genus_path)

        section_struct = %Section{
          id: section.id,
          name: section.name,
          description: section.description
        }

        {:ok, %{lineage | section: section_struct}}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets a taxonomy by name and type.
  """
  @spec get_taxonomy_by_name(String.t(), String.t()) :: Taxonomy.t() | nil
  def get_taxonomy_by_name(name, type) do
    from(t in Taxonomy,
      where: t.name == ^name and t.type == ^type,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Finds the first taxonomy matching a name (for URL parameter lookups).
  """
  @spec find_taxonomy_by_name(String.t()) :: Taxonomy.t() | nil
  def find_taxonomy_by_name(name) when is_binary(name) do
    from(t in Taxonomy,
      where: t.name == ^name,
      limit: 1
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
  Gets multiple taxonomies by IDs in a single query (batch version).

  Returns a map of id => Taxonomy struct.
  """
  @spec get_taxonomies_batch([integer()]) :: %{integer() => Taxonomy.t()}
  def get_taxonomies_batch([]), do: %{}

  def get_taxonomies_batch(ids) do
    from(t in Taxonomy, where: t.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  Resolves taxonomy from a species name by parsing the genus portion.

  Handles two patterns:
  - "Unknown (Family) ..." — finds or creates the Unknown genus under that family
  - "Genus ..." — looks up the genus by name

  Returns `{:ok, taxonomy_map}` or `{:error, reason}`.
  """
  @spec resolve_taxonomy_from_name(String.t()) :: {:ok, Lineage.t()} | {:error, String.t()}
  def resolve_taxonomy_from_name(name) do
    case parse_genus_from_name(name) do
      {"Unknown", family_name} -> resolve_unknown_genus(family_name)
      {genus_name, nil} -> resolve_known_genus(genus_name)
      nil -> {:error, "Could not parse genus from name: #{name}"}
    end
  end

  defp parse_genus_from_name(name) do
    parsed = TaxonName.parse(name)

    cond do
      parsed.genus == "" -> nil
      parsed.unknown? -> {"Unknown", parsed.family}
      true -> {parsed.genus, nil}
    end
  end

  defp resolve_unknown_genus(family_name) do
    case get_family_by_name(family_name) do
      nil ->
        {:error, "Family '#{family_name}' not found"}

      family ->
        {:ok, genus} = find_or_create_unknown_genus(family.id)
        lineage = build_taxonomy_from_genus(genus)
        # Display the genus as "Unknown (Family)" to match species name convention
        display_name = "Unknown (#{family_name})"
        genus_struct = %{lineage.genus | name: display_name}
        {:ok, %{lineage | genus: genus_struct}}
    end
  end

  defp resolve_known_genus(genus_name) do
    case get_genera_by_name(genus_name) do
      [] ->
        {:error, "Genus '#{genus_name}' not found"}

      [genus] ->
        {:ok, build_taxonomy_from_genus(genus)}

      _multiple ->
        {:error, "Multiple genera named '#{genus_name}' — use the full form to disambiguate"}
    end
  end

  defp get_family_by_name(name) do
    from(t in Taxonomy, where: t.name == ^name and t.type == "family")
    |> Repo.one()
  end

  @doc false
  @spec build_taxonomy_from_genus(Taxonomy.t()) :: Lineage.t()
  def build_taxonomy_from_genus(%Taxonomy{id: id}) do
    path = get_taxonomy_path(id)
    Lineage.from_path(path)
  end

  # =====================================================================
  # Hierarchy
  # =====================================================================

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
  Gets the full taxonomic path from a taxonomy up to root.

  Returns a list of taxonomies from the given taxonomy up to the root,
  ordered from root to leaf (e.g., [Family, Genus, Section]).

  Uses a recursive CTE for efficient single-query path retrieval.
  """
  @spec get_taxonomy_path(integer()) :: [Taxonomy.t()]
  def get_taxonomy_path(taxonomy_id) do
    query = """
    WITH RECURSIVE taxonomy_path AS (
      -- Base case: start with the given taxonomy
      SELECT id, name, description, type, rank, parent_id, is_placeholder,
             inserted_at, updated_at, 0 as depth
      FROM taxonomy
      WHERE id = $1::bigint

      UNION ALL

      -- Recursive case: add parent taxonomies
      SELECT t.id, t.name, t.description, t.type, t.rank, t.parent_id, t.is_placeholder,
             t.inserted_at, t.updated_at, tp.depth + 1
      FROM taxonomy t
      INNER JOIN taxonomy_path tp ON t.id = tp.parent_id
    )
    SELECT id, name, description, type, rank, parent_id, is_placeholder, inserted_at, updated_at
    FROM taxonomy_path
    ORDER BY depth DESC
    """

    case Repo.query(query, [taxonomy_id]) do
      {:ok, %{rows: rows, columns: columns}} ->
        atom_columns = Enum.map(columns, &String.to_existing_atom/1)
        Enum.map(rows, &load_taxonomy_row(atom_columns, &1))

      {:error, _} ->
        []
    end
  end

  defp load_taxonomy_row(columns, row) do
    columns
    |> Enum.zip(row)
    |> Map.new()
    |> then(&Repo.load(Taxonomy, &1))
  end

  @doc """
  Returns parent options for the taxonomy form typeahead, with full ancestry paths.

  Each option is a map with `%{id, name, type, rank, path}`. Families show just their
  name as the path. Intermediates show "Family / Rank: Name" (or deeper nesting).

  The `type` parameter determines which parents are valid:
  - `"genus"` or `"intermediate"` — returns families + intermediates
  - anything else — returns `[]`
  """
  @spec list_parent_options_with_paths(String.t() | nil) :: [map()]
  def list_parent_options_with_paths(type) when type in ["genus", "intermediate"] do
    families =
      from(t in Taxonomy,
        where: t.type == "family" and t.is_placeholder == false,
        order_by: t.name,
        select: t
      )
      |> Repo.all()
      |> Enum.map(fn f ->
        %{id: f.id, name: f.name, type: "family", rank: nil, path: f.name}
      end)

    intermediates =
      from(t in Taxonomy,
        where: t.type == "intermediate",
        order_by: t.name,
        select: t
      )
      |> Repo.all()
      |> Enum.map(fn t ->
        path = build_parent_path(t)
        %{id: t.id, name: t.name, type: "intermediate", rank: t.rank, path: path}
      end)

    families ++ intermediates
  end

  def list_parent_options_with_paths("section") do
    from(t in Taxonomy,
      where: t.type == "genus" and t.is_placeholder == false,
      order_by: t.name,
      select: t
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      path = build_parent_path(t)
      %{id: t.id, name: t.name, type: "genus", rank: nil, path: path}
    end)
  end

  def list_parent_options_with_paths(_type), do: []

  defp build_parent_path(taxonomy) do
    ancestors = get_taxonomy_path(taxonomy.id)

    Enum.map_join(ancestors, " / ", fn t ->
      if t.type == "intermediate" do
        "#{t.rank}: #{t.name}"
      else
        t.name
      end
    end)
  end

  # =====================================================================
  # Lists
  # =====================================================================

  @doc """
  Returns all non-placeholder taxonomies.
  """
  @spec list_taxonomies() :: [Taxonomy.t()]
  def list_taxonomies do
    from(t in Taxonomy, where: t.is_placeholder == false)
    |> Repo.all()
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
          rank: t.rank,
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
            not (t.is_placeholder == true and t.type == "genus" and
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
  Returns a paginated list of taxonomies with their parent, optionally filtered by type.

  Same filtering as `list_taxonomies_with_parent/2` but with LIMIT/OFFSET.
  """
  @spec list_taxonomies_with_parent_paginated(String.t() | nil, integer(), integer(), keyword()) ::
          [map()]
  def list_taxonomies_with_parent_paginated(type, limit, offset, opts \\ []) do
    hide_empty_unknown = Keyword.get(opts, :hide_empty_unknown, false)

    base_query =
      from(t in Taxonomy,
        left_join: p in Taxonomy,
        on: t.parent_id == p.id,
        order_by: [t.type, t.name],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: t.id,
          name: t.name,
          description: t.description,
          type: t.type,
          rank: t.rank,
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
            not (t.is_placeholder == true and t.type == "genus" and
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
  Returns the count of taxonomies, optionally filtered by type.

  Respects the same `hide_empty_unknown` option as `list_taxonomies_with_parent/2`.
  """
  @spec count_taxonomies(String.t() | nil, keyword()) :: integer()
  def count_taxonomies(type \\ nil, opts \\ []) do
    hide_empty_unknown = Keyword.get(opts, :hide_empty_unknown, false)

    base_query = from(t in Taxonomy, select: count(t.id))

    query_with_type =
      if type do
        from(t in base_query, where: t.type == ^type)
      else
        base_query
      end

    query =
      if hide_empty_unknown do
        from(t in query_with_type,
          where:
            not (t.is_placeholder == true and t.type == "genus" and
                   fragment(
                     "NOT EXISTS (SELECT 1 FROM species_taxonomy st WHERE st.taxonomy_id = ?)",
                     t.id
                   ))
        )
      else
        query_with_type
      end

    Repo.one(query)
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
  Returns families as `{name, id}` tuples for select inputs.

  Filter options:
  - `:all` — all families (default)
  - `:plant` — families where description == "Plant"
  - `:gall` — families where description != "Plant"
  """
  @spec list_families_for_select(atom()) :: [{String.t(), integer()}]
  def list_families_for_select(filter \\ :all) do
    base =
      from(t in Taxonomy,
        where: t.type == "family",
        order_by: t.name,
        select: {t.name, t.id}
      )

    case filter do
      :plant -> from(t in base, where: t.description == "Plant")
      :gall -> from(t in base, where: t.description != "Plant")
      :all -> base
    end
    |> Repo.all()
  end

  @doc """
  Returns genera for use in typeahead/select components.
  Each result includes the parent family ID for auto-population.
  Excludes genera named "Unknown" as those are created automatically.
  """
  @spec list_genera_for_select(atom()) :: [map()]
  def list_genera_for_select(filter \\ :all) do
    # Use a CTE to walk from each genus up to its ancestor family,
    # handling intermediates and sections in the parent chain.
    plant_only = if filter == :plant, do: 1, else: 0

    query = """
    WITH RECURSIVE genus_to_family AS (
      SELECT g.id as genus_id, g.name as genus_name, g.parent_id as current_parent_id
      FROM taxonomy g
      WHERE g.type = 'genus' AND g.name != 'Unknown'

      UNION ALL

      SELECT gf.genus_id, gf.genus_name, t.parent_id
      FROM genus_to_family gf
      JOIN taxonomy t ON t.id = gf.current_parent_id
      WHERE t.type != 'family'
    )
    SELECT gf.genus_id as id, gf.genus_name as name, f.id as family_id
    FROM genus_to_family gf
    JOIN taxonomy f ON f.id = gf.current_parent_id AND f.type = 'family'
    WHERE ($1::integer = 0 OR f.description = 'Plant')
    ORDER BY gf.genus_name
    """

    case Repo.query(query, [plant_only]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, family_id] ->
          %{id: id, name: name, family_id: family_id}
        end)

      {:error, _} ->
        []
    end
  end

  # =====================================================================
  # Unknown/Placeholder Management
  # =====================================================================

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
  Finds or creates an "Unknown (Family)" placeholder genus under the given family.

  Used for undescribed galls where the genus is not known.
  Returns {:ok, genus} or {:error, changeset}.
  """
  @spec find_or_create_unknown_genus(integer()) ::
          {:ok, Taxonomy.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_unknown_genus(family_id) do
    # Look for an existing placeholder genus under this family
    case Repo.one(
           from(t in Taxonomy,
             where: t.is_placeholder == true and t.type == "genus" and t.parent_id == ^family_id
           )
         ) do
      nil ->
        family = get_taxonomy!(family_id)

        create_taxonomy(%{
          name: "Unknown (#{family.name})",
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
  Returns IDs of "Unknown" genera that have no species linked.

  These are placeholder genera auto-created for each family but not yet
  used for any undescribed species. They create UI noise and should
  typically be hidden from browse/search interfaces.
  """
  @spec empty_unknown_genus_ids() :: [integer()]
  def empty_unknown_genus_ids do
    from(t in Taxonomy,
      where: t.type == "genus" and t.is_placeholder == true,
      where:
        fragment(
          "NOT EXISTS (SELECT 1 FROM species_taxonomy st WHERE st.taxonomy_id = ?)",
          t.id
        ),
      select: t.id
    )
    |> Repo.all()
  end

  # =====================================================================
  # Utility
  # =====================================================================

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

  # =====================================================================
  # Cross-domain Taxonomy Queries
  # =====================================================================

  @doc """
  Lists families for galls that occur on a given host.
  """
  @spec list_gall_families_for_host(integer()) :: [map()]
  def list_gall_families_for_host(host_id) do
    # Use CTE to walk from gall genera up to their ancestor families,
    # handling intermediate ranks in the parent chain.
    query = """
    WITH RECURSIVE genus_to_family AS (
      SELECT st.taxonomy_id as genus_id, t.parent_id as current_parent_id, t.type as current_type
      FROM species_taxonomy st
      JOIN taxonomy t ON st.taxonomy_id = t.id AND t.type = 'genus'
      JOIN species s ON st.species_id = s.id AND s.taxoncode = 'gall'
      JOIN gallhost h ON h.gall_species_id = s.id
      WHERE h.host_species_id = $1::bigint

      UNION ALL

      SELECT gf.genus_id, t.parent_id, t.type
      FROM genus_to_family gf
      JOIN taxonomy t ON t.id = gf.current_parent_id
      WHERE gf.current_type != 'family'
    )
    SELECT DISTINCT f.id, f.name
    FROM genus_to_family gf
    JOIN taxonomy f ON f.id = gf.current_parent_id AND f.type = 'family'
    WHERE gf.current_type != 'family'
    ORDER BY f.name
    """

    case Repo.query(query, [host_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name] -> %{id: id, name: name} end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Lists families for galls that occur on hosts in a given host genus/section.
  """
  @spec list_gall_families_for_host_genus(integer()) :: [map()]
  def list_gall_families_for_host_genus(host_genus_id) do
    # Use CTE to walk from gall genera up to their ancestor families,
    # handling intermediate ranks in the parent chain.
    query = """
    WITH RECURSIVE genus_to_family AS (
      SELECT galler_st.taxonomy_id as genus_id, gt.parent_id as current_parent_id, gt.type as current_type
      FROM species_taxonomy host_st
      JOIN gallhost h ON h.host_species_id = host_st.species_id
      JOIN species s ON h.gall_species_id = s.id AND s.taxoncode = 'gall'
      JOIN species_taxonomy galler_st ON galler_st.species_id = s.id
      JOIN taxonomy gt ON galler_st.taxonomy_id = gt.id AND gt.type = 'genus'
      WHERE host_st.taxonomy_id = $1::bigint

      UNION ALL

      SELECT gf.genus_id, t.parent_id, t.type
      FROM genus_to_family gf
      JOIN taxonomy t ON t.id = gf.current_parent_id
      WHERE gf.current_type != 'family'
    )
    SELECT DISTINCT f.id, f.name
    FROM genus_to_family gf
    JOIN taxonomy f ON f.id = gf.current_parent_id AND f.type = 'family'
    WHERE gf.current_type != 'family'
    ORDER BY f.name
    """

    case Repo.query(query, [host_genus_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name] -> %{id: id, name: name} end)

      {:error, _} ->
        []
    end
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
      group_by: [s.id, s.name, s.type, s.description, g.id, g.name],
      order_by: [g.name, s.name],
      select: %{
        id: s.id,
        name: s.name,
        type: s.type,
        description: s.description,
        genus_id: g.id,
        genus_name: g.name,
        species_count: count(st.species_id)
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists children of a taxonomy node with species counts.

  For intermediate nodes, returns child intermediates and genera with
  the count of species under each. Used by the public intermediate browse page.
  """
  @spec list_children_with_counts(integer()) :: [map()]
  def list_children_with_counts(parent_id) do
    query = """
    WITH RECURSIVE descendants AS (
      -- Base: direct children of each child
      SELECT child.id AS child_id, child.id AS descendant_id, child.type AS descendant_type
      FROM taxonomy child
      WHERE child.parent_id = $1::bigint

      UNION ALL

      -- Recurse: walk down the tree from each child
      SELECT d.child_id, t.id, t.type
      FROM descendants d
      INNER JOIN taxonomy t ON t.parent_id = d.descendant_id
    )
    SELECT t.id, t.name, t.type, t.rank, t.description,
           COUNT(DISTINCT st.species_id) as species_count
    FROM taxonomy t
    LEFT JOIN descendants d ON d.child_id = t.id AND d.descendant_type = 'genus'
    LEFT JOIN species_taxonomy st ON st.taxonomy_id = d.descendant_id
    WHERE t.parent_id = $1::bigint
    GROUP BY t.id, t.name, t.type, t.rank, t.description
    ORDER BY t.type, t.name
    """

    case Repo.query(query, [parent_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, type, rank, description, species_count] ->
          %{
            id: id,
            name: name,
            type: type,
            rank: rank,
            description: description,
            species_count: species_count
          }
        end)

      {:error, _} ->
        []
    end
  end

  # =====================================================================
  # Private Helpers
  # =====================================================================

  defp attr_value(attrs, key), do: attrs[key] || attrs[String.to_existing_atom(key)]

  defp has_linked_species?(taxonomy_id) do
    Repo.exists?(from(st in "species_taxonomy", where: st.taxonomy_id == ^taxonomy_id))
  end

  defp broadcast({:ok, taxonomy}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "taxonomy", {event, taxonomy})
    {:ok, taxonomy}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
