defmodule Gallformers.CatalogMigration do
  @moduledoc """
  The data migration (`9449` §6, Tasks 15–17; `b5bd` M2): fills the new
  back-end's tables from today's (`species`, `taxonomy`, `gallhost`,
  `species_source`, ...), which it only reads — except the kept `keys`
  table, whose couplets it re-targets in place.

  It runs from a production copy, explicitly — never at boot (`b5bd` M0):
  `mix gallformers.catalog.migrate` locally against a copy, or
  `Gallformers.Release.migrate_catalog/0` in the maintenance window.

  ## Repeatable

  A run first empties the new domain tables (taxa, Galls, Facts and their
  details, Gallformers notes, legacy citations, the import tables) and the
  re-keyed columns on `host_range` and `image`, then refills them, audited
  as one system actor. It never touches `replay_log` — the backscan's
  record, replayed after the migration (`Gallformers.Import.Replay`) — nor
  Sources (except creating the legacy Source once), stored Source
  documents or the vocabularies. Taxa and Galls keep stable keys from run
  to run (plant and Gall IDs, names, crosswalk entries); taxa that get new
  IDs (higher taxa, Inducers) draw them afresh from `entity_id_seq`, which
  only ever moves forward and ends above every ID used.

  Everything but the legacy Facts (and the range and gall alias Facts the
  curated decisions make) is written in one transaction; those Facts
  follow in transactions of 500 (see
  `Gallformers.CatalogMigration.LegacyFacts`, *Chunks*). A run that fails
  part-way through them leaves the new tables part-filled: run it again.

  ## Steps

    1. `Gallformers.CatalogMigration.NonGalls` — the gall rows not to
       migrate (`non_galls.csv`), recorded for their old URLs' redirect to
       the gall-lookalikes Article, which
       `Gallformers.CatalogMigration.LookalikesArticle` creates when missing.
    2. `Gallformers.CatalogMigration.Taxa` — higher taxa (rows kept twice
       merged, `taxon_merges.csv`; family kingdoms a curator set,
       `kingdoms.csv`), plants, genus placeholders (crosswalked to their
       genus for their old URLs), `host_range` re-keyed by taxon.
    3. `Gallformers.CatalogMigration.Galls` — Inducer taxa from gall names
       (`priv/catalog_migration/name_suffixes.csv`), Galls, their name parts
       and derived names (`Gallformers.CatalogMigration.GallNames`; today's
       name kept as the override only where the derived one differs).
    4. `Gallformers.CatalogMigration.Citations` — other Sources' record-level
       citations as legacy citations (not Facts).
    5. `Gallformers.CatalogMigration.Notes` — Gallformers ID Notes, verbatim,
       as undated note documents.
    6. `Gallformers.CatalogMigration.Images` — each image's typed reference.
    7. `Gallformers.CatalogMigration.LegacyFacts` — Inducer, Host and Trait
       Facts, attributed to the undated "Gallformers legacy data" Source.
    8. `Gallformers.CatalogMigration.Ranges` — stored gall ranges, compared
       with the host union, as range Facts (`range_decisions.csv`).
    9. `Gallformers.CatalogMigration.Aliases` — aliases sorted by meaning
       into synonyms, common names, gall aliases (`aliases.csv`).
    10. `Gallformers.CatalogMigration.Keys` — key couplets re-targeted
        (`keys.csv`).
    11. The ID tool's lookup table (`Gallformers.Catalog.rebuild_gall_index/0`),
        rebuilt from all of the above. During the run no lookup-table
        refresh is enqueued (`Gallformers.Catalog.without_gall_index_refresh/1`):
        production runs it without Oban.

  ## Curated decisions

  Steps 1 and 8–10 report what needs a curator (worksheets in the report,
  written as CSV by `Report.write_curation/2`) and apply the decisions in
  `priv/catalog_migration/` (`Gallformers.CatalogMigration.Curated`); step
  2 applies `taxon_merges.csv` and `kingdoms.csv`, which have no worksheet,
  checked against today's taxonomy rows before anything is written (as
  `range_decisions.csv` scopes are against today's places). A
  **strict** run (the default; production's, `Gallformers.Release`) stops
  with nothing written when a row needs a decision it does not have, or
  taxa share an accepted name, rank and kingdom (replay would stop on
  them): `{:error, {:pending_decisions, report}}`. A **lenient** run
  (`pending: :skip`), for copies before curation is done, leaves those rows
  out and lists them as pending.

  The result is a `Gallformers.CatalogMigration.Report`: counts reconciled,
  duplicate taxon keys, names needing review or not read, other problems,
  pending decisions and the worksheets.
  """
  use Boundary,
    deps: [
      Gallformers.Articles,
      Gallformers.Audit,
      Gallformers.Catalog,
      Gallformers.Repo,
      Gallformers.Sources,
      Gallformers.Taxa
    ],
    exports: [NameSuffixes, Report, TraitIdExport]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.CatalogMigration.Aliases
  alias Gallformers.CatalogMigration.Citations
  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Galls
  alias Gallformers.CatalogMigration.Images
  alias Gallformers.CatalogMigration.Keys
  alias Gallformers.CatalogMigration.Kingdoms
  alias Gallformers.CatalogMigration.LegacyFacts
  alias Gallformers.CatalogMigration.LookalikesArticle
  alias Gallformers.CatalogMigration.NameSuffixes
  alias Gallformers.CatalogMigration.NonGalls
  alias Gallformers.CatalogMigration.Notes
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Ranges
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.CatalogMigration.Taxa, as: MigrationTaxa
  alias Gallformers.CatalogMigration.TaxonMerges
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa.NameNormalizer

  # Emptied before each run, children first. Never `replay_log`, Sources,
  # their stored documents or the vocabularies; of `source_documents`, only
  # the Gallformers notes (rebuilt from `species_source`).
  @clear [
    "UPDATE host_range SET taxon_id = NULL WHERE taxon_id IS NOT NULL",
    "UPDATE image SET gall_id = NULL, taxon_id = NULL " <>
      "WHERE gall_id IS NOT NULL OR taxon_id IS NOT NULL",
    "DELETE FROM queue_items",
    "DELETE FROM batch_unmapped",
    "DELETE FROM batch_statements",
    "DELETE FROM attribution_evidence",
    "DELETE FROM attribution_names",
    "DELETE FROM attribution_observations",
    "DELETE FROM attributions",
    "DELETE FROM qualifier_facts",
    "DELETE FROM relationship_facts",
    "DELETE FROM trait_facts",
    "DELETE FROM range_facts",
    "DELETE FROM occurrence_facts",
    "DELETE FROM alias_facts",
    "DELETE FROM description_facts",
    "DELETE FROM placement_facts",
    "DELETE FROM name_facts",
    "DELETE FROM synonymy_facts",
    "DELETE FROM split_fact_daughters",
    "DELETE FROM split_facts",
    "DELETE FROM common_name_facts",
    "DELETE FROM facts",
    "DELETE FROM import_batches",
    "DELETE FROM import_packages",
    "DELETE FROM legacy_citations",
    "DELETE FROM non_gall_redirects",
    "DELETE FROM source_documents WHERE kind = 'note'",
    "DELETE FROM galls",
    "DELETE FROM generation_group_taxa",
    "DELETE FROM taxon_ancestry",
    "DELETE FROM taxon_common_names",
    "DELETE FROM legacy_taxon_ids",
    "DELETE FROM taxon_names",
    "DELETE FROM taxa"
  ]

  @doc """
  Runs the migration. Options:

    * `:actor` — the audited actor (default the system actor
      `"catalog_migration"`)
    * `:name_suffixes` — the name-suffix mapping file (default the shipped
      one)
    * `:non_galls`, `:range_decisions`, `:aliases`, `:keys`,
      `:taxon_merges`, `:kingdoms` — the curated decision files (`Gallformers.CatalogMigration.Curated`; default the
      shipped ones)
    * `:pending` — `:fail` (the default, and the only mode for production)
      stops the run, writing nothing, when a curated row needs a decision
      it does not have or taxa share a replay key; `:skip` (for runs on a
      copy before curation is done) leaves those rows out and reports them

  Loads the Catalog vocabularies first (idempotent). Returns the report;
  `{:error, {:pending_decisions, report}}` from a strict run that stopped
  (the report lists them); or `{:error, reason}` for a mapping or decision
  file that cannot be used, before anything is written. Any other failure
  raises.
  """
  @spec run(keyword()) ::
          {:ok, Report.t()} | {:error, {:pending_decisions, Report.t()}} | {:error, term()}
  def run(opts \\ []) do
    # The ID tool's lookup table is rebuilt once at the end, not refreshed
    # per Fact (production runs this without Oban).
    Catalog.without_gall_index_refresh(fn -> migrate(opts) end)
  end

  defp migrate(opts) do
    actor = Keyword.get_lazy(opts, :actor, fn -> Actor.system("catalog_migration") end)
    path = Keyword.get_lazy(opts, :name_suffixes, &NameSuffixes.default_path/0)

    with {:ok, mode} <- pending_mode(opts),
         {:ok, suffixes} <- NameSuffixes.load(path),
         {:ok, curated} <- load_curated(opts),
         {:ok, curated} <- check_taxa_decisions(curated),
         {:ok, ranges} <- Ranges.check(curated.range_decisions),
         curated = %{curated | range_decisions: ranges},
         {:ok, _counts} <- Catalog.load_vocab(actor),
         {:ok, generations} <- generations(suffixes),
         {:ok, {plan, curated_facts, report}} <-
           transaction(actor, "catalog_migration.run", fn ->
             skeleton(actor, suffixes, generations, curated, mode)
           end) do
      :ok = LegacyFacts.assert_all(actor, plan)
      :ok = LegacyFacts.assert_all(actor, %{plan | assertions: curated_facts})

      transaction(actor, "catalog_migration.finish", fn ->
        advance_sequence!("species", "galls", "taxa")

        # Curated `only` range Facts and gall aliases are the legacy Source's too.
        by_legacy =
          for {_kind, _key, %{source_id: id}} = a <- curated_facts, id == plan.source_id, do: a

        report
        |> then(&LegacyFacts.reconcile(%{plan | assertions: plan.assertions ++ by_legacy}, &1))
        |> then(&Ranges.reconcile(curated_facts, &1))
        |> then(&Aliases.reconcile(curated_facts, &1))
        |> rebuild_gall_index()
      end)
    end
  end

  # Step 11: the ID tool's lookup table, from everything above.
  defp rebuild_gall_index(report) do
    :ok = Catalog.rebuild_gall_index()

    Report.reconcile(
      report,
      "Galls in the ID tool's lookup table (gall_index)",
      Old.count("SELECT count(*) FROM galls"),
      Old.count("SELECT count(*) FROM gall_index")
    )
  end

  defp pending_mode(opts) do
    case Keyword.get(opts, :pending, :fail) do
      mode when mode in [:fail, :skip] -> {:ok, mode}
      other -> {:error, {:pending, "must be :fail or :skip, got #{inspect(other)}"}}
    end
  end

  # The curated decision files, read before anything is written.
  defp load_curated(opts) do
    loaders = [
      non_galls: &NonGalls.load/1,
      range_decisions: &Ranges.load/1,
      aliases: &Aliases.load/1,
      keys: &Keys.load/1,
      taxon_merges: &TaxonMerges.load/1,
      kingdoms: &Kingdoms.load/1
    ]

    Enum.reduce_while(loaders, {:ok, %{}}, fn {input, load}, {:ok, acc} ->
      path = Keyword.get_lazy(opts, input, fn -> Curated.default_path(input) end)

      case load.(path) do
        {:ok, decisions} -> {:cont, {:ok, Map.put(acc, input, decisions)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  # The merges and kingdoms checked against today's taxonomy rows, before
  # anything is written: `curated.taxa` for the taxa step.
  defp check_taxa_decisions(curated) do
    rows = Map.new(Old.taxonomy(), &{&1.id, &1})

    with {:ok, merges, merges_stale} <- TaxonMerges.check(curated.taxon_merges, rows),
         {:ok, kingdoms, kingdoms_stale} <- Kingdoms.check(curated.kingdoms, rows, merges) do
      taxa = %{
        merges: merges,
        kingdoms: kingdoms,
        stale: [{"taxon_merges.csv", merges_stale}, {"kingdoms.csv", kingdoms_stale}]
      }

      {:ok, Map.put(curated, :taxa, taxa)}
    end
  end

  @doc false
  # One audited transaction with no time limit (the migration's are long).
  # `fun` may end it with `Repo.rollback/1`, which returns `{:error, value}`.
  @spec transaction(Actor.t(), String.t(), (-> result)) ::
          {:ok, result} | {:error, term()}
        when result: var
  def transaction(actor, operation, fun) do
    Repo.transaction(
      fn ->
        case Audit.transaction(actor, operation, fun) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: :infinity
    )
  end

  # Every generation value the mapping names, with its ID and qualifier.
  defp generations(suffixes) do
    values =
      (Map.values(suffixes.tokens) ++ Map.values(suffixes.galls))
      |> Enum.map(& &1.generation)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    found =
      for value <- values, gv = Catalog.get_generation_value(value), into: %{} do
        {value, %{id: gv.id, qualifier: gv.name_qualifier}}
      end

    case values -- Map.keys(found) do
      [] -> {:ok, found}
      missing -> {:error, {:unknown_generations, Enum.sort(missing)}}
    end
  end

  # Everything but the legacy Facts, which it plans. A strict run with
  # rows awaiting decisions rolls everything back here.
  defp skeleton(actor, suffixes, generations, curated, mode) do
    clear!()
    advance_sequence!("species")

    report = %Report{}
    {excluded, report} = NonGalls.run(actor, curated.non_galls, report)
    report = LookalikesArticle.run(report)
    {taxa, report} = MigrationTaxa.run(actor, curated.taxa, report)
    {galls, report} = Galls.run(actor, suffixes, generations, taxa, report, excluded)

    gall_ids = Map.new(galls, &{&1.id, true})
    gallformers = Sources.get_gallformers_source()

    report =
      report
      |> then(&Citations.run(actor, gall_ids, gallformers && gallformers.id, &1))
      |> then(&Notes.run(actor, gall_ids, gallformers, &1))
      |> then(&Images.run(taxa.plants, &1))

    {plan, report} = LegacyFacts.plan(taxa, galls, report)
    legacy = %{source_id: plan.source_id, stance: :confirm, stated: nil}

    {ranges, report} =
      Ranges.run(
        curated.range_decisions,
        taxa,
        galls,
        %{legacy: legacy, gallformers: gallformers},
        report
      )

    {aliases, report} = Aliases.run(actor, curated.aliases, taxa, galls, legacy, report)
    report = Keys.run(curated.keys, gall_ids, report)
    report = %{report | duplicates: duplicates()}

    if mode == :fail and Report.blocking?(report),
      do: Repo.rollback({:pending_decisions, report}),
      else: {plan, ranges ++ aliases, report}
  end

  defp clear! do
    Enum.each(@clear, &Repo.query!(&1, [], timeout: :infinity))
  end

  # Moves `entity_id_seq` forward (never back) so its next value is above
  # every ID in `tables`.
  defp advance_sequence!(table), do: advance_sequence!(table, nil, nil)

  defp advance_sequence!(a, b, c) do
    maxima =
      [a, b, c]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(", ", &"(SELECT COALESCE(MAX(id), 0) + 1 FROM #{&1})")

    Repo.query!("""
    SELECT setval('entity_id_seq', GREATEST(
      (SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM entity_id_seq),
      #{maxima}), false)
    """)

    :ok
  end

  # Taxa the replay log could not tell apart: the same accepted name (as
  # resolution normalizes it) and rank, in the same kingdom — or with no
  # kingdom, which resolution does not filter on.
  defp duplicates do
    """
    SELECT n.normalized_name, n.name, t.rank, t.kingdom, t.id
    FROM taxa t JOIN taxon_names n ON n.taxon_id = t.id AND n.status = 'accepted'
    ORDER BY n.normalized_name, t.rank, t.id
    """
    |> Old.rows()
    |> Enum.group_by(&{&1.normalized_name, &1.rank})
    |> Enum.flat_map(fn {_key, taxa} -> clashes(taxa) end)
    |> Enum.sort_by(&{NameNormalizer.normalize(&1.name), &1.rank, &1.kingdom || ""})
  end

  defp clashes([_one]), do: []

  defp clashes(taxa) do
    {kingdomless, with_kingdom} = Enum.split_with(taxa, &is_nil(&1.kingdom))

    groups =
      if kingdomless == [],
        do: Enum.group_by(with_kingdom, & &1.kingdom) |> Map.values(),
        else: [taxa]

    for [first | _] = group <- groups, length(group) > 1 do
      %{
        name: first.name,
        rank: String.to_existing_atom(first.rank),
        kingdom: first.kingdom,
        taxon_ids: Enum.map(group, & &1.id)
      }
    end
  end
end
