defmodule Gallformers.Hosts do
  @moduledoc """
  The Hosts context.

  Provides functions for working with host plants and their relationships to galls.
  """

  import Ecto.Query

  alias Gallformers.Hosts.Host
  alias Gallformers.Repo
  alias Gallformers.Species.{Abundance, GallTraits, Species}

  @doc """
  Returns all host species ordered by name.
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
        abundance_name: a.abundance
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
  Gets all hosts for a gall species.

  Returns a list of maps with host_relation_id, host_species_id, and host_name.
  """
  @spec get_hosts_for_gall(integer()) :: [map()]
  def get_hosts_for_gall(gall_species_id) do
    from(h in Host,
      join: s in Species,
      on: h.host_species_id == s.id,
      where: h.gall_species_id == ^gall_species_id,
      select: %{
        host_relation_id: h.id,
        host_species_id: s.id,
        host_name: s.name
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets all galls for a host species.

  Returns a list of maps with gall info.
  """
  @spec get_galls_for_host(integer()) :: [map()]
  def get_galls_for_host(host_species_id) do
    from(h in Host,
      join: s in Species,
      on: h.gall_species_id == s.id,
      left_join: gt in GallTraits,
      on: gt.species_id == s.id,
      where: h.host_species_id == ^host_species_id,
      select: %{
        id: s.id,
        name: s.name,
        undescribed: gt.undescribed,
        datacomplete: s.datacomplete
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets hosts for a Place with their aliases.
  """
  def get_hosts_for_place(place_id) do
    from(s in Species,
      join: hr in "host_range",
      on: hr.species_id == s.id,
      left_join: als in "alias_species",
      on: als.species_id == s.id,
      left_join: a in "alias",
      on: a.id == als.alias_id,
      where: hr.place_id == ^place_id and s.taxoncode == "plant",
      group_by: [s.id, s.name],
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        aliases: fragment("GROUP_CONCAT(?, ', ')", a.name)
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets place codes for a host species (range data).
  """
  @spec get_places_for_host(integer()) :: [String.t()]
  def get_places_for_host(host_species_id) do
    from(hr in "host_range",
      join: p in "place",
      on: hr.place_id == p.id,
      where: hr.species_id == ^host_species_id,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets place codes for a gall species via its hosts.
  """
  @spec get_places_for_gall(integer()) :: [String.t()]
  def get_places_for_gall(gall_species_id) do
    from(p in "place",
      join: hr in "host_range",
      on: hr.place_id == p.id,
      join: h in Host,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id == ^gall_species_id,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets place codes for a list of host species IDs.

  Returns the union of all places where any of the hosts occur.
  Used for computing gall range from a local/pending list of hosts.
  """
  @spec get_places_for_host_species_ids([integer()]) :: [String.t()]
  def get_places_for_host_species_ids([]), do: []

  def get_places_for_host_species_ids(host_species_ids) do
    from(p in "place",
      join: hr in "host_range",
      on: hr.place_id == p.id,
      where: hr.species_id in ^host_species_ids,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets excluded place codes for a gall species (direct range exclusions).
  """
  @spec get_excluded_places_for_gall(integer()) :: [String.t()]
  def get_excluded_places_for_gall(gall_species_id) do
    from(p in "place",
      join: gre in "gall_range_exclusion",
      on: gre.place_id == p.id,
      where: gre.species_id == ^gall_species_id,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Searches for host species by name (case-insensitive).

  Supports multi-word queries where each word must match somewhere in the name.
  For example, "q alba" matches "Quercus alba".

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
  Gets aliases for a host species.
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
  Returns a host with all related data for admin editing.
  """
  @spec get_host_for_edit(integer()) :: map() | nil
  def get_host_for_edit(id) do
    host = get_host(id)

    if host do
      taxonomy = Gallformers.Taxonomy.get_taxonomy_for_species(id)
      places = get_places_for_host(id)
      aliases = get_aliases_for_host(id)

      host
      |> Map.put(:taxonomy, taxonomy)
      |> Map.put(:places, places)
      |> Map.put(:aliases, aliases)
    else
      nil
    end
  end

  @doc """
  Subscribes to host changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "hosts")
  end

  @doc """
  Broadcasts a host change event.
  """
  @spec broadcast_change(map(), atom()) :: {:ok, map()}
  def broadcast_change(host, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "hosts", {event, host})
    {:ok, host}
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

    %Species{}
    |> Species.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:host_created)
  end

  @doc """
  Updates a host species.
  """
  @spec update_host(Species.t(), map()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t()}
  def update_host(%Species{} = host, attrs) do
    host
    |> Species.changeset(attrs)
    |> Repo.update()
    |> broadcast(:host_updated)
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
  # Place/Range Management
  # ============================================

  @doc """
  Gets place IDs (not codes) for a host species.
  """
  @spec get_place_ids_for_host(integer()) :: [integer()]
  def get_place_ids_for_host(host_species_id) do
    from(hr in "host_range",
      where: hr.species_id == ^host_species_id,
      select: hr.place_id
    )
    |> Repo.all()
  end

  @doc """
  Adds a place to a host's range.
  """
  @spec add_place_to_host(integer(), integer()) :: {:ok, map()}
  def add_place_to_host(host_species_id, place_id) do
    Repo.insert_all(
      "host_range",
      [%{species_id: host_species_id, place_id: place_id}],
      on_conflict: :nothing
    )

    broadcast({:ok, %{id: host_species_id}}, :host_updated)
  end

  @doc """
  Removes a place from a host's range.
  """
  @spec remove_place_from_host(integer(), integer()) :: {:ok, map()}
  def remove_place_from_host(host_species_id, place_id) do
    from(hr in "host_range",
      where: hr.species_id == ^host_species_id and hr.place_id == ^place_id
    )
    |> Repo.delete_all()

    broadcast({:ok, %{id: host_species_id}}, :host_updated)
  end

  @doc """
  Toggles a place in a host's range (add if not present, remove if present).
  Returns {:added, place_id} or {:removed, place_id}.
  """
  @spec toggle_place_for_host(integer(), integer()) :: {:added | :removed, integer()}
  def toggle_place_for_host(host_species_id, place_id) do
    existing =
      from(hr in "host_range",
        where: hr.species_id == ^host_species_id and hr.place_id == ^place_id,
        select: count()
      )
      |> Repo.one()

    if existing > 0 do
      remove_place_from_host(host_species_id, place_id)
      {:removed, place_id}
    else
      add_place_to_host(host_species_id, place_id)
      {:added, place_id}
    end
  end

  @doc """
  Bulk updates all places for a host (replaces existing).
  """
  @spec update_host_places(integer(), [integer()]) :: {:ok, map()}
  def update_host_places(host_species_id, place_ids) do
    Repo.transaction(fn ->
      # Delete existing
      from(hr in "host_range",
        where: hr.species_id == ^host_species_id
      )
      |> Repo.delete_all()

      # Insert new
      if place_ids != [] do
        entries = Enum.map(place_ids, &%{species_id: host_species_id, place_id: &1})
        Repo.insert_all("host_range", entries)
      end

      :ok
    end)

    broadcast({:ok, %{id: host_species_id}}, :host_updated)
  end

  # ============================================
  # Alias Management (wrappers for convenience)
  # ============================================

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

  alias Gallformers.Taxonomy

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

  defp broadcast({:ok, host}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "hosts", {event, host})
    {:ok, host}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end

  # ============================================
  # Gall Range Exclusion Management
  # ============================================
  #
  # NOTE: For galls, the gall_range_exclusion table stores EXCLUSIONS (places where
  # the gall does NOT occur even though hosts exist there). This is different
  # from hosts, where the host_range table stores places where the host EXISTS.
  #
  # Gall effective range = (union of all host places) - (excluded places)
  #

  @doc """
  Gets excluded place IDs (not codes) for a gall species.
  """
  @spec get_excluded_place_ids_for_gall(integer()) :: [integer()]
  def get_excluded_place_ids_for_gall(gall_species_id) do
    from(gre in "gall_range_exclusion",
      where: gre.species_id == ^gall_species_id,
      select: gre.place_id
    )
    |> Repo.all()
  end

  @doc """
  Bulk updates all range exclusions for a gall (replaces existing).

  Takes a list of place IDs that should be excluded from the gall's range.
  """
  @spec set_range_exclusions_for_gall(integer(), [integer()]) :: :ok
  def set_range_exclusions_for_gall(gall_species_id, place_ids) do
    Repo.transaction(fn ->
      # Delete existing exclusions
      from(gre in "gall_range_exclusion",
        where: gre.species_id == ^gall_species_id
      )
      |> Repo.delete_all()

      # Insert new exclusions
      if place_ids != [] do
        entries = Enum.map(place_ids, &%{species_id: gall_species_id, place_id: &1})
        Repo.insert_all("gall_range_exclusion", entries)
      end

      :ok
    end)

    :ok
  end

  @doc """
  Toggles a place exclusion for a gall (add if not excluded, remove if excluded).
  Returns {:added, place_id} or {:removed, place_id}.

  Note: "added" means the place is now EXCLUDED from the gall's range.
  """
  @spec toggle_exclusion_for_gall(integer(), integer()) :: {:added | :removed, integer()}
  def toggle_exclusion_for_gall(gall_species_id, place_id) do
    existing =
      from(gre in "gall_range_exclusion",
        where: gre.species_id == ^gall_species_id and gre.place_id == ^place_id,
        select: count()
      )
      |> Repo.one()

    if existing > 0 do
      # Remove exclusion (place is now in range)
      from(gre in "gall_range_exclusion",
        where: gre.species_id == ^gall_species_id and gre.place_id == ^place_id
      )
      |> Repo.delete_all()

      {:removed, place_id}
    else
      # Add exclusion (place is now excluded)
      Repo.insert_all(
        "gall_range_exclusion",
        [%{species_id: gall_species_id, place_id: place_id}],
        on_conflict: :nothing
      )

      {:added, place_id}
    end
  end

  @doc """
  Gets the union of all host places for a gall as place IDs (not codes).
  Used for computing which places can potentially be excluded.
  """
  @spec get_host_place_ids_for_gall(integer()) :: [integer()]
  def get_host_place_ids_for_gall(gall_species_id) do
    from(hr in "host_range",
      join: h in Host,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id == ^gall_species_id,
      distinct: true,
      select: hr.place_id
    )
    |> Repo.all()
  end

  @doc """
  Gets a place ID by its code.
  """
  @spec get_place_id_by_code(String.t()) :: integer() | nil
  def get_place_id_by_code(code) do
    from(p in "place",
      where: p.code == ^code,
      select: p.id
    )
    |> Repo.one()
  end
end
