defmodule Gallformers.Taxa.Event do
  @moduledoc """
  A "taxon changed" event (`8567` rule 6), passed to the listeners of
  `Gallformers.Taxa.Events` after the change is written and before its
  transaction commits.

    * `:move` — `taxon_id` now sits under `to_parent_id` (nil for a root),
      having been under `from_parent_id`. Its subtree moved with it.
    * `:rename` — `taxon_id`'s accepted name is now `new_name`; `old_name`
      was the accepted name before.
    * `:rank` — `taxon_id`'s rank is now `new_rank`, having been `old_rank`.
    * `:add_synonym`, `:remove_synonym` — `taxon_id` gained the synonym
      `new_name`, or lost the synonym `old_name`.
    * `:merge` — `taxon_id` (a lump's absorbed taxon) is being merged into
      `into_taxon_id` (`old_name` and `new_name` their accepted names
      before the merge): its names and taxonomic-act Facts are the
      survivor's already, `fact_map` maps each of its act Facts to the
      survivor's Fact its statements moved onto (nil for one dropped);
      after the listeners it is deleted, so each listener moves what its
      side holds of it (`Gallformers.Taxa.merge/3`).
    * `:split` — `taxon_id` was divided into `into_taxon_ids` (which may
      hold `taxon_id` itself, in its narrow sense); `fact_id` is the split
      Fact that came into effect, when a Source's statement did.
    * `:host_range` — plant `taxon_id`'s Host range rows changed.

  Taxa emits `:move` (`Gallformers.Taxa.place/3`), `:rename`
  (`Gallformers.Taxa.rename/3`), `:rank` (`set_rank/3`), the synonym
  events (`add_synonym/4`, `remove_synonym/2`), `:merge` (`merge/3`) and
  `:split` (`split/3`). `Gallformers.Ranges` emits `:host_range`
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
    :old_rank,
    :new_rank,
    :fact_id,
    into_taxon_ids: [],
    fact_map: %{}
  ]

  @type type ::
          :move | :rename | :rank | :add_synonym | :remove_synonym | :merge | :split | :host_range

  @type t :: %__MODULE__{
          type: type(),
          taxon_id: integer(),
          from_parent_id: integer() | nil,
          to_parent_id: integer() | nil,
          old_name: String.t() | nil,
          new_name: String.t() | nil,
          into_taxon_id: integer() | nil,
          old_rank: atom() | nil,
          new_rank: atom() | nil,
          into_taxon_ids: [integer()],
          fact_id: integer() | nil,
          fact_map: %{integer() => integer() | nil}
        }
end
