defmodule Gallformers.Import.QueueItemNote do
  @moduledoc """
  A curator's note on a queue item (matter `d213`, Task 7), for the next
  curator: saved on its own, decided or not
  (`Gallformers.Import.add_note/3`). A note is not part of the decision and
  is not replayed. It stays with its item through deciding it, rejecting
  or restoring its proposal, and resolving the package again (an item
  replaced by another about the same statement passes its notes on).

  `author_user_id` and `author_name` record who wrote it (the user's ID is
  nil for a system actor). Older decisions carry their note in the
  decision (`"note"`); `Gallformers.Import.notes_for/1` shows those as
  notes too, unsaved (`id` nil).

  The table is `queue_item_notes`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Audit.Actor
  alias Gallformers.Import.QueueItem

  @type t :: %__MODULE__{
          id: integer() | nil,
          queue_item_id: integer() | nil,
          text: String.t() | nil,
          author_user_id: integer() | nil,
          author_name: String.t() | nil,
          queue_item: QueueItem.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "queue_item_notes" do
    field :text, :string
    field :author_user_id, :integer
    field :author_name, :string

    belongs_to :queue_item, QueueItem

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "A changeset for a new note on `item` by `actor`: `text`, trimmed, not blank."
  @spec create_changeset(QueueItem.t(), Actor.t(), term()) :: Ecto.Changeset.t()
  def create_changeset(%QueueItem{id: item_id}, %Actor{} = actor, text) do
    %__MODULE__{
      queue_item_id: item_id,
      author_user_id: if(actor.type == :user, do: actor.id),
      author_name: actor.name
    }
    |> cast(%{text: text}, [:text])
    |> update_change(:text, &String.trim/1)
    |> validate_required([:text])
    |> check_constraint(:text, name: :queue_item_notes_text_check)
    |> foreign_key_constraint(:queue_item_id)
  end
end
