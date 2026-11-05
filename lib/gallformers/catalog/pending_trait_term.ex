defmodule Gallformers.Catalog.PendingTraitTerm do
  @moduledoc """
  A Source's Trait term on a Gall that has no Fact yet (matter `d213`):
  an ambiguous term's use, a disagreement between the readers, or a new
  term they didn't agree on, waiting on a curator's question. It is shown
  on the Gall's page, not in the ID tool, and holds nothing.

  Keeps its origin — the Source, the package and batch, the statement
  (`statement_ref`), the quotes (`evidence`, as the batch gives them) and
  the queue item asking about it — and, once settled, when
  (`settled_at`), under which categories (`settled_categories`: one, or
  each value a term names; none when kept as text) and why (`settled_as`: `"category"`; `"no_fit"`, as text because
  the term fits no category, turned into a Fact if the term is placed
  later; `"kept"`, as text because a curator chose so for this Gall, which
  stands). One per Gall, Source, Trait and normalized term
  (`Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue

  @type t :: %__MODULE__{
          id: integer() | nil,
          gall_id: integer() | nil,
          source_id: integer() | nil,
          package_id: integer() | nil,
          batch_id: integer() | nil,
          queue_item_id: integer() | nil,
          statement_ref: String.t() | nil,
          trait: String.t() | nil,
          term: String.t() | nil,
          normalized_term: String.t() | nil,
          evidence: [map()],
          settled_at: DateTime.t() | nil,
          settled_categories: [String.t()],
          settled_as: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @fields [
    :gall_id,
    :source_id,
    :package_id,
    :batch_id,
    :queue_item_id,
    :statement_ref,
    :trait,
    :term,
    :evidence
  ]

  schema "pending_trait_terms" do
    belongs_to :gall, Gall
    field :source_id, :integer
    field :package_id, :integer
    field :batch_id, :integer
    field :queue_item_id, :integer
    field :statement_ref, :string
    field :trait, :string
    field :term, :string
    field :normalized_term, :string
    field :evidence, {:array, :map}, default: []
    field :settled_at, :utc_datetime
    field :settled_categories, {:array, :string}, default: []
    field :settled_as, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for a waiting term: `:gall_id`, `:source_id`, `:package_id`,
  `:batch_id`, `:trait` (a Trait; generation is not one) and `:term`,
  required; `:queue_item_id`, `:statement_ref`, `:evidence`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pending, attrs) do
    pending
    |> cast(attrs, @fields)
    |> update_change(:term, &String.trim/1)
    |> validate_required([:gall_id, :source_id, :package_id, :batch_id, :trait, :term])
    |> validate_inclusion(:trait, TraitValue.traits())
    |> put_normalized_term()
    |> unique_constraint([:gall_id, :source_id, :trait, :normalized_term], error_key: :term)
    |> foreign_key_constraint(:gall_id)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:package_id)
    |> foreign_key_constraint(:batch_id)
    |> foreign_key_constraint(:queue_item_id)
  end

  defp put_normalized_term(changeset) do
    case get_change(changeset, :term) do
      term when is_binary(term) ->
        put_change(changeset, :normalized_term, TraitTermMapping.normalize(term))

      _ ->
        changeset
    end
  end
end
