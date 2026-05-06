defmodule Gallformers.Ingestions.SourceIngestion do
  @moduledoc """
  Persisted submission record for the source ingestion pipeline.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1, empty_strings_to_nil: 2]

  @behaviour Gallformers.SchemaFields

  alias Gallformers.IngestionPipeline.Workflow

  @input_types ~w(pdf url text docx)
  @statuses ~w(processing needs_duplicate_review needs_review duplicate_confirmed complete failed)

  @processing_stages ~w(
    submitted
    extract
    preprocess
    hash_and_dedup
    duplicate_review
    llm_clean
    metadata
    data_extract
    assemble
    review
    complete
    failed
  )

  @required_fields [:input_type, :status, :processing_stage]

  @optional_fields [
    :raw_input_sha256,
    :preprocessed_text_sha256,
    :doi,
    :normalized_doi,
    :title,
    :authors,
    :normalized_title,
    :title_fingerprint,
    :author_fingerprint,
    :publication_year,
    :minhash_signature,
    :duplicate_of_source_ingestion_id,
    :source_id,
    :artifacts_path,
    :uploaded_by_id,
    :error_stage,
    :error_message,
    :failed_at
  ]

  @signal_fields [
    :raw_input_sha256,
    :preprocessed_text_sha256,
    :doi,
    :normalized_doi,
    :title,
    :authors,
    :normalized_title,
    :title_fingerprint,
    :author_fingerprint,
    :publication_year,
    :minhash_signature
  ]

  @nullable_string_fields [
    :raw_input_sha256,
    :preprocessed_text_sha256,
    :doi,
    :normalized_doi,
    :title,
    :normalized_title,
    :title_fingerprint,
    :author_fingerprint,
    :error_stage,
    :error_message
  ]

  @type input_type :: String.t()
  @type status :: String.t()
  @type processing_stage :: String.t()

  @type t :: %__MODULE__{
          id: integer() | nil,
          input_type: input_type() | nil,
          status: status(),
          processing_stage: processing_stage(),
          raw_input_sha256: String.t() | nil,
          preprocessed_text_sha256: String.t() | nil,
          doi: String.t() | nil,
          normalized_doi: String.t() | nil,
          title: String.t() | nil,
          authors: [String.t()],
          normalized_title: String.t() | nil,
          title_fingerprint: String.t() | nil,
          author_fingerprint: String.t() | nil,
          publication_year: integer() | nil,
          minhash_signature: [integer()],
          duplicate_of_source_ingestion_id: integer() | nil,
          source_id: integer() | nil,
          artifacts_path: String.t(),
          uploaded_by_id: integer() | nil,
          error_stage: String.t() | nil,
          error_message: String.t() | nil,
          failed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "source_ingestions" do
    field :input_type, :string
    field :status, :string, default: "processing"
    field :processing_stage, :string, default: "submitted"
    field :raw_input_sha256, :string
    field :preprocessed_text_sha256, :string
    field :doi, :string
    field :normalized_doi, :string
    field :title, :string
    field :authors, {:array, :string}, default: []
    field :normalized_title, :string
    field :title_fingerprint, :string
    field :author_fingerprint, :string
    field :publication_year, :integer
    field :minhash_signature, {:array, :integer}, default: []
    field :artifacts_path, :string, default: ""
    field :error_stage, :string
    field :error_message, :string
    field :failed_at, :utc_datetime

    belongs_to :duplicate_of_source_ingestion, __MODULE__
    belongs_to :source, Gallformers.Sources.Source
    belongs_to :uploaded_by, Gallformers.Accounts.User

    has_many :canonical_duplicates, __MODULE__, foreign_key: :duplicate_of_source_ingestion_id

    has_many :duplicate_candidates, Gallformers.Ingestions.DuplicateCandidate,
      foreign_key: :source_ingestion_id

    has_many :candidate_duplicates, Gallformers.Ingestions.DuplicateCandidate,
      foreign_key: :candidate_source_ingestion_id

    has_many :species_entries, Gallformers.Ingestions.SourceIngestionSpecies

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @spec input_types() :: [input_type()]
  def input_types, do: @input_types

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @spec processing_stages() :: [processing_stage()]
  def processing_stages, do: @processing_stages

  @spec signal_fields() :: [atom()]
  def signal_fields, do: @signal_fields

  @doc """
  Creates a changeset for a persisted source ingestion.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(source_ingestion, attrs) do
    source_ingestion
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> trim_strings()
    |> empty_strings_to_nil(@nullable_string_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:input_type, @input_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:processing_stage, @processing_stages)
    |> validate_workflow_state_pair()
    |> validate_length(:raw_input_sha256, is: 64)
    |> validate_length(:preprocessed_text_sha256, is: 64)
    |> validate_number(:publication_year,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 3000
    )
    |> unique_constraint(:artifacts_path, name: :source_ingestions_artifacts_path_unique)
    |> foreign_key_constraint(:duplicate_of_source_ingestion_id)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:uploaded_by_id)
    |> check_constraint(:duplicate_of_source_ingestion_id,
      name: :source_ingestions_no_self_duplicate,
      message: "cannot point to itself as the canonical ingestion"
    )
  end

  def transition_changeset(source_ingestion, status, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:status, status)
      |> put_default_stage_for_status(source_ingestion)
      |> maybe_put_failed_at(status)

    changeset(source_ingestion, attrs)
  end

  defp validate_workflow_state_pair(changeset) do
    status = get_field(changeset, :status)
    processing_stage = get_field(changeset, :processing_stage)

    if status in @statuses and processing_stage in @processing_stages and
         not Workflow.valid_state?({status, processing_stage}) do
      add_error(changeset, :processing_stage, "is invalid for status #{status}")
    else
      changeset
    end
  end

  defp put_default_stage_for_status(attrs, %__MODULE__{processing_stage: processing_stage}) do
    case Gallformers.Utils.attr_value(attrs, :processing_stage) do
      nil ->
        case Gallformers.Utils.attr_value(attrs, :status) do
          "needs_duplicate_review" -> Map.put(attrs, :processing_stage, "duplicate_review")
          "needs_review" -> Map.put(attrs, :processing_stage, "review")
          "duplicate_confirmed" -> Map.put(attrs, :processing_stage, "duplicate_review")
          "complete" -> Map.put(attrs, :processing_stage, "complete")
          "failed" -> Map.put(attrs, :processing_stage, "failed")
          _ -> Map.put(attrs, :processing_stage, processing_stage)
        end

      _ ->
        attrs
    end
  end

  defp maybe_put_failed_at(attrs, "failed") do
    case Gallformers.Utils.attr_value(attrs, :failed_at) do
      nil -> Map.put(attrs, :failed_at, DateTime.utc_now(:second))
      _ -> attrs
    end
  end

  defp maybe_put_failed_at(attrs, _status), do: attrs
end
