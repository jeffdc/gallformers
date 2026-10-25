defmodule Gallformers.Taxa.ActFacts.NameFact do
  @moduledoc """
  A name Fact's details: the taxon bears this name at this rank. Natural key
  taxon + normalized name (`Gallformers.Taxa.NameNormalizer`) + rank; a
  taxon's name Facts compete in the slot `"taxon:<id>:name"`, so the newest
  current one is its accepted name by the Sources. `name` keeps the form
  first recorded.

  Authorship and status words ("comb. nov.") are each Source's own wording,
  kept on its attribution (`authorship_as_written`, `status_as_written`).
  Recorded only in phase 1: the taxon's accepted name in `taxon_names` does
  not follow it.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Taxa.ActFacts

  alias Gallformers.Facts.Fact
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          taxon_id: integer() | nil,
          name: String.t() | nil,
          normalized_name: String.t() | nil,
          rank: Rank.t() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t(),
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "name_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :taxon, Taxon
    field :name, :string
    field :normalized_name, :string
    field :rank, Ecto.Enum, values: Rank.all()
  end

  @impl true
  def kind, do: "taxon_name"

  @impl true
  def changeset(name_fact, attrs) do
    name_fact
    |> cast(attrs, [:taxon_id, :name, :rank])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:taxon_id, :name, :rank])
    |> put_normalized(:name, :normalized_name)
    |> foreign_key_constraint(:taxon_id)
    |> unique_constraint([:taxon_id, :normalized_name, :rank])
  end

  defp put_normalized(changeset, from, to) do
    case get_change(changeset, from) do
      nil -> changeset
      value -> put_change(changeset, to, NameNormalizer.normalize(value))
    end
  end

  @impl true
  def slot(%__MODULE__{taxon_id: taxon_id}), do: "taxon:#{taxon_id}:name"

  @impl true
  def natural_key(%__MODULE__{} = n), do: {n.taxon_id, n.normalized_name, n.rank}

  @impl true
  def existing_query(%__MODULE__{} = n) do
    from(f in __MODULE__,
      where:
        f.taxon_id == ^n.taxon_id and f.normalized_name == ^n.normalized_name and
          f.rank == ^n.rank
    )
  end
end
