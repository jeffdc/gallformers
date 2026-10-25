defmodule Gallformers.Catalog.Vocab.GenerationValue do
  @moduledoc """
  A generation value (`8567` *Generation groups*): a stage of the Inducer's
  life cycle that induces a clearly different Gall. Unique across groups, so
  a value names its group. `name_qualifier` is the text derived Gall names
  use for it (`8567` rule 9), e.g. `"sexgen"` for `sexual`.
  """
  use Ecto.Schema

  alias Gallformers.Catalog.Vocab.GenerationGroup

  @type t :: %__MODULE__{
          id: integer() | nil,
          group_id: integer() | nil,
          value: String.t() | nil,
          definition: String.t() | nil,
          name_qualifier: String.t() | nil,
          position: integer() | nil,
          group: GenerationGroup.t() | Ecto.Association.NotLoaded.t()
        }

  schema "generation_values" do
    field :value, :string
    field :definition, :string
    field :name_qualifier, :string
    field :position, :integer

    belongs_to :group, GenerationGroup
  end
end
