defmodule Gallformers.Catalog.Vocab.GenerationGroup do
  @moduledoc """
  A named set of generation values (`8567` *Generation groups*), e.g.
  heterogony (agamic, sexual). Each group is mapped to taxa at any rank
  (`Gallformers.Catalog.Vocab.GenerationGroupTaxon`); a Gall's generation
  must come from a group that applies to its Inducer.
  """
  use Ecto.Schema

  alias Gallformers.Catalog.Vocab.GenerationGroupTaxon
  alias Gallformers.Catalog.Vocab.GenerationValue

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          values: [GenerationValue.t()] | Ecto.Association.NotLoaded.t(),
          taxa: [GenerationGroupTaxon.t()] | Ecto.Association.NotLoaded.t()
        }

  schema "generation_groups" do
    field :name, :string
    field :description, :string

    has_many :values, GenerationValue, foreign_key: :group_id, preload_order: [asc: :position]
    has_many :taxa, GenerationGroupTaxon, foreign_key: :group_id
  end
end
