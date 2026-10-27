defmodule Gallformers.Taxa.Event do
  @moduledoc """
  A "taxon changed" event (`8567` rule 6), passed to the listeners of
  `Gallformers.Taxa.Events` after the change is written and before its
  transaction commits.

    * `:move` — `taxon_id` now sits under `to_parent_id` (nil for a root),
      having been under `from_parent_id`. Its subtree moved with it.
    * `:rename` — `taxon_id`'s accepted name is now `new_name`; `old_name`
      was the accepted name before.
    * `:merge` — `taxon_id` was merged into `into_taxon_id`.
    * `:split` — `taxon_id` was divided into `into_taxon_ids`.
    * `:host_range` — plant `taxon_id`'s Host range rows changed.

  Taxa emits `:move` (`Gallformers.Taxa.place/3`) and `:rename`
  (`Gallformers.Taxa.rename/3`) in phase 1; merges and splits come with the
  operations that make them. `Gallformers.Ranges` emits `:host_range`
  (`Gallformers.Ranges.update_taxon_places/3`): the range is the taxon's,
  kept outside Taxa.
  """

  @enforce_keys [:type, :taxon_id]
  defstruct [
    :type,
    :taxon_id,
    :from_parent_id,
    :to_parent_id,
    :old_name,
    :new_name,
    :into_taxon_id,
    into_taxon_ids: []
  ]

  @type type :: :move | :rename | :merge | :split | :host_range

  @type t :: %__MODULE__{
          type: type(),
          taxon_id: integer(),
          from_parent_id: integer() | nil,
          to_parent_id: integer() | nil,
          old_name: String.t() | nil,
          new_name: String.t() | nil,
          into_taxon_id: integer() | nil,
          into_taxon_ids: [integer()]
        }
end
