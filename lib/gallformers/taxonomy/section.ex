defmodule Gallformers.Taxonomy.Section do
  @moduledoc "A taxonomic section, an optional subdivision within a genus."

  defstruct [:id, :name, :description]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          description: String.t() | nil
        }
end
