defmodule Gallformers.Import.BatchUnmapped do
  @moduledoc """
  A batch's `unmapped` entry (`9449` §5): a Source term that fits no
  vocabulary value, kept with the batch for review and to show where the
  vocabularies should grow. Never a Fact by itself (`9449` §4): resolving
  queues each term for a curator, who may map or state it
  (`Gallformers.Import.SetAside`).

  Copied from the batch when it is validated, so not audited. A dispute
  decided `skip` on a Trait Fact adds one after the batch's own, keeping
  the Source's words as text on the Gall (`Gallformers.Import.Disputes`),
  inside the decision's audited transaction.
  """
  use Ecto.Schema

  alias Gallformers.Import.Batch

  @type t :: %__MODULE__{
          id: integer() | nil,
          batch_id: integer() | nil,
          position: non_neg_integer() | nil,
          term: String.t() | nil,
          slot: String.t() | nil,
          gall_ref: String.t() | nil,
          note: String.t() | nil,
          evidence: [map()],
          batch: Batch.t() | Ecto.Association.NotLoaded.t()
        }

  schema "batch_unmapped" do
    field :position, :integer
    field :term, :string
    field :slot, :string
    field :gall_ref, :string
    field :note, :string
    field :evidence, {:array, :map}, default: []

    belongs_to :batch, Batch
  end

  @doc "The rows for a decoded batch's `unmapped` entries, for `Repo.insert_all/2`."
  @spec rows(integer(), map()) :: [map()]
  def rows(batch_id, content) do
    content
    |> Map.get("unmapped", [])
    |> Enum.with_index()
    |> Enum.map(fn {entry, position} ->
      %{
        batch_id: batch_id,
        position: position,
        term: entry["term"],
        slot: entry["slot"],
        gall_ref: entry["gall"],
        note: entry["note"],
        evidence: entry["evidence"] || []
      }
    end)
  end
end
