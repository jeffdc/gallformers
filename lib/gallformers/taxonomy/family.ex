defmodule Gallformers.Taxonomy.Family do
  @moduledoc "A taxonomic family (e.g., Cynipidae, Fagaceae)."

  defstruct [:id, :name, :description]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          description: String.t() | nil
        }
end
