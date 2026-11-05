defmodule Gallformers.Import.StatementEdit do
  @moduledoc """
  A curator's edit on one of a package's Facts before approval (matter
  `f14c`, item 4), by batch and statement ref (the Fact's `id` in the
  batch). Applying the batch honours it (`Gallformers.Import.FactEdits`),
  so the Facts preview shows it; the replay log records it. Deleting it
  undoes it.

  Kinds, with their `value`:

    * `:drop` — `%{}`: the Fact is not written.
    * `:host` — `%{"host_taxon_id" => plant}`: a Host Fact (`host_of`) is
      written on that plant, for this statement only.
    * `:trait_value` — `%{"values" => [value, ...]}`: a Trait Fact is
      written on these values of its Trait (one Fact each), the Source's
      term kept on the attribution.
    * `:note` — `%{}`: a note only, changing nothing.

  Any edit may carry a `note`; a `:note` edit must. One edit of a kind per
  statement: editing again replaces it. `author_user_id` and
  `author_name` record who made it (the user's ID is nil for a system
  actor).

  The table is `package_statement_edits`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Audit.Actor
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package

  @kinds [:drop, :host, :trait_value, :note]

  @type kind :: :drop | :host | :trait_value | :note

  @type t :: %__MODULE__{
          id: integer() | nil,
          package_id: integer() | nil,
          batch_id: integer() | nil,
          statement_ref: String.t() | nil,
          kind: kind() | nil,
          value: map(),
          note: String.t() | nil,
          author_user_id: integer() | nil,
          author_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "package_statement_edits" do
    field :statement_ref, :string
    field :kind, Ecto.Enum, values: @kinds
    field :value, :map, default: %{}
    field :note, :string
    field :author_user_id, :integer
    field :author_name, :string

    belongs_to :package, Package
    belongs_to :batch, Batch

    timestamps(type: :utc_datetime)
  end

  @doc "The edit kinds."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  A changeset for `edit` (new, or the one of its kind it replaces) by
  `actor`: `kind`, `value` and `note` (trimmed; blank is none, which a
  `:note` edit refuses).
  """
  @spec changeset(t(), Actor.t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = edit, %Actor{} = actor, attrs) do
    edit
    |> cast(attrs, [:package_id, :batch_id, :statement_ref, :kind, :value, :note])
    |> update_change(:note, &(&1 && String.trim(&1)))
    |> then(&if get_change(&1, :note) == "", do: put_change(&1, :note, nil), else: &1)
    |> put_change(:author_user_id, if(actor.type == :user, do: actor.id))
    |> put_change(:author_name, actor.name)
    |> validate_required([:package_id, :batch_id, :statement_ref, :kind])
    |> validate_note()
    |> unique_constraint([:batch_id, :statement_ref, :kind])
    |> check_constraint(:note, name: :package_statement_edits_note_check)
    |> foreign_key_constraint(:batch_id)
  end

  defp validate_note(changeset) do
    if get_field(changeset, :kind) == :note and get_field(changeset, :note) in [nil, ""],
      do: add_error(changeset, :note, "can't be blank"),
      else: changeset
  end
end
