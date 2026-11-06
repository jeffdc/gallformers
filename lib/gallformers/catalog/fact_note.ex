defmodule Gallformers.Catalog.FactNote do
  @moduledoc """
  A curator's note on a Fact (matter `ec2c`): "only on young trees", shown
  with the Fact on its Gall's page (`Gallformers.Catalog.add_fact_note/3`,
  `Gallformers.Catalog.list_fact_notes/1`). Not a Gallformers statement: a
  note leaves the Fact's attributions, and so its standing, as they are.

  `author_user_id` and `author_name` record who wrote it (the user's ID is
  nil for a system actor, and after the user is deleted); `inserted_at` is
  its date. The table is `fact_notes`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Audit.Actor
  alias Gallformers.Facts.Fact

  @type t :: %__MODULE__{
          id: integer() | nil,
          fact_id: integer() | nil,
          text: String.t() | nil,
          author_user_id: integer() | nil,
          author_name: String.t() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "fact_notes" do
    field :text, :string
    field :author_user_id, :integer
    field :author_name, :string

    belongs_to :fact, Fact

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  A changeset for a new note on Fact `fact_id` by `actor` (or, replaying,
  by the author named in `opts[:author_name]`): `text`, trimmed, not blank.
  """
  @spec create_changeset(integer(), Actor.t(), term(), keyword()) :: Ecto.Changeset.t()
  def create_changeset(fact_id, %Actor{} = actor, text, opts \\ []) do
    %__MODULE__{
      fact_id: fact_id,
      author_user_id: if(actor.type == :user and is_nil(opts[:author_name]), do: actor.id),
      author_name: opts[:author_name] || actor.name
    }
    |> cast(%{text: text}, [:text])
    |> update_change(:text, &String.trim/1)
    |> validate_required([:text])
    |> check_constraint(:text, name: :fact_notes_text_check)
    |> foreign_key_constraint(:fact_id)
  end
end
