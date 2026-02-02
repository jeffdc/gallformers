defmodule Gallformers.Places do
  @moduledoc """
  The Places context.

  Provides functions for working with geographic places (states, provinces, regions).
  """

  import Ecto.Query
  alias Gallformers.Places.Place
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  @doc """
  Returns all places (states/provinces) ordered by name.
  """
  @spec list_places() :: [Place.t()]
  def list_places do
    from(p in Place,
      where: p.type in ["state", "province"],
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Gets a place by code.
  """
  @spec get_place_by_code(String.t()) :: Place.t() | nil
  def get_place_by_code(code) do
    from(p in Place,
      where: p.code == ^code
    )
    |> Repo.one()
  end

  @doc """
  Gets a place by ID.
  """
  @spec get_place(integer()) :: Place.t() | nil
  def get_place(id) do
    Repo.get(Place, id)
  end

  @doc """
  Gets a place by ID, raising if not found.
  """
  @spec get_place!(integer()) :: Place.t()
  def get_place!(id) do
    Repo.get!(Place, id)
  end

  @doc """
  Gets a place's parent by ID.
  """
  def get_parent_place(place_id) do
    from(p in "place",
      join: pp in "placeplace",
      on: pp.parent_id == p.id,
      where: pp.place_id == ^place_id,
      select: %{
        id: p.id,
        name: p.name,
        code: p.code,
        type: p.type
      },
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Searches places by name (case-insensitive).
  """
  @spec search_places(String.t(), integer()) :: [Place.t()]
  def search_places(query, limit \\ 20) do
    search_pattern = "%#{String.downcase(query)}%"

    from(p in Place,
      where: fragment("lower(?) LIKE ?", p.name, ^search_pattern),
      order_by: p.name,
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns all places ordered by name.
  """
  @spec list_all_places() :: [Place.t()]
  def list_all_places do
    from(p in Place,
      order_by: p.name
    )
    |> Repo.all()
  end

  # Range management - semantic wrappers for V2 schema

  @doc """
  Gets host ranges for a species (places where the host plant exists).
  """
  @spec get_host_ranges(integer()) :: [Place.t()]
  def get_host_ranges(species_id) do
    from(p in Place,
      join: hr in "host_range",
      on: hr.place_id == p.id,
      where: hr.species_id == ^species_id,
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Gets gall range exclusions for a species (places excluded from gall's range).
  """
  @spec get_gall_range_exclusions(integer()) :: [Place.t()]
  def get_gall_range_exclusions(species_id) do
    from(p in Place,
      join: gre in "gall_range_exclusion",
      on: gre.place_id == p.id,
      where: gre.species_id == ^species_id,
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Gets the range for a species based on its taxoncode.
  For plants: returns places where the host exists
  For galls: returns places EXCLUDED from the gall's range
  """
  @spec get_species_range(Species.t()) :: [Place.t()]
  def get_species_range(%Species{taxoncode: "plant", id: id}) do
    get_host_ranges(id)
  end

  def get_species_range(%Species{taxoncode: "gall", id: id}) do
    get_gall_range_exclusions(id)
  end

  def get_species_range(_), do: []

  # Admin functions

  @doc """
  Returns a changeset for tracking place changes.
  """
  @spec change_place(Place.t(), map()) :: Ecto.Changeset.t()
  def change_place(%Place{} = place, attrs \\ %{}) do
    Place.changeset(place, attrs)
  end

  @doc """
  Creates a place.
  """
  @spec create_place(map()) :: {:ok, Place.t()} | {:error, Ecto.Changeset.t()}
  def create_place(attrs \\ %{}) do
    %Place{}
    |> Place.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:place_created)
  end

  @doc """
  Updates a place.
  """
  @spec update_place(Place.t(), map()) :: {:ok, Place.t()} | {:error, Ecto.Changeset.t()}
  def update_place(%Place{} = place, attrs) do
    place
    |> Place.changeset(attrs)
    |> Repo.update()
    |> broadcast(:place_updated)
  end

  @doc """
  Deletes a place.
  """
  @spec delete_place(Place.t()) :: {:ok, Place.t()} | {:error, Ecto.Changeset.t()}
  def delete_place(%Place{} = place) do
    Repo.delete(place)
    |> broadcast(:place_deleted)
  end

  @doc """
  Subscribes to place changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "places")
  end

  defp broadcast({:ok, place}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "places", {event, place})
    {:ok, place}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
