defmodule Gallformers.Catalog.Facts.OccurrenceFact do
  @moduledoc """
  A recorded-occurrence Fact's details (`9449` §4): a place where a Source
  says the Gall has been recorded. When and at what stage are each Source's
  own words and go on its attribution (`when_as_written`,
  `stage_as_written`), as does the place as written (`value_as_written`),
  so two Sources recording one place make one Fact with two attributions.

  Natural key Gall + place; no slot. Separate from range adjustments.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Catalog.Assert

  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts.Fact
  alias Gallformers.Places.Place

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          gall_id: integer() | nil,
          place_id: integer() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "occurrence_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :gall, Gall
    belongs_to :place, Place
  end

  @impl true
  def kind, do: "gall_occurrence"

  @impl true
  def changeset(occurrence, attrs) do
    occurrence
    |> cast(attrs, [:gall_id, :place_id])
    |> validate_required([:gall_id, :place_id])
    |> foreign_key_constraint(:gall_id)
    |> foreign_key_constraint(:place_id)
    |> unique_constraint([:gall_id, :place_id])
  end

  @impl true
  def slot(_occurrence), do: nil

  @impl true
  def natural_key(%__MODULE__{} = o), do: {o.gall_id, o.place_id}

  @impl true
  def existing_query(%__MODULE__{} = o) do
    from(f in __MODULE__, where: f.gall_id == ^o.gall_id and f.place_id == ^o.place_id)
  end
end
