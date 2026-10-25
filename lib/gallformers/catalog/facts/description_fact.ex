defmodule Gallformers.Catalog.Facts.DescriptionFact do
  @moduledoc """
  A description Fact's details (`9449` §4): the Gall's description. One
  Fact per Gall; each Source's description is its attribution's quotes (a
  collage of direct quotes, in reading order), so the details hold only the
  Gall.

  Natural key Gall; no slot.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Catalog.Assert

  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts.Fact

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          gall_id: integer() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "description_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :gall, Gall
  end

  @impl true
  def kind, do: "gall_description"

  @impl true
  def changeset(description, attrs) do
    description
    |> cast(attrs, [:gall_id])
    |> validate_required([:gall_id])
    |> foreign_key_constraint(:gall_id)
    |> unique_constraint(:gall_id)
  end

  @impl true
  def slot(_description), do: nil

  @impl true
  def natural_key(%__MODULE__{gall_id: gall_id}), do: gall_id

  @impl true
  def existing_query(%__MODULE__{gall_id: gall_id}),
    do: from(f in __MODULE__, where: f.gall_id == ^gall_id)
end
