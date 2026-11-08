defmodule Gallformers.Repo.Migrations.FoldTermPlurals do
  @moduledoc """
  A word's plural is the same term as its singular (matter `c8c3` item 10:
  Nastasi & Davis's "swelling" and "swellings" were two questions).
  `Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1` now folds each
  word's plural into its singular, so the keys stored with that function
  are computed again:

    * `trait_term_mappings.normalized_term`. Terms that become one are
      merged into the oldest row: one status, categories and candidates
      agreeing, it keeps them; otherwise the term is used in more than one
      sense, so it is ambiguous between all their values.
    * `pending_trait_terms.normalized_term` and
      `trait_term_candidates.normalized_term`.
    * the `statement_ref` of Trait-term and set-aside queue items
      (`"u:<trait>:<normalized term>"`, recomputed from the item's subject),
      so their decisions still meet the questions the import asks.

  A row whose new key another row of its table already holds (other than
  the merged term rows) keeps its old key. The folding is copied here as
  it was written, so later changes to the function don't change what this
  migration did. Down does nothing: the old keys aren't kept.
  """
  use Ecto.Migration

  @max_term_bytes 200
  @not_plural ~w(this its has was always sometimes perhaps whereas series species thus plus yes
                 lens gas bias chaos canvas atlas)

  def up do
    Carbonite.Migrations.insert_migration_transaction("fold_term_plurals",
      meta: %{actor: %{type: "system", name: "migration"}, operation: "migration.fold_term_plurals"}
    )

    # The audit transaction is queued; the data changes below run at once.
    flush()

    fold_mappings()
    fold_keys("pending_trait_terms", ["gall_id", "source_id", "trait"])
    fold_keys("trait_term_candidates", ["trait"])
    fold_queue_refs()
  end

  def down, do: :ok

  # -- the term table --------------------------------------------------------------

  defp fold_mappings do
    %{rows: rows} =
      repo().query!(
        "SELECT id, trait, term, normalized_term, status, categories, candidates " <>
          "FROM trait_term_mappings ORDER BY id"
      )

    rows
    |> Enum.group_by(fn [_id, trait, term | _] -> {trait, normalize(term)} end)
    |> Enum.each(fn {{_trait, key}, [[id | _] = first | rest]} ->
      if rest != [], do: merge(first, rest)
      repo().query!("UPDATE trait_term_mappings SET normalized_term = $1 WHERE id = $2", [key, id])
    end)
  end

  # The other rows are deleted; the first takes their one status, or
  # becomes ambiguous between all their values.
  defp merge([id | _] = first, rest) do
    rows = [first | rest]

    repo().query!("DELETE FROM trait_term_mappings WHERE id = ANY($1)", [
      Enum.map(rest, &hd/1)
    ])

    case Enum.uniq_by(rows, fn [_, _, _, _, status, categories, candidates] ->
           {status, Enum.sort(categories), Enum.sort(candidates)}
         end) do
      [_one] ->
        :ok

      _several ->
        values =
          rows
          |> Enum.flat_map(fn [_, _, _, _, _, categories, candidates] -> categories ++ candidates end)
          |> Enum.uniq()

        repo().query!(
          "UPDATE trait_term_mappings SET status = 'ambiguous', categories = '{}', " <>
            "candidates = $1 WHERE id = $2",
          [values, id]
        )
    end
  end

  # -- other tables keyed by the normalized term ------------------------------------

  defp fold_keys(table, scope) do
    columns = Enum.join(["id", "term", "normalized_term" | scope], ", ")
    %{rows: rows} = repo().query!("SELECT #{columns} FROM #{table} ORDER BY id")

    taken = MapSet.new(rows, fn [_id, _term, old | scoped] -> {scoped, old} end)

    Enum.reduce(rows, taken, fn [id, term, old | scoped], taken ->
      key = normalize(term)

      cond do
        key == old ->
          taken

        MapSet.member?(taken, {scoped, key}) ->
          taken

        true ->
          repo().query!("UPDATE #{table} SET normalized_term = $1 WHERE id = $2", [key, id])
          taken |> MapSet.delete({scoped, old}) |> MapSet.put({scoped, key})
      end
    end)
  end

  defp fold_queue_refs do
    %{rows: rows} =
      repo().query!("""
      SELECT id, batch_id, kind::text, statement_ref,
             coalesce(subject->>'trait', subject->>'slot'), subject->>'term'
      FROM queue_items
      WHERE kind::text IN ('trait_term', 'set_aside_term', 'set_aside_statement')
        AND statement_ref LIKE 'u:%'
      ORDER BY id
      """)

    taken = MapSet.new(rows, fn [_id, batch, kind, ref, _, _] -> {batch, kind, ref} end)

    Enum.reduce(rows, taken, fn
      [id, batch, kind, old, trait, term], taken when is_binary(trait) and is_binary(term) ->
        ref = ref(trait, term)

        if ref == old or MapSet.member?(taken, {batch, kind, ref}) do
          taken
        else
          repo().query!("UPDATE queue_items SET statement_ref = $1 WHERE id = $2", [ref, id])
          taken |> MapSet.delete({batch, kind, old}) |> MapSet.put({batch, kind, ref})
        end

      _row, taken ->
        taken
    end)
  end

  # `Gallformers.Import.TraitTerms.statement_ref/2`, as written.
  defp ref(trait, term) do
    normalized = normalize(term)

    term_part =
      if byte_size(normalized) <= @max_term_bytes do
        normalized
      else
        hash = :crypto.hash(:sha256, normalized) |> Base.encode16(case: :lower)
        String.slice(normalized, 0, 100) <> "#" <> binary_part(hash, 0, 12)
      end

    "u:#{trait}:#{term_part}"
  end

  # `Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1`, as written.
  defp normalize(term) do
    term
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> String.split()
    |> Enum.map_join(" ", &singular_word/1)
  end

  defp singular_word(word), do: Regex.replace(~r/[[:alpha:]]+$/u, word, &singular/1)

  defp singular(word) when word in @not_plural, do: word

  defp singular(word) do
    cond do
      String.length(word) <= 3 -> word
      String.ends_with?(word, ["ss", "us", "is"]) -> word
      String.length(word) > 4 and String.ends_with?(word, "ies") -> String.slice(word, 0..-4//1) <> "y"
      String.ends_with?(word, ["sses", "shes", "ches", "xes", "zes"]) -> String.slice(word, 0..-3//1)
      String.ends_with?(word, "s") -> String.slice(word, 0..-2//1)
      true -> word
    end
  end
end
