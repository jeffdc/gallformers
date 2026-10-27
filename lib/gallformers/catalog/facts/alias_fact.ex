defmodule Gallformers.Catalog.Facts.AliasFact do
  @moduledoc """
  An alias Fact's details (`9449` §4): another name for the Gall, of a
  `kind` (`803b` decision 4):

    * `:common_name` — a common name (the default; every alias the import
      contract states is one);
    * `:former_label` — a Gallformers label the Gall had before (e.g. an
      undescribed gall's earlier name);
    * `:code` — an informal code.

  (Scientific names are taxon synonyms, in `Gallformers.Taxa`.)

  Natural key Gall + name, ignoring case; `name` keeps the form first
  recorded. The kind is a property of the Fact, not part of its key: an
  assert that gives a kind sets it on the Fact found (`update_existing/2`);
  one that gives none leaves it. No slot.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Catalog.Assert

  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts.Fact

  @kinds [:common_name, :former_label, :code]

  @type kind :: :common_name | :former_label | :code

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          gall_id: integer() | nil,
          name: String.t() | nil,
          kind: kind(),
          fact: Fact.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "alias_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :gall, Gall
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds, default: :common_name
  end

  @doc "The kinds of gall alias."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @impl true
  def kind, do: "gall_alias"

  @impl true
  def changeset(alias_fact, attrs) do
    alias_fact
    |> cast(attrs, [:gall_id, :name, :kind])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:gall_id, :name, :kind])
    |> foreign_key_constraint(:gall_id)
    |> unique_constraint(:name, name: :alias_facts_gall_id_name_index)
    |> check_constraint(:kind, name: :alias_facts_kind_check)
  end

  @impl true
  def slot(_alias_fact), do: nil

  @impl true
  def natural_key(%__MODULE__{} = a), do: {a.gall_id, String.downcase(a.name)}

  @impl true
  def existing_query(%__MODULE__{} = a) do
    from(f in __MODULE__,
      where: f.gall_id == ^a.gall_id and fragment("lower(?)", f.name) == ^String.downcase(a.name)
    )
  end

  @doc """
  The change to the alias Fact found by an assert: its kind, when the
  assert gave one that differs; else nil.
  """
  @impl true
  def update_existing(%__MODULE__{} = existing, %Ecto.Changeset{} = asserted) do
    kind = get_field(asserted, :kind)

    if given?(asserted, :kind) and kind != existing.kind,
      do: change(existing, kind: kind),
      else: nil
  end

  defp given?(%Ecto.Changeset{params: params}, field),
    do: Map.has_key?(params, Atom.to_string(field))
end
