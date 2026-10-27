defmodule Gallformers.Catalog.Gall do
  @moduledoc """
  A Gall entry (`9449` §4): the abstract Gall Gallformers catalogs.

    * `id` — from `entity_id_seq`, shared with taxa (`8567` rule 4);
      migrated Galls keep their species IDs.
    * `generation_value_id` — the generation that identifies the Gall (not a
      Fact), from the generation vocabulary.
    * `name` — the derived name (`8567` rule 9, `86e7`;
      `Gallformers.Catalog.GallName`); `name_override` replaces it where set.
      The name shown (`display_name/1`) is unique, ignoring case.
    * The name parts besides the Inducer (a Fact) and the generation:
      `form_label` ("australis", "bud"), `host_qualifier_taxon_id` (a Host
      taxon, rendered "(on Quercus douglasii)") and `descriptor` (an
      undescribed Gall's, e.g. `q-havardii-cup-gall`).
    * `gallformers_code`, `abundance_id`, `datacomplete` — editorial
      carry-overs from today's gall rows, edited with
      `Gallformers.Catalog.update_gall_editorial/3`.
    * `default_source_id` — the Source the Gall page leads with (`803b`
      decision 3): today's default description (`useasdefault`), a
      citation or the Gallformers note alike. Editorial, nullable.

  Everything Sources state about a Gall (its Inducer, Hosts, Traits, …) is a
  Fact (`Gallformers.Catalog.Facts`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          id: integer() | nil,
          gallformers_code: String.t() | nil,
          generation_value_id: integer() | nil,
          generation_value: GenerationValue.t() | Ecto.Association.NotLoaded.t() | nil,
          name: String.t() | nil,
          name_override: String.t() | nil,
          form_label: String.t() | nil,
          descriptor: String.t() | nil,
          host_qualifier_taxon_id: integer() | nil,
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
    field :form_label, :string
    field :descriptor, :string
    # A foreign key to `taxa`; taxa are known by ID here (`8567` rule 3).
    field :host_qualifier_taxon_id, :integer
    field :abundance_id, :integer
    field :datacomplete, :boolean, default: false
    # A foreign key to `source`; Sources are known by ID here.
    field :default_source_id, :integer

    belongs_to :generation_value, GenerationValue

    timestamps(type: :utc_datetime)
  end

  @name_parts [:form_label, :descriptor, :host_qualifier_taxon_id]

  @fields [
            :gallformers_code,
            :generation_value_id,
            :name,
            :name_override,
            :abundance_id,
            :datacomplete,
            :default_source_id
          ] ++ @name_parts

  @taken "is already the name of another Gall (names are unique, ignoring case)"

  @doc """
  A changeset for a new Gall. `attrs` may give `:id` (a migrated Gall's
  species ID); otherwise the sequence gives one.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(gall, attrs) do
    gall
    |> cast(attrs, [:id | @fields])
    |> trim_names()
    |> validate_required([:name])
    |> validate_host_qualifier()
    |> name_constraints()
    |> unique_constraint(:gallformers_code, name: :galls_gallformers_code_index)
    |> foreign_key_constraint(:generation_value_id)
    |> foreign_key_constraint(:abundance_id)
    |> foreign_key_constraint(:default_source_id)
  end

  @doc """
  A changeset for a deliberate edit of a Gall's name parts (`form_label`,
  `descriptor`, `host_qualifier_taxon_id`) and `name_override` (nil clears
  it). The caller puts the derived `name`
  (`Gallformers.Catalog.update_name_parts/3`).
  """
  @spec name_parts_changeset(t(), map()) :: Ecto.Changeset.t()
  def name_parts_changeset(gall, attrs) do
    gall
    |> cast(attrs, [:name_override | @name_parts])
    |> trim_names()
    |> validate_host_qualifier()
    |> name_constraints()
  end

  @doc """
  A changeset for a deliberate edit of a Gall's editorial fields
  (`gallformers_code`, `abundance_id`, `datacomplete`, `default_source_id`);
  nothing else. A blank code is nil. The caller enforces the rules that
  need the Gall's Facts and Sources
  (`Gallformers.Catalog.update_gall_editorial/3`).
  """
  @spec editorial_changeset(t(), map()) :: Ecto.Changeset.t()
  def editorial_changeset(gall, attrs) do
    gall
    |> cast(attrs, [:gallformers_code, :abundance_id, :datacomplete, :default_source_id])
    |> update_change(:gallformers_code, &trim/1)
    |> validate_required([:datacomplete])
    |> unique_constraint(:gallformers_code, name: :galls_gallformers_code_index)
    |> foreign_key_constraint(:abundance_id)
    |> foreign_key_constraint(:default_source_id)
  end

  @doc """
  A changeset giving a Gall a new derived `name` (an accepted rename
  proposal, `Gallformers.Catalog.accept_gall_rename/2`).
  """
  @spec rename_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def rename_changeset(gall, name) when is_binary(name),
    do: gall |> change(name: name) |> name_constraints()

  defp trim_names(changeset) do
    Enum.reduce([:name, :name_override, :form_label, :descriptor], changeset, fn field, cs ->
      update_change(cs, field, &trim/1)
    end)
  end

  defp name_constraints(changeset) do
    changeset
    |> unique_constraint(:name, name: :galls_display_name_index, message: @taken)
    |> foreign_key_constraint(:host_qualifier_taxon_id)
  end

  # A Host qualifier names a Host: a plant (kingdom Plantae).
  defp validate_host_qualifier(changeset) do
    case get_change(changeset, :host_qualifier_taxon_id) do
      nil ->
        changeset

      id ->
        case Taxa.get_taxon(id) do
          %Taxon{kingdom: "Plantae"} -> changeset
          %Taxon{} -> add_error(changeset, :host_qualifier_taxon_id, "must be a plant")
          nil -> add_error(changeset, :host_qualifier_taxon_id, "does not exist")
        end
    end
  end

  defp trim(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim(value), do: value

  @doc "The name shown: the override where set, else the derived name."
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name_override: override}) when is_binary(override), do: override
  def display_name(%__MODULE__{name: name}), do: name
end
