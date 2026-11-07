defmodule Gallformers.Facts.Fact do
  @moduledoc """
  A Fact: one statement about the world, standing on its own, that Sources
  confirm or deny through `Gallformers.Facts.Attribution`s (`9449` §2).

    * `kind` names the kind of Fact; its typed details live in a table owned
      by `Catalog` or `Taxa`, keyed by this Fact's ID.
    * `standing` is precomputed by `Gallformers.Facts` from the attributions
      (`Gallformers.Facts.Standing`); hot reads use it.
    * `slot` groups Facts that compete for one value (a Gall's detachable, a
      taxon's placement), e.g. `"gall:123:detachable"`. Multi-valued kinds
      have none. It never changes once the Fact exists.
    * `contest` groups Facts in different slots (or none) that claim one
      thing for different holders, `contest_holder`: a name as one taxon's
      accepted name, or as a synonym of another (`"taxon_name:<normalized
      name>"`, held by `"taxon:<id>"`). Which kinds claim and which yield is
      `Gallformers.Facts`' data (`Gallformers.Facts.Standing.settle_contests/2`).
      Both or neither; never changed once the Fact exists.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Standing

  @standings [:current, :withdrawn, :superseded, :retracted, :unsupported]

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: String.t() | nil,
          standing: Standing.standing() | nil,
          slot: String.t() | nil,
          contest: String.t() | nil,
          contest_holder: String.t() | nil,
          attributions: [Attribution.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "facts" do
    field :kind, :string
    field :standing, Ecto.Enum, values: @standings, default: :unsupported
    field :slot, :string
    field :contest, :string
    field :contest_holder, :string

    has_many :attributions, Attribution

    timestamps(type: :utc_datetime)
  end

  @doc "Creates a changeset for a new Fact: its kind, slot and contest."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(fact, attrs) do
    fact
    |> cast(attrs, [:kind, :slot, :contest, :contest_holder])
    |> validate_required([:kind])
    |> check_constraint(:kind, name: :facts_kind_present, message: "can't be blank")
    |> check_constraint(:contest_holder,
      name: :facts_contest_holder,
      message: "is given with a contest, and only then"
    )
  end
end
