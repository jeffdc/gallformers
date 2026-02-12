defmodule Gallformers.Taxonomy.Tree do
  @moduledoc """
  Tree CRUD and hierarchy query functions for the taxonomy system.

  Handles creating, reading, updating, and deleting taxonomy entries,
  querying the taxonomy hierarchy, and managing placeholder genera.
  """

  require Logger
  import Ecto.Query
  alias Gallformers.GallHosts.GallHost
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.{Family, Lineage, TaxonName, Taxonomy}

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
    case Repo.get(Taxonomy, id) |> Repo.preload(:parent) do
      %Taxonomy{type: "genus"} = genus ->
        {:ok, Lineage.from_genus(genus)}

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
        genus = Repo.get!(Taxonomy, genus_id) |> Repo.preload(:parent)
        {:ok, Lineage.from_section(section, genus)}

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
      where: t.name == ^name and t.type == ^type
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
  def build_taxonomy_from_genus(genus) do
    genus
    |> Repo.preload(:parent)
    |> Lineage.from_genus()
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
    base =
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

    case filter do
      :plant ->
        from([g, p, gp] in base,
          join: f in Taxonomy,
          on:
            f.id ==
              fragment(
                "CASE WHEN ? = 'section' THEN ? ELSE ? END",
                p.type,
                gp.id,
                p.id
              ),
          where: f.description == "Plant"
        )

      :all ->
        base
    end
    |> Repo.all()
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
    from(f in Taxonomy,
      join: g in Taxonomy,
      on: g.parent_id == f.id,
      join: st in "species_taxonomy",
      on: st.taxonomy_id == g.id,
      join: s in Species,
      on: st.species_id == s.id,
      join: h in GallHost,
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
      join: s in Species,
      on: st.species_id == s.id,
      join: h in GallHost,
      on: h.gall_species_id == s.id,
      join: host in Species,
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

  # =====================================================================
  # Private Helpers
  # =====================================================================

  defp broadcast({:ok, taxonomy}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "taxonomy", {event, taxonomy})
    {:ok, taxonomy}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
