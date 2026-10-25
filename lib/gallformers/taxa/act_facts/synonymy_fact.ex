defmodule Gallformers.Taxa.ActFacts.SynonymyFact do
  @moduledoc """
  A synonymy Fact's details: `name` is a synonym of the accepted taxon.

  In phase 1 a synonym is a name, not a taxon: the Source's synonym may be
  one the tree already holds as a name of the accepted taxon, so it resolves
  to that taxon itself. The natural key is therefore the synonym's
  normalized name (`Gallformers.Taxa.NameNormalizer`) + the accepted taxon;
  what each Source's name resolved to is on its attribution's names. A lump
  is several synonymy Facts. No slot.

  Recorded only in phase 1: the tree's names do not follow it.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Taxa.ActFacts

  alias Gallformers.Facts.Fact
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          name: String.t() | nil,
          normalized_name: String.t() | nil,
          accepted_taxon_id: integer() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t(),
          accepted_taxon: Taxon.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "synonymy_facts" do
    belongs_to :fact, Fact, primary_key: true
    field :name, :string
    field :normalized_name, :string
    belongs_to :accepted_taxon, Taxon
  end

  @impl true
  def kind, do: "taxon_synonymy"

  @impl true
  def changeset(synonymy, attrs) do
    synonymy
    |> cast(attrs, [:name, :accepted_taxon_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :accepted_taxon_id])
    |> put_normalized_name()
    |> foreign_key_constraint(:accepted_taxon_id)
    |> unique_constraint([:normalized_name, :accepted_taxon_id])
  end

  defp put_normalized_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :normalized_name, NameNormalizer.normalize(name))
    end
  end

  @impl true
  def slot(_synonymy), do: nil

  @impl true
  def natural_key(%__MODULE__{} = s), do: {s.normalized_name, s.accepted_taxon_id}

  @impl true
  def existing_query(%__MODULE__{} = s) do
    from(f in __MODULE__,
      where:
        f.normalized_name == ^s.normalized_name and f.accepted_taxon_id == ^s.accepted_taxon_id
    )
  end
end
