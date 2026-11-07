defmodule Gallformers.Import.SourceCorrection do
  @moduledoc """
  A curator's correction to a Source's applied Facts (matter `f14c`, "The
  Source's Facts after approval"; `Gallformers.Import.SourceCorrections`):
  what the Source was wrongly said to state, and what it states instead,
  with the curator's note of why.

  Kinds:

    * `:withdraw` — the Source's statement withdrawn: it didn't say it.
    * `:host` — a Host statement moved to another plant.
    * `:values` — a Trait statement moved to other values of its Trait.
    * `:parent` — a placement statement moved to another parent.
    * `:accepted` — a synonymy statement moved to another accepted taxon.

  `summary` says, in words, the statement corrected as it was ("Host Rubus
  (genus) of Aphis rubifolii's gall"); `change` what it became (nil for a
  withdrawal). The record keeps no Fact IDs: the words stay readable when
  the Facts are merged or deleted. `author_user_id` and `author_name`
  record who made it (the user's ID is nil for a system actor and after the
  user is deleted); `inserted_at` is when, and moves the Source's Updated
  date (`Gallformers.Import.SourceDates`).

  The table is `source_corrections`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Audit.Actor
  alias Gallformers.Sources.Source

  @kinds [:withdraw, :host, :values, :parent, :accepted]

  @type kind :: :withdraw | :host | :values | :parent | :accepted

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_id: integer() | nil,
          kind: kind() | nil,
          summary: String.t() | nil,
          change: String.t() | nil,
          note: String.t() | nil,
          author_user_id: integer() | nil,
          author_name: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "source_corrections" do
    field :kind, Ecto.Enum, values: @kinds
    field :summary, :string
    field :change, :string
    field :note, :string
    field :author_user_id, :integer
    field :author_name, :string

    belongs_to :source, Source

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The correction kinds."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  A changeset for a new correction by `actor` (or, replaying, by the author
  named in `opts[:author_name]`): `source_id`, `kind`, `summary`, `change`
  and `note` (trimmed, required).
  """
  @spec create_changeset(Actor.t(), map(), keyword()) :: Ecto.Changeset.t()
  def create_changeset(%Actor{} = actor, attrs, opts \\ []) do
    %__MODULE__{
      author_user_id: if(actor.type == :user and is_nil(opts[:author_name]), do: actor.id),
      author_name: opts[:author_name] || actor.name
    }
    |> cast(attrs, [:source_id, :kind, :summary, :change, :note])
    |> update_change(:note, &String.trim/1)
    |> validate_required([:source_id, :kind, :summary, :note, :author_name])
    |> check_constraint(:note, name: :source_corrections_note_check)
    |> foreign_key_constraint(:source_id)
  end
end
