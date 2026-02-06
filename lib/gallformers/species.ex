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
  alias Gallformers.Search.Ranking
  alias Gallformers.Species.{Abundance, Alias, Species}
  require Logger

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
  Searches species by name or alias using FTS5 for fast prefix matching.
  Falls back to LIKE search for mid-word matches that FTS5 misses.

  This is the primary search function - it tries FTS5 first for speed
  and relevance ranking, then falls back to LIKE for edge cases.
  """
  @spec search_species(String.t(), integer()) :: [map()]
  def search_species(query, limit \\ 100) when is_binary(query) do
    fts_results = search_species_fts(query, limit)

    if Enum.empty?(fts_results) do
      # Fall back to LIKE for mid-word matches
      search_species_like_impl(query, limit)
    else
      fts_results
    end
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
          fragment("lower(?) LIKE ?", s.name, ^term) or
            fragment("lower(?) LIKE ?", a.name, ^term)
      )
    end)
    |> Repo.all()
  end

  # ============================================
  # FTS5 Full-Text Search Functions
  # ============================================

  @doc """
  Searches species using FTS5 full-text search with bm25() ranking.

  Supports prefix matching (e.g., "qu alba" matches "Quercus alba").
  Returns results ranked by relevance.
  """
  @spec search_species_fts(String.t(), integer()) :: [map()]
  def search_species_fts(query, limit \\ 100) when is_binary(query) do
    sanitized = sanitize_fts_query(query)

    if sanitized == "" do
      []
    else
      # Add * suffix to each term for prefix matching
      search_terms = Ranking.parse_query(sanitized)
      fts_query = Enum.map_join(search_terms, " ", &"#{&1}*")

      sql = """
      SELECT f.species_id, s.name, s.taxoncode, s.datacomplete, a.abundance as abundance_name
      FROM species_fts f
      JOIN species s ON s.id = f.species_id
      LEFT JOIN abundance a ON s.abundance_id = a.id
      WHERE species_fts MATCH ?
      ORDER BY bm25(species_fts)
      LIMIT ?
      """

      case Repo.query(sql, [fts_query, limit]) do
        {:ok, %{rows: rows}} ->
          rows
          |> Enum.map(&transform_species_fts_row/1)
          |> Ranking.add_scores_and_sort(search_terms)

        {:error, error} ->
          Logger.warning("FTS query failed: #{inspect(error)}, query: #{fts_query}")
          []
      end
    end
  end

  defp transform_species_fts_row([id, name, taxoncode, datacomplete, abundance_name]) do
    %{
      id: id,
      name: name,
      taxoncode: taxoncode,
      datacomplete: datacomplete == 1,
      abundance_name: abundance_name
    }
  end

  @doc """
  Searches species using LIKE for mid-word matches.

  Use this directly when you specifically need LIKE matching
  (e.g., searching for a substring in the middle of a name).
  """
  @spec search_species_like(String.t(), integer()) :: [map()]
  def search_species_like(query, limit \\ 100) when is_binary(query) do
    search_species_like_impl(query, limit)
  end

  @doc """
  Sanitizes a query string for FTS5 MATCH syntax.

  Escapes special FTS5 characters: - " * : ^ ( )
  """
  @spec sanitize_fts_query(String.t()) :: String.t()
  def sanitize_fts_query(query) when is_binary(query) do
    query
    |> String.replace(~r/["\-*:^()]+/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Updates the FTS index entry for a single species.

  Call this after updating a species name or aliases.
  """
  @spec update_species_fts(integer()) :: :ok | {:error, any()}
  def update_species_fts(species_id) do
    # Execute as two separate statements since SQLite doesn't support multiple
    # statements in a single query
    with {:ok, _} <- Repo.query("DELETE FROM species_fts WHERE species_id = ?", [species_id]),
         {:ok, _} <-
           Repo.query(
             """
             INSERT INTO species_fts(species_id, name, aliases)
             SELECT s.id, s.name, COALESCE(GROUP_CONCAT(a.name, ' '), '')
             FROM species s
             LEFT JOIN alias_species als ON als.species_id = s.id
             LEFT JOIN alias a ON a.id = als.alias_id
             WHERE s.id = ?
             GROUP BY s.id
             """,
             [species_id]
           ) do
      :ok
    end
  end

  @doc """
  Removes a species from the FTS index.

  Call this before deleting a species.
  """
  @spec delete_species_fts(integer()) :: :ok | {:error, any()}
  def delete_species_fts(species_id) do
    case Repo.query("DELETE FROM species_fts WHERE species_id = ?", [species_id]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Rebuilds the entire FTS index from scratch.

  Use this for maintenance or after bulk data changes.
  """
  @spec rebuild_species_fts() :: :ok | {:error, any()}
  def rebuild_species_fts do
    with {:ok, _} <- Repo.query("DELETE FROM species_fts", []),
         {:ok, _} <-
           Repo.query(
             """
             INSERT INTO species_fts(species_id, name, aliases)
             SELECT s.id, s.name, COALESCE(GROUP_CONCAT(a.name, ' '), '')
             FROM species s
             LEFT JOIN alias_species als ON als.species_id = s.id
             LEFT JOIN alias a ON a.id = als.alias_id
             GROUP BY s.id
             """,
             []
           ) do
      :ok
    end
  end

  @doc """
  Searches species by name using FTS5 for fast prefix matching.
  Used for typeahead when selecting hosts.

  Falls back to LIKE search for mid-word matches.
  """
  @spec search_species_by_name(String.t(), String.t() | nil, integer()) :: [map()]
  def search_species_by_name(query, taxoncode \\ nil, limit \\ 20) do
    fts_results = search_species_by_name_fts(query, taxoncode, limit)

    if Enum.empty?(fts_results) do
      search_species_by_name_like(query, taxoncode, limit)
    else
      fts_results
    end
  end

  # FTS5-based name search with optional taxoncode filter
  defp search_species_by_name_fts(query, taxoncode, limit) do
    sanitized = sanitize_fts_query(query)

    if sanitized == "" do
      []
    else
      fts_query =
        sanitized
        |> String.split(~r/\s+/, trim: true)
        |> Enum.map_join(" ", &"#{&1}*")

      # Build SQL with optional taxoncode filter
      {sql, params} =
        if taxoncode do
          {"""
           SELECT f.species_id, s.name, s.taxoncode
           FROM species_fts f
           JOIN species s ON s.id = f.species_id
           WHERE species_fts MATCH ? AND s.taxoncode = ?
           ORDER BY bm25(species_fts)
           LIMIT ?
           """, [fts_query, taxoncode, limit]}
        else
          {"""
           SELECT f.species_id, s.name, s.taxoncode
           FROM species_fts f
           JOIN species s ON s.id = f.species_id
           WHERE species_fts MATCH ?
           ORDER BY bm25(species_fts)
           LIMIT ?
           """, [fts_query, limit]}
        end

      case Repo.query(sql, params) do
        {:ok, %{rows: rows}} -> Enum.map(rows, &transform_species_name_row/1)
        {:error, _} -> []
      end
    end
  end

  defp transform_species_name_row([id, name, tc]), do: %{id: id, name: name, taxoncode: tc}

  # LIKE-based fallback for mid-word matches
  defp search_species_by_name_like(query, taxoncode, limit) do
    search_term = "%#{String.downcase(query)}%"

    base_query =
      from(s in Species,
        where: fragment("lower(?) LIKE ?", s.name, ^search_term),
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
      {:ok, species} ->
        update_species_fts(species.id)
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
      {:ok, updated_species} ->
        update_species_fts(updated_species.id)
        broadcast(result, :species_updated)

      {:error, _} ->
        result
    end
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
  Renames a species, optionally adding the old name as a scientific synonym alias.

  This handles the complex rename logic including potential genus reassignment.
  If the genus part of the name changes, the species may need to be reassigned
  to a different genus (or a new genus created).

  Returns {:ok, species} on success, {:error, reason} on failure.
  """
  @spec rename_species(integer(), String.t(), boolean()) ::
          {:ok, Species.t()} | {:error, atom() | String.t()}
  def rename_species(species_id, new_name, add_alias?) do
    if species_name_exists?(new_name) do
      {:error, :name_exists}
    else
      do_rename_species(species_id, new_name, add_alias?)
    end
  end

  defp do_rename_species(species_id, new_name, add_alias?) do
    species = get_species!(species_id)
    old_name = species.name

    Repo.transaction(fn ->
      if add_alias?, do: add_rename_alias(species_id, old_name)

      species
      |> Species.changeset(%{name: new_name})
      |> Repo.update!()
    end)
  end

  defp add_rename_alias(species_id, old_name) do
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
  1. Creates a "scientific synonym" alias with the old species name
  2. Updates the species name by replacing the old genus with the new genus

  This is called within a Taxonomy transaction, so no additional transaction
  is created here.

  ## Examples

      iex> rename_for_genus_change(species, "Quercus", "Oakus")
      :ok  # "Quercus alba" becomes "Oakus alba", synonym "Quercus alba" created
  """
  @spec rename_for_genus_change(Species.t(), String.t(), String.t()) :: :ok
  def rename_for_genus_change(%Species{} = species, old_genus_name, new_genus_name) do
    old_species_name = species.name
    new_species_name = replace_genus_in_name(old_species_name, old_genus_name, new_genus_name)

    # Create synonym alias with the old name (best-effort, don't fail transaction)
    add_rename_alias(species.id, old_species_name)

    # Update the species name
    species
    |> Species.changeset(%{name: new_species_name})
    |> Repo.update!()

    :ok
  end

  # Replaces the genus portion (first word) of a species name.
  defp replace_genus_in_name(species_name, old_genus, new_genus) do
    case String.split(species_name, " ", parts: 2) do
      [^old_genus, epithet] -> "#{new_genus} #{epithet}"
      [^old_genus] -> new_genus
      [_other_genus, epithet] -> "#{new_genus} #{epithet}"
      _ -> species_name
    end
  end

  @doc """
  Deletes a species and all associated data.

  Performs a complete cleanup in the correct order:
  1. Deletes S3 images (before DB cascade removes image paths)
  2. Deletes gall record(s) via Galls context (cascades to filter associations)
  3. Deletes FTS index entry
  4. Deletes the species (cascades to image rows, hosts, aliases, etc.)

  Returns {:ok, species} on success or {:error, reason} on failure.
  """
  @spec delete_species(Species.t()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_species(%Species{} = species) do
    Repo.transaction(fn ->
      # 1. Delete S3 images first (before DB records are cascade deleted)
      Gallformers.Images.delete_images_from_s3_for_species(species.id)

      # 2. Delete the gall_traits record for this species
      # This cascades to all filter associations (gall_shape, gall_texture, etc.)
      Gallformers.Galls.delete_gall_traits(species.id)

      # 3. Delete from FTS index
      delete_species_fts(species.id)

      # 4. Delete the species record (cascades to image rows, hosts, etc.)
      case Repo.delete(species) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
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

    # Update FTS index after alias is added
    case result do
      {:ok, _} -> update_species_fts(species_id)
      _ -> :ok
    end

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

    # Update FTS index after alias is removed
    update_species_fts(species_id)

    broadcast({:ok, %{id: species_id}}, :species_updated)
  end

  @doc """
  Subscribes to species changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "species")
  end

  defp broadcast({:ok, species}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "species", {event, species})
    {:ok, species}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
