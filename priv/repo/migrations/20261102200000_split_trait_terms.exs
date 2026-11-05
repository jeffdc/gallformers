defmodule Gallformers.Repo.Migrations.SplitTraitTerms do
  @moduledoc """
  `trait_term_mappings` becomes the term table (matter d213, Task A): one
  Source term per row, placed once for every Source
  (`Gallformers.Catalog.Vocab.TraitTermMapping`).

    * `term` (as written) and `normalized_term` (lowercased, whitespace
      collapsed: the key, unique per trait);
    * `status`: `placed` (under its `categories`), `ambiguous` (its
      `candidates`: each use is decided on its own) or `no_fit`;
    * `categories`: the Trait values it is placed under. One, except a
      seeded rule (the leaf rule, "on the leaf" with no side stated → upper
      leaf and lower leaf): the check `trait_term_mappings_one_category`
      allows a second category only on a row placed by the seed with a
      rule;
    * `placed_by` (`seed`, `agreement`, `curator`, `superadmin`) and
      `placed_at`: how and when its status was set; `spot_checked_at`;
    * `rule`: kept for the guide text.

  The table keeps its name, though its rows are now terms rather than
  mappings: it is audited, and Carbonite records its history by table
  name, so a rename would part the terms from the history of the mappings
  they were split from; the replay kind `term_mapping_added` (6611) also
  names it.

  Today's rows are split (`split/1`): a row listing several terms ("oval,
  ovate, ovoid, ellipsoid, egg-shaped" → globular) becomes one row per
  term, each placed by the seed; a row with candidates ("swelling") becomes
  an ambiguous term, its seeded rule rewritten for format v4 (the category
  depends on the gall: `depends_on_gall`, never `unmapped`); the leaf
  rule, the one row mapping onto two values, stays one term, "on the
  leaf", its condition kept as its rule. The
  generation values' other names (trait `generation`) are split the same
  way. Rows are written in the order they had, so the generator's output
  keeps the contract's order.

  `replay_log.kind` gains `trait_term_edit` (`Gallformers.Import.VocabEdits`).
  The kind check is rebuilt from the kinds it allows now plus this one, so
  kinds other migrations add are kept whatever order they run in.
  """
  use Ecto.Migration

  @statuses ~w(placed ambiguous no_fit)
  @placed_by ~w(seed agreement curator superadmin)
  @kinds ["trait_term_edit"]

  @leaf_term "on the leaf, with no side, vein or midrib stated"
  @leaf_rule "On the leaf, with no side, vein or midrib stated: the Gall is on both sides, " <>
               "so the term gives two Facts, upper leaf and lower leaf."

  # The seeded rule for a term with candidates sent it to `unmapped`; in
  # format v4 a Trait term never goes there (d213, Task B).
  @candidates_rule_v3 "Choose the candidate whose definition the Source's description " <>
                        "fits. When nothing distinguishes them, record the term in unmapped " <>
                        "and name the candidates."
  @ambiguous_rule "The category depends on the gall: suggest the candidate whose definition " <>
                    "this gall's description fits, and set depends_on_gall; when nothing " <>
                    "distinguishes them, give category null with depends_on_gall."

  def up do
    alter table(:trait_term_mappings) do
      add :normalized_term, :text
      add :categories, {:array, :text}, null: false, default: []
      add :status, :text
      add :placed_by, :text
      add :placed_at, :utc_datetime
      add :spot_checked_at, :utc_datetime
    end

    drop constraint(:trait_term_mappings, :trait_term_mappings_target_present)
    drop unique_index(:trait_term_mappings, [:trait, :term])

    # The table is audited: the split is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("split_trait_terms",
      meta: meta("split_trait_terms")
    )

    flush()

    %{rows: rows} =
      repo().query!(
        "SELECT trait, term, maps_to, candidates, rule FROM trait_term_mappings ORDER BY id"
      )

    old =
      for [trait, term, maps_to, candidates, rule] <- rows,
          do: %{trait: trait, term: term, maps_to: maps_to, candidates: candidates, rule: rule}

    repo().query!("DELETE FROM trait_term_mappings")

    for row <- split(old) do
      repo().query!(
        """
        INSERT INTO trait_term_mappings
          (trait, term, normalized_term, categories, candidates, rule, status, placed_by, placed_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, 'seed', date_trunc('second', now() AT TIME ZONE 'UTC'))
        """,
        [
          row.trait,
          row.term,
          row.normalized_term,
          row.categories,
          row.candidates,
          row.rule,
          row.status
        ]
      )
    end

    alter table(:trait_term_mappings) do
      remove :maps_to
      modify :normalized_term, :text, null: false
      modify :status, :text, null: false
      modify :placed_by, :text, null: false
      modify :placed_at, :utc_datetime, null: false
    end

    create unique_index(:trait_term_mappings, [:trait, :normalized_term])

    create constraint(:trait_term_mappings, :trait_term_mappings_term_present,
             check: "btrim(term) <> '' AND normalized_term <> ''"
           )

    create constraint(:trait_term_mappings, :trait_term_mappings_placed_by_check,
             check: "placed_by IN (#{list(@placed_by)})"
           )

    # A placed term has its categories and no candidates; an ambiguous one
    # candidates and no category; a term fitting no category neither.
    create constraint(:trait_term_mappings, :trait_term_mappings_status_check,
             check: """
             (status = 'placed' AND cardinality(categories) > 0 AND cardinality(candidates) = 0)
             OR (status = 'ambiguous' AND cardinality(categories) = 0
                 AND cardinality(candidates) > 0)
             OR (status = 'no_fit' AND cardinality(categories) = 0
                 AND cardinality(candidates) = 0)
             """
           )

    create constraint(:trait_term_mappings, :trait_term_mappings_status_known,
             check: "status IN (#{list(@statuses)})"
           )

    # One category per term; only a seeded rule (the leaf rule) has two.
    create constraint(:trait_term_mappings, :trait_term_mappings_one_category,
             check: "cardinality(categories) <= 1 OR (placed_by = 'seed' AND rule IS NOT NULL)"
           )

    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    # Both tables are audited: the changes are recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("unsplit_trait_terms",
      meta: meta("unsplit_trait_terms")
    )

    execute "DELETE FROM replay_log WHERE kind IN (#{list(@kinds)})"
    replace_kind_check(current_kinds() -- @kinds)

    for name <- ~w(one_category status_known status_check placed_by_check term_present) do
      drop constraint(:trait_term_mappings, :"trait_term_mappings_#{name}")
    end

    drop unique_index(:trait_term_mappings, [:trait, :normalized_term])

    alter table(:trait_term_mappings) do
      add :maps_to, {:array, :text}, null: false, default: []
    end

    flush()

    # The terms stay one per row; a term fitting no category had no mapping.
    # The leaf rule and the candidates' rule are as seeded before.
    repo().query!("DELETE FROM trait_term_mappings WHERE status = 'no_fit'")
    repo().query!("UPDATE trait_term_mappings SET maps_to = categories")

    repo().query!(
      "UPDATE trait_term_mappings SET term = $1, rule = NULL WHERE term = 'on the leaf' AND rule = $2",
      [@leaf_term, @leaf_rule]
    )

    repo().query!("UPDATE trait_term_mappings SET rule = $1 WHERE rule = $2", [
      @candidates_rule_v3,
      @ambiguous_rule
    ])

    alter table(:trait_term_mappings) do
      remove :normalized_term
      remove :categories
      remove :status
      remove :placed_by
      remove :placed_at
      remove :spot_checked_at
    end

    create unique_index(:trait_term_mappings, [:trait, :term])

    create constraint(:trait_term_mappings, :trait_term_mappings_target_present,
             check: "cardinality(maps_to) > 0 OR cardinality(candidates) > 0"
           )
  end

  @doc """
  Today's rows (`%{trait, term, maps_to, candidates, rule}`, in order) as
  term rows (`%{trait, term, normalized_term, status, categories,
  candidates, rule}`), in order: see the moduledoc.
  """
  def split(rows) do
    rows
    |> Enum.flat_map(&split_row/1)
    |> Enum.uniq_by(&{&1.trait, &1.normalized_term})
  end

  defp split_row(%{term: @leaf_term} = row),
    do: [term_row(row, "on the leaf", "placed", row.maps_to, [], @leaf_rule)]

  defp split_row(%{maps_to: [], candidates: [_ | _]} = row),
    do: [term_row(row, row.term, "ambiguous", [], row.candidates, ambiguous_rule(row.rule))]

  defp split_row(%{maps_to: [_, _ | _]} = row),
    do: [term_row(row, row.term, "placed", row.maps_to, [], row.rule || row.term)]

  defp split_row(row) do
    for term <- String.split(row.term, ","),
        String.trim(term) != "",
        do: term_row(row, String.trim(term), "placed", row.maps_to, [], row.rule)
  end

  defp ambiguous_rule(@candidates_rule_v3), do: @ambiguous_rule
  defp ambiguous_rule(rule), do: rule

  defp term_row(row, term, status, categories, candidates, rule) do
    %{
      trait: row.trait,
      term: term,
      normalized_term: normalize(term),
      status: status,
      categories: categories,
      candidates: candidates,
      rule: rule
    }
  end

  # As `Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1` does it,
  # held here so the migration does not change with the code.
  defp normalize(term) do
    term
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> String.split()
    |> Enum.join(" ")
  end

  defp current_kinds do
    %{rows: [[definition]]} =
      repo().query!(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'replay_log_kind_check'"
      )

    Regex.scan(~r/'([a-z_]+)'/, definition, capture: :all_but_first) |> List.flatten()
  end

  defp replace_kind_check(kinds) do
    drop constraint(:replay_log, :replay_log_kind_check)

    create constraint(:replay_log, :replay_log_kind_check, check: "kind IN (#{list(kinds)})")
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")

  # The audit record a data change in a migration needs: an actor and an
  # operation (`transactions_meta_attribution`).
  defp meta(name),
    do: %{actor: %{type: "system", name: "migration"}, operation: "migration.#{name}"}
end
