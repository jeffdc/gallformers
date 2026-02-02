defmodule Gallformers.FilterFields.Season do
  @moduledoc """
  Ecto schema for the season table.

  Seasons when galls can be observed (e.g., "spring", "summer", "fall", "winter").
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          season: String.t() | nil
        }

  schema "season" do
    field :season, :string
  end
end
