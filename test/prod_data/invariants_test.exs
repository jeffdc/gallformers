defmodule Gallformers.ProdData.InvariantsTest do
  @moduledoc """
  Invariants of the new back-end (`Gallformers.Catalog`, `Gallformers.Taxa`)
  on a converted production copy (`Gallformers.ProdDataCase`).
  """
  use Gallformers.ProdDataCase

  @moduletag :prod_data

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.LegacyCitation
  alias Gallformers.Catalog.NonGallRedirect
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Catalog.ReadModels.PotentialRange
  alias Gallformers.Sources.Source
  alias Gallformers.Taxa.Taxon

  # Every n-th Gall (by ID) is compared with its potential range.
  @gall_index_stride 10

  test "database has converted data" do
    assert data_count(Gall) >= 1000
    assert data_count(Taxon) > 500
  end

  describe "Galls" do
    test "every Gall has a display name" do
      bad =
        Repo.all(
          from g in Gall,
            where: fragment("btrim(COALESCE(?, ?, '')) = ''", g.name_override, g.name),
            select: g.id
        )

      assert bad == [], "Found #{length(bad)} Galls without a display name: #{inspect(bad)}"
    end

    test "each Gall has at most one current Inducer" do
      # No curator flag covers a Gall with several Inducers, so there must be none.
      bad =
        Repo.all(
          from r in Current.relationships("inducer_of"),
            group_by: r.object_gall_id,
            having: count(r.subject_taxon_id, :distinct) > 1,
            select: {r.object_gall_id, fragment("array_agg(DISTINCT ?)", r.subject_taxon_id)}
        )

      assert bad == [],
             "Found #{length(bad)} Galls with more than one current Inducer: #{inspect(Enum.take(bad, 10))}"
    end

    test "every current Host is a Plantae taxon" do
      bad =
        Repo.all(
          from r in Current.relationships("host_of"),
            join: t in Taxon,
            on: t.id == r.subject_taxon_id,
            where: is_nil(t.kingdom) or t.kingdom != "Plantae",
            select: %{gall_id: r.object_gall_id, taxon_id: t.id, kingdom: t.kingdom}
        )

      assert bad == [],
             "Found #{length(bad)} current Hosts outside Plantae: #{inspect(Enum.take(bad, 10))}"
    end

    test "every legacy citation's Source exists" do
      bad =
        Repo.all(
          from c in LegacyCitation,
            left_join: s in Source,
            on: s.id == c.source_id,
            where: is_nil(s.id),
            select: %{id: c.id, gall_id: c.gall_id, source_id: c.source_id}
        )

      assert bad == [],
             "Found #{length(bad)} legacy citations without their Source: #{inspect(Enum.take(bad, 10))}"
    end

    test "no non-gall redirect's species ID is a Gall" do
      bad =
        Repo.all(
          from n in NonGallRedirect,
            join: g in Gall,
            on: g.id == n.species_id,
            select: %{species_id: n.species_id, name: n.name}
        )

      assert bad == [],
             "Found #{length(bad)} non-gall redirects whose ID is a Gall: #{inspect(Enum.take(bad, 10))}"
    end
  end

  describe "taxon tree" do
    # Walks `taxa.parent_id` up from every taxon, stopping at a taxon already
    # on the path, so a cycle ends the walk instead of looping.
    @closure """
    WITH RECURSIVE closure(ancestor_id, descendant_id, depth, path) AS (
      SELECT id, id, 0, ARRAY[id] FROM taxa
      UNION ALL
      SELECT t.parent_id, c.descendant_id, c.depth + 1, c.path || t.parent_id
      FROM closure c
      JOIN taxa t ON t.id = c.ancestor_id
      WHERE t.parent_id IS NOT NULL AND NOT t.parent_id = ANY(c.path)
    )
    """

    test "no taxon is its own ancestor (no parent_id cycles)" do
      %{rows: rows} =
        Repo.query!(
          @closure <>
            """
            SELECT DISTINCT c.descendant_id
            FROM closure c
            JOIN taxa t ON t.id = c.ancestor_id
            WHERE t.parent_id = ANY(c.path)
            ORDER BY 1
            """,
          [],
          timeout: :infinity
        )

      bad = List.flatten(rows)
      assert bad == [], "Found #{length(bad)} taxa on a parent_id cycle: #{inspect(bad)}"
    end

    test "taxon_ancestry matches parent_id" do
      missing =
        Repo.query!(
          @closure <>
            """
            SELECT ancestor_id, descendant_id, depth FROM closure
            EXCEPT
            SELECT ancestor_id, descendant_id, depth FROM taxon_ancestry
            ORDER BY 2, 3
            """,
          [],
          timeout: :infinity
        ).rows

      extra =
        Repo.query!(
          @closure <>
            """
            SELECT ancestor_id, descendant_id, depth FROM taxon_ancestry
            EXCEPT
            SELECT ancestor_id, descendant_id, depth FROM closure
            ORDER BY 2, 3
            """,
          [],
          timeout: :infinity
        ).rows

      assert missing == [],
             "Found #{length(missing)} [ancestor, descendant, depth] rows that parent_id implies but taxon_ancestry lacks: #{inspect(Enum.take(missing, 10))}"

      assert extra == [],
             "Found #{length(extra)} taxon_ancestry rows that parent_id does not imply: #{inspect(Enum.take(extra, 10))}"
    end
  end

  describe "gall_index" do
    test "has exactly one row per Gall" do
      missing =
        Repo.all(
          from g in Gall,
            left_join: r in GallIndex,
            on: r.gall_id == g.id,
            where: is_nil(r.gall_id),
            select: g.id
        )

      orphans =
        Repo.all(
          from r in GallIndex,
            left_join: g in Gall,
            on: g.id == r.gall_id,
            where: is_nil(g.id),
            select: r.gall_id
        )

      assert missing == [], "Found #{length(missing)} Galls without a gall_index row"
      assert orphans == [], "Found #{length(orphans)} gall_index rows of no Gall"
    end

    test "a sample of rows matches PotentialRange.for_galls/1" do
      rows =
        Repo.all(
          from r in GallIndex,
            where: fragment("? % ? = 0", r.gall_id, ^@gall_index_stride),
            order_by: r.gall_id
        )

      assert rows != []

      ranges = rows |> Enum.map(& &1.gall_id) |> PotentialRange.for_galls()

      bad =
        for row <- rows,
            expected = Map.fetch!(ranges, row.gall_id),
            stored = stored_range(row),
            stored != expected_range(expected) do
          %{gall_id: row.gall_id, stored: stored, expected: expected_range(expected)}
        end

      assert bad == [],
             "Found #{length(bad)} of #{length(rows)} sampled gall_index rows whose range differs from PotentialRange: #{inspect(Enum.take(bad, 5))}"
    end
  end

  defp stored_range(%GallIndex{everywhere: true, place_ids: []}), do: :everywhere
  defp stored_range(%GallIndex{everywhere: true} = row), do: {:everywhere, row.place_ids}
  defp stored_range(%GallIndex{place_ids: ids}), do: Enum.sort(ids)

  defp expected_range(:everywhere), do: :everywhere
  defp expected_range(places), do: places |> Enum.map(& &1.place_id) |> Enum.sort()
end
