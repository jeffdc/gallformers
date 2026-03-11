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

  alias Gallformers.Places
  alias Gallformers.Plants.HostTraits
  alias Gallformers.Ranges
  alias Gallformers.Repo
  alias Gallformers.Search.TextMatch
  alias Gallformers.Species.{Abundance, Species}
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.TreeBuilder
  alias Gallformers.Wcvp

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
    # Use recursive CTE to walk from genus up through any intermediate ranks
    # (subfamily, tribe, etc.) to find the ancestor family. A direct parent_id
    # join only works when genus is an immediate child of family.
    {:ok, %{rows: rows}} =
      Repo.query("""
      WITH RECURSIVE genus_to_family AS (
        SELECT g.id AS genus_id, g.name AS genus_name, g.description AS genus_description,
               g.parent_id AS current_parent_id
        FROM taxonomy g
        WHERE g.type = 'genus'

        UNION ALL

        SELECT gf.genus_id, gf.genus_name, gf.genus_description, t.parent_id
        FROM genus_to_family gf
        JOIN taxonomy t ON t.id = gf.current_parent_id
        WHERE t.type != 'family'
      )
      SELECT f.id, f.name, f.description,
             gf.genus_id, gf.genus_name, gf.genus_description,
             s.id, s.name
      FROM genus_to_family gf
      JOIN taxonomy f ON f.id = gf.current_parent_id AND f.type = 'family'
      JOIN species_taxonomy st ON st.taxonomy_id = gf.genus_id
      JOIN species s ON s.id = st.species_id AND s.taxoncode = 'plant'
      WHERE f.description = 'Plant'
      ORDER BY f.name, gf.genus_name, s.name
      """)

    Enum.map(rows, fn [fid, fname, fdesc, gid, gname, gdesc, sid, sname] ->
      %{
        family_id: fid,
        family_name: fname,
        family_description: fdesc,
        genus_id: gid,
        genus_name: gname,
        genus_description: gdesc,
        species_id: sid,
        species_name: sname,
        undescribed: false
      }
    end)
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
    terms = TextMatch.parse_terms(query)

    if terms == [] do
      []
    else
      normalized = query |> String.downcase() |> String.trim()
      search_hosts_with_terms(terms, normalized, limit)
    end
  end

  defp search_hosts_with_terms(terms, raw_query, limit) do
    prefix_pattern = "#{raw_query}%"

    # Relevance ranking: exact match (0) > prefix match (1) > contains (2)
    # MIN() picks the best rank across all aliases for a grouped host
    base_query =
      from(s in Species,
        left_join: als in "alias_species",
        on: als.species_id == s.id,
        left_join: a in "alias",
        on: a.id == als.alias_id,
        where: s.taxoncode == "plant",
        group_by: [s.id, s.name, s.datacomplete],
        order_by: [
          asc:
            fragment(
              """
              MIN(CASE
                WHEN lower(?) = ? OR lower(?) = ? THEN 0
                WHEN lower(?) LIKE ? OR lower(?) LIKE ? THEN 1
                ELSE 2
              END)
              """,
              s.name,
              ^raw_query,
              a.name,
              ^raw_query,
              s.name,
              ^prefix_pattern,
              a.name,
              ^prefix_pattern
            ),
          asc: s.name
        ],
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
    filter = TextMatch.build_filter(query, [:name])

    from(s in Species,
      where: s.taxoncode == "plant",
      where: ^filter,
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
  # Host Traits
  # ============================================

  @doc """
  Gets host traits for a species.

  Returns `nil` if no host traits record exists for the given species.
  """
  @spec get_host_traits(integer()) :: HostTraits.t() | nil
  def get_host_traits(species_id) do
    Repo.get(HostTraits, species_id)
  end

  @doc """
  Creates or updates host traits for a species.

  If no record exists for the species_id, inserts a new one.
  If one exists, updates it with the given attrs.
  """
  @spec upsert_host_traits(integer(), map()) ::
          {:ok, HostTraits.t()} | {:error, Ecto.Changeset.t()}
  def upsert_host_traits(species_id, attrs) do
    case Repo.get(HostTraits, species_id) do
      nil ->
        %HostTraits{species_id: species_id}
        |> HostTraits.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> HostTraits.changeset(attrs)
        |> Repo.update()
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
          link_new_host_taxonomy(host.id, params)
          host

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp link_new_host_taxonomy(host_id, params) do
    Taxonomy.link_species_taxonomy(
      host_id,
      params.taxonomy,
      params.genus_is_new,
      params.parent_id
    )

    if section_id = params[:selected_section_id] do
      Taxonomy.link_species_to_taxonomy(host_id, section_id)
    end

    for a <- params.aliases do
      create_alias_for_host(host_id, %{name: a.name, type: a.type})
    end
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
          maybe_upsert_host_traits(host.id, params[:host_traits])
          Gallformers.Species.touch(host.id)
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
         range_entries: range_entries,
         original_range_entries: original_range_entries,
         all_places: all_places
       }) do
    if range_entries != original_range_entries do
      place_code_to_id = Map.new(all_places, &{&1.code, &1.id})

      entries =
        Enum.map(range_entries, fn {code, %{precision: precision, distribution_type: dt}} ->
          {Map.get(place_code_to_id, code), precision, dt}
        end)
        |> Enum.reject(fn {id, _, _} -> is_nil(id) end)

      Ranges.update_host_places(host_id, entries)
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

  defp maybe_upsert_host_traits(_host_id, nil), do: :ok

  defp maybe_upsert_host_traits(host_id, traits) do
    case upsert_host_traits(host_id, traits) do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # Updates the species→section link in species_taxonomy when section changes.
  defp update_species_section_link(_species_id, same, same), do: :ok
  defp update_species_section_link(nil, _new, _old), do: :ok

  defp update_species_section_link(species_id, new_section_id, old_section_id) do
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

  # ============================================
  # Range Review
  # ============================================

  @doc """
  Lists hosts for range review with optional filters.

  ## Options

    * `:filter` - `:all | :confirmed | :unconfirmed` (default `:unconfirmed`)
    * `:wcvp_match` - `:all | :yes | :no` (default `:all`)
    * `:has_range` - `:all | :yes | :no` (default `:all`)
    * `:search` - string prefix match on species name (default `""`)
    * `:limit` - max results to return (default `50`)
    * `:offset` - number of results to skip (default `0`)

  Returns a list of maps with id, name, family_name, genus_name, range_count,
  wcvp_id, wcvp_synced_at, and range_confirmed.
  """
  @spec list_hosts_for_range_review(keyword()) :: [map()]
  def list_hosts_for_range_review(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    base_range_review_query(opts)
    |> group_by([s, ht, _hr, _st, _g, _f], [ht.wcvp_id, ht.wcvp_synced_at, ht.range_confirmed])
    |> order_by([s], s.name)
    |> limit(^limit)
    |> offset(^offset)
    |> select([s, ht, hr, _st, g, f], %{
      id: s.id,
      name: s.name,
      family_name: max(f.name),
      genus_name: max(g.name),
      range_count: count(hr.place_id),
      wcvp_id: ht.wcvp_id,
      wcvp_synced_at: ht.wcvp_synced_at,
      range_confirmed: ht.range_confirmed
    })
    |> Repo.all()
  end

  @doc """
  Returns the count of hosts matching range review filters.

  Accepts the same filter options as `list_hosts_for_range_review/1`
  (`:filter`, `:wcvp_match`, `:has_range`, `:search`) but ignores
  `:limit` and `:offset`.
  """
  @spec count_hosts_for_range_review(keyword()) :: non_neg_integer()
  def count_hosts_for_range_review(opts \\ []) do
    sub = base_range_review_query(opts) |> select([s], s.id)
    from(x in subquery(sub), select: count()) |> Repo.one()
  end

  defp base_range_review_query(opts) do
    filter = Keyword.get(opts, :filter, :unconfirmed)
    wcvp_match = Keyword.get(opts, :wcvp_match, :all)
    has_range = Keyword.get(opts, :has_range, :all)
    search = Keyword.get(opts, :search, "")
    wcvp_built_at = Keyword.get(opts, :wcvp_built_at)
    sync_status = Keyword.get(opts, :sync_status, :all)

    from(s in Species,
      left_join: ht in HostTraits,
      on: ht.species_id == s.id,
      left_join: hr in "host_range",
      on: hr.species_id == s.id,
      left_join: st in "species_taxonomy",
      on: st.species_id == s.id,
      left_join: g in "taxonomy",
      on: g.id == st.taxonomy_id and g.type == "genus",
      left_join: f in "taxonomy",
      on: f.id == g.parent_id and f.type == "family",
      where: s.taxoncode == "plant",
      group_by: [s.id, s.name]
    )
    |> apply_range_review_filter(filter, wcvp_built_at)
    |> apply_wcvp_match_filter(wcvp_match)
    |> apply_has_range_filter(has_range)
    |> apply_sync_status_filter(sync_status, wcvp_built_at)
    |> apply_search_filter(search)
  end

  defp apply_range_review_filter(query, :all, _wcvp_built_at), do: query

  defp apply_range_review_filter(query, :confirmed, _wcvp_built_at) do
    from([s, ht] in query, where: ht.range_confirmed == true)
  end

  defp apply_range_review_filter(query, :unconfirmed, nil) do
    from([s, ht] in query,
      where: is_nil(ht.range_confirmed) or ht.range_confirmed == false
    )
  end

  defp apply_range_review_filter(query, :unconfirmed, wcvp_built_at) do
    from([s, ht] in query,
      where:
        is_nil(ht.range_confirmed) or ht.range_confirmed == false or
          (not is_nil(ht.wcvp_synced_at) and ht.wcvp_synced_at < ^wcvp_built_at)
    )
  end

  defp apply_wcvp_match_filter(query, :all), do: query

  defp apply_wcvp_match_filter(query, :yes) do
    from([s, ht] in query, where: not is_nil(ht.wcvp_id) and ht.wcvp_id != "")
  end

  defp apply_wcvp_match_filter(query, :no) do
    from([s, ht] in query, where: is_nil(ht.wcvp_id) or ht.wcvp_id == "")
  end

  defp apply_has_range_filter(query, :all), do: query

  defp apply_has_range_filter(query, :yes) do
    from([s, _ht, hr] in query, having: count(hr.place_id) > 0)
  end

  defp apply_has_range_filter(query, :no) do
    from([s, _ht, hr] in query, having: count(hr.place_id) == 0)
  end

  defp apply_sync_status_filter(query, :all, _wcvp_built_at), do: query

  defp apply_sync_status_filter(query, :never, _wcvp_built_at) do
    from([s, ht] in query, where: is_nil(ht.wcvp_synced_at))
  end

  defp apply_sync_status_filter(query, :stale, nil), do: query

  defp apply_sync_status_filter(query, :stale, wcvp_built_at) do
    from([s, ht] in query,
      where: not is_nil(ht.wcvp_synced_at) and ht.wcvp_synced_at < ^wcvp_built_at
    )
  end

  defp apply_sync_status_filter(query, :current, nil) do
    from([s, ht] in query, where: not is_nil(ht.wcvp_synced_at))
  end

  defp apply_sync_status_filter(query, :current, wcvp_built_at) do
    from([s, ht] in query,
      where: not is_nil(ht.wcvp_synced_at) and ht.wcvp_synced_at >= ^wcvp_built_at
    )
  end

  defp apply_search_filter(query, ""), do: query
  defp apply_search_filter(query, nil), do: query

  defp apply_search_filter(query, search) do
    case TextMatch.parse_terms(search) do
      [] ->
        query

      terms ->
        Enum.reduce(terms, query, fn term, q ->
          from([s, ht, hr, st, g, f] in q,
            having:
              fragment("lower(?) LIKE ?", s.name, ^term) or
                fragment("lower(coalesce(max(?), '')) LIKE ?", g.name, ^term) or
                fragment("lower(coalesce(max(?), '')) LIKE ?", f.name, ^term)
          )
        end)
    end
  end

  @doc """
  Marks hosts as range-confirmed in bulk.

  For hosts with existing host_traits rows, updates them.
  For hosts without host_traits rows, creates them.

  Returns `{count, nil}` where count is the number of hosts confirmed.
  """
  @spec bulk_confirm_host_ranges([integer()]) :: {integer(), nil}
  def bulk_confirm_host_ranges([]), do: {0, nil}

  def bulk_confirm_host_ranges(species_ids) do
    # Find which species already have host_traits rows
    existing_ids =
      from(ht in HostTraits,
        where: ht.species_id in ^species_ids,
        select: ht.species_id
      )
      |> Repo.all()
      |> MapSet.new()

    # Update existing rows
    {updated, _} =
      from(ht in HostTraits,
        where: ht.species_id in ^species_ids
      )
      |> Repo.update_all(set: [range_confirmed: true])

    # Insert missing rows
    missing_ids = Enum.reject(species_ids, &MapSet.member?(existing_ids, &1))

    inserted =
      if missing_ids != [] do
        entries =
          Enum.map(missing_ids, fn id ->
            %{species_id: id, range_confirmed: true}
          end)

        {count, _} = Repo.insert_all(HostTraits, entries)
        count
      else
        0
      end

    {updated + inserted, nil}
  end

  @doc """
  Syncs a single host's range from WCVP data.

  Looks up the host's WCVP data by wcvp_id (or name-matches if no wcvp_id),
  converts TDWG codes to place entries, and updates the host's range.
  Updates wcvp_synced_at on success.

  Accepts optional `ref_data` map with preloaded `:tdwg_lookup` and
  `:place_code_to_id` to avoid reloading per call in bulk operations.

  Returns `{:ok, summary}` or `{:error, reason}`.
  """
  @spec sync_host_from_wcvp(integer(), map()) :: {:ok, map()} | {:error, String.t()}
  def sync_host_from_wcvp(species_id, ref_data \\ %{}) do
    host_traits = get_host_traits(species_id)
    species = Repo.get(Species, species_id)

    cond do
      is_nil(species) ->
        {:error, "Species not found"}

      # Has wcvp_id — sync directly
      host_traits && host_traits.wcvp_id not in [nil, ""] ->
        do_sync_host_from_wcvp(species_id, host_traits, ref_data)

      # No wcvp_id — try name matching
      true ->
        case Wcvp.Lookup.match_by_name(species.name, resolve_synonyms: true) do
          nil ->
            {:error, "No WCVP match found for #{species.name}"}

          wcvp_match ->
            # Store the link first
            {:ok, updated_traits} =
              upsert_host_traits(species_id, %{
                wcvp_id: wcvp_match.plant_name_id,
                powo_id: wcvp_match.powo_id
              })

            # Then sync range
            do_sync_host_from_wcvp(species_id, updated_traits, ref_data)
        end
    end
  end

  @doc """
  Returns preloaded reference data for bulk sync operations.

  Load once before calling `sync_host_from_wcvp/2` in a loop.
  """
  @spec load_sync_ref_data() :: map()
  def load_sync_ref_data do
    tdwg_lookup = Wcvp.Tdwg.load()
    all_places = Places.list_all_places()

    %{
      tdwg_lookup: tdwg_lookup,
      place_code_to_id: Map.new(all_places, &{&1.code, &1.id})
    }
  end

  defp do_sync_host_from_wcvp(species_id, host_traits, ref_data) do
    case Wcvp.Lookup.get(host_traits.wcvp_id) do
      nil ->
        {:error, "WCVP record not found for ID #{host_traits.wcvp_id}"}

      wcvp_data ->
        tdwg_lookup = Map.get_lazy(ref_data, :tdwg_lookup, &Wcvp.Tdwg.load/0)

        place_code_to_id =
          Map.get_lazy(ref_data, :place_code_to_id, fn ->
            Map.new(Places.list_all_places(), &{&1.code, &1.id})
          end)

        native_entries =
          Wcvp.Tdwg.convert_tdwg_codes(
            wcvp_data.native_distribution,
            tdwg_lookup
          )

        introduced_entries =
          Wcvp.Tdwg.convert_tdwg_codes(
            wcvp_data.introduced_distribution,
            tdwg_lookup
          )

        place_entries =
          build_sync_place_entries(native_entries, introduced_entries, place_code_to_id)

        Ranges.update_host_places(species_id, place_entries)

        now = DateTime.utc_now() |> DateTime.truncate(:second)
        upsert_host_traits(species_id, %{wcvp_synced_at: now})

        {:ok,
         %{
           native_count: length(native_entries),
           introduced_count: length(introduced_entries),
           total_places: length(place_entries)
         }}
    end
  end

  @doc """
  Computes a six-bucket diff between current host range and POWO/WCVP data.

  Takes:
  - `range_entries` — the unified map: `%{code => %{precision, distribution_type}}`
  - `native_codes` — MapSet of place codes POWO says are native (already converted from TDWG)
  - `introduced_codes` — MapSet of place codes POWO says are introduced (already converted from TDWG)

  Returns a map with six buckets based on the 3x3 state matrix:

  | Existing \\ POWO | Not present | Native           | Introduced               |
  |------------------|-------------|------------------|--------------------------|
  | Not present      | no-op       | add_native       | add_introduced           |
  | Native           | remove      | agree            | reclassify_to_introduced |
  | Introduced       | remove      | reclassify_to_native | agree                |
  """
  @spec compute_powo_diff(map(), MapSet.t(), MapSet.t()) :: map()
  def compute_powo_diff(range_entries, native_codes, introduced_codes) do
    current_codes = MapSet.new(Map.keys(range_entries))
    all_powo = MapSet.union(native_codes, introduced_codes)

    current_native =
      range_entries
      |> Enum.filter(fn {_, %{distribution_type: dt}} -> dt == "native" end)
      |> MapSet.new(fn {code, _} -> code end)

    current_introduced =
      range_entries
      |> Enum.filter(fn {_, %{distribution_type: dt}} -> dt == "introduced" end)
      |> MapSet.new(fn {code, _} -> code end)

    # Six buckets from the state matrix
    add_native = MapSet.difference(native_codes, current_codes)
    add_introduced = MapSet.difference(introduced_codes, current_codes)
    remove = MapSet.difference(current_codes, all_powo)
    reclassify_to_introduced = MapSet.intersection(current_native, introduced_codes)
    reclassify_to_native = MapSet.intersection(current_introduced, native_codes)

    agree_native = MapSet.intersection(current_native, native_codes)
    agree_introduced = MapSet.intersection(current_introduced, introduced_codes)
    agree_count = MapSet.size(agree_native) + MapSet.size(agree_introduced)

    has_changes =
      MapSet.size(add_native) > 0 or MapSet.size(add_introduced) > 0 or
        MapSet.size(remove) > 0 or MapSet.size(reclassify_to_introduced) > 0 or
        MapSet.size(reclassify_to_native) > 0

    %{
      add_native: MapSet.to_list(add_native),
      add_introduced: MapSet.to_list(add_introduced),
      remove: MapSet.to_list(remove),
      reclassify_to_introduced: MapSet.to_list(reclassify_to_introduced),
      reclassify_to_native: MapSet.to_list(reclassify_to_native),
      agree_count: agree_count,
      has_changes: has_changes
    }
  end

  defp build_sync_place_entries(native_entries, introduced_entries, place_code_to_id) do
    native =
      Enum.map(native_entries, fn %{code: code, precision: precision} ->
        {Map.get(place_code_to_id, code), precision, "native"}
      end)

    introduced =
      Enum.map(introduced_entries, fn %{code: code, precision: precision} ->
        {Map.get(place_code_to_id, code), precision, "introduced"}
      end)

    (native ++ introduced) |> Enum.reject(fn {id, _, _} -> is_nil(id) end)
  end
end
