defmodule Gallformers.Taxonomy do
  @moduledoc """
  The Taxonomy context.

  Provides functions for working with taxonomic classifications.
  """

  require Logger
  import Ecto.Query
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.{TaxonName, Taxonomy, Tree}

  # =====================================================================
  # Delegated to Taxonomy.Tree — CRUD
  # =====================================================================

  defdelegate change_taxonomy(taxonomy, attrs \\ %{}), to: Tree
  defdelegate create_taxonomy(attrs \\ %{}), to: Tree
  defdelegate update_taxonomy(taxonomy, attrs), to: Tree
  defdelegate delete_taxonomy(taxonomy), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Lookups
  # =====================================================================

  defdelegate get_taxonomy(id), to: Tree
  defdelegate get_taxonomy!(id), to: Tree
  defdelegate get_taxonomy_by_name(name, type), to: Tree
  defdelegate get_genera_by_name(name), to: Tree
  defdelegate get_taxonomies_batch(ids), to: Tree
  defdelegate resolve_taxonomy_from_name(name), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Hierarchy
  # =====================================================================

  defdelegate get_parent(id), to: Tree
  defdelegate get_children(id), to: Tree
  defdelegate get_children_for_parents(ids), to: Tree
  defdelegate get_taxonomy_path(id), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Lists
  # =====================================================================

  defdelegate list_taxonomies(), to: Tree
  defdelegate list_taxonomies_by_type(type), to: Tree
  defdelegate list_taxonomies_with_parent(type \\ nil, opts \\ []), to: Tree
  defdelegate list_child_genera(family_id), to: Tree
  defdelegate list_child_sections(genus_id), to: Tree
  defdelegate list_sections_for_family_tree(family_id), to: Tree
  defdelegate list_sections_for_family(family_id), to: Tree
  defdelegate list_sections_for_genus(genus_id), to: Tree
  defdelegate list_families_for_select(filter \\ :all), to: Tree
  defdelegate list_genera_for_select(), to: Tree
  defdelegate list_parents_for_genus(), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Unknown/Placeholder Management
  # =====================================================================

  defdelegate get_unknown_placeholder(parent_id), to: Tree
  defdelegate find_or_create_unknown_genus(family_id), to: Tree
  defdelegate empty_unknown_genus_ids(), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Utility
  # =====================================================================

  defdelegate display_name(taxonomy), to: Tree
  defdelegate update_genus_parent(genus_id, new_parent_id), to: Tree
  defdelegate move_genera(genus_ids, old_family_id, new_family_id), to: Tree

  # =====================================================================
  # TaxonName delegates
  # =====================================================================

  @doc """
  Returns true if the given genus name represents a placeholder (Unknown) genus.
  """
  @spec placeholder_genus_name?(String.t() | nil) :: boolean()
  defdelegate placeholder_genus_name?(name), to: TaxonName, as: :unknown_genus?

  @doc """
  Extracts the epithet (everything after the genus portion) from a species name.
  Handles "Unknown (Family) epithet" and "Genus epithet" formats.
  """
  defdelegate extract_epithet(name), to: TaxonName, as: :epithet

  # =====================================================================
  # 1-arity get_taxonomy_by_name (stays — URL parameter lookup)
  # =====================================================================

  # The 1-arity version is also delegated but needs special handling since
  # defdelegate can't distinguish arities for same name. We delegate to the
  # 2-arg version in Tree won't work. Tree has both arities, so we delegate
  # the 1-arity explicitly.

  # Note: The 1-arity get_taxonomy_by_name is handled by Tree's 1-arity clause.
  # Elixir's defdelegate for 2-arity (name, type) covers calls with 2 args.
  # Calls with 1 arg go through the 2-arity defdelegate default? No — we need
  # an explicit function for 1-arity.
  def get_taxonomy_by_name(name) when is_binary(name) do
    Tree.get_taxonomy_by_name(name)
  end

  # =====================================================================
  # Species-Taxonomy Linkage (stays in Taxonomy context)
  # =====================================================================

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
            result = Tree.build_taxonomy_from_genus(single_genus)
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

  defp extract_family_info(genus) do
    taxonomy = Tree.build_taxonomy_from_genus(genus)

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
  def link_species_taxonomy(species_id, %{genus: genus_name} = _taxonomy, true, parent_id)
      when is_binary(genus_name) do
    if placeholder_genus_name?(genus_name) do
      # For Unknown genus, use find_or_create to avoid duplicates per family
      {:ok, genus} = find_or_create_unknown_genus(parent_id)
      link_species_to_taxonomy(species_id, genus.id)
    else
      # New genus - create it under the parent (section or family)
      {:ok, _genus} = create_genus_for_species(genus_name, parent_id, species_id)
    end

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

  # =====================================================================
  # Reclassification (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Reassigns a species to a different genus.

  Wraps `update_species_genus/2` in a transaction. Also renames the species to
  reflect the new genus (e.g., "Andricus quercuslanigera" → "Callirhytis quercuslanigera"),
  adding a scientific synonym alias for the old name. If the new genus is an Unknown
  placeholder and the species has gall_traits, forces `undescribed=true`.

  Returns `{:ok, updated_species}` on success or `{:error, reason}` on failure.
  """
  @spec reassign_species_taxonomy(integer(), integer(), keyword()) ::
          {:ok, Species.t()} | {:error, term()}
  def reassign_species_taxonomy(species_id, new_genus_id, opts \\ []) do
    add_alias? = Keyword.get(opts, :add_alias?, true)
    rotate_former_undescribed = Keyword.get(opts, :rotate_former_undescribed, false)
    explicit_alias_type = Keyword.get(opts, :alias_type)
    # Capture undescribed state BEFORE maybe_force_undescribed changes it
    was_undescribed? = species_undescribed?(species_id)

    Repo.transaction(fn ->
      case update_species_genus(species_id, new_genus_id) do
        :ok ->
          maybe_force_undescribed(species_id, new_genus_id)
          maybe_rotate_former_undescribed(species_id, rotate_former_undescribed)

          rename_species_for_reclassification(
            species_id,
            new_genus_id,
            add_alias?,
            was_undescribed?,
            explicit_alias_type
          )

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, species} -> {:ok, species}
      {:error, reason} -> {:error, reason}
    end
  end

  # Renames a species to reflect its new genus after reclassification.
  defp rename_species_for_reclassification(
         species_id,
         new_genus_id,
         add_alias?,
         was_undescribed?,
         explicit_alias_type
       ) do
    species = Repo.get!(Species, species_id)
    genus = get_taxonomy!(new_genus_id) |> Repo.preload(:parent)
    new_genus_display = Taxonomy.display_name(genus)

    epithet = TaxonName.epithet(species.name)
    new_name = TaxonName.build(new_genus_display, epithet)

    if new_name != species.name do
      old_genus_display = TaxonName.genus_display(species.name)

      alias_type =
        explicit_alias_type ||
          if was_undescribed?,
            do: "former_undescribed",
            else: "scientific"

      Gallformers.Species.rename_for_genus_change(
        species,
        old_genus_display,
        new_genus_display,
        add_alias?,
        alias_type: alias_type
      )

      # Return the updated species
      Repo.get!(Species, species_id)
    else
      species
    end
  end

  defp maybe_rotate_former_undescribed(_species_id, false), do: :ok

  defp maybe_rotate_former_undescribed(species_id, true) do
    Gallformers.Species.rotate_former_undescribed_alias(species_id)
  end

  # Returns true if the species has gall_traits with undescribed=true.
  defp species_undescribed?(species_id) do
    case Repo.get(GallTraits, species_id) do
      %GallTraits{undescribed: true} -> true
      _ -> false
    end
  end

  # If the new genus is Unknown and the species has gall_traits, force undescribed=true.
  defp maybe_force_undescribed(species_id, genus_id) do
    genus = get_taxonomy(genus_id)

    if genus && genus.is_placeholder do
      case Repo.get(GallTraits, species_id) do
        nil -> :ok
        gall_traits -> GallTraits.changeset(gall_traits, %{undescribed: true}) |> Repo.update!()
      end
    end
  end

  # =====================================================================
  # Search (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Searches families by name prefix (case-insensitive).

  Used by the reclassify modal family typeahead.
  Returns maps with id and name.
  """
  @spec search_families(String.t(), integer()) :: [map()]
  def search_families(query, limit \\ 20) do
    name_pattern = "#{String.downcase(query)}%"

    from(f in Taxonomy,
      where: f.type == "family",
      where: fragment("lower(?) LIKE ?", f.name, ^name_pattern),
      order_by: f.name,
      limit: ^limit,
      select: %{id: f.id, name: f.name}
    )
    |> Repo.all()
  end

  @doc """
  Searches genera by name, returning genus with parent family info.

  Used by the reclassify modal typeahead. When `family_id` is provided,
  constrains results to genera within that family.
  """
  @spec search_genera(String.t(), integer() | nil, integer()) :: [map()]
  def search_genera(query, family_id \\ nil, limit \\ 20) do
    name_pattern = "#{String.downcase(query)}%"

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

    Repo.all(base)
  end

  @doc """
  Looks up taxonomy info (genus, section, family) from a species name.

  Extracts the genus from the first word of the species name,
  looks it up in the taxonomy table, and returns the full taxonomy path.

  Returns a map with the same structure as `get_taxonomy_for_species/1`,
  or nil if the genus is not found.
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

  # =====================================================================
  # Species-Taxonomy Queries (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Gets the genus, section, and family for a species.

  Returns a map with taxonomy names, IDs, and descriptions (common names) or nil if not found.
  Section is optional and will only be present for plant hosts in genera
  that have sections (primarily Quercus).
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

  # =====================================================================
  # Taxonomy Resolution for Species Forms (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Resolves taxonomy for a species name, filtering to a set of valid family IDs.

  Used by both gall and host forms to resolve genus disambiguation against
  the relevant domain (gall families or plant families).
  """
  @spec resolve_taxonomy_for_species(map() | nil, MapSet.t(), keyword()) :: tuple()
  def resolve_taxonomy_for_species(taxonomy, family_ids, opts \\ [])

  def resolve_taxonomy_for_species(nil, _family_ids, opts) do
    if Keyword.get(opts, :include_section, false) do
      {nil, false, nil, nil, []}
    else
      {nil, false, nil, []}
    end
  end

  def resolve_taxonomy_for_species(taxonomy, family_ids, opts) do
    include_section = Keyword.get(opts, :include_section, false)

    cond do
      # Genus is new - user must select a family
      Map.get(taxonomy, :genus_is_new) ->
        if include_section do
          {taxonomy, true, nil, nil, []}
        else
          {taxonomy, true, nil, []}
        end

      # Genus exists in multiple families - filter to valid families
      Map.get(taxonomy, :requires_disambiguation) ->
        matching_families =
          Enum.filter(taxonomy.possible_families, fn family ->
            MapSet.member?(family_ids, family.family_id)
          end)

        resolve_disambiguation(taxonomy, matching_families, include_section)

      # Genus exists in exactly one family - check if it's a valid family
      true ->
        resolve_single_family(taxonomy, family_ids, include_section)
    end
  end

  defp resolve_single_family(taxonomy, family_ids, include_section) do
    if MapSet.member?(family_ids, taxonomy.family_id) do
      if include_section do
        {taxonomy, false, taxonomy.family_id, taxonomy.section_id, []}
      else
        {taxonomy, false, taxonomy.family_id, []}
      end
    else
      new_genus = %{genus: taxonomy.genus, genus_id: nil, genus_is_new: true}

      if include_section do
        {new_genus, true, nil, nil, []}
      else
        {new_genus, true, nil, []}
      end
    end
  end

  defp resolve_disambiguation(taxonomy, [], include_section) do
    new_genus = %{genus: taxonomy.genus, genus_id: nil, genus_is_new: true}

    if include_section do
      {new_genus, true, nil, nil, []}
    else
      {new_genus, true, nil, []}
    end
  end

  defp resolve_disambiguation(taxonomy, [single], include_section) do
    resolved = %{
      genus: taxonomy.genus,
      genus_id: single.genus_id,
      genus_is_new: false,
      section: single.section,
      section_id: single.section_id,
      family: single.family,
      family_id: single.family_id
    }

    if include_section do
      {resolved, false, single.family_id, single.section_id, []}
    else
      {resolved, false, single.family_id, []}
    end
  end

  defp resolve_disambiguation(taxonomy, multiple, include_section) do
    if include_section do
      {taxonomy, false, nil, nil, multiple}
    else
      {taxonomy, false, nil, multiple}
    end
  end

  @doc """
  Updates a genus's section if it changed.

  Compares `new_section_id` against `old_section_id` for the given genus.
  If changed, updates the genus's parent to the new section (or family if section cleared).
  """
  @spec maybe_update_genus_section(
          integer() | nil,
          integer() | nil,
          integer() | nil,
          integer() | nil
        ) :: :ok
  def maybe_update_genus_section(genus_id, new_section_id, old_section_id, family_id)

  def maybe_update_genus_section(nil, _new, _old, _family_id), do: :ok
  def maybe_update_genus_section(_genus_id, same, same, _family_id), do: :ok

  def maybe_update_genus_section(genus_id, new_section_id, _old_section_id, family_id) do
    new_parent_id = new_section_id || family_id

    if new_parent_id do
      update_genus_parent(genus_id, new_parent_id)
    end

    :ok
  end

  @doc """
  Resolves a genus ID, handling placeholder genera.

  If the selected genus is a placeholder, finds or creates the Unknown genus
  under the given family. Otherwise returns the genus ID as-is.
  """
  @spec resolve_genus_id(%{id: integer(), is_placeholder: boolean()}, %{id: integer()}) ::
          integer()
  def resolve_genus_id(%{is_placeholder: true}, %{id: family_id}) do
    {:ok, unknown_genus} = find_or_create_unknown_genus(family_id)
    unknown_genus.id
  end

  def resolve_genus_id(%{id: genus_id}, _family), do: genus_id

  # =====================================================================
  # Gall-Host Taxonomy Queries (stays in Taxonomy context)
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

  # =====================================================================
  # Deletion Impact & Cascade (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Gathers all data that would be deleted if this taxonomy is deleted.
  Returns counts and lists for UI display.
  """
  @spec get_deletion_impact(Taxonomy.t()) :: map()
  def get_deletion_impact(%Taxonomy{id: id, type: "family"} = taxonomy) do
    genera = list_child_genera(id)
    genera_ids = Enum.map(genera, & &1.id)

    sections = list_sections_for_family_tree(id)
    section_ids = Enum.map(sections, & &1.id)

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

    all_taxonomy_ids = genera_ids ++ section_ids
    species_count = count_species_for_taxonomies(all_taxonomy_ids)

    Logger.info(
      "Family #{taxonomy.name}: deleting #{length(genera)} genera, #{length(sections)} sections, #{species_count} species"
    )

    result =
      Repo.transaction(fn ->
        delete_species_for_cascade(all_taxonomy_ids)
        Enum.each(sections, &Repo.delete!/1)
        Enum.each(genera, &Repo.delete!/1)
        Repo.delete!(taxonomy)

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

    all_taxonomy_ids = [id | section_ids]
    species_count = count_species_for_taxonomies(all_taxonomy_ids)

    Logger.info(
      "Genus #{taxonomy.name}: deleting #{length(sections)} sections, #{species_count} species"
    )

    result =
      Repo.transaction(fn ->
        delete_species_for_cascade(all_taxonomy_ids)
        Enum.each(sections, &Repo.delete!/1)
        Repo.delete!(taxonomy)

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
    Logger.info("Simple delete for #{taxonomy.type} #{taxonomy.name} (id=#{taxonomy.id})")

    result = Repo.delete(taxonomy)
    log_cascade_result(result, taxonomy)
    broadcast(result, :taxonomy_deleted)
  end

  defp delete_species_for_cascade([]), do: :ok

  defp delete_species_for_cascade(taxonomy_ids) do
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

  # =====================================================================
  # Sections Management (stays in Taxonomy context)
  # =====================================================================

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

  # =====================================================================
  # PubSub (stays in Taxonomy context)
  # =====================================================================

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
