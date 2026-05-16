defmodule Gallformers.Galls.HostAssociations do
  @moduledoc """
  Manages the many-to-many relationship between gall species and their host plants.

  Internal module — public API is exposed through `Gallformers.Galls`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Gallformers.Galls.GallHost
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
        host_name: s.name,
        genus_placeholder: s.genus_placeholder
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns true when every host in the given list is flagged as a genus-level
  placeholder (e.g. "Quercus spp").

  Takes the host maps produced by `get_hosts_for_gall/1` so callers that have
  already loaded hosts don't pay for a second DB round trip. Returns false for
  an empty list.
  """
  @spec only_placeholder_hosts?([map()]) :: boolean()
  def only_placeholder_hosts?(hosts) when is_list(hosts) do
    hosts != [] and Enum.all?(hosts, & &1.genus_placeholder)
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
        result = Repo.delete(host_relation)
        broadcast_species_change(species_id, :species_updated)
        result
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
    multi =
      Multi.new()
      |> add_remove_steps(hosts_to_remove)
      |> add_insert_steps(gall_id, hosts_to_add)
      |> add_range_step(gall_id, gall_range_entries)
      |> add_confirm_range_step(gall_id, opts[:confirm_range])
      |> Multi.run(:touch, fn _repo, _changes -> Gallformers.Species.touch(gall_id) end)

    case Repo.transaction(multi) do
      {:ok, _changes} ->
        broadcast_species_change(gall_id, :species_updated)
        {:ok, :ok}

      {:error, failed_step, reason, _changes_so_far} ->
        {:error, {failed_step, reason}}
    end
  end

  defp add_remove_steps(multi, hosts_to_remove) do
    Enum.reduce(hosts_to_remove, multi, fn relation_id, acc ->
      Multi.run(acc, {:remove, relation_id}, fn repo, _changes ->
        delete_relation(repo, relation_id)
      end)
    end)
  end

  defp delete_relation(repo, relation_id) do
    case repo.get(GallHost, relation_id) do
      nil -> {:error, :not_found}
      relation -> repo.delete(relation)
    end
  end

  defp add_insert_steps(multi, gall_id, hosts_to_add) do
    Enum.reduce(hosts_to_add, multi, fn host, acc ->
      attrs = %{gall_species_id: gall_id, host_species_id: host.host_species_id}

      Multi.insert(
        acc,
        {:add, host.host_species_id},
        GallHost.changeset(%GallHost{}, attrs)
      )
    end)
  end

  defp add_range_step(multi, _gall_id, nil), do: multi

  defp add_range_step(multi, gall_id, gall_range_entries) do
    Multi.run(multi, :set_range, fn _repo, _changes ->
      Gallformers.Ranges.set_gall_range(gall_id, gall_range_entries)
    end)
  end

  defp add_confirm_range_step(multi, _gall_id, nil), do: multi
  defp add_confirm_range_step(multi, _gall_id, false), do: multi

  defp add_confirm_range_step(multi, gall_id, _truthy) do
    Multi.run(multi, :confirm_range, fn _repo, _changes ->
      {:ok, Gallformers.Galls.confirm_gall_range(gall_id)}
    end)
  end

  # Broadcasts on the species PubSub topic so admin forms pick up changes.
  defp broadcast_species_change(species_id, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "species", {event, %{id: species_id}})
  end
end
