defmodule Gallformers.Curation.Item do
  @moduledoc """
  One edit in a curator's change set (matter `ec2c`; the table is
  `change_set_items`), with a stable ID:

    * `kind` — `:fact` (a Gallformers statement: add, withdraw or correct a
      Fact), `:note` (a note on a Fact), `:editorial` (a Gall's or plant's
      editorial field), `:photo` (an observation's photo for a Gall) or
      `:reading` (fixing how Gallformers read a Source's statement of a
      Fact, matter `87a1`: `source_id` that Source);
    * the subject, `subject_type` (`:gall`, `:plant`) and `subject_id`, and
      `key` (`Gallformers.Curation.Key`): one item per subject and key, of
      each kind (and, for a reading, of each Source);
    * `spec` — the edit, stored with string keys (`Gallformers.Curation`
      reads it back as the spec `add_item/2` took);
    * `evidence` — the item's own evidence (nil: the set's);
    * `seen` and `seen_at` — what the item saw when added (the Facts its key
      named, their standings; the field's value) and when: Review flags
      what other curators changed after it;
    * `status` — `:draft`; `:submitted` in a package (`package_id`, the Fact
      refs it became there, `package_refs`) the import job has yet to apply;
      `:in_review`, that package waiting for an admin;
    * `outcome` — why the last apply held it back (`%{"held" => reason}`).

  The virtual fields are filled when read through `Gallformers.Curation`:
  `subject` (`{:gall, id}`, `{:plant, id}`), `subject_name`, `text` (the
  item in words), `state` (`:in_tray`, or `:waiting` for an outcome) and
  `spec` decoded.
  """
  use Ecto.Schema

  alias Gallformers.Curation.ChangeSet
  alias Gallformers.Curation.Key

  @type status :: :draft | :submitted | :in_review

  @type t :: %__MODULE__{
          id: integer() | nil,
          change_set_id: integer() | nil,
          kind: :fact | :note | :editorial | :photo | :reading | nil,
          subject_type: :gall | :plant | nil,
          subject_id: integer() | nil,
          key: Key.t() | nil,
          source_id: integer() | nil,
          stored_spec: map() | nil,
          evidence: map() | nil,
          seen: map(),
          seen_at: DateTime.t() | nil,
          status: status(),
          package_id: integer() | nil,
          package_refs: [String.t()],
          stored_outcome: map() | nil,
          subject: {:gall | :plant, integer()} | nil,
          subject_name: String.t() | nil,
          text: String.t() | nil,
          state: :in_tray | :waiting | nil,
          spec: map() | nil,
          outcome: {:held, String.t()} | {:waiting_review, integer()} | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "change_set_items" do
    field :kind, Ecto.Enum, values: [:fact, :note, :editorial, :photo, :reading]
    field :subject_type, Ecto.Enum, values: [:gall, :plant]
    field :subject_id, :integer
    field :key, Key
    field :source_id, :integer
    field :stored_spec, :map, source: :spec
    field :evidence, :map
    field :seen, :map, default: %{}
    field :seen_at, :utc_datetime_usec
    field :status, Ecto.Enum, values: [:draft, :submitted, :in_review], default: :draft
    field :package_id, :integer
    field :package_refs, {:array, :string}, default: []
    field :stored_outcome, :map, source: :outcome

    field :subject, :any, virtual: true
    field :subject_name, :string, virtual: true
    field :text, :string, virtual: true
    field :state, Ecto.Enum, values: [:in_tray, :waiting], virtual: true
    field :spec, :map, virtual: true
    field :outcome, :any, virtual: true

    belongs_to :change_set, ChangeSet

    timestamps(type: :utc_datetime_usec)
  end
end
