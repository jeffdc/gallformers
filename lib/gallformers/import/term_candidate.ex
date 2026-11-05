defmodule Gallformers.Import.TermCandidate do
  @moduledoc """
  A seed candidate for the term table (matter `d213`, Task F): a Source
  term for a Trait, gathered from producer packages
  (`Gallformers.Import.TermCandidates`), for a superadmin to rule on
  before go-live. One per Trait and normalized term
  (`Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1`).

    * `term` — as most often written.
    * `counts_by_source` — each package's uses and their count per
      suggested category, `%{package => %{"uses" => n, "suggestions" =>
      [%{"category", "count"}]}}` (a category of nil: the producer set the
      term aside, or suggested none).
    * `suggestions` — those summed, most first; `total` the uses.
    * `uses` — a few example uses, `%{"source", "gall", "category",
      "quote"}`.
    * `decision` — once decided: `%{"place" => c}`, `%{"ambiguous" =>
      [c]}` or `%{"no_fit" => true}`, with who and when. The term edit it
      made is the replayed record; the candidate only says it is done.

  The table is `trait_term_candidates`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Audit.Actor

  @type suggestion :: %{String.t() => String.t() | nil | non_neg_integer()}

  @type t :: %__MODULE__{
          id: integer() | nil,
          trait: String.t() | nil,
          term: String.t() | nil,
          normalized_term: String.t() | nil,
          counts_by_source: %{String.t() => %{String.t() => term()}},
          suggestions: [suggestion()],
          uses: [map()],
          total: non_neg_integer(),
          decision: map() | nil,
          decided_at: DateTime.t() | nil,
          decided_by_user_id: integer() | nil,
          decided_by_name: String.t() | nil
        }

  schema "trait_term_candidates" do
    field :trait, :string
    field :term, :string
    field :normalized_term, :string
    field :counts_by_source, :map, default: %{}
    field :suggestions, {:array, :map}, default: []
    field :uses, {:array, :map}, default: []
    field :total, :integer, default: 0
    field :decision, :map
    field :decided_at, :utc_datetime
    field :decided_by_user_id, :integer
    field :decided_by_name, :string

    timestamps(type: :utc_datetime)
  end

  @doc "A changeset of a candidate's gathered fields (all but its decision)."
  @spec gathered_changeset(t(), map()) :: Ecto.Changeset.t()
  def gathered_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :trait,
      :term,
      :normalized_term,
      :counts_by_source,
      :suggestions,
      :uses,
      :total
    ])
    |> validate_required([:trait, :term, :normalized_term])
    |> unique_constraint([:trait, :normalized_term])
    |> check_constraint(:trait, name: :trait_term_candidates_trait_check)
  end

  @doc "A changeset recording `decision`, by `actor`, at `at`."
  @spec decide_changeset(t(), map(), Actor.t(), DateTime.t()) :: Ecto.Changeset.t()
  def decide_changeset(candidate, decision, %Actor{} = actor, %DateTime{} = at) do
    change(candidate,
      decision: decision,
      decided_at: DateTime.truncate(at, :second),
      decided_by_user_id: if(actor.type == :user, do: actor.id),
      decided_by_name: actor.name
    )
  end

  @doc "Whether the candidate is decided."
  @spec decided?(t()) :: boolean()
  def decided?(%__MODULE__{decided_at: at}), do: at != nil

  @doc "The packages its uses come from, by name."
  @spec sources(t()) :: [String.t()]
  def sources(%__MODULE__{counts_by_source: counts}), do: counts |> Map.keys() |> Enum.sort()

  @doc """
  The category every use suggests, when they all suggest the same one (and
  none set the term aside); else nil.
  """
  @spec agreed_category(t()) :: String.t() | nil
  def agreed_category(%__MODULE__{suggestions: [%{"category" => category}]})
      when is_binary(category),
      do: category

  def agreed_category(_candidate), do: nil

  @doc "The categories its uses suggest (not nil), most first."
  @spec suggested_categories(t()) :: [String.t()]
  def suggested_categories(%__MODULE__{suggestions: suggestions}),
    do: for(%{"category" => c} <- suggestions, is_binary(c), do: c)
end
