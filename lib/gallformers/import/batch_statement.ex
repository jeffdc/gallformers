defmodule Gallformers.Import.BatchStatement do
  @moduledoc """
  One statement of a batch — a taxon (`kind: :taxon`, ref `t1`), a Gall
  (`:gall`, `g1`), an act (`:act`, `a1`) or a Fact (`:fact`, `f1`) — with
  how it resolved (`9449` §5):

    * `resolution` — `:resolved` (to `taxon_id` / `gall_id`, or for an
      act or Fact to an existing `fact_id`), `:ambiguous` (several
      `candidate_ids`), `:unresolved`, or `:new` (the Source presents it as
      new).
    * `method` — how it resolved (`"exact"`, `"synonym"`, `"abbreviation"`,
      `"name_reading"`, `"fused_epithet"`, `"identified_by"`,
      `"undescribed"`, …).
    * `flags` — what a curator must look at even when resolved, e.g.
      `"synonym_held_valid"` (the tree holds the name as a synonym while
      this Source treats it as valid: never merged silently).
    * `detail` — the names as written and tried, the reason.
    * `delta` — when applied: `:confirms_existing`, `:new` or
      `:denies_or_replaces` (Task 13).

  Derived from the batch and rebuilt each time it is resolved, so not
  audited; decisions about statements are queue items.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Import.Batch

  @type kind :: :taxon | :gall | :act | :fact
  @type resolution :: :resolved | :ambiguous | :unresolved | :new

  @type t :: %__MODULE__{
          id: integer() | nil,
          batch_id: integer() | nil,
          kind: kind() | nil,
          ref: String.t() | nil,
          resolution: resolution() | nil,
          method: String.t() | nil,
          taxon_id: integer() | nil,
          gall_id: integer() | nil,
          fact_id: integer() | nil,
          candidate_ids: [integer()],
          flags: [String.t()],
          detail: map(),
          delta: :confirms_existing | :new | :denies_or_replaces | nil,
          batch: Batch.t() | Ecto.Association.NotLoaded.t()
        }

  schema "batch_statements" do
    field :kind, Ecto.Enum, values: [:taxon, :gall, :act, :fact]
    field :ref, :string
    field :resolution, Ecto.Enum, values: [:resolved, :ambiguous, :unresolved, :new]
    field :method, :string
    field :taxon_id, :integer
    field :gall_id, :integer
    field :fact_id, :integer
    field :candidate_ids, {:array, :integer}, default: []
    field :flags, {:array, :string}, default: []
    field :detail, :map, default: %{}
    field :delta, Ecto.Enum, values: [:confirms_existing, :new, :denies_or_replaces]

    belongs_to :batch, Batch
  end

  @fields [
    :batch_id,
    :kind,
    :ref,
    :resolution,
    :method,
    :taxon_id,
    :gall_id,
    :fact_id,
    :candidate_ids,
    :flags,
    :detail,
    :delta
  ]

  @doc "A changeset for a statement's resolution."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(statement, attrs) do
    statement
    |> cast(attrs, @fields)
    |> validate_required([:batch_id, :kind, :ref, :resolution])
    |> unique_constraint([:batch_id, :kind, :ref])
    |> foreign_key_constraint(:batch_id)
    |> foreign_key_constraint(:taxon_id)
    |> foreign_key_constraint(:gall_id)
    |> foreign_key_constraint(:fact_id)
  end
end
