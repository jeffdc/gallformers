defmodule Gallformers.Taxonomy.Genus do
  @moduledoc "A taxonomic genus (e.g., Andricus, Quercus)."

  defstruct [:id, :name, :description]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          description: String.t() | nil
        }
end
