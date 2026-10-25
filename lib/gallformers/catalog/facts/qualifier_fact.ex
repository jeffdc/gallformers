defmodule Gallformers.Catalog.Facts.QualifierFact do
  @moduledoc """
  A qualifier Fact's details (`9449` §4): a qualifier of a Relationship Fact
  (`of_fact_id`), its own Fact so Sources confirm or deny it independently
  of the Relationship (`8567` *Sources–Facts design* point 6).

  Which qualifiers fit which Relationship types, and their values, follow
  `Gallformers.Catalog.RelationshipTypes`. Multi-valued qualifiers
  (`parasitism_mode`) get one Fact per value. `required_for_formation`'s
  contract value `true` is stored as `"true"`.

  Natural key Relationship + qualifier + value. `lethality` is single-valued
  (lethal or non-lethal), so its Facts compete in the slot
  `"relationship:<of_fact_id>:lethality"`; the other qualifiers have no slot.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Catalog.Assert

  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Facts.Fact
  alias Gallformers.Repo

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          of_fact_id: integer() | nil,
          qualifier: String.t() | nil,
          value: String.t() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "qualifier_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :of, RelationshipFact, foreign_key: :of_fact_id, references: :fact_id
    field :qualifier, :string
    field :value, :string
  end

  @impl true
  def kind, do: "gall_qualifier"

  @impl true
  def changeset(qualifier, attrs) do
    qualifier
    |> cast(stringify_value(attrs), [:of_fact_id, :qualifier, :value])
    |> validate_required([:of_fact_id, :qualifier, :value])
    |> validate_inclusion(:qualifier, RelationshipTypes.qualifier_names())
    |> validate_value()
    |> check_constraint(:value, name: :qualifier_facts_value_check)
    |> foreign_key_constraint(:of_fact_id)
    |> unique_constraint([:of_fact_id, :qualifier, :value])
  end

  # The contract states required_for_formation as the boolean `true`.
  defp stringify_value(%{value: value} = attrs) when is_boolean(value),
    do: %{attrs | value: to_string(value)}

  defp stringify_value(attrs), do: attrs

  defp validate_value(changeset) do
    case get_field(changeset, :qualifier) do
      nil ->
        changeset

      qualifier ->
        validate_inclusion(changeset, :value, RelationshipTypes.qualifier_values(qualifier))
    end
  end

  @impl true
  def prepare(changeset) do
    of_fact_id = get_field(changeset, :of_fact_id)
    qualifier = get_field(changeset, :qualifier)

    case Repo.one(from(r in RelationshipFact, where: r.fact_id == ^of_fact_id, select: r.type)) do
      nil ->
        add_error(changeset, :of_fact_id, "is not a Relationship Fact")

      type ->
        if qualifier in RelationshipTypes.qualifiers(type),
          do: changeset,
          else: add_error(changeset, :qualifier, "does not fit a #{type} Relationship")
    end
  end

  # A Relationship is either lethal or non-lethal: one value, the newest Source's.
  @impl true
  def slot(%__MODULE__{qualifier: "lethality", of_fact_id: of_fact_id}),
    do: "relationship:#{of_fact_id}:lethality"

  def slot(_qualifier), do: nil

  @impl true
  def natural_key(%__MODULE__{} = q), do: {q.of_fact_id, q.qualifier, q.value}

  @impl true
  def existing_query(%__MODULE__{} = q) do
    from(f in __MODULE__,
      where: f.of_fact_id == ^q.of_fact_id and f.qualifier == ^q.qualifier and f.value == ^q.value
    )
  end
end
