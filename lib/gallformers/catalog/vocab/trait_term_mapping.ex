defmodule Gallformers.Catalog.Vocab.TraitTermMapping do
  @moduledoc """
  A common Source term mapped onto a Trait's values (`traits.json`
  `mappings`): `maps_to` the values it stands for, or `candidates` to choose
  between by definition, following `rule`. Unique on trait + term.

  Trait `"generation"` holds the generation values' other names (e.g. "stem
  mother" → fundatrix, `8567` *Aphid life-cycle values*).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          trait: String.t() | nil,
          term: String.t() | nil,
          maps_to: [String.t()],
          candidates: [String.t()],
          rule: String.t() | nil
        }

  schema "trait_term_mappings" do
    field :trait, :string
    field :term, :string
    field :maps_to, {:array, :string}, default: []
    field :candidates, {:array, :string}, default: []
    field :rule, :string
  end
end
