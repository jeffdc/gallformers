defmodule Gallformers.Taxonomy.SpeciesLink do
  @moduledoc """
  Species-taxonomy linkage operations.

  Handles the junction between species and taxonomy entries:
  - Linking species to genera (species_taxonomy table)
  - Resolving taxonomy from species names
  - Querying species by taxonomy
  - Section-species management
  """

  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.{TaxonName, Taxonomy, Tree}

  # =====================================================================
  # Genus Name Extraction
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

  # =====================================================================
  # Species-Taxonomy Junction Operations
  # =====================================================================

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
    if TaxonName.unknown_genus?(genus_name) do
      # For Unknown genus, use find_or_create to avoid duplicates per family
      {:ok, genus} = Tree.find_or_create_unknown_genus(parent_id)
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
  Creates a new genus under a family and links a species to it.

  Used when creating a new species with a genus that doesn't exist yet.
  Creates the genus taxonomy entry and the species-taxonomy relationship.

  Returns `{:ok, genus}` on success or `{:error, reason}` on failure.
  """
  @spec create_genus_for_species(String.t(), integer(), integer()) ::
          {:ok, Taxonomy.t()} | {:error, term()}
  def create_genus_for_species(genus_name, family_id, species_id) do
    case Tree.create_taxonomy(%{name: genus_name, type: "genus", parent_id: family_id}) do
      {:ok, genus} ->
        link_species_to_taxonomy(species_id, genus.id)
        {:ok, genus}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a species' genus link.

  Removes any existing genus links and creates a new one to the specified genus.
  Used when renaming a species to a different genus.
  """
  @spec update_species_genus(integer(), integer()) :: :ok | {:error, term()}
  def update_species_genus(species_id, new_genus_id) do
    # Find all genus and section taxonomy IDs — both must be cleaned up
    # when reclassifying, since sections belong to a specific genus and
    # the old section link would be stale after moving to a new genus.
    genus_and_section_ids_query =
      from(t in Taxonomy,
        where: t.type in ["genus", "section"],
        select: t.id
      )

    # Remove existing genus AND section links for this species
    # (SQLite doesn't support JOINs in DELETE, so we use a subquery)
    from(st in "species_taxonomy",
      where:
        st.species_id == ^species_id and st.taxonomy_id in subquery(genus_and_section_ids_query)
    )
    |> Repo.delete_all()

    # Then link to the new genus
    case link_species_to_taxonomy(species_id, new_genus_id) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # =====================================================================
  # Taxonomy Resolution for Species
  # =====================================================================

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
         %{} = genus <- Tree.get_taxonomy_by_name(genus_name, "genus") do
      build_taxonomy_map(genus, Tree.get_parent(genus.id))
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
    family = Tree.get_parent(section.id)

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
        genera = Tree.get_genera_by_name(genus_name)

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
  Resolves a genus ID, handling placeholder genera.

  If the selected genus is a placeholder, finds or creates the Unknown genus
  under the given family. Otherwise returns the genus ID as-is.
  """
  @spec resolve_genus_id(%{id: integer(), is_placeholder: boolean()}, %{id: integer()}) ::
          integer()
  def resolve_genus_id(%{is_placeholder: true}, %{id: family_id}) do
    {:ok, unknown_genus} = Tree.find_or_create_unknown_genus(family_id)
    unknown_genus.id
  end

  def resolve_genus_id(%{id: genus_id}, _family), do: genus_id

  # =====================================================================
  # Species-Taxonomy Queries
  # =====================================================================

  @doc """
  Gets the genus, section, and family for a species.

  Returns a map with taxonomy names, IDs, and descriptions (common names) or nil if not found.
  Section is optional and will only be present for plant hosts in genera
  that have sections (primarily Quercus).
  """
  @spec get_taxonomy_for_species(integer()) :: map() | nil
  def get_taxonomy_for_species(species_id) do
    # Get the genus link. The genus parent may be a family directly,
    # or a section (whose parent is the family). We join two levels up
    # to handle both: genus → parent → grandparent.
    genus_query =
      from st in "species_taxonomy",
        join: g in Taxonomy,
        on: st.taxonomy_id == g.id and g.type == "genus",
        left_join: parent in Taxonomy,
        on: g.parent_id == parent.id,
        left_join: grandparent in Taxonomy,
        on: parent.parent_id == grandparent.id,
        where: st.species_id == ^species_id,
        limit: 1,
        select: %{
          genus: g.name,
          genus_id: g.id,
          genus_description: g.description,
          parent_type: parent.type,
          parent_name: parent.name,
          parent_id: parent.id,
          parent_description: parent.description,
          grandparent_name: grandparent.name,
          grandparent_id: grandparent.id,
          grandparent_description: grandparent.description
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

        # Resolve family: if genus parent is a section, family is one more level up
        {family, family_id, family_description} =
          if genus_result.parent_type == "section" do
            {genus_result.grandparent_name, genus_result.grandparent_id,
             genus_result.grandparent_description}
          else
            {genus_result.parent_name, genus_result.parent_id, genus_result.parent_description}
          end

        %{
          genus: genus_result.genus,
          genus_id: genus_result.genus_id,
          genus_description: genus_result.genus_description,
          section: section_result && section_result.section,
          section_id: section_result && section_result.section_id,
          section_description: section_result && section_result.section_description,
          family: family,
          family_id: family_id,
          family_description: family_description
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

  @doc """
  Gets all species in a Section by ID.
  """
  def get_species_for_section(section_id) do
    from(s in Species,
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
  # Section-Species Management
  # =====================================================================

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
         %{id: genus_id} <- Tree.get_taxonomy_by_name(genus_name, "genus") do
      from(t in Taxonomy, where: t.id == ^section_id)
      |> Repo.update_all(set: [parent_id: genus_id])
    end

    :ok
  end
end
