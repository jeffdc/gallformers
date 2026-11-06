defmodule Gallformers.Curation.ChangeSet do
  @moduledoc """
  A curator's change set (matter `ec2c`): the tray that follows them across
  pages, saved with their account (`user_id`, one set per curator; their
  name as `user_name`), with the evidence given once for the set
  (`evidence`, `t:Gallformers.Curation.evidence/0`, stored with string
  keys) and its items (`Gallformers.Curation.Item`). Private to its author
  until applied; not audited or replayed (drafts are not data).
  """
  use Ecto.Schema

  alias Gallformers.Curation.Item

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          user_name: String.t() | nil,
          evidence: map() | nil,
          items: [Item.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "change_sets" do
    field :user_id, :integer
    field :user_name, :string
    field :evidence, :map

    has_many :items, Item, preload_order: [asc: :id]

    timestamps(type: :utc_datetime_usec)
  end
end
