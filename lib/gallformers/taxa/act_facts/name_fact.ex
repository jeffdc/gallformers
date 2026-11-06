defmodule Gallformers.Taxa.ActFacts.NameFact do
  @moduledoc """
  A name Fact's details: the taxon bears this name at this rank, with this
  authorship, in this sense (`sensu`, for a name in a Source's sense).
  Natural key taxon + normalized name (`Gallformers.Taxa.NameNormalizer`)
  + rank + sensu (ignoring case) + normalized authorship
  (`Gallformers.Taxa.NameNormalizer.normalize_authorship/1`: "(Ashmead,
  1881)" and "(Ashmead 1881)" are one Fact, "Ashmead, 1881" another); a
  taxon's name Facts compete in the slot `"taxon:<id>:name"`, so the newest
  current one is its accepted name by the Sources (`f923`). `name`,
  `sensu` and `authorship` keep the form first recorded.

  Each Source's own wording is kept on its attribution
  (`authorship_as_written`, `status_as_written` such as "comb. nov.").
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @behaviour Gallformers.Taxa.ActFacts

  alias Gallformers.Facts.Fact
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          fact_id: integer() | nil,
          taxon_id: integer() | nil,
          name: String.t() | nil,
          normalized_name: String.t() | nil,
          rank: Rank.t() | nil,
          sensu: String.t() | nil,
          authorship: String.t() | nil,
          normalized_authorship: String.t() | nil,
          fact: Fact.t() | Ecto.Association.NotLoaded.t(),
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "name_facts" do
    belongs_to :fact, Fact, primary_key: true
    belongs_to :taxon, Taxon
    field :name, :string
    field :normalized_name, :string
    field :rank, Ecto.Enum, values: Rank.all()
    field :sensu, :string
    field :authorship, :string
    field :normalized_authorship, :string, default: ""
  end

  @impl true
  def kind, do: "taxon_name"

  @impl true
  def changeset(name_fact, attrs) do
    name_fact
    |> cast(attrs, [:taxon_id, :name, :rank, :sensu, :authorship])
    |> update_change(:name, &String.trim/1)
    |> update_change(:sensu, &blank_to_nil/1)
    |> update_change(:authorship, &blank_to_nil/1)
    |> validate_required([:taxon_id, :name, :rank])
    |> put_normalized(:name, :normalized_name)
    |> put_normalized_authorship()
    |> foreign_key_constraint(:taxon_id)
    |> unique_constraint([:taxon_id, :normalized_name, :rank],
      name: :name_facts_natural_key_index
    )
  end

  defp put_normalized(changeset, from, to) do
    case get_change(changeset, from) do
      nil -> changeset
      value -> put_change(changeset, to, NameNormalizer.normalize(value))
    end
  end

  @impl true
  def key(%__MODULE__{} = n) do
    %{taxon_id: n.taxon_id, name: n.name, rank: n.rank, sensu: n.sensu, authorship: n.authorship}
  end

  @impl true
  def slot(%__MODULE__{taxon_id: taxon_id}), do: "taxon:#{taxon_id}:name"

  @impl true
  def natural_key(%__MODULE__{} = n),
    do: {n.taxon_id, n.normalized_name, n.rank, sensu_key(n.sensu), n.normalized_authorship}

  @impl true
  def existing_query(%__MODULE__{} = n) do
    from(f in __MODULE__,
      where:
        f.taxon_id == ^n.taxon_id and f.normalized_name == ^n.normalized_name and
          f.rank == ^n.rank and fragment("lower(COALESCE(?, ''))", f.sensu) == ^sensu_key(n.sensu) and
          f.normalized_authorship == ^n.normalized_authorship
    )
  end

  defp put_normalized_authorship(changeset) do
    authorship = get_field(changeset, :authorship)
    put_change(changeset, :normalized_authorship, NameNormalizer.normalize_authorship(authorship))
  end

  defp sensu_key(nil), do: ""
  defp sensu_key(sensu), do: String.downcase(sensu)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
