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
  # Composite Save Operations
  # ============================================

  @doc """
  Creates a new host species with all associations in a single transaction.

  Handles species creation, taxonomy linking, and aliases.

  ## Params

    * `:species_attrs` - Map of species attributes (name, taxoncode, etc.)
    * `:taxonomy` - Taxonomy map with genus info
    * `:genus_is_new` - Boolean, whether to create a new genus
    * `:parent_id` - Family or section ID for taxonomy linking
    * `:aliases` - List of alias maps with `:name` and `:type`

  Returns `{:ok, species}` or `{:error, changeset | reason}`.
  """
  @spec create_host_with_associations(map()) ::
          {:ok, Species.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_host_with_associations(params) do
    Repo.transaction(fn ->
      case create_host(params.species_attrs) do
        {:ok, host} ->
          Taxonomy.link_species_taxonomy(
            host.id,
            params.taxonomy,
            params.genus_is_new,
            params.parent_id
          )

          for a <- params.aliases do
            create_alias_for_host(host.id, %{name: a.name, type: a.type})
          end

          host

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a host species with all associations in a single transaction.

  Handles species update, alias changes, place changes, and section updates.

  ## Params

    * `:species_attrs` - Map of species attributes to update
    * `:alias_changes` - Tuple `{to_add, to_remove}` from DeferredChanges
    * `:place_changes` - Map with `:original_places`, `:current_places`, `:all_places`
    * `:section_update` - Map with `:genus_id`, `:selected_section_id`, `:section_id`, `:family_id`

  Returns `{:ok, species}` or `{:error, changeset | reason}`.
  """
  @spec update_host_with_associations(Species.t(), map()) ::
          {:ok, Species.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_host_with_associations(host, params) do
    {aliases_to_add, aliases_to_remove} = params.alias_changes

    Repo.transaction(fn ->
      case update_host(host, params.species_attrs) do
        {:ok, updated_host} ->
          save_alias_changes(host.id, aliases_to_add, aliases_to_remove)
          save_place_changes(host.id, params.place_changes)
          maybe_update_section(params.section_update)
          updated_host

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp save_alias_changes(host_id, to_add, to_remove) do
    for alias_id <- to_remove do
      Gallformers.Species.remove_alias_from_species(host_id, alias_id)
    end

    for a <- to_add do
      Gallformers.Species.create_alias_for_species(host_id, %{name: a.name, type: a.type})
    end
  end

  defp save_place_changes(host_id, %{
         original_places: original_places,
         current_places: current_places,
         all_places: all_places
       }) do
    place_code_to_id = Map.new(all_places, &{&1.code, &1.id})

    original_set = MapSet.new(original_places)
    current_set = MapSet.new(current_places)

    if original_set != current_set do
      place_ids =
        Enum.map(current_places, &Map.get(place_code_to_id, &1)) |> Enum.reject(&is_nil/1)

      Ranges.update_host_places(host_id, place_ids)
    end
  end

  defp maybe_update_section(%{genus_id: _genus_id} = section_update) do
    # Only update the species→section link in species_taxonomy, not genus.parent_id.
    # Sections are children of genera (Family → Genus → Section).
    update_species_section_link(
      section_update[:species_id],
      section_update.selected_section_id,
      section_update.section_id
    )
  end

  defp maybe_update_section(_), do: :ok

  # Updates the species→section link in species_taxonomy when section changes.
  defp update_species_section_link(_species_id, same, same), do: :ok
  defp update_species_section_link(nil, _new, _old), do: :ok

  defp update_species_section_link(species_id, new_section_id, old_section_id) do
    import Ecto.Query

    # Remove old section link if any
    if old_section_id do
      from(st in "species_taxonomy",
        where: st.species_id == ^species_id and st.taxonomy_id == ^old_section_id
      )
      |> Repo.delete_all()
    end

    # Add new section link if any
    if new_section_id do
      Taxonomy.link_species_to_taxonomy(species_id, new_section_id)
    end

    :ok
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
end
