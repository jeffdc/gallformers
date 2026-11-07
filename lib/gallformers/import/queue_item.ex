defmodule Gallformers.Import.QueueItem do
  @moduledoc """
  An item in the admin queue (`9449` §5; `e381`): something an import
  cannot settle on its own. Nothing ambiguous is applied automatically.

  Kinds:

    * `:ambiguous_match` — a name or Gall matched several entries
      (`proposal` lists them, with the reason)
    * `:unresolved_name` — a name that matched nothing and is not new
    * `:unresolved_host` — a Host name that matched no plant; the gall
      batch waits until an admin adds a synonym or the plant (`d585`)
    * `:undescribed_gall` — candidate undescribed Gall entries for a Gall
      the Source describes (one proposed, or several offered)
    * `:dispute` — a phase 6 finding the producer disputes
    * `:same_date_conflict` — opposite stances on one Fact with the same date
      (or several current Facts of one slot tied for the newest). One a
      merge brought about (`Gallformers.Import.Merge`) comes from no
      package: its `subject` names the Facts (`"fact_ids"`), the Gall they
      are about (`"gall_id"`) and the merge (`"merge"`), its
      `statement_ref` is `"merge:"` and the Facts' words
    * `:taxonomy_disagreement` — a taxonomic act, or a name held valid, that
      disagrees with the tree
    * `:generation_outside_group` — a generation outside its Inducer's groups
    * `:gall_rename` — a taxonomy change would change a Gall's derived name
      (`Gallformers.Import.GallRenames`): `subject` is `%{"gall_id"}`,
      `proposal` `%{"gall_id", "from", "to", "collision"}`. It comes from no
      package (`package_id` is nil for this kind only), and a Gall has at
      most one open.
    * `:set_aside_statement` — a statement the producer set aside
      (`unmapped`) as hedged or not a Fact. One per term within a package,
      covering every Gall it was set aside for
      (`Gallformers.Import.SetAside`). Never blocking.
    * `:trait_term` — a Source's Trait term the import could not place on
      its own (matter `d213`): an ambiguous term's use, a new term the
      readers placed differently, a format 3 term
      (`Gallformers.Import.TraitTerms`). One per term within a package,
      covering its Galls. Never blocking.
    * `:set_aside_term` — before `:trait_term`, a Trait term the producer
      set aside. No longer made; kept so that older rows load.
    * `:taxonomy_acceptance` — a Source's taxonomic statement (placement,
      name, synonymy, split, common name) that differs from the tree and is
      newer than the latest accepted statement in its slot: accept it (the
      tree follows) or decline it with a reason (matter `f923` Task 6,
      `Gallformers.Import.TaxonomyQueue`). `subject` names the statement
      (`"fact_id"`, `"attribution_id"`, `"source_id"`) and what it states.
      One queue across Sources: its package is optional (nil for a
      statement reopened after its package was applied), it never holds
      approval, and a statement has at most one open.
    * `:split_inducer` — an accepted split of the Gall's Inducer: which
      taxon induces it now, a daughter or not known yet (matter `f923`
      "Splits", `Gallformers.Import.SplitQuestions`). `subject` is
      `%{"gall_id", "taxon_id", "into_taxon_ids", "fact_id", "source_id"}`.
      It comes from no package (optional, as for `:taxonomy_acceptance`),
      never holds approval, and a Gall has at most one open.

  `statement_ref` is the batch statement it is about (`t1`, `g1`, `f3`;
  `u:<slot>:<term>` for what was set aside and for a Trait term);
  `subject` what it is about, `proposal` the proposed answer and
  candidates, `decision` the admin's answer with `decided_by_*` and
  `decided_at`. An open item's proposal can be rejected
  (`proposal_rejected_at`, `proposal_rejected_by_name`): the item stays
  open, and accepting proposals in bulk leaves it out
  (`Gallformers.Import.Proposals`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package

  @kinds [
    :ambiguous_match,
    :unresolved_name,
    :unresolved_host,
    :undescribed_gall,
    :dispute,
    :same_date_conflict,
    :taxonomy_disagreement,
    :generation_outside_group,
    :gall_rename,
    :set_aside_term,
    :set_aside_statement,
    :trait_term,
    :taxonomy_acceptance,
    :split_inducer
  ]

  @type kind ::
          :ambiguous_match
          | :unresolved_name
          | :unresolved_host
          | :undescribed_gall
          | :dispute
          | :same_date_conflict
          | :taxonomy_disagreement
          | :generation_outside_group
          | :gall_rename
          | :set_aside_term
          | :set_aside_statement
          | :trait_term
          | :taxonomy_acceptance
          | :split_inducer

  @type t :: %__MODULE__{
          id: integer() | nil,
          package_id: integer() | nil,
          batch_id: integer() | nil,
          kind: kind() | nil,
          statement_ref: String.t() | nil,
          subject: map(),
          proposal: map(),
          reason: String.t() | nil,
          status: :open | :decided | nil,
          decision: map() | nil,
          decided_by_user_id: integer() | nil,
          decided_by_name: String.t() | nil,
          decided_at: DateTime.t() | nil,
          proposal_rejected_at: DateTime.t() | nil,
          proposal_rejected_by_name: String.t() | nil,
          package: Package.t() | Ecto.Association.NotLoaded.t() | nil,
          batch: Batch.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "queue_items" do
    field :kind, Ecto.Enum, values: @kinds
    field :statement_ref, :string
    field :subject, :map, default: %{}
    field :proposal, :map, default: %{}
    field :reason, :string
    field :status, Ecto.Enum, values: [:open, :decided], default: :open
    field :decision, :map
    field :decided_by_user_id, :integer
    field :decided_by_name, :string
    field :decided_at, :utc_datetime
    field :proposal_rejected_at, :utc_datetime
    field :proposal_rejected_by_name, :string

    belongs_to :package, Package
    belongs_to :batch, Batch

    timestamps(type: :utc_datetime)
  end

  @doc "Every queue item kind."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  A changeset recording an admin's `decision` (a map, checked by
  `Gallformers.Import.Queue`) on an open item, with who (`actor`) and when.
  """
  @spec decide_changeset(t(), map(), Gallformers.Audit.Actor.t()) :: Ecto.Changeset.t()
  def decide_changeset(item, decision, actor) do
    item
    |> change(
      status: :decided,
      decision: decision,
      decided_by_user_id: if(actor.type == :user, do: actor.id),
      decided_by_name: actor.name,
      decided_at: DateTime.utc_now(:second)
    )
    |> check_constraint(:decision, name: :queue_items_decided_check)
  end

  @doc """
  A changeset marking an open item's proposal rejected by `actor` (nil:
  restoring it).
  """
  @spec reject_changeset(t(), Gallformers.Audit.Actor.t() | nil) :: Ecto.Changeset.t()
  def reject_changeset(item, nil),
    do: change(item, proposal_rejected_at: nil, proposal_rejected_by_name: nil)

  def reject_changeset(item, actor),
    do:
      change(item,
        proposal_rejected_at: DateTime.utc_now(:second),
        proposal_rejected_by_name: actor.name
      )

  @doc """
  A changeset for a new (open) queue item. Every kind but `:gall_rename`
  needs its package, but a `:same_date_conflict` a merge brought about, a
  `:taxonomy_acceptance` and a `:split_inducer` (where the package is
  optional).
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:package_id, :batch_id, :kind, :statement_ref, :subject, :proposal, :reason])
    |> validate_required([:kind])
    |> validate_package()
    |> unique_constraint([:batch_id, :kind, :statement_ref], name: :queue_items_statement_unique)
    |> unique_constraint(:subject, name: :queue_items_open_gall_rename_index)
    |> unique_constraint(:subject, name: :queue_items_open_taxonomy_acceptance_index)
    |> unique_constraint(:subject, name: :queue_items_open_split_inducer_index)
    |> check_constraint(:package_id, name: :queue_items_package_check)
    |> foreign_key_constraint(:package_id)
    |> foreign_key_constraint(:batch_id)
  end

  defp validate_package(changeset) do
    case get_field(changeset, :kind) do
      :gall_rename ->
        validate_change(changeset, :package_id, fn _, _ -> [package_id: "must be empty"] end)

      kind when kind in [:same_date_conflict, :taxonomy_acceptance, :split_inducer] ->
        changeset

      _kind ->
        validate_required(changeset, [:package_id])
    end
  end
end
