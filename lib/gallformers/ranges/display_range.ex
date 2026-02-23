defmodule Gallformers.Ranges.DisplayRange do
  @moduledoc """
  Represents range data expanded for map display.

  - `in_range` — exact leaf codes (host confirmed in specific subdivision)
  - `inherited_range` — leaf codes expanded from country-level ranges
  - `excluded_range` — explicitly excluded codes (galls only, empty for hosts)
  """
  defstruct in_range: [], inherited_range: [], excluded_range: []

  @type t :: %__MODULE__{
          in_range: [String.t()],
          inherited_range: [String.t()],
          excluded_range: [String.t()]
        }
end
