defmodule Gallformers.Catalog.ReadModels.GallSummary do
  @moduledoc """
  What the ID tool and pages show of a Gall (`9449` §4): its name and
  generation, and its current Inducer, Hosts and Traits.

    * `inducers` — the taxa of its current `inducer_of` Facts. A Gall has at
      most one Inducer (domain rule), so this is normally empty (unknown) or
      one; more than one means current Sources disagree, for a curator.
    * `hosts` — the plant taxa of its current `host_of` Facts, by name.
    * `traits` — each Trait's current values, by Trait name (`detachable`'s
      slot leaves one).

  Each taxon is its ID, accepted name (from `Gallformers.Taxa`) and rank.
  Computed on read from current Facts.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @type taxon :: %{taxon_id: integer(), name: String.t(), rank: Gallformers.Taxa.Rank.t()}

  @type t :: %__MODULE__{
          gall_id: integer(),
          name: String.t(),
          generation: String.t() | nil,
          inducers: [taxon()],
          hosts: [taxon()],
          traits: %{String.t() => [String.t()]}
        }

  @enforce_keys [:gall_id, :name]
  defstruct [:gall_id, :name, :generation, inducers: [], hosts: [], traits: %{}]

  @doc "A Gall's summary. Raises if there is no such Gall."
  @spec for_gall(integer()) :: t()
  def for_gall(gall_id) when is_integer(gall_id) do
    gall = Repo.get!(Gall, gall_id)

    %__MODULE__{
      gall_id: gall.id,
      name: Gall.display_name(gall),
      generation: generation(gall),
      inducers: related_taxa("inducer_of", gall.id),
      hosts: related_taxa("host_of", gall.id),
      traits: traits(gall.id)
    }
  end

  defp generation(%Gall{generation_value_id: nil}), do: nil
  defp generation(%Gall{generation_value_id: id}), do: Repo.get!(GenerationValue, id).value

  defp related_taxa(type, gall_id) do
    from(r in Current.relationships(type),
      where: r.object_gall_id == ^gall_id,
      select: r.subject_taxon_id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      taxon = Taxa.get_taxon!(id)
      %{taxon_id: id, name: Taxa.accepted_name(taxon), rank: taxon.rank}
    end)
    |> Enum.sort_by(&{&1.name, &1.taxon_id})
  end

  @doc "The summaries of the Galls whose current `type` Relationship has a subject among `taxon_ids`."
  @spec for_related(String.t(), [integer()]) :: [t()]
  def for_related(_type, []), do: []

  def for_related(type, taxon_ids) do
    from(r in Current.relationships(type),
      where: r.subject_taxon_id in ^taxon_ids,
      distinct: true,
      order_by: r.object_gall_id,
      select: r.object_gall_id
    )
    |> Repo.all()
    |> Enum.map(&for_gall/1)
  end

  defp traits(gall_id) do
    from(t in Current.traits(gall_id),
      join: v in TraitValue,
      on: v.id == t.trait_value_id,
      order_by: [v.trait, v.value],
      select: {v.trait, v.value}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
