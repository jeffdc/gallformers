defmodule Gallformers.Catalog.Vocab.TraitTermMapping do
  @moduledoc """
  A Source's term for a Trait (matter `d213`): one term per row, placed
  once for every Source (`traits.json` `mappings`). Unique on trait and
  normalized term (`normalize/1`), so "Ovoid" and "ovoid" are one term.

    * `status` `:placed` — under its `categories`: the Trait values a Fact
      takes when a Source uses the term, one Fact each. One category, or
      several when the term's words name several values ("green-yellow" →
      green and yellow; "protruding from both sides" → upper leaf and
      lower leaf), however it was placed (`d213`). Guessing between values
      is never placement: "on the leaf", with no side stated, is under
      `leaf`.
    * `:ambiguous` — the term is used in more than one sense across
      Sources, so it never maps automatically: each use is decided from its
      own context, between its `candidates`.
    * `:no_fit` — the term fits no category; it stays text on the Gall.

  `placed_by` (`:seed`, `:agreement` — the producer and the checker placed
  it under the same categories independently —, `:curator`, `:superadmin`) and
  `placed_at` say how and when its status was set; `spot_checked_at` when a
  placement was last spot-checked. `rule` is guide text.

  Trait `"generation"` holds the generation values' other names (e.g.
  "stem mother" → fundatrix, `8567` *Aphid life-cycle values*).

  The table is `trait_term_mappings`, the name it had when it held
  mappings (see the migration `SplitTraitTerms`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Catalog.Vocab.TraitValue

  @statuses [:placed, :ambiguous, :no_fit]
  @placed_by [:seed, :agreement, :curator, :superadmin]

  # What each status holds: {categories, candidates}, each `:some` or `:none`.
  @shapes %{placed: {:some, :none}, ambiguous: {:none, :some}, no_fit: {:none, :none}}

  @type status :: :placed | :ambiguous | :no_fit
  @type placed_by :: :seed | :agreement | :curator | :superadmin

  @type t :: %__MODULE__{
          id: integer() | nil,
          trait: String.t() | nil,
          term: String.t() | nil,
          normalized_term: String.t() | nil,
          status: status() | nil,
          categories: [String.t()],
          candidates: [String.t()],
          placed_by: placed_by() | nil,
          placed_at: DateTime.t() | nil,
          spot_checked_at: DateTime.t() | nil,
          rule: String.t() | nil
        }

  schema "trait_term_mappings" do
    field :trait, :string
    field :term, :string
    field :normalized_term, :string
    field :status, Ecto.Enum, values: @statuses
    field :categories, {:array, :string}, default: []
    field :candidates, {:array, :string}, default: []
    field :placed_by, Ecto.Enum, values: @placed_by
    field :placed_at, :utc_datetime
    field :spot_checked_at, :utc_datetime
    field :rule, :string
  end

  @typedoc "The categories a term is placed under: one value, or the values its words name."
  @type categories :: String.t() | [String.t()]

  @doc "The categories as a list: one value, or several, each once (nil: none)."
  @spec categories(categories() | nil) :: [String.t()]
  def categories(categories), do: categories |> List.wrap() |> Enum.uniq()

  @doc "Whether two placements are under the same categories, in any order."
  @spec same_categories?(categories(), categories()) :: boolean()
  def same_categories?(a, b), do: MapSet.new(categories(a)) == MapSet.new(categories(b))

  @doc "The statuses a term may have."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "The ways a term is placed."
  @spec placed_by_values() :: [placed_by()]
  def placed_by_values, do: @placed_by

  @doc "The traits a term may belong to: generation and every Trait."
  @spec traits() :: [String.t()]
  def traits, do: ["generation" | TraitValue.traits()]

  @doc """
  A term as compared: NFC, lowercased, whitespace collapsed, and each
  word's plural taken as its singular (`c8c3`: "swellings" is the term
  "swelling", "covered in short hairs" is "covered in short hair"), as
  `Gallformers.Import.SetAside` compares set-aside terms. The result is a
  key, never shown: a word is folded by its ending alone ("berries" →
  "berry", "patches" → "patch", "masses" → "mass", "chambers" →
  "chamber"), except words of three letters or fewer, those ending in
  "ss", "us" or "is" ("hairless", "glabrous") and a few that only look
  plural ("species", "this").
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(term) when is_binary(term) do
    term
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> String.split()
    |> Enum.map_join(" ", &singular_word/1)
  end

  @not_plural ~w(this its has was always sometimes perhaps whereas series species thus plus yes
                 lens gas bias chaos canvas atlas)

  # The word's trailing letters as their singular (a hyphenated word's
  # last part: "green-yellows" is "green-yellow").
  defp singular_word(word), do: Regex.replace(~r/[[:alpha:]]+$/u, word, &singular/1)

  defp singular(word) when word in @not_plural, do: word

  defp singular(word) do
    cond do
      String.length(word) <= 3 ->
        word

      String.ends_with?(word, ["ss", "us", "is"]) ->
        word

      String.length(word) > 4 and String.ends_with?(word, "ies") ->
        String.slice(word, 0..-4//1) <> "y"

      String.ends_with?(word, ["sses", "shes", "ches", "xes", "zes"]) ->
        String.slice(word, 0..-3//1)

      String.ends_with?(word, "s") ->
        String.slice(word, 0..-2//1)

      true ->
        word
    end
  end

  @doc """
  A changeset setting a term's status: `attrs` (atom keys) `:trait` and
  `:term` (for a new term), `:status`, `:categories`, `:candidates`,
  `:placed_by`, `:placed_at`, `:rule`. `values` are the Trait's values
  (generation values for trait `"generation"`): categories and candidates
  are among them. A placed term has one category, an ambiguous one its
  candidates, and one fitting no category neither.
  """
  @spec changeset(t(), map(), [String.t()]) :: Ecto.Changeset.t()
  def changeset(term, attrs, values) do
    term
    |> cast(attrs, [
      :trait,
      :term,
      :status,
      :categories,
      :candidates,
      :placed_by,
      :placed_at,
      :rule
    ])
    |> update_change(:term, &String.trim/1)
    |> validate_required([:trait, :term, :status, :placed_by, :placed_at])
    |> validate_inclusion(:trait, traits())
    |> put_normalized_term()
    |> empty_when_nil([:categories, :candidates])
    |> validate_subset(:categories, values, message: "must be values of the Trait")
    |> validate_subset(:candidates, values, message: "must be values of the Trait")
    |> validate_distinct([:categories, :candidates])
    |> validate_status()
    |> unique_constraint([:trait, :normalized_term],
      name: :trait_term_mappings_trait_normalized_term_index,
      error_key: :term
    )
    |> check_constraint(:status, name: :trait_term_mappings_status_check)
  end

  @doc "A changeset recording a spot check of the term's placement at `at`."
  @spec spot_check_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def spot_check_changeset(term, at), do: change(term, spot_checked_at: at)

  defp put_normalized_term(changeset) do
    case get_change(changeset, :term) do
      term when is_binary(term) -> put_change(changeset, :normalized_term, normalize(term))
      _ -> changeset
    end
  end

  defp empty_when_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      if get_field(acc, field) == nil, do: put_change(acc, field, []), else: acc
    end)
  end

  defp validate_status(changeset) do
    case Map.fetch(@shapes, get_field(changeset, :status)) do
      {:ok, {categories, candidates}} ->
        changeset
        |> validate_count(:categories, categories)
        |> validate_count(:candidates, candidates)

      :error ->
        changeset
    end
  end

  defp validate_distinct(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      values = get_field(acc, field)

      if is_list(values) and Enum.uniq(values) != values,
        do: add_error(acc, field, "must not repeat a value"),
        else: acc
    end)
  end

  defp validate_count(changeset, field, expected) do
    case {expected, length(get_field(changeset, field))} do
      {:some, 0} -> add_error(changeset, field, "can't be empty")
      {:none, n} when n > 0 -> add_error(changeset, field, "must be empty")
      _ -> changeset
    end
  end
end
