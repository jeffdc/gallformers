defmodule Gallformers.Facts.Standing.Conflict do
  @moduledoc """
  A disagreement the standing rules cannot settle, for a curator to decide.

    * `:same_date` — one Fact's newest attributions tie on date and disagree
      in stance (rule 3). `fact_ids` is that one Fact; `attributions` are the
      tied newest attributions.
    * `:slot_tie` — several current Facts in one slot tie for the newest
      confirmation (rule 5). `fact_ids` are the tied Facts; `attributions`
      are their tied confirmations.

  The Facts involved keep their previous standing until it is decided
  (`Gallformers.Facts.Standing`). `attributions` are the maps the caller gave
  `Gallformers.Facts.Standing`, so they carry whatever identifies them there
  (the `Gallformers.Facts` context passes attribution and Source IDs).
  """

  @enforce_keys [:type, :fact_ids, :attributions]
  defstruct [:type, :fact_ids, :attributions]

  @type type :: :same_date | :slot_tie

  @type t :: %__MODULE__{
          type: type(),
          fact_ids: [term()],
          attributions: [map()]
        }
end
