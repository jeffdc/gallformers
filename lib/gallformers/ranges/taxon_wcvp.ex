defmodule Gallformers.Ranges.TaxonWcvp do
  @moduledoc """
  A plant taxon's WCVP link and range review state (`taxon_wcvp`, audited),
  one row per taxon, deleted with it:

    * `wcvp_id`, `powo_id` — the WCVP record (`plant_name_id`) and its POWO ID
    * `wcvp_match_status` — `no_match` (no WCVP record matched its name) or
      `ignored` (left out of WCVP matching and sync), nil otherwise
    * `range_confirmed` — a curator confirmed its Host range
    * `wcvp_synced_at` — when its range was last taken from WCVP

  Today's `host_traits` holds the same by species ID; this is its
  taxon-keyed successor (`Gallformers.Ranges.Wcvp`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @match_statuses ~w(no_match ignored)

  @type t :: %__MODULE__{
          taxon_id: integer() | nil,
          wcvp_id: String.t() | nil,
          powo_id: String.t() | nil,
          wcvp_match_status: String.t() | nil,
          range_confirmed: boolean(),
          wcvp_synced_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:taxon_id, :id, autogenerate: false}
  schema "taxon_wcvp" do
    field :wcvp_id, :string
    field :powo_id, :string
    field :wcvp_match_status, :string
    field :range_confirmed, :boolean, default: false
    field :wcvp_synced_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "The match statuses: `no_match`, `ignored`."
  @spec match_statuses() :: [String.t()]
  def match_statuses, do: @match_statuses

  @doc "A changeset for the link's fields; blank IDs are nil."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:wcvp_id, :powo_id, :wcvp_match_status, :range_confirmed, :wcvp_synced_at],
      empty_values: [nil, ""]
    )
    |> validate_required([:range_confirmed])
    |> validate_inclusion(:wcvp_match_status, @match_statuses)
    |> foreign_key_constraint(:taxon_id, name: :taxon_wcvp_taxon_id_fkey)
    |> check_constraint(:wcvp_match_status, name: :taxon_wcvp_match_status_check)
  end
end
