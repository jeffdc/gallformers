defmodule Gallformers.Taxa.LegacyId do
  @moduledoc """
  A crosswalk entry from an identifier of the old model to a taxon (`9449`
  §3), for `/taxonomy/:id` redirects, `fa=` bookmarks, the data migration
  and the replay log. Unique per `{kind, legacy_id}`; many entries may map to
  one taxon.

    * `:taxonomy` — `legacy_id` is an old `taxonomy.id` (family, genus,
      section or an intermediate rank).
    * `:gall_inducer` — `legacy_id` is an old gall `species.id`, mapped to
      that row's Inducer taxon; an agamic/sexgen pair maps both rows to one
      Inducer.

  `legacy_name` keeps the old row's name as it was, for review and replay.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Taxa.Taxon

  @type kind :: :taxonomy | :gall_inducer

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: kind() | nil,
          legacy_id: integer() | nil,
          legacy_name: String.t() | nil,
          taxon_id: integer() | nil,
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "legacy_taxon_ids" do
    field :kind, Ecto.Enum, values: [:taxonomy, :gall_inducer]
    field :legacy_id, :integer
    field :legacy_name, :string

    belongs_to :taxon, Taxon

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Creates a changeset for a crosswalk entry."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(legacy_id, attrs) do
    legacy_id
    |> cast(attrs, [:kind, :legacy_id, :legacy_name, :taxon_id])
    |> validate_required([:kind, :legacy_id, :taxon_id])
    |> unique_constraint([:kind, :legacy_id], message: "is already mapped")
    |> foreign_key_constraint(:taxon_id)
  end
end
