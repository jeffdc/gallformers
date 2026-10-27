defmodule Gallformers.Catalog.Gall do
  @moduledoc """
  A Gall entry (`9449` §4): the abstract Gall Gallformers catalogs.

    * `id` — from `entity_id_seq`, shared with taxa (`8567` rule 4);
      migrated Galls keep their species IDs.
    * `generation_value_id` — the generation that identifies the Gall (not a
      Fact), from the generation vocabulary.
    * `name` — the derived name (`8567` rule 9); `name_override` replaces it
      where set. The name shown (`display_name/1`) is unique.
    * `gallformers_code`, `abundance_id`, `datacomplete` — editorial
      carry-overs from today's gall rows.
    * `default_source_id` — the Source the Gall page leads with (`803b`
      decision 3): today's default description (`useasdefault`), a
      citation or the Gallformers note alike. Editorial, nullable.

  Everything Sources state about a Gall (its Inducer, Hosts, Traits, …) is a
  Fact (`Gallformers.Catalog.Facts`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Catalog.Vocab.GenerationValue

  @type t :: %__MODULE__{
          id: integer() | nil,
          gallformers_code: String.t() | nil,
          generation_value_id: integer() | nil,
          generation_value: GenerationValue.t() | Ecto.Association.NotLoaded.t() | nil,
          name: String.t() | nil,
          name_override: String.t() | nil,
          abundance_id: integer() | nil,
          datacomplete: boolean(),
          default_source_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "galls" do
    field :gallformers_code, :string
    field :name, :string
    field :name_override, :string
    field :abundance_id, :integer
    field :datacomplete, :boolean, default: false
    # A foreign key to `source`; Sources are known by ID here.
    field :default_source_id, :integer

    belongs_to :generation_value, GenerationValue

    timestamps(type: :utc_datetime)
  end

  @fields [
    :gallformers_code,
    :generation_value_id,
    :name,
    :name_override,
    :abundance_id,
    :datacomplete,
    :default_source_id
  ]

  @doc """
  A changeset for a new Gall. `attrs` may give `:id` (a migrated Gall's
  species ID); otherwise the sequence gives one.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(gall, attrs) do
    gall
    |> cast(attrs, [:id | @fields])
    |> update_change(:name, &trim/1)
    |> update_change(:name_override, &trim/1)
    |> validate_required([:name])
    |> unique_constraint(:name, name: :galls_display_name_index)
    |> unique_constraint(:gallformers_code, name: :galls_gallformers_code_index)
    |> foreign_key_constraint(:generation_value_id)
    |> foreign_key_constraint(:abundance_id)
    |> foreign_key_constraint(:default_source_id)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  @doc "The name shown: the override where set, else the derived name."
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name_override: override}) when is_binary(override), do: override
  def display_name(%__MODULE__{name: name}), do: name
end
