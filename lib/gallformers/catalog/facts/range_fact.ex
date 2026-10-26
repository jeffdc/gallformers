defmodule Gallformers.Catalog.Facts.RangeFact do
  @moduledoc """
  A range-adjustment Fact's details (`9449` §4; `8567` rule 10): an
  adjustment to the Gall's potential range, which is computed from its
  Hosts' ranges and never stored
  (`Gallformers.Catalog.ReadModels.PotentialRange`).

    * `:exclude` — the Gall does not occur in a place within its Hosts'
      ranges
    * `:only` — it occurs only in this place (one Fact per place)

  There is no adjustment that widens the range: a Gall's range never leaves
  every one of its Hosts' ranges. A place where a Source says the Gall
  occurs but none of its Hosts grows is a recorded occurrence
  (`Gallformers.Catalog.Facts.OccurrenceFact`).

  Natural key Gall + adjustment + place. The adjustments for one Gall and
  place compete in the slot `"gall:<id>:place:<place_id>"`, so when an
  `exclude` and an `only` name the same place, the newest current one wins.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Catalog.Assert

  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts.Fact
  alias Gallformers.Places.Place

  @type adjustment :: :exclude | :only

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          gall_id: integer() | nil,
          adjustment: adjustment() | nil,
          place_id: integer() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "range_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :gall, Gall
    field :adjustment, Ecto.Enum, values: [:exclude, :only]
    belongs_to :place, Place
  end

  @impl true
  def kind, do: "gall_range"

  @impl true
  def changeset(range, attrs) do
    range
    |> cast(attrs, [:gall_id, :adjustment, :place_id])
    |> validate_required([:gall_id, :adjustment, :place_id])
    |> foreign_key_constraint(:gall_id)
    |> foreign_key_constraint(:place_id)
    |> unique_constraint([:gall_id, :adjustment, :place_id])
  end

  @impl true
  def slot(%__MODULE__{gall_id: gall_id, place_id: place_id}),
    do: "gall:#{gall_id}:place:#{place_id}"

  @impl true
  def natural_key(%__MODULE__{} = r), do: {r.gall_id, r.adjustment, r.place_id}

  @impl true
  def existing_query(%__MODULE__{} = r) do
    from(f in __MODULE__,
      where:
        f.gall_id == ^r.gall_id and f.adjustment == ^r.adjustment and f.place_id == ^r.place_id
    )
  end
end
