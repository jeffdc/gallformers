defmodule Gallformers.Facts.Attribution do
  @moduledoc """
  One Source's stance on one Fact (`9449` §2): it confirms or denies it, as
  of `stated_on`. There is at most one per Fact and Source; a Source that
  states the Fact again (a re-import, a newer Gallformers statement) updates
  it, and audit keeps what it replaced.

    * `stated_on` / `stated_precision` — a partial date stored as the first
      day of its period (`Gallformers.Sources.PartialDate`): the Source's
      authored date, or for Gallformers the statement's own date. Both are
      nil for an undated (legacy) statement.
    * `value_as_written` — a controlled value as the Source wrote it.
    * `batch_id` — the import batch that last wrote it.
    * `statement_text` — Gallformers' statement; required for the Gallformers
      Source.
    * `when_as_written`, `stage_as_written` — for occurrences.
    * `status_as_written`, `authorship_as_written` — for taxonomic acts: the
      Source's own status words ("syn. nov.", "comb. nov.") and, for a name,
      its authorship ("(Ashmead, 1881)"), as written.

  Evidence (quotes), the taxa it names, and the Observations it cites are
  `Gallformers.Facts.Evidence`, `Gallformers.Facts.AttributionName` and
  `Gallformers.Facts.AttributionObservation`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Facts.AttributionName
  alias Gallformers.Facts.AttributionObservation
  alias Gallformers.Facts.Evidence
  alias Gallformers.Facts.Fact
  alias Gallformers.Facts.Standing
  alias Gallformers.Sources.PartialDate
  alias Gallformers.Sources.Source

  @type t :: %__MODULE__{
          id: integer() | nil,
          fact_id: integer() | nil,
          source_id: integer() | nil,
          stance: Standing.stance() | nil,
          stated_on: Date.t() | nil,
          stated_precision: PartialDate.precision() | nil,
          value_as_written: String.t() | nil,
          batch_id: integer() | nil,
          statement_text: String.t() | nil,
          when_as_written: String.t() | nil,
          stage_as_written: String.t() | nil,
          status_as_written: String.t() | nil,
          authorship_as_written: String.t() | nil,
          evidence: [Evidence.t()] | Ecto.Association.NotLoaded.t(),
          names: [AttributionName.t()] | Ecto.Association.NotLoaded.t(),
          observations: [AttributionObservation.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @fields [
    :fact_id,
    :stance,
    :value_as_written,
    :batch_id,
    :statement_text,
    :when_as_written,
    :stage_as_written,
    :status_as_written,
    :authorship_as_written
  ]

  schema "attributions" do
    field :stance, Ecto.Enum, values: [:confirm, :deny]
    field :stated_on, :date
    field :stated_precision, Ecto.Enum, values: [:year, :month, :day]
    field :value_as_written, :string
    field :batch_id, :integer
    field :statement_text, :string
    field :when_as_written, :string
    field :stage_as_written, :string
    field :status_as_written, :string
    field :authorship_as_written, :string

    belongs_to :fact, Fact
    belongs_to :source, Source

    has_many :evidence, Evidence, on_replace: :delete
    has_many :names, AttributionName, on_replace: :delete
    has_many :observations, AttributionObservation, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for `source`'s attribution of a Fact.

  `attrs` takes `fact_id`, `stance`, `value_as_written`, `batch_id`,
  `statement_text`, `when_as_written`, `stage_as_written`,
  `status_as_written`, `authorship_as_written` and `stated`. The
  Source comes from `source`, never from `attrs`.

  `stated` is a partial date (`"1897"`, `"1897-05"`, `"1897-05-14"`), or nil
  for an undated statement. When `attrs` has no `stated` key the attribution
  takes the Source's authored date (nil if the Source has none).

  Evidence, names and Observations are cast by `Gallformers.Facts`.
  """
  @spec changeset(t(), map(), Source.t()) :: Ecto.Changeset.t()
  def changeset(attribution, attrs, %Source{} = source) do
    attribution
    |> cast(attrs, @fields)
    |> put_change(:source_id, source.id)
    |> put_stated(attrs, source)
    |> validate_required([:fact_id, :source_id, :stance])
    |> validate_statement_text(source)
    |> foreign_key_constraint(:fact_id)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:batch_id)
    |> unique_constraint([:fact_id, :source_id])
    |> check_constraint(:stated, name: :attributions_stated_date_precision)
  end

  defp put_stated(changeset, attrs, source) do
    case Map.fetch(attrs, :stated) do
      {:ok, nil} ->
        change(changeset, stated_on: nil, stated_precision: nil)

      {:ok, partial} when is_binary(partial) ->
        case PartialDate.parse(partial) do
          {:ok, {date, precision}} ->
            change(changeset, stated_on: date, stated_precision: precision)

          :error ->
            add_error(changeset, :stated, "must be YYYY, YYYY-MM or YYYY-MM-DD")
        end

      {:ok, _other} ->
        add_error(changeset, :stated, "must be YYYY, YYYY-MM or YYYY-MM-DD")

      :error ->
        change(changeset,
          stated_on: source.authored_date,
          stated_precision: source.authored_precision
        )
    end
  end

  defp validate_statement_text(changeset, %Source{kind: :gallformers}),
    do: validate_required(changeset, [:statement_text])

  defp validate_statement_text(changeset, _source), do: changeset
end
