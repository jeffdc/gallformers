defmodule Gallformers.Taxonomy.Reclassification do
  @moduledoc """
  Reclassification, deletion cascade, and impact analysis for taxonomy entries.

  Handles reassigning species between genera (with rename and alias creation),
  cascade deletion of taxonomy hierarchies, and impact analysis for deletion UI.
  """

  require Logger
  import Ecto.Query
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.{SpeciesLink, TaxonName, Taxonomy, Tree}

  # =====================================================================
  # Reclassification
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
      case Gallformers.Taxonomy.update_species_genus(species_id, new_genus_id) do
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
    genus = Tree.get_taxonomy!(new_genus_id) |> Repo.preload(:parent)
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
    genus = Tree.get_taxonomy(genus_id)

    if genus && genus.is_placeholder do
      case Repo.get(GallTraits, species_id) do
        nil -> :ok
        gall_traits -> GallTraits.changeset(gall_traits, %{undescribed: true}) |> Repo.update!()
      end
    end
  end

  # =====================================================================
  # Deletion Impact
  # =====================================================================

  @doc """
  Gathers all data that would be deleted if this taxonomy is deleted.
  Returns counts and lists for UI display.
  """
  @spec get_deletion_impact(Taxonomy.t()) :: map()
  def get_deletion_impact(%Taxonomy{id: id, type: "family"} = taxonomy) do
    genera = Tree.list_child_genera(id)
    genera_ids = Enum.map(genera, & &1.id)

    sections = Tree.list_sections_for_family_tree(id)
    section_ids = Enum.map(sections, & &1.id)

    all_taxonomy_ids = genera_ids ++ section_ids

    species_count =
      SpeciesLink.count_species_for_taxonomies(all_taxonomy_ids)

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
    sections = Tree.list_child_sections(id)
    section_ids = Enum.map(sections, & &1.id)

    all_taxonomy_ids = [id | section_ids]

    species_count =
      SpeciesLink.count_species_for_taxonomies(all_taxonomy_ids)

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

  # =====================================================================
  # Deletion Cascade
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

    genera = Tree.list_child_genera(id)
    genera_ids = Enum.map(genera, & &1.id)

    sections = Tree.list_sections_for_family_tree(id)
    section_ids = Enum.map(sections, & &1.id)

    all_taxonomy_ids = genera_ids ++ section_ids

    species_count =
      SpeciesLink.count_species_for_taxonomies(all_taxonomy_ids)

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

    sections = Tree.list_child_sections(id)
    section_ids = Enum.map(sections, & &1.id)

    all_taxonomy_ids = [id | section_ids]

    species_count =
      SpeciesLink.count_species_for_taxonomies(all_taxonomy_ids)

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
