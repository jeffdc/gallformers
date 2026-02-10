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
  alias Gallformers.Taxonomy.{Search, SpeciesLink, TaxonName, Taxonomy, Tree}

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
  # Delegated to Taxonomy.SpeciesLink — Species-Taxonomy Linkage
  # =====================================================================

  defdelegate extract_genus_from_name(name), to: SpeciesLink
  defdelegate link_species_to_taxonomy(species_id, taxonomy_id), to: SpeciesLink

  defdelegate link_species_taxonomy(species_id, taxonomy, genus_is_new, parent_id),
    to: SpeciesLink

  defdelegate create_genus_for_species(genus_name, family_id, species_id), to: SpeciesLink
  defdelegate update_species_genus(species_id, new_genus_id), to: SpeciesLink

  # =====================================================================
  # Delegated to Taxonomy.SpeciesLink — Taxonomy Resolution
  # =====================================================================

  defdelegate get_taxonomy_from_species_name(name), to: SpeciesLink
  defdelegate lookup_taxonomy_for_new_species(name), to: SpeciesLink
  defdelegate resolve_taxonomy_for_species(taxonomy, family_ids, opts \\ []), to: SpeciesLink
  defdelegate maybe_update_genus_section(genus_id, new, old, family_id), to: SpeciesLink
  defdelegate resolve_genus_id(genus, family), to: SpeciesLink

  # =====================================================================
  # Delegated to Taxonomy.SpeciesLink — Species-Taxonomy Queries
  # =====================================================================

  defdelegate get_taxonomy_for_species(species_id), to: SpeciesLink
  defdelegate get_taxonomy_for_species_batch(species_ids), to: SpeciesLink
  defdelegate get_species_ids_for_genus(genus_id), to: SpeciesLink
  defdelegate get_species_ids_for_genera(genus_ids), to: SpeciesLink
  defdelegate get_species_ids_for_family(family_id), to: SpeciesLink
  defdelegate get_species_ids_for_taxonomies(taxonomy_ids), to: SpeciesLink
  defdelegate get_species_for_section(section_id), to: SpeciesLink
  defdelegate count_species_for_taxonomies(taxonomy_ids), to: SpeciesLink
  defdelegate update_section_species(section_id, species_ids), to: SpeciesLink

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
  # Delegated to Taxonomy.Search — Typeahead & Search Queries
  # =====================================================================

  defdelegate search_families(query, limit \\ 20), to: Search
  defdelegate search_genera(query, family_id \\ nil, limit \\ 20), to: Search
  defdelegate search_genera_and_sections(query, limit \\ 20, opts \\ []), to: Search
  defdelegate search_taxonomies(query, type \\ nil, limit \\ 50), to: Search
  defdelegate search_sections(query), to: Search

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

  # =====================================================================
  # Sections Management (stays in Taxonomy context)
  # =====================================================================

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
