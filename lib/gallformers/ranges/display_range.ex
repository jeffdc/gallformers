defmodule Gallformers.Ranges.DisplayRange do
  @moduledoc """
  Represents range data expanded for map display.

  - `in_range` — exact leaf codes (host confirmed in specific subdivision)
  - `inherited_range` — leaf codes expanded from country-level ranges
  - `introduced_range` — leaf codes from "introduced" distribution_type entries
  """
  defstruct in_range: [], inherited_range: [], introduced_range: []

  @type t :: %__MODULE__{
          in_range: [String.t()],
          inherited_range: [String.t()],
          introduced_range: [String.t()]
        }
end
