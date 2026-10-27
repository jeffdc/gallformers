defmodule Gallformers.Taxa.ReadModels.HostPage do
  @moduledoc """
  What the Host page (`/host/:id`) shows of a host plant's taxon (`803b`
  Task 5): a Plantae taxon at species rank or below (today's plants keep
  their IDs).

    * `name` — the accepted name; `rank`;
    * `lineage` — the taxon and the taxa above it, root first
      (`Gallformers.Taxa.lineage/1`), for the taxonomy breadcrumb;
    * `synonyms` (`%{name, sensu}`) and `common_names`, each by name;
    * `datacomplete` and `abundance` (its name, or nil) — the plant's
      editorial flags (`803b` decision 6).

  The Galls on the host are the Catalog's
  (`Gallformers.Catalog.list_galls_for_hosts/1`): Taxa knows nothing about
  Galls.
  """
  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  # A host page is a plant at species rank or below; higher plant taxa have
  # their rank pages.
  @host_ranks [:species, :subspecies, :variety, :form]

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          rank: Rank.t(),
          lineage: [Taxa.lineage_entry()],
          synonyms: [%{name: String.t(), sensu: String.t() | nil}],
          common_names: [String.t()],
          datacomplete: boolean(),
          abundance: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:id, :name, :rank]
  defstruct [
    :id,
    :name,
    :rank,
    :abundance,
    :inserted_at,
    :updated_at,
    datacomplete: false,
    lineage: [],
    synonyms: [],
    common_names: []
  ]

  @doc """
  The Host page of taxon `id`, or `:not_found` when there is no such taxon,
  or it is not a plant at species rank or below.
  """
  @spec for_taxon(integer()) :: {:ok, t()} | :not_found
  def for_taxon(id) when is_integer(id) do
    case Repo.get(Taxon, id) do
      %Taxon{kingdom: "Plantae", rank: rank} = taxon when rank in @host_ranks ->
        {:ok, build(taxon)}

      _ ->
        :not_found
    end
  end

  defp build(%Taxon{} = taxon) do
    %__MODULE__{
      id: taxon.id,
      name: Taxa.accepted_name(taxon.id),
      rank: taxon.rank,
      lineage: Taxa.lineage(taxon.id),
      synonyms:
        taxon.id
        |> Taxa.list_synonyms()
        |> Enum.map(&%{name: &1.name, sensu: &1.sensu})
        |> Enum.sort_by(&{&1.name, &1.sensu}),
      common_names: taxon.id |> Taxa.list_common_names() |> Enum.map(& &1.name) |> Enum.sort(),
      datacomplete: taxon.datacomplete,
      abundance: abundance(taxon.abundance_id),
      inserted_at: taxon.inserted_at,
      updated_at: taxon.updated_at
    }
  end

  defp abundance(nil), do: nil

  defp abundance(id),
    do: Repo.one(from(a in "abundance", where: a.id == ^id, select: a.abundance))
end
