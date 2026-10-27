defmodule Gallformers.Species do
  @moduledoc """
  The Species context.

  Provides shared functions for working with species records regardless of type.
  For gall-specific logic, see `Gallformers.Galls`.
  For host/plant-specific logic, see `Gallformers.Plants`.
  """
  use Boundary,
    deps: [
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Taxonomy,
      Gallformers.TextMatch
    ],
    dirty_xrefs: [
      Gallformers.Galls.GallTraits,
      Gallformers.Images
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Species.{Abundance, Alias, Species}

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
  Returns all abundance options.
  """
  @spec list_abundances() :: [Abundance.t()]
  def list_abundances do
    Repo.all(Abundance)
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
  Searches species by name using ILIKE matching.
  Used for typeahead when selecting hosts.
  """
  @spec search_species_by_name(String.t(), String.t() | nil, integer()) :: [map()]
  def search_species_by_name(query, taxoncode \\ nil, limit \\ 20) do
    search_species_by_name_like(query, taxoncode, limit)
  end

  # ILIKE-based name search
  defp search_species_by_name_like(query, taxoncode, limit) do
    name_filter = Gallformers.TextMatch.build_filter(query, [:name])

    base_query =
      from(s in Species,
        where: ^name_filter,
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
  Creates a species and places it in the taxonomy tree.

  The `taxonomy_opts` keyword list must include:
  - `:taxonomy` - A `%Lineage{}` struct for tree placement
  - `:parent_id` - Family/section ID (required when genus is new)
  - `:section_id` - Section to link the species to (optional)

  Returns `{:ok, species}` or `{:error, changeset}`.
  """
  @spec create_species(map(), keyword()) :: {:ok, Species.t()} | {:error, Ecto.Changeset.t()}
  def create_species(attrs, taxonomy_opts) do
    result =
      %Species{}
      |> Species.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, species} ->
        lineage = Keyword.fetch!(taxonomy_opts, :taxonomy)
        opts = Keyword.take(taxonomy_opts, [:parent_id, :section_id])
        Gallformers.Taxonomy.place_species_in_tree(species.id, lineage, opts)
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
