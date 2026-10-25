defmodule Gallformers.Taxa.ActFacts.CommonNameFact do
  @moduledoc """
  A common-name Fact's details: the taxon's organism is called this (e.g.
  "Poplar vagabond aphid"). Natural key taxon + common name, ignoring case;
  `common_name` keeps the form first recorded. No slot. (Common names of
  Galls are alias Facts, owned by `Catalog`.)

  Recorded only in phase 1: the taxon's editorial common names
  (`taxon_common_names`) do not follow it.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Taxa.ActFacts

  alias Gallformers.Facts.Fact
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          taxon_id: integer() | nil,
          common_name: String.t() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t(),
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "common_name_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :taxon, Taxon
    field :common_name, :string
  end

  @impl true
  def kind, do: "taxon_common_name"

  @impl true
  def changeset(common_name, attrs) do
    common_name
    |> cast(attrs, [:taxon_id, :common_name])
    |> update_change(:common_name, &String.trim/1)
    |> validate_required([:taxon_id, :common_name])
    |> foreign_key_constraint(:taxon_id)
    |> unique_constraint(:common_name, name: :common_name_facts_taxon_id_common_name_index)
  end

  @impl true
  def slot(_common_name), do: nil

  @impl true
  def natural_key(%__MODULE__{} = c), do: {c.taxon_id, String.downcase(c.common_name)}

  @impl true
  def existing_query(%__MODULE__{} = c) do
    from(f in __MODULE__,
      where:
        f.taxon_id == ^c.taxon_id and
          fragment("lower(?)", f.common_name) == ^String.downcase(c.common_name)
    )
  end
end
