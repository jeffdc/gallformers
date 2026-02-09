defmodule Gallformers.Plants do
  @moduledoc """
  The Plants context.

  Manages plant species (Species with taxoncode='plant'). In the gall domain,
  these are referred to as "hosts" since galls form on them, but this context
  treats them as a type of Species.

  For gall↔host relationships, see `Gallformers.GallHosts`.
  For geographic range data, see `Gallformers.Ranges`.
  """

  import Ecto.Query

  alias Gallformers.Ranges
  alias Gallformers.Repo
  alias Gallformers.Species.{Abundance, Species}
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.TreeBuilder

  @topic "hosts"

  # ============================================
  # Explore Tree
  # ============================================

  @doc """
  Returns a hierarchical tree of host species organized by Family → Genus → Species.

  ## Options
  - `:key_style` - `:short` for `f-123` format (default), `:long` for `family-123` format
  """
  @spec get_hosts_tree(keyword()) :: [map()]
  def get_hosts_tree(opts \\ []) do
    fetch_host_tree_data()
    |> TreeBuilder.build_tree("/host/", opts)
  end

  defp fetch_host_tree_data do
    from(f in Taxonomy.Taxonomy,
      join: g in Taxonomy.Taxonomy,
      on: g.parent_id == f.id and g.type == "genus",
      join: st in "species_taxonomy",
      on: st.taxonomy_id == g.id,
      join: s in Species,
      on: s.id == st.species_id,
      where: f.type == "family" and f.description == "Plant" and s.taxoncode == "plant",
      order_by: [f.name, g.name, s.name],
      select: %{
        family_id: f.id,
        family_name: f.name,
        family_description: f.description,
        genus_id: g.id,
        genus_name: g.name,
        genus_description: g.description,
        species_id: s.id,
        species_name: s.name,
        undescribed: false
      }
    )
    |> Repo.all()
  end

  # ============================================
  # Query Functions
  # ============================================

  @doc """
  Returns all host (plant) species ordered by name.
  """
  @spec list_hosts() :: [map()]
  def list_hosts do
    from(s in Species,
      where: s.taxoncode == "plant",
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns paginated host species.
  """
  @spec list_hosts_paginated(integer(), integer()) :: [map()]
  def list_hosts_paginated(limit, offset) do
    from(s in Species,
      where: s.taxoncode == "plant",
      order_by: s.name,
      limit: ^limit,
      offset: ^offset,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of all host species.
  """
  @spec count_hosts() :: integer()
  def count_hosts do
    from(s in Species,
      where: s.taxoncode == "plant",
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets a host species by ID.
  """
  @spec get_host(integer()) :: map() | nil
  def get_host(id) do
    from(s in Species,
      left_join: a in Abundance,
      on: s.abundance_id == a.id,
      where: s.id == ^id and s.taxoncode == "plant",
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete,
        abundance_id: s.abundance_id,
        abundance_name: a.abundance,
        inserted_at: s.inserted_at,
        updated_at: s.updated_at
      }
    )
    |> Repo.one()
  end

  @doc """
  Gets a host species by name.
  """
  @spec get_host_by_name(String.t()) :: map() | nil
  def get_host_by_name(name) do
    from(s in Species,
      where: s.name == ^name and s.taxoncode == "plant",
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete
      }
    )
    |> Repo.one()
  end

  @doc """
  Gets a host species by ID as a Species struct (for changesets).
  """
  @spec get_host_species(integer()) :: Species.t() | nil
  def get_host_species(id) do
    from(s in Species,
      where: s.id == ^id and s.taxoncode == "plant"
    )
    |> Repo.one()
  end

  @doc """
  Searches for host species by name (case-insensitive).

  Supports multi-word queries where each word must match somewhere in the name
  or aliases. For example, "q alba" matches "Quercus alba".

  Used for typeahead/autocomplete functionality.
  Returns up to `limit` results ordered by name.
  """
  @spec search_hosts(String.t(), integer()) :: [map()]
  def search_hosts(query, limit \\ 20) when is_binary(query) do
    terms =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&"%#{&1}%")

    if terms == [] do
      []
    else
      search_hosts_with_terms(terms, limit)
    end
  end

  defp search_hosts_with_terms(terms, limit) do
    base_query =
      from(s in Species,
        left_join: als in "alias_species",
        on: als.species_id == s.id,
        left_join: a in "alias",
        on: a.id == als.alias_id,
        where: s.taxoncode == "plant",
        group_by: [s.id, s.name, s.datacomplete],
        order_by: s.name,
        limit: ^limit,
        select: %{
          id: s.id,
          name: s.name,
          datacomplete: s.datacomplete
        }
      )

    # Add a WHERE clause for each search term (all must match)
    query_with_terms =
      Enum.reduce(terms, base_query, fn term, q ->
        from([s, als, a] in q,
          where:
            fragment("lower(?) LIKE ?", s.name, ^term) or
              fragment("lower(?) LIKE ?", a.name, ^term)
        )
      end)

    hosts = Repo.all(query_with_terms)
    attach_aliases_batch(hosts)
  end

  # Batch-load aliases for multiple hosts in a single query (avoids N+1)
  defp attach_aliases_batch([]), do: []

  defp attach_aliases_batch(hosts) do
    host_ids = Enum.map(hosts, & &1.id)

    aliases_by_host =
      from(a in "alias",
        join: als in "alias_species",
        on: als.alias_id == a.id,
        where: als.species_id in ^host_ids,
        select: {als.species_id, a.name}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.map(hosts, fn host ->
      Map.put(host, :aliases, Map.get(aliases_by_host, host.id, []))
    end)
  end

  @doc """
  Searches host species by name for section assignment.
  Returns hosts that match the query.
  """
  @spec search_hosts_for_section(String.t(), integer()) :: [map()]
  def search_hosts_for_section(query, limit \\ 20) do
    search_pattern = "%#{String.downcase(query)}%"

    from(s in Species,
      where: s.taxoncode == "plant",
      where: fragment("lower(?) LIKE ?", s.name, ^search_pattern),
      order_by: s.name,
      limit: ^limit,
      select: %{
        id: s.id,
        name: s.name
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns a host with all related data for admin editing.
  """
  @spec get_host_for_edit(integer()) :: map() | nil
  def get_host_for_edit(id) do
    host = get_host(id)

    if host do
      taxonomy = Taxonomy.get_taxonomy_for_species(id)
      places = Ranges.get_places_for_host(id)
      aliases = get_aliases_for_host(id)

      host
      |> Map.put(:taxonomy, taxonomy)
      |> Map.put(:places, places)
      |> Map.put(:aliases, aliases)
    else
      nil
    end
  end

  # ============================================
  # PubSub
  # ============================================

  @doc """
  Subscribes to host changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, @topic)
  end

  @doc """
  Broadcasts a host change event.
  """
  @spec broadcast_change(map(), atom()) :: {:ok, map()}
  def broadcast_change(host, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, @topic, {event, host})
    {:ok, host}
  end

  defp broadcast({:ok, host}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, @topic, {event, host})
    {:ok, host}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end

  # ============================================
  # CRUD Operations
  # ============================================

  @doc """
  Returns a changeset for tracking host changes.
  """
  @spec change_host(Species.t(), map()) :: Ecto.Changeset.t()
  def change_host(%Species{} = host, attrs \\ %{}) do
    Species.changeset(host, Map.put(attrs, "taxoncode", "plant"))
  end

  @doc """
  Creates a new host species.
  """
  @spec create_host(map()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t()}
  def create_host(attrs) do
    attrs = Map.put(attrs, "taxoncode", "plant")

    result =
      %Species{}
      |> Species.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, species} ->
        Gallformers.Species.update_species_fts(species.id)
        broadcast(result, :host_created)

      {:error, _} ->
        result
    end
  end

  @doc """
  Updates a host species.
  """
  @spec update_host(Species.t(), map()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t()}
  def update_host(%Species{} = host, attrs) do
    result =
      host
      |> Species.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_host} ->
        Gallformers.Species.update_species_fts(updated_host.id)
        broadcast(result, :host_updated)

      {:error, _} ->
        result
    end
  end

  @doc """
  Deletes a host species and all associations.

  Performs a complete cleanup in the correct order:
  1. Deletes S3 images (before DB cascade removes image paths)
  2. Deletes FTS index entry
  3. Deletes the species (cascades to image rows, host relations, etc.)

  Returns {:ok, species} on success or {:error, reason} on failure.
  """
  @spec delete_host(integer()) ::
          {:ok, Species.t()} | {:error, :not_found | Ecto.Changeset.t() | term()}
  def delete_host(host_id) do
    case get_host_species(host_id) do
      nil ->
        {:error, :not_found}

      host ->
        Repo.transaction(fn -> do_delete_host(host) end)
        |> broadcast(:host_deleted)
    end
  end

  defp do_delete_host(host) do
    # 1. Delete S3 images first (before DB records are cascade deleted)
    Gallformers.Images.delete_images_from_s3_for_species(host.id)

    # 2. Delete from FTS index
    Gallformers.Species.delete_species_fts(host.id)

    # 3. Delete the species record (cascades to image rows, host relations, etc.)
    case Repo.delete(host) do
      {:ok, deleted} -> deleted
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # ============================================
  # Alias Management
  # ============================================

  @doc """
  Gets aliases for a host species (names only).
  """
  @spec get_aliases_for_host(integer()) :: [String.t()]
  def get_aliases_for_host(host_id) do
    from(a in "alias",
      join: als in "alias_species",
      on: als.alias_id == a.id,
      where: als.species_id == ^host_id,
      select: a.name
    )
    |> Repo.all()
  end

  @doc """
  Gets aliases for a host with full details (id, name, type).
  """
  @spec get_aliases_for_host_full(integer()) :: [map()]
  def get_aliases_for_host_full(host_id) do
    from(a in "alias",
      join: als in "alias_species",
      on: als.alias_id == a.id,
      where: als.species_id == ^host_id,
      select: %{id: a.id, name: a.name, type: a.type}
    )
    |> Repo.all()
  end

  @doc """
  Creates an alias for a host.
  Delegates to Species.create_alias_for_species/2.
  """
  @spec create_alias_for_host(integer(), map()) ::
          {:ok, Gallformers.Species.Alias.t()} | {:error, Ecto.Changeset.t()}
  def create_alias_for_host(host_id, alias_attrs) do
    Gallformers.Species.create_alias_for_species(host_id, alias_attrs)
  end

  @doc """
  Removes an alias from a host.
  Delegates to Species.remove_alias_from_species/2.
  """
  @spec remove_alias_from_host(integer(), integer()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def remove_alias_from_host(host_id, alias_id) do
    Gallformers.Species.remove_alias_from_species(host_id, alias_id)
  end

  # ============================================
  # Rename Support
  # ============================================

  @doc """
  Renames a host species, optionally adding the old name as an alias.

  Handles genus changes:
  - If genus unchanged: simple rename
  - If new genus exists: rename + update taxonomy link
  - If new genus doesn't exist: returns {:needs_genus_confirmation, info}
    so caller can show confirmation dialog before calling rename_host_with_new_genus/4
  """
  @spec rename_host(integer(), String.t(), boolean()) ::
          {:ok, Species.t()}
          | {:needs_genus_confirmation, map()}
          | {:error, :not_found | :name_exists | Ecto.Changeset.t()}
  def rename_host(host_id, new_name, add_alias? \\ false) do
    with {:ok, host} <- fetch_host_species(host_id),
         :ok <- check_name_available(new_name, host_id) do
      handle_rename(host, new_name, add_alias?)
    end
  end

  defp handle_rename(host, new_name, add_alias?) do
    old_genus = Taxonomy.extract_genus_from_name(host.name)
    new_genus = Taxonomy.extract_genus_from_name(new_name)

    if old_genus == new_genus do
      # No genus change - simple rename
      do_simple_rename(host, new_name, add_alias?)
    else
      # Genus is changing - check if new genus exists
      handle_genus_change(host, new_name, new_genus, add_alias?)
    end
  end

  defp handle_genus_change(host, new_name, new_genus_name, add_alias?) do
    case Taxonomy.get_taxonomy_by_name(new_genus_name, "genus") do
      nil ->
        # New genus doesn't exist - need confirmation from user
        current_taxonomy = Taxonomy.get_taxonomy_for_species(host.id)
        family_id = current_taxonomy && current_taxonomy.family_id
        family_name = current_taxonomy && current_taxonomy.family

        {:needs_genus_confirmation,
         %{
           host_id: host.id,
           old_name: host.name,
           new_name: new_name,
           new_genus: new_genus_name,
           family_id: family_id,
           family_name: family_name,
           add_alias: add_alias?
         }}

      existing_genus ->
        # New genus exists - rename and update link
        do_rename_with_genus_update(host, new_name, existing_genus.id, add_alias?)
    end
  end

  defp do_simple_rename(host, new_name, add_alias?) do
    with {:ok, updated_host} <- do_rename_host(host, new_name) do
      maybe_add_alias(host.id, host.name, add_alias?)
      broadcast({:ok, updated_host}, :host_updated)
    end
  end

  defp do_rename_with_genus_update(host, new_name, new_genus_id, add_alias?) do
    Repo.transaction(fn ->
      with {:ok, updated_host} <- do_rename_host(host, new_name),
           :ok <- Taxonomy.update_species_genus(host.id, new_genus_id) do
        maybe_add_alias(host.id, host.name, add_alias?)
        updated_host
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, updated_host} -> broadcast({:ok, updated_host}, :host_updated)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Renames a host and creates a new genus for it.

  Called after user confirms they want to create a new genus.
  Creates the genus under the specified family, then renames the host
  and links it to the new genus.
  """
  @spec rename_host_with_new_genus(integer(), String.t(), String.t(), integer(), boolean()) ::
          {:ok, Species.t()} | {:error, term()}
  def rename_host_with_new_genus(host_id, new_name, new_genus_name, family_id, add_alias?) do
    with {:ok, host} <- fetch_host_species(host_id),
         :ok <- check_name_available(new_name, host_id) do
      do_rename_with_new_genus(host, new_name, new_genus_name, family_id, add_alias?)
    end
  end

  defp do_rename_with_new_genus(host, new_name, new_genus_name, family_id, add_alias?) do
    Repo.transaction(fn ->
      with {:ok, new_genus} <- create_genus(new_genus_name, family_id),
           {:ok, updated_host} <- do_rename_host(host, new_name) do
        Taxonomy.update_species_genus(host.id, new_genus.id)
        maybe_add_alias(host.id, host.name, add_alias?)
        updated_host
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, updated_host} -> broadcast({:ok, updated_host}, :host_updated)
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_genus(name, family_id) do
    Taxonomy.create_taxonomy(%{name: name, type: "genus", parent_id: family_id})
  end

  defp fetch_host_species(host_id) do
    case get_host_species(host_id) do
      nil -> {:error, :not_found}
      host -> {:ok, host}
    end
  end

  defp check_name_available(new_name, host_id) do
    existing =
      from(s in Species,
        where: s.name == ^new_name and s.id != ^host_id
      )
      |> Repo.one()

    if existing, do: {:error, :name_exists}, else: :ok
  end

  defp do_rename_host(host, new_name) do
    host
    |> Species.changeset(%{name: new_name})
    |> Repo.update()
  end

  defp maybe_add_alias(host_id, old_name, true) do
    Gallformers.Species.create_alias_for_species(host_id, %{
      name: old_name,
      type: "scientific"
    })
  end

  defp maybe_add_alias(_host_id, _old_name, false), do: :ok
end
