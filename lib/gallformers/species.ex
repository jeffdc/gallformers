defmodule Gallformers.Species do
  @moduledoc """
  The Species context.

  Provides shared functions for working with species records regardless of type.
  For gall-specific logic, see `Gallformers.Galls`.
  For host/plant-specific logic, see `Gallformers.Plants`.
  """

  import Ecto.Query

  alias Gallformers.Images.Image
  alias Gallformers.Repo
  alias Gallformers.Species.{Abundance, Alias, Species}
  alias Gallformers.Taxonomy.TaxonName

  @doc """
  Returns all species.
  """
  @spec list_species() :: [Species.t()]
  def list_species do
    Repo.all(Species)
  end

  @doc """
  Gets a single species by ID.
  """
  @spec get_species(integer()) :: Species.t() | nil
  def get_species(id) do
    Repo.get(Species, id)
  end

  @doc """
  Gets a single species by ID, raising if not found.
  """
  @spec get_species!(integer()) :: Species.t()
  def get_species!(id) do
    Repo.get!(Species, id)
  end

  @doc """
  Returns species info for a list of IDs.

  Returns a list of maps with :id, :name, and :taxoncode, ordered by name.
  """
  @spec list_species_by_ids([integer()]) :: [map()]
  def list_species_by_ids(species_ids) when is_list(species_ids) do
    from(s in Species,
      where: s.id in ^species_ids,
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
  Enriches a list of species maps with common names and host/gall counts.

  Takes a list of maps with at least :id, :name, :taxoncode keys.
  Returns the same list with :common_name and :count added to each.

  Uses batch queries to avoid N+1 (3 queries total regardless of list size).
  """
  @spec enrich_with_common_names_and_counts([map()]) :: [map()]
  def enrich_with_common_names_and_counts([]), do: []

  def enrich_with_common_names_and_counts(species_list) do
    species_ids = Enum.map(species_list, & &1.id)

    # Batch fetch all aliases (1 query)
    aliases_map = get_aliases_for_species_batch(species_ids)

    # Separate galls from hosts for counting
    {galls, hosts} = Enum.split_with(species_list, fn s -> s.taxoncode == "gall" end)
    gall_ids = Enum.map(galls, & &1.id)
    host_ids = Enum.map(hosts, & &1.id)

    # Batch fetch counts (2 queries)
    host_counts = Gallformers.GallHosts.get_host_counts_for_galls(gall_ids)
    gall_counts = Gallformers.GallHosts.get_gall_counts_for_hosts(host_ids)

    counts = Map.merge(host_counts, gall_counts)

    Enum.map(species_list, fn species ->
      aliases = Map.get(aliases_map, species.id, [])
      common_alias = Enum.find(aliases, fn a -> a.type == "common" end)

      species
      |> Map.put(:common_name, common_alias && common_alias.name)
      |> Map.put(:count, Map.get(counts, species.id, 0))
    end)
  end

  @doc """
  Gets all images for a species, ordered by sort_order.
  """
  @spec get_images_for_species(integer()) :: [map()]
  def get_images_for_species(species_id) do
    from(i in Image,
      left_join: src in assoc(i, :source),
      where: i.species_id == ^species_id,
      order_by: [asc: i.sort_order, asc: i.id],
      select: %{
        id: i.id,
        path: i.path,
        sort_order: i.sort_order,
        creator: i.creator,
        attribution: i.attribution,
        sourcelink: i.sourcelink,
        license: i.license,
        licenselink: i.licenselink,
        caption: i.caption,
        source_title: src.title,
        uploader: i.uploader,
        lastchangedby: i.lastchangedby
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets aliases for a species.
  """
  @spec get_aliases_for_species(integer()) :: [map()]
  def get_aliases_for_species(species_id) do
    from(a in Alias,
      join: als in "alias_species",
      on: als.alias_id == a.id,
      where: als.species_id == ^species_id,
      select: %{
        id: a.id,
        name: a.name,
        type: a.type,
        description: a.description
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets aliases for multiple species in a single query (batch version).

  Returns a map of species_id => [%{id, name, type, description}].
  """
  @spec get_aliases_for_species_batch([integer()]) :: %{integer() => [map()]}
  def get_aliases_for_species_batch([]), do: %{}

  def get_aliases_for_species_batch(species_ids) do
    from(a in Alias,
      join: als in "alias_species",
      on: als.alias_id == a.id,
      where: als.species_id in ^species_ids,
      select: %{
        species_id: als.species_id,
        id: a.id,
        name: a.name,
        type: a.type,
        description: a.description
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.species_id, fn row ->
      %{id: row.id, name: row.name, type: row.type, description: row.description}
    end)
  end

  @doc """
  Returns all abundance options.
  """
  @spec list_abundances() :: [Abundance.t()]
  def list_abundances do
    Repo.all(Abundance)
  end

  @doc """
  Gets an abundance by ID.
  """
  @spec get_abundance(integer()) :: Abundance.t() | nil
  def get_abundance(id) do
    Repo.get(Abundance, id)
  end

  # ============================================
  # Search Functions
  # ============================================

  @doc """
  Searches species by name or alias using ILIKE matching.

  This is the primary search function. Supports multi-word queries
  where each word must match somewhere in the name or aliases.
  """
  @spec search_species(String.t(), integer()) :: [map()]
  def search_species(query, limit \\ 100) when is_binary(query) do
    search_species_like_impl(query, limit)
  end

  # LIKE-based search implementation (fallback for mid-word matches)
  defp search_species_like_impl(query, limit) do
    terms =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&"%#{&1}%")

    if terms == [] do
      []
    else
      search_species_with_terms(terms, limit)
    end
  end

  defp search_species_with_terms(terms, limit) do
    base_query =
      from(s in Species,
        left_join: als in "alias_species",
        on: als.species_id == s.id,
        left_join: a in "alias",
        on: a.id == als.alias_id,
        left_join: ab in Abundance,
        on: s.abundance_id == ab.id,
        group_by: [s.id, s.name, s.taxoncode, s.datacomplete, ab.abundance],
        order_by: s.name,
        limit: ^limit,
        select: %{
          id: s.id,
          name: s.name,
          taxoncode: s.taxoncode,
          datacomplete: s.datacomplete,
          abundance_name: ab.abundance
        }
      )

    # Add WHERE clause for each search term (all must match)
    Enum.reduce(terms, base_query, fn term, q ->
      from([s, als, a, ab] in q,
        where:
          ilike(s.name, ^term) or
            ilike(a.name, ^term)
      )
    end)
    |> Repo.all()
  end

  @doc """
  Searches species using ILIKE for substring matches.

  Use this directly when you specifically need ILIKE matching
  (e.g., searching for a substring in the middle of a name).
  """
  @spec search_species_like(String.t(), integer()) :: [map()]
  def search_species_like(query, limit \\ 100) when is_binary(query) do
    search_species_like_impl(query, limit)
  end

  @doc """
  Searches species by name using ILIKE matching.
  Used for typeahead when selecting hosts.
  """
  @spec search_species_by_name(String.t(), String.t() | nil, integer()) :: [map()]
  def search_species_by_name(query, taxoncode \\ nil, limit \\ 20) do
    search_species_by_name_like(query, taxoncode, limit)
  end

  # ILIKE-based name search
  defp search_species_by_name_like(query, taxoncode, limit) do
    search_term = "%#{String.downcase(query)}%"

    base_query =
      from(s in Species,
        where: ilike(s.name, ^search_term),
        order_by: s.name,
        limit: ^limit,
        select: %{
          id: s.id,
          name: s.name,
          taxoncode: s.taxoncode
        }
      )

    query =
      if taxoncode do
        from(s in base_query, where: s.taxoncode == ^taxoncode)
      else
        base_query
      end

    Repo.all(query)
  end

  # ============================================
  # Species Edit / Admin
  # ============================================

  @doc """
  Returns a changeset for tracking species changes.
  """
  @spec change_species(Species.t(), map()) :: Ecto.Changeset.t()
  def change_species(%Species{} = species, attrs \\ %{}) do
    Species.changeset(species, attrs)
  end

  @doc """
  Creates a species.
  """
  @spec create_species(map()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t()}
  def create_species(attrs \\ %{}) do
    result =
      %Species{}
      |> Species.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _species} ->
        broadcast(result, :species_created)

      {:error, _} ->
        result
    end
  end

  @doc """
  Updates a species.
  """
  @spec update_species(Species.t(), map()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t()}
  def update_species(%Species{} = species, attrs) do
    result =
      species
      |> Species.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _updated_species} ->
        broadcast(result, :species_updated)

      {:error, _} ->
        result
    end
  end

  @doc """
  Updates the `updated_at` timestamp on a species without changing any other fields.
  """
  @spec touch(integer()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t()}
  def touch(species_id) do
    Species
    |> Repo.get!(species_id)
    |> Ecto.Changeset.change(%{updated_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  @doc """
  Checks if a species name already exists.
  """
  @spec species_name_exists?(String.t()) :: boolean()
  def species_name_exists?(name) do
    from(s in Species, where: s.name == ^name)
    |> Repo.exists?()
  end

  @doc """
  Finds species that have an alias matching the given name (case-insensitive).

  Returns a list of maps with species info and alias type, useful for warning
  admins when a new species name collides with an existing alias.
  """
  @spec find_species_with_alias(String.t()) :: [map()]
  def find_species_with_alias(name) do
    from(a in Alias,
      join: s in assoc(a, :species),
      where: fragment("lower(?) = lower(?)", a.name, ^name),
      select: %{
        species_id: s.id,
        species_name: s.name,
        taxoncode: s.taxoncode,
        alias_type: a.type
      }
    )
    |> Repo.all()
  end

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
    species = get_species!(species_id)

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

  @doc """
  Deletes a species and all associated data.

  Performs a complete cleanup in the correct order:
  1. Deletes S3 images (before DB cascade removes image paths)
  2. Deletes the species (cascades to image rows, hosts, aliases, etc.)

  Returns {:ok, species} on success or {:error, reason} on failure.
  """
  @spec delete_species(Species.t()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_species(%Species{} = species) do
    Repo.transaction(fn ->
      # 1. Delete S3 images first (before DB records are cascade deleted)
      Gallformers.Images.delete_images_from_s3_for_species(species.id)

      # 2. Collect alias IDs before deletion (CASCADE will remove alias_species rows)
      alias_ids =
        from(als in "alias_species", where: als.species_id == ^species.id, select: als.alias_id)
        |> Repo.all()

      # 3. Delete the species record (cascades to gall_traits, host_traits,
      #    image rows, host relations, alias_species, etc.)
      case Repo.delete(species) do
        {:ok, deleted} ->
          # 4. Clean up aliases that no longer have any species links
          delete_orphaned_aliases(alias_ids)
          deleted

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> broadcast(:species_deleted)
  end

  # Alias management

  @doc """
  Creates an alias and associates it with a species.
  """
  @spec create_alias_for_species(integer(), map()) ::
          {:ok, Gallformers.Species.Alias.t()} | {:error, Ecto.Changeset.t()}
  def create_alias_for_species(species_id, alias_attrs) do
    result =
      Repo.transaction(fn ->
        # Create the alias
        alias_changeset =
          %Alias{}
          |> Ecto.Changeset.cast(alias_attrs, [:name, :type, :description])
          |> Ecto.Changeset.validate_required([:name, :type])

        case Repo.insert(alias_changeset) do
          {:ok, new_alias} ->
            # Link to species
            Repo.insert_all("alias_species", [
              %{alias_id: new_alias.id, species_id: species_id}
            ])

            new_alias

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    broadcast(result, :species_updated)
  end

  @doc """
  Removes an alias from a species.
  """
  @spec remove_alias_from_species(integer(), integer()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def remove_alias_from_species(species_id, alias_id) do
    from(als in "alias_species",
      where: als.species_id == ^species_id and als.alias_id == ^alias_id
    )
    |> Repo.delete_all()

    # Delete the alias if it has no remaining species links
    delete_orphaned_aliases([alias_id])

    broadcast({:ok, %{id: species_id}}, :species_updated)
  end

  @doc """
  Subscribes to species changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "species")
  end

  # Deletes alias records that have no remaining alias_species links.
  # Aliases can be shared across species (rare but possible), so we only
  # delete those with zero remaining links.
  defp delete_orphaned_aliases([]), do: :ok

  defp delete_orphaned_aliases(alias_ids) do
    from(a in "alias",
      where:
        a.id in ^alias_ids and
          a.id not in subquery(from(als in "alias_species", select: als.alias_id))
    )
    |> Repo.delete_all()

    :ok
  end

  defp broadcast({:ok, species}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "species", {event, species})
    {:ok, species}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
