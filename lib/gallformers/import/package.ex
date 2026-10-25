defmodule Gallformers.Import.Package do
  @moduledoc """
  A delivered import package (`9449` §5): one Source's document and batches
  in the private bucket under `import/<key>/`.

    * `status` — `:received` (registered) → `:validated` (phase 4 and the
      readiness gate passed; `:invalid` when they did not) → `:resolving` →
      `:awaiting_review` → `:approved` or `:denied`.
    * `problems` — the last validation's problems, as
      `%{"level", "file", "message"}` maps (warnings included).
    * `source_id` — the Source, once matched or created (Task 13).
    * `format_version`, `vocabulary_version` — from the batches.
    * `submitter_user_id`, `submitter_name` — who delivered it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Import.Batch

  @statuses [:received, :invalid, :validated, :resolving, :awaiting_review, :approved, :denied]

  @type status ::
          :received | :invalid | :validated | :resolving | :awaiting_review | :approved | :denied

  @type t :: %__MODULE__{
          id: integer() | nil,
          key: String.t() | nil,
          s3_prefix: String.t() | nil,
          status: status() | nil,
          source_id: integer() | nil,
          format_version: integer() | nil,
          vocabulary_version: String.t() | nil,
          submitter_user_id: integer() | nil,
          submitter_name: String.t() | nil,
          problems: [map()],
          validated_at: DateTime.t() | nil,
          batches: [Batch.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "import_packages" do
    field :key, :string
    field :s3_prefix, :string
    field :status, Ecto.Enum, values: @statuses, default: :received
    field :source_id, :integer
    field :format_version, :integer
    field :vocabulary_version, :string
    field :submitter_user_id, :integer
    field :submitter_name, :string
    field :problems, {:array, :map}, default: []
    field :validated_at, :utc_datetime

    has_many :batches, Batch

    timestamps(type: :utc_datetime)
  end

  @doc "The private-bucket prefix of the package with `key`."
  @spec prefix(String.t()) :: String.t()
  def prefix(key), do: "import/#{key}/"

  @doc "A changeset registering a package: `key`, `submitter_user_id`, `submitter_name`."
  @spec register_changeset(t(), map()) :: Ecto.Changeset.t()
  def register_changeset(package, attrs) do
    package
    |> cast(attrs, [:key, :submitter_user_id, :submitter_name])
    |> validate_required([:key, :submitter_name])
    |> validate_format(:key, ~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/,
      message: "must be a folder name (letters, digits, '.', '_' and '-')"
    )
    |> then(fn cs ->
      case get_change(cs, :key) do
        nil -> cs
        key -> put_change(cs, :s3_prefix, prefix(key))
      end
    end)
    |> check_constraint(:key, name: :import_packages_key_check)
    |> unique_constraint(:key)
    |> foreign_key_constraint(:submitter_user_id)
  end

  @doc "A changeset recording a validation's outcome."
  @spec validated_changeset(t(), map()) :: Ecto.Changeset.t()
  def validated_changeset(package, attrs) do
    package
    |> cast(attrs, [:status, :problems, :format_version, :vocabulary_version, :validated_at])
    |> validate_required([:status, :validated_at])
  end

  @doc "A changeset changing the package's status."
  @spec status_changeset(t(), status()) :: Ecto.Changeset.t()
  def status_changeset(package, status), do: change(package, status: status)
end
