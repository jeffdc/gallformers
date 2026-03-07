defmodule Gallformers.GallHosts do
  @moduledoc """
  The GallHosts context.

  Manages the many-to-many relationship between gall species and their host plants.
  A gall forms on one or more host plant species; a host plant may have multiple
  gall species that form on it.

  Both galls and hosts are Species records (differentiated by taxoncode), and
  the `gallhost` table is the join table linking them.
  """

  import Ecto.Query

  alias Gallformers.GallHosts.GallHost
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  @doc """
  Gets all hosts for a gall species.

  Returns a list of maps with host_relation_id, host_species_id, and host_name.
  """
  @spec get_hosts_for_gall(integer()) :: [map()]
  def get_hosts_for_gall(gall_species_id) do
    from(h in GallHost,
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
  Gets hosts for multiple gall species in a single query (batch version).

  Returns a map of gall_species_id => [%{host_species_id, host_name}].
  """
  @spec get_hosts_for_galls([integer()]) :: %{integer() => [map()]}
  def get_hosts_for_galls([]), do: %{}

  def get_hosts_for_galls(gall_species_ids) do
    from(h in GallHost,
      join: s in Species,
      on: h.host_species_id == s.id,
      where: h.gall_species_id in ^gall_species_ids,
      select: %{
        gall_species_id: h.gall_species_id,
        host_species_id: s.id,
        host_name: s.name
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.gall_species_id, fn row ->
      %{host_species_id: row.host_species_id, host_name: row.host_name}
    end)
  end

  @doc """
  Gets all galls for a host species.

  Returns a list of maps with gall info.
  """
  @spec get_galls_for_host(integer()) :: [map()]
  def get_galls_for_host(host_species_id) do
    from(h in GallHost,
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
  Gets galls for multiple host species in a single query (batch version).

  Returns a map of host_species_id => count of galls.
  This is optimized for counting - returns counts rather than full gall records.
  """
  @spec get_gall_counts_for_hosts([integer()]) :: %{integer() => integer()}
  def get_gall_counts_for_hosts([]), do: %{}

  def get_gall_counts_for_hosts(host_species_ids) do
    from(h in GallHost,
      where: h.host_species_id in ^host_species_ids,
      group_by: h.host_species_id,
      select: {h.host_species_id, count(h.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets host counts for multiple gall species in a single query (batch version).

  Returns a map of gall_species_id => count of hosts.
  """
  @spec get_host_counts_for_galls([integer()]) :: %{integer() => integer()}
  def get_host_counts_for_galls([]), do: %{}

  def get_host_counts_for_galls(gall_species_ids) do
    from(h in GallHost,
      where: h.gall_species_id in ^gall_species_ids,
      group_by: h.gall_species_id,
      select: {h.gall_species_id, count(h.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets the host species IDs for a gall.

  Simpler version of get_hosts_for_gall when you only need IDs.
  """
  @spec get_host_species_ids_for_gall(integer()) :: [integer()]
  def get_host_species_ids_for_gall(gall_species_id) do
    from(h in GallHost,
      where: h.gall_species_id == ^gall_species_id,
      select: h.host_species_id
    )
    |> Repo.all()
  end

  @doc """
  Creates a gall-host relationship.
  """
  @spec create_gall_host(map()) :: {:ok, GallHost.t()} | {:error, Ecto.Changeset.t()}
  def create_gall_host(attrs) do
    %GallHost{}
    |> GallHost.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Associates a host with a gall species and broadcasts a species update.
  """
  @spec add_host_to_gall(integer(), integer()) ::
          {:ok, GallHost.t()} | {:error, Ecto.Changeset.t()}
  def add_host_to_gall(gall_species_id, host_species_id) do
    attrs = %{gall_species_id: gall_species_id, host_species_id: host_species_id}

    case create_gall_host(attrs) do
      {:ok, host_relation} ->
        broadcast_species_change(gall_species_id, :species_updated)
        {:ok, host_relation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Removes a host association from a gall species by relation ID.
  """
  @spec remove_host_from_gall(integer()) :: {:ok, map()} | {:error, :not_found}
  def remove_host_from_gall(host_relation_id) do
    case Repo.get(GallHost, host_relation_id) do
      nil ->
        {:error, :not_found}

      host_relation ->
        species_id = host_relation.gall_species_id
        Repo.delete(host_relation)
        broadcast_species_change(species_id, :species_updated)
    end
  end

  @doc """
  Deletes a gall-host relationship by ID.
  """
  @spec delete_gall_host(integer()) :: {:ok, GallHost.t()} | {:error, :not_found}
  def delete_gall_host(id) do
    case Repo.get(GallHost, id) do
      nil -> {:error, :not_found}
      gall_host -> Repo.delete(gall_host)
    end
  end

  @doc """
  Gets a gall-host relationship by ID.
  """
  @spec get_gall_host(integer()) :: GallHost.t() | nil
  def get_gall_host(id), do: Repo.get(GallHost, id)

  @doc """
  Saves all gall-host mapping changes in a single transaction.

  Adds and removes host associations, and optionally updates the gall's
  curated range in gall_range.

  `hosts_to_remove` is a MapSet of relation IDs. `hosts_to_add` is a list of
  maps with `:host_species_id`. `gall_range_entries` is an optional list of
  `{place_id, precision}` tuples for the gall_range table.
  """
  @spec save_gall_host_changes(
          integer(),
          [map()],
          MapSet.t(),
          [{integer(), String.t()}] | nil,
          keyword()
        ) ::
          {:ok, :ok} | {:error, term()}
  def save_gall_host_changes(
        gall_id,
        hosts_to_add,
        hosts_to_remove,
        gall_range_entries \\ nil,
        opts \\ []
      ) do
    Repo.transaction(fn ->
      for relation_id <- hosts_to_remove do
        remove_host_from_gall(relation_id)
      end

      for host <- hosts_to_add do
        add_host_to_gall(gall_id, host.host_species_id)
      end

      if gall_range_entries do
        Gallformers.Ranges.set_gall_range(gall_id, gall_range_entries)
      end

      if opts[:confirm_range] do
        Gallformers.Galls.confirm_gall_range(gall_id)
      end

      Gallformers.Species.touch(gall_id)
      :ok
    end)
  end

  # Broadcasts on the species PubSub topic so admin forms pick up changes.
  defp broadcast_species_change(species_id, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "species", {event, %{id: species_id}})
  end
end
