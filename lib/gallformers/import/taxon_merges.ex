defmodule Gallformers.Import.TaxonMerges do
  @moduledoc """
  Import's "taxon changed" listener for lumps (`Gallformers.Taxa.Events`,
  matter `f923` Task 4): on a `:merge` event, before Taxa deletes the
  absorbed taxon, it moves what the Catalog and the import tables hold of
  it onto the survivor (`Gallformers.Import.Merge.repoint_lumped_taxon/5`:
  its Inducer and other gall Facts, the import rows naming it, its
  images), as the actor of the merge's transaction. An open question or a
  package under review naming the taxon refuses the merge
  (`{:error, {:blocked, blockers}}`).

  Registered after `Gallformers.Catalog.TaxonListener` and before
  `Gallformers.Import.GallRenames`, so the rename proposals see the Galls'
  Inducers re-pointed.
  """
  @behaviour Gallformers.Taxa.Events

  alias Gallformers.Audit
  alias Gallformers.Import.Merge
  alias Gallformers.Taxa.Event

  @impl true
  def taxon_changed(%Event{type: :merge} = event) do
    {:ok, actor} = Audit.current_actor()

    Merge.repoint_lumped_taxon(actor, event.taxon_id, event.into_taxon_id, event.fact_map, %{
      absorbed: event.old_name,
      survivor: event.new_name
    })
  end

  def taxon_changed(%Event{}), do: :ok
end
