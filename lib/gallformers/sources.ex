defmodule Gallformers.Sources do
  @moduledoc """
  The Sources context.

  Provides functions for working with scientific references and citations.
  """

  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Sources.Source
  alias Gallformers.Species.Species
  alias Gallformers.Species.SpeciesSource

  @doc """
  Returns all sources ordered by title.
  """
  @spec list_sources() :: [Source.t()]
  def list_sources do
    from(s in Source,
      order_by: s.title
    )
    |> Repo.all()
  end

  @doc """
  Returns paginated sources.
  """
  @spec list_sources_paginated(integer(), integer()) :: [Source.t()]
  def list_sources_paginated(limit, offset) do
    from(s in Source,
      order_by: s.title,
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of all sources.
  """
  @spec count_sources() :: integer()
  def count_sources do
    from(s in Source,
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets a source by ID.
  """
  @spec get_source(integer()) :: Source.t() | nil
  def get_source(id) do
    Repo.get(Source, id)
  end

  @doc """
  Gets a source by ID, raising if not found.
  """
  @spec get_source!(integer()) :: Source.t()
  def get_source!(id) do
    Repo.get!(Source, id)
  end

  @doc """
  Gets a source by title.
  """
  @spec get_source_by_title(String.t()) :: Source.t() | nil
  def get_source_by_title(title) do
    from(s in Source,
      where: s.title == ^title
    )
    |> Repo.one()
  end

  @doc """
  Searches sources by title or author.
  """
  @spec search_sources(String.t()) :: [Source.t()]
  def search_sources(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Source,
      where:
        fragment("lower(?) LIKE ?", s.title, ^search_term) or
          fragment("lower(?) LIKE ?", s.author, ^search_term),
      order_by: s.title
    )
    |> Repo.all()
  end

  # Gallformers Notes source ID - should appear second after default
  @gallformers_notes_source_id 58

  @doc """
  Gets all sources for a species.

  Sources are sorted with:
  1. Default source first (if any)
  2. Gallformers Notes second (unless it's the default)
  3. Remaining sources alphabetically by title
  """
  @spec get_sources_for_species(integer()) :: [map()]
  def get_sources_for_species(species_id) do
    from(ss in SpeciesSource,
      join: s in Source,
      on: ss.source_id == s.id,
      where: ss.species_id == ^species_id,
      select: %{
        id: s.id,
        title: s.title,
        author: s.author,
        pubyear: s.pubyear,
        link: s.link,
        citation: s.citation,
        license: s.license,
        licenselink: s.licenselink,
        description: ss.description,
        useasdefault: ss.useasdefault,
        externallink: ss.externallink
      }
    )
    |> Repo.all()
    |> sort_sources_with_priority()
  end

  # Sort sources: default first, Gallformers Notes second, then alphabetically
  defp sort_sources_with_priority(sources) do
    Enum.sort_by(sources, fn source ->
      cond do
        source.useasdefault -> {0, source.title}
        source.id == @gallformers_notes_source_id -> {1, source.title}
        true -> {2, source.title}
      end
    end)
  end

  @doc """
  Gets all species associated with a source.
  """
  @spec get_species_for_source(integer()) :: [map()]
  def get_species_for_source(source_id) do
    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      where: ss.source_id == ^source_id,
      order_by: sp.name,
      select: %{
        id: sp.id,
        name: sp.name,
        taxoncode: sp.taxoncode,
        description: ss.description,
        externallink: ss.externallink
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets the count of species associated with a source.
  """
  @spec count_species_for_source(integer()) :: integer()
  def count_species_for_source(source_id) do
    from(ss in SpeciesSource,
      where: ss.source_id == ^source_id,
      select: count(ss.id)
    )
    |> Repo.one()
  end

  # Admin functions

  @doc """
  Returns a changeset for tracking source changes.
  """
  @spec change_source(Source.t(), map()) :: Ecto.Changeset.t()
  def change_source(%Source{} = source, attrs \\ %{}) do
    Source.changeset(source, attrs)
  end

  @doc """
  Creates a source.
  """
  @spec create_source(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:source_created)
  end

  @doc """
  Updates a source.
  """
  @spec update_source(Source.t(), map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
    |> broadcast(:source_updated)
  end

  @doc """
  Deletes a source.
  """
  @spec delete_source(Source.t()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def delete_source(%Source{} = source) do
    Repo.delete(source)
    |> broadcast(:source_deleted)
  end

  @doc """
  Subscribes to source changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "sources")
  end

  defp broadcast({:ok, source}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "sources", {event, source})
    {:ok, source}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end

  # ============================================
  # SpeciesSource (mapping) functions
  # ============================================

  @doc """
  Returns a changeset for tracking species-source mapping changes.
  """
  @spec change_species_source(SpeciesSource.t(), map()) :: Ecto.Changeset.t()
  def change_species_source(%SpeciesSource{} = species_source, attrs \\ %{}) do
    SpeciesSource.changeset(species_source, attrs)
  end

  @doc """
  Gets a species-source mapping by ID.
  """
  @spec get_species_source(integer()) :: SpeciesSource.t() | nil
  def get_species_source(id) do
    Repo.get(SpeciesSource, id)
  end

  @doc """
  Gets a species-source mapping by ID, raising if not found.
  """
  @spec get_species_source!(integer()) :: SpeciesSource.t()
  def get_species_source!(id) do
    Repo.get!(SpeciesSource, id)
  end

  @doc """
  Gets a species-source mapping by species_id and source_id.
  """
  @spec get_species_source_by_ids(integer(), integer()) :: SpeciesSource.t() | nil
  def get_species_source_by_ids(species_id, source_id) do
    from(ss in SpeciesSource,
      where: ss.species_id == ^species_id and ss.source_id == ^source_id
    )
    |> Repo.one()
  end

  @doc """
  Creates a species-source mapping.

  If useasdefault is set to 1, clears all other defaults for that species first.
  """
  @spec create_species_source(map()) :: {:ok, SpeciesSource.t()} | {:error, Ecto.Changeset.t()}
  def create_species_source(attrs \\ %{}) do
    changeset = SpeciesSource.changeset(%SpeciesSource{}, attrs)

    result =
      if setting_as_default?(attrs) do
        species_id = get_species_id_from_attrs(attrs)
        insert_with_default_transaction(changeset, species_id)
      else
        Repo.insert(changeset)
      end

    result |> broadcast(:species_source_created)
  end

  @doc """
  Updates a species-source mapping.

  If useasdefault is set to 1, clears all other defaults for that species first.
  """
  @spec update_species_source(SpeciesSource.t(), map()) ::
          {:ok, SpeciesSource.t()} | {:error, Ecto.Changeset.t()}
  def update_species_source(%SpeciesSource{} = species_source, attrs) do
    changeset = SpeciesSource.changeset(species_source, attrs)

    result =
      if setting_as_default?(attrs) do
        update_with_default_transaction(changeset, species_source.species_id, species_source.id)
      else
        Repo.update(changeset)
      end

    result |> broadcast(:species_source_updated)
  end

  # Inserts a species-source mapping with transaction to clear other defaults
  defp insert_with_default_transaction(changeset, species_id) do
    Repo.transaction(fn ->
      clear_other_defaults(species_id, nil)
      insert_or_rollback(changeset)
    end)
  end

  # Updates a species-source mapping with transaction to clear other defaults
  defp update_with_default_transaction(changeset, species_id, exclude_id) do
    Repo.transaction(fn ->
      clear_other_defaults(species_id, exclude_id)
      update_or_rollback(changeset)
    end)
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp setting_as_default?(attrs) do
    useasdefault = attrs["useasdefault"] || attrs[:useasdefault]
    useasdefault in [true, "true"]
  end

  # Gets species_id from attrs (handles both string and atom keys)
  defp get_species_id_from_attrs(attrs) do
    species_id = attrs["species_id"] || attrs[:species_id]

    case species_id do
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
      _ -> nil
    end
  end

  # Clears useasdefault flag on all other mappings for a species
  defp clear_other_defaults(species_id, exclude_id) when not is_nil(species_id) do
    query =
      from(ss in SpeciesSource,
        where: ss.species_id == ^species_id and ss.useasdefault == true
      )

    query =
      if exclude_id do
        from(ss in query, where: ss.id != ^exclude_id)
      else
        query
      end

    Repo.update_all(query, set: [useasdefault: false])
  end

  defp clear_other_defaults(_, _), do: :ok

  @doc """
  Deletes a species-source mapping.
  """
  @spec delete_species_source(SpeciesSource.t()) ::
          {:ok, SpeciesSource.t()} | {:error, Ecto.Changeset.t()}
  def delete_species_source(%SpeciesSource{} = species_source) do
    Repo.delete(species_source)
    |> broadcast(:species_source_deleted)
  end

  @doc """
  Checks if a species is already linked to a source.
  """
  @spec species_source_exists?(integer(), integer()) :: boolean()
  def species_source_exists?(species_id, source_id) do
    from(ss in SpeciesSource,
      where: ss.species_id == ^species_id and ss.source_id == ^source_id
    )
    |> Repo.exists?()
  end

  @doc """
  Searches species-source mappings by species name, source title, or description.
  Returns mappings with full species and source info for display.
  """
  @spec search_species_source_mappings(String.t(), integer()) :: [map()]
  def search_species_source_mappings(query, limit \\ 50) do
    search_term = "%#{String.downcase(query)}%"

    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      join: src in Source,
      on: ss.source_id == src.id,
      where:
        fragment("lower(?) LIKE ?", sp.name, ^search_term) or
          fragment("lower(?) LIKE ?", src.title, ^search_term) or
          fragment("lower(?) LIKE ?", src.author, ^search_term) or
          fragment("lower(?) LIKE ?", ss.description, ^search_term),
      order_by: [asc: sp.name, asc: src.title],
      limit: ^limit,
      select: %{
        id: ss.id,
        species_id: sp.id,
        species_name: sp.name,
        species_taxoncode: sp.taxoncode,
        source_id: src.id,
        source_title: src.title,
        source_author: src.author,
        source_pubyear: src.pubyear,
        description: ss.description,
        externallink: ss.externallink,
        useasdefault: ss.useasdefault
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets all species-source mappings for a specific species.
  Returns mappings in the same format as search_species_source_mappings for display.
  """
  @spec get_species_source_mappings_for_species(integer()) :: [map()]
  def get_species_source_mappings_for_species(species_id) do
    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      join: src in Source,
      on: ss.source_id == src.id,
      where: ss.species_id == ^species_id,
      order_by: [asc: src.title],
      select: %{
        id: ss.id,
        species_id: sp.id,
        species_name: sp.name,
        species_taxoncode: sp.taxoncode,
        source_id: src.id,
        source_title: src.title,
        source_author: src.author,
        source_pubyear: src.pubyear,
        description: ss.description,
        externallink: ss.externallink,
        useasdefault: ss.useasdefault
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets a species-source mapping with full details for editing.
  """
  @spec get_species_source_for_edit(integer()) :: map() | nil
  def get_species_source_for_edit(id) do
    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      join: src in Source,
      on: ss.source_id == src.id,
      where: ss.id == ^id,
      select: %{
        id: ss.id,
        species_id: sp.id,
        species_name: sp.name,
        species_taxoncode: sp.taxoncode,
        source_id: src.id,
        source_title: src.title,
        source_author: src.author,
        source_pubyear: src.pubyear,
        description: ss.description,
        externallink: ss.externallink,
        useasdefault: ss.useasdefault
      }
    )
    |> Repo.one()
  end
end
