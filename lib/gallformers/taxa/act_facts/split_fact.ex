defmodule Gallformers.Taxa.ActFacts.SplitFact do
  @moduledoc """
  A split Fact's details: the taxon was divided into the daughter taxa. It
  states the division only; assigning records to the daughters is curator
  work (phase 2).

  The natural key is the taxon + the set of daughters, held canonically as
  `into_taxon_ids` sorted and distinct, so the same division stated in any
  order is one Fact; a different set (one more daughter) is another. The
  database checks the canonical form, and `split_fact_daughters` holds the
  same set as rows so each daughter has a foreign key. No slot.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Taxa.ActFacts

  alias Gallformers.Facts.Fact
  alias Gallformers.Repo
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          taxon_id: integer() | nil,
          into_taxon_ids: [integer()],
          fact: Fact.t() | Ecto.Association.NotLoaded.t(),
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "split_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :taxon, Taxon
    field :into_taxon_ids, {:array, :id}, default: []
  end

  @impl true
  def kind, do: "taxon_split"

  @impl true
  def changeset(split, attrs) do
    split
    |> cast(attrs, [:taxon_id, :into_taxon_ids])
    |> validate_required([:taxon_id, :into_taxon_ids])
    |> validate_into()
    |> update_change(:into_taxon_ids, &Enum.sort/1)
    |> validate_daughters_exist()
    |> foreign_key_constraint(:taxon_id)
    |> unique_constraint([:taxon_id, :into_taxon_ids])
  end

  defp validate_into(changeset) do
    taxon_id = get_field(changeset, :taxon_id)

    validate_change(changeset, :into_taxon_ids, fn :into_taxon_ids, into ->
      cond do
        length(Enum.uniq(into)) != length(into) -> [into_taxon_ids: "lists a taxon twice"]
        length(into) < 2 -> [into_taxon_ids: "needs at least two taxa"]
        taxon_id in into -> [into_taxon_ids: "can't include the taxon split"]
        true -> []
      end
    end)
  end

  defp validate_daughters_exist(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_daughters_exist(changeset) do
    into = get_field(changeset, :into_taxon_ids)
    found = Repo.aggregate(from(t in Taxon, where: t.id in ^into), :count)

    if found == length(into),
      do: changeset,
      else: add_error(changeset, :into_taxon_ids, "does not exist")
  end

  @impl true
  def slot(_split), do: nil

  @impl true
  def natural_key(%__MODULE__{} = s), do: {s.taxon_id, s.into_taxon_ids}

  @impl true
  def existing_query(%__MODULE__{} = s) do
    from(f in __MODULE__,
      where:
        f.taxon_id == ^s.taxon_id and f.into_taxon_ids == type(^s.into_taxon_ids, {:array, :id})
    )
  end

  @impl true
  def after_insert(%__MODULE__{fact_id: fact_id, into_taxon_ids: into}) do
    rows = Enum.map(into, &%{fact_id: fact_id, taxon_id: &1})
    {_, _} = Repo.insert_all("split_fact_daughters", rows)
    :ok
  end
end
