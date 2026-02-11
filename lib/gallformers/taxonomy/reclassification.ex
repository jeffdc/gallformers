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
  - `undescribed?` - whether the species is currently undescribed
  - `former_undescribed_choice` - `:keep`, `:replace`, or `nil`

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

    {alias_type, rotate?} = resolve_alias_opts(params)

    cond do
      genus_changed? ->
        target_epithet = TaxonName.epithet(new_name)

        reassign_species_taxonomy(species_id, genus_id,
          add_alias?: add_alias?,
          alias_type: alias_type,
          rotate_former_undescribed: rotate?,
          target_epithet: target_epithet
        )

      name_changed? ->
        if rotate?,
          do: Gallformers.Species.rotate_former_undescribed_alias(species_id)

        Gallformers.Species.rename_species(species_id, new_name, add_alias?, alias_type)

      true ->
        {:ok, Repo.get!(Species, species_id)}
    end
  end

  defp resolve_alias_opts(params) do
    case params[:former_undescribed_choice] do
      :keep -> {"scientific", false}
      :replace -> {"former_undescribed", true}
      nil -> {if(params[:undescribed?], do: "former_undescribed", else: "scientific"), false}
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
    rotate_former_undescribed = Keyword.get(opts, :rotate_former_undescribed, false)
    explicit_alias_type = Keyword.get(opts, :alias_type)
    target_epithet = Keyword.get(opts, :target_epithet)
    # Capture undescribed state BEFORE force_undescribed_if_placeholder changes it
    was_undescribed? = Gallformers.Galls.undescribed?(species_id)

    Repo.transaction(fn ->
      case SpeciesLink.update_species_genus(species_id, new_genus_id) do
        :ok ->
          Gallformers.Galls.force_undescribed_if_placeholder(species_id, new_genus_id)
          maybe_rotate_former_undescribed(species_id, rotate_former_undescribed)

          rename_species_for_reclassification(
            species_id,
            new_genus_id,
            add_alias?,
            was_undescribed?,
            explicit_alias_type,
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
  defp rename_species_for_reclassification(
         species_id,
         new_genus_id,
         add_alias?,
         was_undescribed?,
         explicit_alias_type,
         target_epithet
       ) do
    species = Repo.get!(Species, species_id)
    genus = Tree.get_taxonomy!(new_genus_id) |> Repo.preload(:parent)
    new_genus_display = Taxonomy.display_name(genus)

    epithet = target_epithet || TaxonName.epithet(species.name)
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

      # When target_epithet was provided, rename_for_genus_change produced
      # "NewGenus old_epithet" — correct the name to use the target epithet.
      updated = Repo.get!(Species, species_id)

      if updated.name != new_name do
        updated
        |> Species.changeset(%{name: new_name})
        |> Repo.update!()
      else
        updated
      end
    else
      species
    end
  end

  defp maybe_rotate_former_undescribed(_species_id, false), do: :ok

  defp maybe_rotate_former_undescribed(species_id, true) do
    Gallformers.Species.rotate_former_undescribed_alias(species_id)
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
