defmodule Gallformers.Taxa.TaxonNote do
  @moduledoc """
  A "based on" note on a plant's editorial edit (matter `ec2c`): what an
  edit that departs from WCVP follows ("per Flora of North America", "iNat
  treats these as one species"), shown on the plant's page so the next
  curator knows why it differs from WCVP (`Gallformers.Taxa.add_taxon_note/5`).
  Not evidence in the Fact sense.

  `about` is what the edit changed: `"name"`, `"authorship"`, `"synonyms"`
  or `"range"`.
  `author_user_id` and `author_name` record who wrote it; `inserted_at` is
  its date. The table is `taxon_notes`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Audit.Actor
  alias Gallformers.Taxa.Taxon

  @abouts ~w(name authorship synonyms range)

  @type t :: %__MODULE__{
          id: integer() | nil,
          taxon_id: integer() | nil,
          about: String.t() | nil,
          text: String.t() | nil,
          author_user_id: integer() | nil,
          author_name: String.t() | nil,
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "taxon_notes" do
    field :about, :string
    field :text, :string
    field :author_user_id, :integer
    field :author_name, :string

    belongs_to :taxon, Taxon

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "What a note may be about."
  @spec abouts() :: [String.t()]
  def abouts, do: @abouts

  @doc """
  A changeset for a new note on taxon `taxon_id`'s `about` by `actor` (or,
  replaying, by `opts[:author_name]`): `text`, trimmed, not blank.
  """
  @spec create_changeset(integer(), String.t(), Actor.t(), term(), keyword()) ::
          Ecto.Changeset.t()
  def create_changeset(taxon_id, about, %Actor{} = actor, text, opts \\ []) do
    %__MODULE__{
      taxon_id: taxon_id,
      author_user_id: if(actor.type == :user and is_nil(opts[:author_name]), do: actor.id),
      author_name: opts[:author_name] || actor.name
    }
    |> cast(%{about: about, text: text}, [:about, :text])
    |> update_change(:text, &String.trim/1)
    |> validate_required([:about, :text])
    |> validate_inclusion(:about, @abouts)
    |> check_constraint(:text, name: :taxon_notes_text_check)
    |> foreign_key_constraint(:taxon_id)
  end
end
