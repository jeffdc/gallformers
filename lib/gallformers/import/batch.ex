defmodule Gallformers.Import.Batch do
  @moduledoc """
  One batch file of a package (`9449` §5): `taxonomy.json` or `gall.json`.

    * `producer_batch_id` — the producer's `batch_id`, unique across all
      packages: a batch is imported once, and re-applying it is a no-op.
    * `content` — the batch as validated (decoded JSON); `sha256` its bytes'.
    * `status` — `:pending` (validated, not yet resolved), `:blocked`
      (waiting: a gall batch waits for its taxonomy batch and for every Host
      name to resolve), `:ready` (resolved, nothing waiting), `:applied`
      (with `applied_at`), `:denied` (with `denied_reason`;
      `Gallformers.Import.deny_batch/3`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.BatchUnmapped
  alias Gallformers.Import.Package

  @type status :: :pending | :blocked | :ready | :applied | :denied

  @type t :: %__MODULE__{
          id: integer() | nil,
          package_id: integer() | nil,
          file: String.t() | nil,
          batch_type: :taxonomy | :gall | nil,
          mode: :replace | :add | nil,
          producer_batch_id: String.t() | nil,
          sha256: String.t() | nil,
          content: map() | nil,
          status: status() | nil,
          applied_at: DateTime.t() | nil,
          denied_reason: String.t() | nil,
          package: Package.t() | Ecto.Association.NotLoaded.t(),
          statements: [BatchStatement.t()] | Ecto.Association.NotLoaded.t(),
          unmapped: [BatchUnmapped.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "import_batches" do
    field :file, :string
    field :batch_type, Ecto.Enum, values: [:taxonomy, :gall]
    field :mode, Ecto.Enum, values: [:replace, :add]
    field :producer_batch_id, :string
    field :sha256, :string
    field :content, :map

    field :status, Ecto.Enum,
      values: [:pending, :blocked, :ready, :applied, :denied],
      default: :pending

    field :applied_at, :utc_datetime
    field :denied_reason, :string

    belongs_to :package, Package
    has_many :statements, BatchStatement
    has_many :unmapped, BatchUnmapped

    timestamps(type: :utc_datetime)
  end

  @doc "A changeset recording a validated batch."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(batch, attrs) do
    batch
    |> cast(attrs, [:package_id, :file, :batch_type, :mode, :producer_batch_id, :sha256, :content])
    |> validate_required([
      :package_id,
      :file,
      :batch_type,
      :mode,
      :producer_batch_id,
      :sha256,
      :content
    ])
    |> unique_constraint(:producer_batch_id)
    |> unique_constraint([:package_id, :file])
    |> foreign_key_constraint(:package_id)
  end

  @doc "A changeset changing the batch's status."
  @spec status_changeset(t(), status()) :: Ecto.Changeset.t()
  def status_changeset(batch, :applied),
    do: change(batch, status: :applied, applied_at: DateTime.utc_now(:second))

  def status_changeset(batch, status), do: change(batch, status: status)

  @doc "A changeset denying the batch, `reason` (trimmed) required."
  @spec deny_changeset(t(), String.t() | nil) :: Ecto.Changeset.t()
  def deny_changeset(batch, reason) do
    batch
    |> cast(%{denied_reason: reason && String.trim(reason)}, [:denied_reason])
    |> validate_required([:denied_reason])
    |> put_change(:status, :denied)
    |> check_constraint(:denied_reason, name: :import_batches_denied_check)
  end
end
