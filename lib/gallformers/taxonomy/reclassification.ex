defmodule Gallformers.Taxonomy.Reclassification do
  @moduledoc """
  Reclassification, deletion cascade, and impact analysis for taxonomy entries.

  Handles reassigning species between genera (with rename and alias creation),
  cascade deletion of taxonomy hierarchies, and impact analysis for deletion UI.
  """

  require Logger
  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Species.{Alias, Species}
  alias Gallformers.TaxonName
  alias Gallformers.Taxonomy.{SpeciesLink, Taxonomy, Tree}

  # =====================================================================
  # Reclassification
  # =====================================================================

  @doc """
  Performs a combined reclassify (genus change) and/or rename (epithet change).

  Accepts a species ID and a params map with keys:
  - `new_name` - desired species name
  - `genus_changed?` - whether the genus is changing
  - `name_changed?` - whether the name is changing
  - `add_alias?` - whether to create an alias for the old name
  - `genus_id` - target genus ID (when using existing genus)
  - `genus_is_new` - true when creating a new genus (with `genus_name`, `family_id` or `family_is_new`)

  Returns `{:ok, species}` or `{:error, reason}`.
  """
  @spec reclassify_species(integer(), map()) :: {:ok, Species.t()} | {:error, term()}
  def reclassify_species(species_id, %{} = params) do
    %{
      genus_changed?: genus_changed?,
      name_changed?: name_changed?,
      add_alias?: add_alias?,
      new_name: new_name
    } = params

    cond do
      genus_changed? ->
        with {:ok, genus_id} <- resolve_genus_id(params) do
          target_epithet = TaxonName.epithet(new_name)

          reassign_species_taxonomy(species_id, genus_id,
            add_alias?: add_alias?,
            target_epithet: target_epithet
          )
        end

      name_changed? ->
        rename_species(species_id, new_name, add_alias?)

      true ->
        {:ok, Repo.get!(Species, species_id)}
    end
  end

  # Resolves genus_id from params, creating family and/or genus when needed.
  defp resolve_genus_id(%{genus_is_new: true} = params) do
    with {:ok, family_id} <- resolve_family_id(params) do
      genus_name = params.genus_name

      case Tree.create_taxonomy(%{name: genus_name, type: "genus", parent_id: family_id}) do
        {:ok, genus} -> {:ok, genus.id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp resolve_genus_id(%{genus_id: genus_id}), do: {:ok, genus_id}

  defp resolve_family_id(%{family_is_new: true} = params) do
    case Tree.create_taxonomy(%{
           name: params.family_name,
           type: "family",
           description: params.family_type
         }) do
      {:ok, family} -> {:ok, family.id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_family_id(%{family_id: family_id}), do: {:ok, family_id}

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
    case rename_for_genus_change(
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
    case rename_species(species.id, final_name, false) do
      {:ok, final} -> final
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # =====================================================================
  # Species Rename
  # =====================================================================

  @doc """
  Renames a species, optionally adding the old name as a scientific synonym alias.

  This handles the complex rename logic including potential genus reassignment.
  If the genus part of the name changes, the species may need to be reassigned
  to a different genus (or a new genus created).

  Returns {:ok, species} on success, {:error, reason} on failure.
  """
  @spec rename_species(integer(), String.t(), boolean()) ::
          {:ok, Species.t()} | {:error, atom() | String.t()}
  def rename_species(species_id, new_name, add_alias?) do
    species = Repo.get!(Species, species_id)

    Repo.transaction(fn ->
      case do_rename(species, new_name, add_alias?) do
        {:ok, updated} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Adds a rename alias for a species' old name as a scientific synonym.
  """
  def add_rename_alias(species_id, old_name) do
    alias_changeset =
      %Alias{}
      |> Ecto.Changeset.cast(
        %{name: old_name, type: "scientific", description: "Previous name"},
        [:name, :type, :description]
      )

    case Repo.insert(alias_changeset) do
      {:ok, new_alias} ->
        Repo.insert_all("alias_species", [%{alias_id: new_alias.id, species_id: species_id}])

      {:error, _} ->
        nil
    end
  end

  @doc """
  Renames a species for a genus change.

  Called by Taxonomy when a genus is renamed. For each species linked to
  that genus, this function:
  1. Checks for name collisions
  2. Creates a "scientific synonym" alias with the old species name
  3. Updates the species name by replacing the old genus with the new genus

  This is called within a Taxonomy transaction, so no additional transaction
  is created here.

  Returns `{:ok, species}` on success, `{:error, :name_exists}` on collision.

  ## Examples

      iex> rename_for_genus_change(species, "Quercus", "Oakus")
      {:ok, species}  # "Quercus alba" becomes "Oakus alba", synonym "Quercus alba" created
  """
  @spec rename_for_genus_change(Species.t(), String.t(), String.t(), boolean()) ::
          {:ok, Species.t()} | {:error, :name_exists}
  def rename_for_genus_change(
        %Species{} = species,
        old_genus_name,
        new_genus_name,
        add_alias? \\ true
      ) do
    new_species_name = TaxonName.replace_genus(species.name, old_genus_name, new_genus_name)

    do_rename(species, new_species_name, add_alias?)
  end

  # Core rename helper used by all rename paths.
  # Checks for name collisions, optionally adds alias, and updates species name.
  # Must be called within a transaction when atomicity with other operations is needed.
  defp do_rename(%Species{} = species, new_name, _add_alias?)
       when new_name == species.name,
       do: {:ok, species}

  defp do_rename(%Species{} = species, new_name, add_alias?) do
    case check_name_collision(species.id, new_name) do
      :ok ->
        if add_alias?, do: add_rename_alias(species.id, species.name)

        updated =
          species
          |> Species.changeset(%{name: new_name})
          |> Repo.update!()

        {:ok, updated}

      {:error, _} = err ->
        err
    end
  end

  defp check_name_collision(species_id, new_name) do
    case from(s in Species,
           where: s.name == ^new_name and s.id != ^species_id,
           select: s.id,
           limit: 1
         )
         |> Repo.one() do
      nil -> :ok
      _id -> {:error, :name_exists}
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
    genera = Tree.list_genera_for_family(id)
    genera_ids = Enum.map(genera, & &1.id)

    intermediates = Tree.list_intermediates_for_family(id)

    sections = Tree.list_sections_for_family_tree(id)
    section_ids = Enum.map(sections, & &1.id)

    all_taxonomy_ids = genera_ids ++ section_ids

    species_count =
      SpeciesLink.count_species_for_taxonomies(all_taxonomy_ids)

    %{
      taxonomy: taxonomy,
      genera: genera,
      genera_count: length(genera),
      intermediates: intermediates,
      intermediates_count: length(intermediates),
      sections: sections,
      sections_count: length(sections),
      species_count: species_count,
      has_impact: genera != [] or intermediates != [] or sections != [] or species_count > 0
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

  def get_deletion_impact(%Taxonomy{id: id, type: "intermediate"} = taxonomy) do
    children = Tree.get_children(id)
    reparent_target = if taxonomy.parent_id, do: Tree.get_taxonomy!(taxonomy.parent_id), else: nil

    %{
      taxonomy: taxonomy,
      children: children,
      children_count: length(children),
      reparent_target: if(reparent_target, do: reparent_target.name),
      genera: [],
      genera_count: 0,
      sections: [],
      sections_count: 0,
      species_count: 0,
      has_impact: children != []
    }
  end

  def get_deletion_impact(%Taxonomy{id: id, type: "section"} = taxonomy) do
    species_count = SpeciesLink.count_species_for_taxonomies([id])

    %{
      taxonomy: taxonomy,
      genera: [],
      genera_count: 0,
      sections: [],
      sections_count: 0,
      species_count: species_count,
      has_impact: species_count > 0
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

    genera = Tree.list_genera_for_family(id)
    genera_ids = Enum.map(genera, & &1.id)

    intermediates = Tree.list_intermediates_for_family(id)

    sections = Tree.list_sections_for_family_tree(id)
    section_ids = Enum.map(sections, & &1.id)

    all_taxonomy_ids = genera_ids ++ section_ids

    species_count =
      SpeciesLink.count_species_for_taxonomies(all_taxonomy_ids)

    Logger.info(
      "Family #{taxonomy.name}: deleting #{length(genera)} genera, #{length(intermediates)} intermediates, #{length(sections)} sections, #{species_count} species"
    )

    result =
      Repo.transaction(fn ->
        delete_species_for_cascade(all_taxonomy_ids)
        Enum.each(sections, &Repo.delete!/1)
        Enum.each(genera, &Repo.delete!/1)
        # Intermediates ordered deepest-first for safe deletion
        Enum.each(intermediates, &Repo.delete!/1)
        Repo.delete!(taxonomy)

        %{
          taxonomy: taxonomy,
          genera: genera,
          genera_count: length(genera),
          intermediates: intermediates,
          intermediates_count: length(intermediates),
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

  def delete_taxonomy_cascade(%Taxonomy{id: id, type: "intermediate"} = taxonomy) do
    Logger.info("Collapse-upward delete for intermediate #{taxonomy.name} (id=#{id})")

    result =
      Repo.transaction(fn ->
        # Re-parent children to the intermediate's parent (collapse upward)
        {count, _} =
          from(t in Taxonomy, where: t.parent_id == ^id)
          |> Repo.update_all(set: [parent_id: taxonomy.parent_id])

        Logger.info(
          "Re-parented #{count} children from #{taxonomy.name} to parent #{taxonomy.parent_id}"
        )

        Repo.delete!(taxonomy)
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
      Gallformers.Species.delete_species(species)
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
