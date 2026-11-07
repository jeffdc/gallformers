defmodule Gallformers.Taxa.ReadModels.SpeciesPage do
  @moduledoc """
  What the species page (`/species/:id`, matter `803b`, "The species
  page") shows of an organism's taxon: a taxon at species rank or below
  that is not a plant (plants have their Host pages).

    * `name` — the accepted name, with its `authorship`; `rank`, `kingdom`;
    * `lineage` — the taxon and the taxa above it, root first
      (`Gallformers.Taxa.lineage/1`), for the breadcrumb;
    * `synonyms` (`%{id, name, sensu}`) and `common_names` (`%{id, name}`),
      each by name, with the IDs an edit removes them by;
    * `merged` — the taxa merged into it (lumps, `Gallformers.Taxa.merge/3`):
      `%{taxon_id, name, at}` by when, the name the taxon had (from the
      audit trail; nil when it holds none);
    * `inserted_at`, `updated_at`.

  The Galls it induces are the Catalog's, and where it stands in the Sources
  (its placement and name with their Sources, splits) is
  `Gallformers.Import`'s: Taxa knows nothing about Galls or Sources.
  """
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          authorship: String.t() | nil,
          rank: Rank.t(),
          kingdom: String.t() | nil,
          lineage: [Taxa.lineage_entry()],
          synonyms: [%{id: integer(), name: String.t(), sensu: String.t() | nil}],
          common_names: [%{id: integer(), name: String.t()}],
          merged: [%{taxon_id: integer(), name: String.t() | nil, at: DateTime.t()}],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:id, :name, :rank]
  defstruct [
    :id,
    :name,
    :authorship,
    :rank,
    :kingdom,
    :inserted_at,
    :updated_at,
    lineage: [],
    synonyms: [],
    common_names: [],
    merged: []
  ]

  @doc """
  The species page of taxon `id`: `{:ok, page}`; `{:plant, id}` for a plant
  at species rank or below (its Host page); `{:higher, %{rank, name}}` for
  a taxon above species rank (its rank's page, if it has one);
  `:not_found` when there is no such taxon.
  """
  @spec for_taxon(integer()) ::
          {:ok, t()}
          | {:plant, integer()}
          | {:higher, %{rank: Rank.t(), name: String.t()}}
          | :not_found
  def for_taxon(id) when is_integer(id) do
    case Taxa.get_taxon(id) do
      nil ->
        :not_found

      %Taxon{rank: rank} = taxon ->
        cond do
          rank not in Rank.species_and_below() ->
            {:higher, %{rank: rank, name: Taxa.accepted_name(taxon)}}

          taxon.kingdom == "Plantae" ->
            {:plant, taxon.id}

          true ->
            {:ok, build(taxon)}
        end
    end
  end

  defp build(%Taxon{} = taxon) do
    accepted = Enum.find(taxon.names, &(&1.status == :accepted))

    %__MODULE__{
      id: taxon.id,
      name: accepted.name,
      authorship: accepted.authorship,
      rank: taxon.rank,
      kingdom: taxon.kingdom,
      lineage: Taxa.lineage(taxon.id),
      synonyms:
        taxon.id
        |> Taxa.list_synonyms()
        |> Enum.map(&%{id: &1.id, name: &1.name, sensu: &1.sensu})
        |> Enum.sort_by(&{&1.name, &1.sensu || ""}),
      common_names:
        taxon.id
        |> Taxa.list_common_names()
        |> Enum.map(&%{id: &1.id, name: &1.name})
        |> Enum.sort_by(& &1.name),
      merged: Taxa.merged_into(taxon.id),
      inserted_at: taxon.inserted_at,
      updated_at: taxon.updated_at
    }
  end
end
