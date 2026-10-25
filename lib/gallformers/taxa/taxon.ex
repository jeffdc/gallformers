defmodule Gallformers.Taxa.Taxon do
  @moduledoc """
  A taxon at any rank (`9449` §3): one stable ID, shared with Galls through
  `entity_id_seq` (`8567` rule 4).

    * `rank` — the contract's rank list (`Gallformers.Taxa.Rank`).
    * `parent_id` — its place in the editorial tree; changed only through
      `Gallformers.Taxa.place/3`, which validates the tree.
    * `origin` — `:curated` (gall formers and associates) or `:powo` (plants).
    * `kingdom` — `"Plantae"` for plants; set for others when known.

  Its names (one accepted, any synonyms) are `Gallformers.Taxa.TaxonName`s.
  `matched_name` is filled by `Gallformers.Taxa.resolve_name/2` with the
  name that matched.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.TaxonName

  @type origin :: :curated | :powo

  @type t :: %__MODULE__{
          id: integer() | nil,
          rank: Rank.t() | nil,
          parent_id: integer() | nil,
          origin: origin() | nil,
          kingdom: String.t() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          names: [TaxonName.t()] | Ecto.Association.NotLoaded.t(),
          common_names: [CommonName.t()] | Ecto.Association.NotLoaded.t(),
          matched_name: TaxonName.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "taxa" do
    field :rank, Ecto.Enum, values: Rank.all()
    field :origin, Ecto.Enum, values: [:curated, :powo]
    field :kingdom, :string
    field :matched_name, :any, virtual: true

    belongs_to :parent, __MODULE__
    has_many :names, TaxonName
    has_many :common_names, CommonName

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new taxon (its names are added separately).
  `attrs` may give `:id` (a migrated plant keeping its species ID);
  otherwise the sequence gives one.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(taxon, attrs) do
    taxon
    |> cast(attrs, [:id, :rank, :parent_id, :origin, :kingdom])
    |> validate_required([:rank, :origin])
    |> check_constraint(:kingdom, name: :taxa_kingdom_present, message: "can't be blank")
    |> foreign_key_constraint(:parent_id)
  end

  @doc "Creates a changeset moving the taxon under `parent_id` (nil for a root)."
  @spec parent_changeset(t(), integer() | nil) :: Ecto.Changeset.t()
  def parent_changeset(taxon, parent_id) do
    taxon
    |> change(parent_id: parent_id)
    |> foreign_key_constraint(:parent_id)
  end
end
