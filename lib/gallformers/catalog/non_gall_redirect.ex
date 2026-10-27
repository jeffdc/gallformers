defmodule Gallformers.Catalog.NonGallRedirect do
  @moduledoc """
  An old gall `species` ID excluded as a non-gall (a gall lookalike) by
  the data migration (`priv/catalog_migration/non_galls.csv`), with its
  old name. It is no Gall; its old `/gall/:id` URL redirects to the
  gall-lookalikes Article (`803b` §4).
  """
  use Ecto.Schema

  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Repo

  @type t :: %__MODULE__{species_id: integer() | nil, name: String.t() | nil}

  @primary_key {:species_id, :id, autogenerate: false}
  schema "non_gall_redirects" do
    field :name, :string
  end

  @doc """
  Records excluded non-galls, as the data migration does: `rows` are maps
  of `:species_id` and `:name`. Returns how many were inserted.
  """
  @spec insert_all(Actor.t(), [%{species_id: integer(), name: String.t()}]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def insert_all(%Actor{} = actor, rows) when is_list(rows) do
    Audit.transaction(actor, "catalog.insert_non_gall_redirects", fn ->
      {count, _} = Repo.insert_all(__MODULE__, rows)
      count
    end)
  end

  @doc "Whether `id` is an old gall ID excluded as a non-gall."
  @spec non_gall?(integer()) :: boolean()
  def non_gall?(id) when is_integer(id),
    do: Repo.exists?(from(r in __MODULE__, where: r.species_id == ^id))
end
