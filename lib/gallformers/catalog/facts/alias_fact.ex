defmodule Gallformers.Catalog.Facts.AliasFact do
  @moduledoc """
  An alias Fact's details (`9449` §4): a common name for the Gall.
  (Scientific names are taxon synonyms, in `Gallformers.Taxa`.)

  Natural key Gall + name, ignoring case; `name` keeps the form first
  recorded. No slot.
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
          name: String.t() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "alias_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :gall, Gall
    field :name, :string
  end

  @impl true
  def kind, do: "gall_alias"

  @impl true
  def changeset(alias_fact, attrs) do
    alias_fact
    |> cast(attrs, [:gall_id, :name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:gall_id, :name])
    |> foreign_key_constraint(:gall_id)
    |> unique_constraint(:name, name: :alias_facts_gall_id_name_index)
  end

  @impl true
  def slot(_alias_fact), do: nil

  @impl true
  def natural_key(%__MODULE__{} = a), do: {a.gall_id, String.downcase(a.name)}

  @impl true
  def existing_query(%__MODULE__{} = a) do
    from(f in __MODULE__,
      where: f.gall_id == ^a.gall_id and fragment("lower(?)", f.name) == ^String.downcase(a.name)
    )
  end
end
