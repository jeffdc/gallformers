defmodule Gallformers.Import.ReplayEntry do
  @moduledoc """
  One entry of the replay log (`9449` §5): a data-changing step during the
  backscan on preview, recorded in order by stable keys (`batch_id` and
  statement refs, taxon names, legacy IDs — never database IDs), so it can
  be replayed after the cutover data migration (Task 14).

  Kinds: `:batch_applied`, `:queue_decision`, `:synonym_added`,
  `:plant_added`, `:taxonomy_edit`, `:package_denied`, `:batch_denied`,
  `:source_edit`, `:trait_value_added`, `:term_mapping_added` (6611's,
  replayed only), `:trait_term_edit`, `:vocab_requests_decided` (6611's
  vocabulary backlog, replaced by the vocabulary page of `d213`: no longer
  written, kept so earlier entries load), `:fact_edit` and
  `:fact_edit_removed` (a curator's edits on a package's Facts,
  `Gallformers.Import.FactEdits`), `:fact_note` and `:taxon_note`
  (curators' notes, `Gallformers.Import.CurationNotes`), `:deletion` and
  `:merge` (a Gall or taxon deleted, a Gall or plant merged:
  `Gallformers.Import.Deletion`, `Gallformers.Import.Merge`), and
  `:taxonomic_decision` (a Source's taxonomic statement accepted, declined
  or reopened: `Gallformers.Import.TaxonomicDecisions`) and
  `:taxonomic_statement` (a statement the taxonomy admin credits to a
  Source: `Gallformers.Import.TaxonomyStatements`), `:source_correction`
  (a curator's correction to a Source's applied Facts:
  `Gallformers.Import.SourceCorrections`) and `:queue_decision_undone` (a
  decided question undone, keyed as its `:queue_decision`:
  `Gallformers.Import.Undo`). The log is ordered by `id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [
    :batch_applied,
    :queue_decision,
    :synonym_added,
    :plant_added,
    :taxonomy_edit,
    :package_denied,
    :batch_denied,
    :source_edit,
    :trait_value_added,
    :term_mapping_added,
    :trait_term_edit,
    :vocab_requests_decided,
    :fact_edit,
    :fact_edit_removed,
    :fact_note,
    :taxon_note,
    :deletion,
    :merge,
    :taxonomic_decision,
    :taxonomic_statement,
    :source_correction,
    :queue_decision_undone
  ]

  @type kind ::
          :batch_applied
          | :queue_decision
          | :synonym_added
          | :plant_added
          | :taxonomy_edit
          | :package_denied
          | :batch_denied
          | :source_edit
          | :trait_value_added
          | :term_mapping_added
          | :trait_term_edit
          | :vocab_requests_decided
          | :fact_edit
          | :fact_edit_removed
          | :fact_note
          | :taxon_note
          | :deletion
          | :merge
          | :taxonomic_decision
          | :taxonomic_statement
          | :source_correction
          | :queue_decision_undone

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: kind() | nil,
          key: map() | nil,
          payload: map(),
          inserted_at: DateTime.t() | nil
        }

  schema "replay_log" do
    field :kind, Ecto.Enum, values: @kinds
    field :key, :map
    field :payload, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The entry kinds."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "A changeset for a new entry: `kind`, `key` (stable references), `payload`."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:kind, :key, :payload])
    |> validate_required([:kind, :key])
  end
end
