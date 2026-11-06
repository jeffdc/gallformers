defmodule Gallformers.CatalogMigration.LegacyTaxonomyTest do
  @moduledoc """
  Today's non-plant tree as undated statements of the "Gallformers legacy
  data" Source at cutover (`f923` Task 3): each non-plant taxon's
  placement, accepted name (rank, authorship, sensu), synonyms and common
  names. Plants get none: their data stays editorial. Re-running changes
  nothing.

  Not async: the migration rebuilds every new table inside the sandbox.
  """
  use Gallformers.DataCase, async: false

  # The migration converts the seeds' old tables, which is what this tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.LegacyTaxonomy
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Sources
  alias Mix.Tasks.Gallformers.Catalog.Migrate

  setup do
    # As `make test-db` runs it: with the test's curated decisions.
    curated = Migrate.curated_paths("test/support/fixtures/catalog_migration")
    assert {:ok, %Report{} = report} = CatalogMigration.run([actor: test_actor()] ++ curated)
    %{report: report, legacy: Sources.get_legacy_data_source()}
  end

  # The legacy Source's current statements of `kind`, as `{taxon, value}`.
  defp current(kind, legacy) do
    {sql, value} =
      case kind do
        "taxon_placement" -> {"placement_facts", "d.parent_id"}
        "taxon_name" -> {"name_facts", "d.name"}
        "taxon_common_name" -> {"common_name_facts", "d.common_name"}
      end

    Repo.query!(
      """
      SELECT d.taxon_id, #{value}, f.standing, a.stated_on
      FROM #{sql} d
      JOIN facts f ON f.id = d.fact_id
      JOIN attributions a ON a.fact_id = f.id AND a.source_id = $1
      ORDER BY d.taxon_id
      """,
      [legacy.id]
    ).rows
  end

  defp non_plant_taxa do
    Repo.query!("""
    SELECT t.id, t.parent_id, n.name FROM taxa t
    JOIN taxon_names n ON n.taxon_id = t.id AND n.status = 'accepted'
    WHERE t.kingdom IS DISTINCT FROM 'Plantae' ORDER BY t.id
    """).rows
  end

  test "each non-plant taxon has one current, undated placement and name of the legacy Source",
       %{legacy: legacy} do
    taxa = non_plant_taxa()
    assert taxa != []

    assert current("taxon_placement", legacy) ==
             for([id, parent_id, _name] <- taxa, do: [id, parent_id, "current", nil])

    assert current("taxon_name", legacy) ==
             for([id, _parent_id, name] <- taxa, do: [id, name, "current", nil])
  end

  test "the name statements carry the tree's rank, authorship and sensu", %{legacy: legacy} do
    mismatches =
      Repo.query!(
        """
        SELECT t.id FROM taxa t
        JOIN taxon_names n ON n.taxon_id = t.id AND n.status = 'accepted'
        JOIN name_facts d ON d.taxon_id = t.id
        JOIN attributions a ON a.fact_id = d.fact_id AND a.source_id = $1
        WHERE d.rank <> t.rank::text OR d.authorship IS DISTINCT FROM n.authorship
           OR d.sensu IS DISTINCT FROM n.sensu
        """,
        [legacy.id]
      ).rows

    assert mismatches == []
  end

  test "each non-plant synonym and common name is a current legacy statement", %{legacy: legacy} do
    synonyms =
      Repo.query!("""
      SELECT n.taxon_id, n.normalized_name FROM taxon_names n JOIN taxa t ON t.id = n.taxon_id
      WHERE n.status = 'synonym' AND t.kingdom IS DISTINCT FROM 'Plantae' ORDER BY 1, 2
      """).rows

    stated =
      Repo.query!(
        """
        SELECT d.accepted_taxon_id, d.normalized_name FROM synonymy_facts d
        JOIN facts f ON f.id = d.fact_id AND f.standing = 'current'
        JOIN attributions a ON a.fact_id = f.id AND a.source_id = $1 ORDER BY 1, 2
        """,
        [legacy.id]
      ).rows

    assert synonyms != []
    assert stated == synonyms

    common =
      Repo.query!("""
      SELECT c.taxon_id, c.name FROM taxon_common_names c JOIN taxa t ON t.id = c.taxon_id
      WHERE t.kingdom IS DISTINCT FROM 'Plantae' ORDER BY 1, 2
      """).rows

    assert Enum.sort(
             for [t, n, "current", nil] <- current("taxon_common_name", legacy), do: [t, n]
           ) ==
             common
  end

  test "plants get none", %{legacy: legacy} do
    assert Repo.query!(
             """
             SELECT count(*) FROM taxa t
             WHERE t.kingdom = 'Plantae' AND EXISTS (
               SELECT 1 FROM placement_facts d JOIN attributions a ON a.fact_id = d.fact_id
               WHERE d.taxon_id = t.id AND a.source_id = $1
               UNION ALL
               SELECT 1 FROM name_facts d JOIN attributions a ON a.fact_id = d.fact_id
               WHERE d.taxon_id = t.id AND a.source_id = $1)
             """,
             [legacy.id]
           ).rows == [[0]]
  end

  test "the report reconciles the statements", %{report: report} do
    assert %{old: n, new: n} =
             Enum.find(report.reconciliation, &(&1.label =~ "Legacy taxonomic statements"))

    assert n > 0
  end

  test "re-running changes nothing" do
    changes_before = Repo.aggregate(test_audit_changes(), :count)

    assert :ok = LegacyTaxonomy.run(test_actor())

    assert Repo.aggregate(test_audit_changes(), :count) == changes_before
  end
end
