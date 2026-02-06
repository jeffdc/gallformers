defmodule Gallformers.Ranges do
  @moduledoc """
  The Ranges context.

  Manages geographic range data for species:
  - **Host ranges** (host_range table): Where host plants exist geographically
  - **Gall range exclusions** (gall_range_exclusion table): Where galls do NOT occur
    despite suitable hosts existing

  Gall effective range is computed as:
      (union of all host plant ranges) - (explicit exclusions)

  This is not stored directly but computed from the two tables.
  """

  import Ecto.Query

  alias Gallformers.GallHosts.GallHost
  alias Gallformers.Ranges.{GallRangeExclusion, HostRange}
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  # ============================================
  # Host Range Queries
  # ============================================

  @doc """
  Gets hosts (plant species) for a Place with their aliases.
  """
  def get_hosts_for_place(place_id) do
    from(s in Species,
      join: hr in HostRange,
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
    from(hr in HostRange,
      join: p in "place",
      on: hr.place_id == p.id,
      where: hr.species_id == ^host_species_id,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets place IDs (not codes) for a host species.
  """
  @spec get_place_ids_for_host(integer()) :: [integer()]
  def get_place_ids_for_host(host_species_id) do
    from(hr in HostRange,
      where: hr.species_id == ^host_species_id,
      select: hr.place_id
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
      join: hr in HostRange,
      on: hr.place_id == p.id,
      where: hr.species_id in ^host_species_ids,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets places for multiple hosts in a single query, grouped by host species ID.

  Returns a map of species_id => [place_code].
  """
  @spec get_places_for_hosts([integer()]) :: %{integer() => [String.t()]}
  def get_places_for_hosts([]), do: %{}

  def get_places_for_hosts(host_species_ids) do
    from(hr in HostRange,
      join: p in "place",
      on: hr.place_id == p.id,
      where: hr.species_id in ^host_species_ids,
      select: {hr.species_id, p.code}
    )
    |> Repo.all()
    |> Enum.group_by(fn {id, _code} -> id end, fn {_id, code} -> code end)
  end

  # ============================================
  # Host Range Management
  # ============================================

  @doc """
  Adds a place to a host's range.
  """
  @spec add_place_to_host(integer(), integer()) :: {:ok, map()}
  def add_place_to_host(host_species_id, place_id) do
    %HostRange{}
    |> HostRange.changeset(%{species_id: host_species_id, place_id: place_id})
    |> Repo.insert(on_conflict: :nothing)

    {:ok, %{id: host_species_id}}
  end

  @doc """
  Removes a place from a host's range.
  """
  @spec remove_place_from_host(integer(), integer()) :: {:ok, map()}
  def remove_place_from_host(host_species_id, place_id) do
    from(hr in HostRange,
      where: hr.species_id == ^host_species_id and hr.place_id == ^place_id
    )
    |> Repo.delete_all()

    {:ok, %{id: host_species_id}}
  end

  @doc """
  Toggles a place in a host's range (add if not present, remove if present).
  Returns {:added, place_id} or {:removed, place_id}.
  """
  @spec toggle_place_for_host(integer(), integer()) :: {:added | :removed, integer()}
  def toggle_place_for_host(host_species_id, place_id) do
    existing =
      from(hr in HostRange,
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
      from(hr in HostRange,
        where: hr.species_id == ^host_species_id
      )
      |> Repo.delete_all()

      # Insert new
      if place_ids != [] do
        entries = Enum.map(place_ids, &%{species_id: host_species_id, place_id: &1})
        Repo.insert_all(HostRange, entries)
      end

      :ok
    end)

    {:ok, %{id: host_species_id}}
  end

  # ============================================
  # Gall Range Queries (via hosts)
  # ============================================

  @doc """
  Gets place codes for a gall species via its hosts.
  This is the POTENTIAL range (before exclusions are applied).
  """
  @spec get_places_for_gall(integer()) :: [String.t()]
  def get_places_for_gall(gall_species_id) do
    from(p in "place",
      join: hr in HostRange,
      on: hr.place_id == p.id,
      join: h in GallHost,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id == ^gall_species_id,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets place codes for multiple gall species in a single query (batch version).

  Returns a map of gall_species_id => [place_codes].
  """
  @spec get_places_for_galls([integer()]) :: %{integer() => [String.t()]}
  def get_places_for_galls([]), do: %{}

  def get_places_for_galls(gall_species_ids) do
    from(p in "place",
      join: hr in HostRange,
      on: hr.place_id == p.id,
      join: h in GallHost,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id in ^gall_species_ids,
      distinct: true,
      select: {h.gall_species_id, p.code}
    )
    |> Repo.all()
    |> Enum.group_by(fn {gall_id, _code} -> gall_id end, fn {_gall_id, code} -> code end)
  end

  @doc """
  Gets the union of all host places for a gall as place IDs (not codes).
  Used for computing which places can potentially be excluded.
  """
  @spec get_host_place_ids_for_gall(integer()) :: [integer()]
  def get_host_place_ids_for_gall(gall_species_id) do
    from(hr in HostRange,
      join: h in GallHost,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id == ^gall_species_id,
      distinct: true,
      select: hr.place_id
    )
    |> Repo.all()
  end

  # ============================================
  # Gall Range Exclusion Queries
  # ============================================

  @doc """
  Gets excluded place codes for a gall species (direct range exclusions).
  """
  @spec get_excluded_places_for_gall(integer()) :: [String.t()]
  def get_excluded_places_for_gall(gall_species_id) do
    from(p in "place",
      join: gre in GallRangeExclusion,
      on: gre.place_id == p.id,
      where: gre.species_id == ^gall_species_id,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets excluded place IDs (not codes) for a gall species.
  """
  @spec get_excluded_place_ids_for_gall(integer()) :: [integer()]
  def get_excluded_place_ids_for_gall(gall_species_id) do
    from(gre in GallRangeExclusion,
      where: gre.species_id == ^gall_species_id,
      select: gre.place_id
    )
    |> Repo.all()
  end

  # ============================================
  # Gall Range Exclusion Management
  # ============================================

  @doc """
  Bulk updates all range exclusions for a gall (replaces existing).

  Takes a list of place IDs that should be excluded from the gall's range.
  """
  @spec set_range_exclusions_for_gall(integer(), [integer()]) :: :ok
  def set_range_exclusions_for_gall(gall_species_id, place_ids) do
    Repo.transaction(fn ->
      # Delete existing exclusions
      from(gre in GallRangeExclusion,
        where: gre.species_id == ^gall_species_id
      )
      |> Repo.delete_all()

      # Insert new exclusions
      if place_ids != [] do
        entries = Enum.map(place_ids, &%{species_id: gall_species_id, place_id: &1})
        Repo.insert_all(GallRangeExclusion, entries)
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
      from(gre in GallRangeExclusion,
        where: gre.species_id == ^gall_species_id and gre.place_id == ^place_id,
        select: count()
      )
      |> Repo.one()

    if existing > 0 do
      # Remove exclusion (place is now in range)
      from(gre in GallRangeExclusion,
        where: gre.species_id == ^gall_species_id and gre.place_id == ^place_id
      )
      |> Repo.delete_all()

      {:removed, place_id}
    else
      # Add exclusion (place is now excluded)
      %GallRangeExclusion{}
      |> GallRangeExclusion.changeset(%{species_id: gall_species_id, place_id: place_id})
      |> Repo.insert(on_conflict: :nothing)

      {:added, place_id}
    end
  end

  # ============================================
  # Utility
  # ============================================

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
