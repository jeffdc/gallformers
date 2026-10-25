defmodule Gallformers.Catalog.Facts.RelationshipFact do
  @moduledoc """
  A Relationship Fact's details (`9449` §4): `type` (one of
  `Gallformers.Catalog.RelationshipTypes`) from a subject to an object, each
  a taxon or a Gall by the type's endpoint kinds:

  | Endpoints | Subject | Object | Gall context |
  |---|---|---|---|
  | `:taxon_to_gall` | `subject_taxon_id` | `object_gall_id` | none |
  | `:gall_to_gall` | `subject_gall_id` | `object_gall_id` (another Gall) | none |
  | `:taxon_to_taxon_in_gall` | `subject_taxon_id` | `object_taxon_id` | `gall_context_id` |

  Natural key type + subject + object + Gall context; no slot (a Gall has at
  most one Inducer, but competing Inducers are a curator's call, not a
  slot). A `host_of` subject must be a plant (kingdom Plantae), checked
  through `Gallformers.Taxa`; a genus-level Host is allowed.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Catalog.Assert

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Facts.Fact
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          type: String.t() | nil,
          subject_taxon_id: integer() | nil,
          subject_gall_id: integer() | nil,
          object_taxon_id: integer() | nil,
          object_gall_id: integer() | nil,
          gall_context_id: integer() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t()
        }

  @endpoint_fields [
    :subject_taxon_id,
    :subject_gall_id,
    :object_taxon_id,
    :object_gall_id,
    :gall_context_id
  ]

  # The endpoint columns each kind uses; the others must be blank.
  @columns %{
    taxon_to_gall: [:subject_taxon_id, :object_gall_id],
    gall_to_gall: [:subject_gall_id, :object_gall_id],
    taxon_to_taxon_in_gall: [:subject_taxon_id, :object_taxon_id, :gall_context_id]
  }

  @primary_key false
  schema "relationship_facts" do
    belongs_to :fact, Fact, primary_key: true
    field :type, :string
    belongs_to :subject_taxon, Taxon
    belongs_to :subject_gall, Gall
    belongs_to :object_taxon, Taxon
    belongs_to :object_gall, Gall
    belongs_to :gall_context, Gall
  end

  @impl true
  def kind, do: "gall_relationship"

  @impl true
  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:type | @endpoint_fields])
    |> validate_required([:type])
    |> validate_inclusion(:type, RelationshipTypes.names())
    |> validate_endpoints()
    |> check_constraint(:type, name: :relationship_facts_endpoint_kinds)
    |> check_constraint(:object_gall_id, name: :relationship_facts_not_own_gall)
    |> foreign_key_constraint(:subject_taxon_id)
    |> foreign_key_constraint(:subject_gall_id)
    |> foreign_key_constraint(:object_taxon_id)
    |> foreign_key_constraint(:object_gall_id)
    |> foreign_key_constraint(:gall_context_id)
    |> unique_constraint(:type, name: :relationship_facts_natural_key_index)
  end

  defp validate_endpoints(changeset) do
    case RelationshipTypes.get(get_field(changeset, :type)) do
      %{endpoints: endpoints} ->
        used = Map.fetch!(@columns, endpoints)

        changeset
        |> validate_required(used)
        |> validate_blank(@endpoint_fields -- used)
        |> validate_not_own_gall()

      nil ->
        changeset
    end
  end

  defp validate_blank(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      if get_field(acc, field) == nil,
        do: acc,
        else: add_error(acc, field, "must be blank for this type")
    end)
  end

  defp validate_not_own_gall(changeset) do
    subject = get_field(changeset, :subject_gall_id)

    if subject != nil and subject == get_field(changeset, :object_gall_id),
      do: add_error(changeset, :object_gall_id, "can't be the subject Gall"),
      else: changeset
  end

  @impl true
  def prepare(changeset) do
    case get_field(changeset, :type) do
      "host_of" -> validate_plant(changeset, :subject_taxon_id)
      _ -> changeset
    end
  end

  defp validate_plant(changeset, field) do
    case Taxa.get_taxon(get_field(changeset, field)) do
      %Taxon{kingdom: "Plantae"} -> changeset
      %Taxon{} -> add_error(changeset, field, "must be a plant")
      nil -> add_error(changeset, field, "does not exist")
    end
  end

  @impl true
  def slot(_relationship), do: nil

  @impl true
  def natural_key(%__MODULE__{} = r) do
    {r.type, r.subject_taxon_id || r.subject_gall_id, r.object_taxon_id || r.object_gall_id,
     r.gall_context_id}
  end

  @impl true
  def existing_query(%__MODULE__{} = r) do
    Enum.reduce(@endpoint_fields, from(f in __MODULE__, where: f.type == ^r.type), fn field, q ->
      case Map.fetch!(r, field) do
        nil -> where(q, [f], is_nil(field(f, ^field)))
        id -> where(q, [f], field(f, ^field) == ^id)
      end
    end)
  end
end
