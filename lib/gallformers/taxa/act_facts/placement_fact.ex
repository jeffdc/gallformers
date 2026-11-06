defmodule Gallformers.Taxa.ActFacts.PlacementFact do
  @moduledoc """
  A placement Fact's details: the taxon sits under the parent, or at the
  root of the tree (`parent_id` nil). Natural key taxon + parent (the root
  one value); a taxon's placement Facts compete in the slot
  `"taxon:<id>:placement"`, so the newest current one wins. Recorded only in
  phase 1: the editorial tree (`taxa.parent_id`) does not follow it.
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
          parent_id: integer() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t(),
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t(),
          parent: Taxon.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "placement_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :taxon, Taxon
    belongs_to :parent, Taxon
  end

  @impl true
  def kind, do: "taxon_placement"

  @impl true
  def changeset(placement, attrs) do
    placement
    |> cast(attrs, [:taxon_id, :parent_id])
    |> validate_required([:taxon_id])
    |> validate_not_own_parent()
    |> foreign_key_constraint(:taxon_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:taxon_id, :parent_id], name: :placement_facts_natural_key_index)
  end

  defp validate_not_own_parent(changeset) do
    if get_field(changeset, :taxon_id) == get_field(changeset, :parent_id) do
      add_error(changeset, :parent_id, "can't be the taxon itself")
    else
      changeset
    end
  end

  @impl true
  def key(%__MODULE__{} = p), do: %{taxon_id: p.taxon_id, parent_id: p.parent_id}

  @impl true
  def slot(%__MODULE__{taxon_id: taxon_id}), do: "taxon:#{taxon_id}:placement"

  @impl true
  def natural_key(%__MODULE__{taxon_id: taxon_id, parent_id: parent_id}),
    do: {taxon_id, parent_id}

  @impl true
  def existing_query(%__MODULE__{taxon_id: taxon_id, parent_id: nil}) do
    from(p in __MODULE__, where: p.taxon_id == ^taxon_id and is_nil(p.parent_id))
  end

  def existing_query(%__MODULE__{taxon_id: taxon_id, parent_id: parent_id}) do
    from(p in __MODULE__, where: p.taxon_id == ^taxon_id and p.parent_id == ^parent_id)
  end
end
