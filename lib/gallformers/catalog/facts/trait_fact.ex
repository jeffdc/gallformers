defmodule Gallformers.Catalog.Facts.TraitFact do
  @moduledoc """
  A Trait Fact's details (`9449` §4): the Gall has this Trait value
  (`Gallformers.Catalog.Vocab.TraitValue`). Asserted by `trait` and `value`
  names, resolved to the value's row; the Source's own word goes on its
  attribution (`value_as_written`).

  Natural key Gall + Trait value. Multi-valued Traits have no slot;
  `detachable` has one value per Gall, so its Facts compete in the slot
  `"gall:<id>:detachable"` and the newest current one wins. Generation is
  not a Trait Fact: it identifies the Gall.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Catalog.Assert

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Facts.Fact
  alias Gallformers.Repo

  @single_valued ["detachable"]

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          gall_id: integer() | nil,
          trait_value_id: integer() | nil,
          trait: String.t() | nil,
          value: String.t() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t(),
          trait_value: TraitValue.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "trait_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :gall, Gall
    belongs_to :trait_value, TraitValue
    # The Trait value asserted, by name; resolved to `trait_value_id`.
    field :trait, :string, virtual: true
    field :value, :string, virtual: true
  end

  @impl true
  def kind, do: "gall_trait"

  @impl true
  def changeset(trait_fact, attrs) do
    trait_fact
    |> cast(attrs, [:gall_id, :trait, :value])
    |> validate_required([:gall_id, :trait, :value])
    |> validate_inclusion(:trait, TraitValue.traits())
    |> foreign_key_constraint(:gall_id)
    |> foreign_key_constraint(:trait_value_id)
    |> unique_constraint([:gall_id, :trait_value_id])
  end

  @impl true
  def prepare(changeset) do
    trait = get_field(changeset, :trait)
    value = get_field(changeset, :value)

    case Repo.one(
           from(t in TraitValue, where: t.trait == ^trait and t.value == ^value, select: t.id)
         ) do
      nil -> add_error(changeset, :value, "is not a #{trait} value")
      id -> put_change(changeset, :trait_value_id, id)
    end
  end

  @impl true
  def slot(%__MODULE__{trait: trait, gall_id: gall_id}) when trait in @single_valued,
    do: "gall:#{gall_id}:#{trait}"

  def slot(_trait_fact), do: nil

  @impl true
  def natural_key(%__MODULE__{} = t), do: {t.gall_id, t.trait_value_id}

  @impl true
  def existing_query(%__MODULE__{} = t) do
    from(f in __MODULE__,
      where: f.gall_id == ^t.gall_id and f.trait_value_id == ^t.trait_value_id
    )
  end
end
