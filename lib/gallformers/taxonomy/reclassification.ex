defmodule Gallformers.Taxonomy.Reclassification do
  @moduledoc """
  Reclassification, deletion cascade, and impact analysis for taxonomy entries.

  Handles reassigning species between genera (with rename and alias creation),
  cascade deletion of taxonomy hierarchies, and impact analysis for deletion UI.
  """

  require Logger
  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.{SpeciesLink, TaxonName, Taxonomy, Tree}

  # =====================================================================
  # Reclassification
  # =====================================================================

  @doc """
  Performs a combined reclassify (genus change) and/or rename (epithet change).

  Accepts a species ID and a params map with keys:
  - `genus_id` - target genus ID
  - `new_name` - desired species name
  - `old_name` - current species name
  - `genus_changed?` - whether the genus is changing
  - `name_changed?` - whether the name is changing
  - `add_alias?` - whether to create an alias for the old name

  Returns `{:ok, species}` or `{:error, reason}`.
  """
  @spec reclassify_species(integer(), map()) :: {:ok, Species.t()} | {:error, term()}
  def reclassify_species(species_id, %{} = params) do
    %{
      genus_changed?: genus_changed?,
      name_changed?: name_changed?,
      add_alias?: add_alias?,
      new_name: new_name,
      genus_id: genus_id
    } = params

    cond do
      genus_changed? ->
        target_epithet = TaxonName.epithet(new_name)

        reassign_species_taxonomy(species_id, genus_id,
          add_alias?: add_alias?,
          target_epithet: target_epithet
        )

      name_changed? ->
        Gallformers.Species.rename_species(species_id, new_name, add_alias?)

      true ->
        {:ok, Repo.get!(Species, species_id)}
    end
  end

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
    target_epithet = Keyword.get(opts, :target_epithet)

    Repo.transaction(fn ->
      case SpeciesLink.update_species_genus(species_id, new_genus_id) do
        :ok ->
          Gallformers.Galls.force_undescribed_if_placeholder(species_id, new_genus_id)

          rename_species_for_reclassification(
            species_id,
            new_genus_id,
            add_alias?,
            target_epithet
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
  # Returns the updated species or calls Repo.rollback on collision.
  defp rename_species_for_reclassification(species_id, new_genus_id, add_alias?, target_epithet) do
    species = Repo.get!(Species, species_id)
    genus = Tree.get_taxonomy!(new_genus_id) |> Repo.preload(:parent)
    new_genus_display = Taxonomy.display_name(genus)

    epithet = target_epithet || TaxonName.epithet(species.name)
    new_name = TaxonName.build(new_genus_display, epithet)

    if new_name == species.name do
      species
    else
      old_genus_display = TaxonName.genus_display(species.name)

      do_reclassify_rename(species, old_genus_display, new_genus_display, new_name, add_alias?)
    end
  end

  # Performs genus rename then optional epithet correction, rolling back on collision.
  defp do_reclassify_rename(species, old_genus, new_genus, final_name, add_alias?) do
    case Gallformers.Species.rename_for_genus_change(
           species,
           old_genus,
           new_genus,
           add_alias?
         ) do
      {:ok, updated} ->
        maybe_correct_epithet(updated, final_name)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # When target_epithet was provided, rename_for_genus_change produced
  # "NewGenus old_epithet" — correct the name to use the target epithet.
  defp maybe_correct_epithet(species, final_name) when species.name == final_name, do: species

  defp maybe_correct_epithet(species, final_name) do
    case Gallformers.Species.rename_species(species.id, final_name, false) do
      {:ok, final} -> final
      {:error, reason} -> Repo.rollback(reason)
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
