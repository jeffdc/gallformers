defmodule Gallformers.Import.SourceDatesTest do
  @moduledoc """
  A Source's two derived dates (matter `f14c`, "Review queue and the
  Sources list"), `Gallformers.Import.source_dates/1`: Ingested, when its
  first package's batch was applied; Updated, when its data was last
  edited (its latest applied batch, or a later change to an attribution
  of it). A Source from the old data (no applied package, or one that was
  in Gallformers before its first package) has no Ingested date. A reading
  fix (matter `87a1`) moves Updated, never Ingested.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures

  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Import
  alias Gallformers.Sources.Source

  setup :audit_test_metadata

  @t1 ~U[2026-10-01 09:00:00Z]
  @t2 ~U[2026-10-20 15:30:00Z]
  @t3 ~U[2026-11-02 12:00:00Z]

  # A Source that came with an import: created no earlier than its package.
  defp imported_source do
    source = source_fixture("Galls of the Sierra", "1957")
    back_date!(source, ~U[2026-09-30 00:00:00Z])
    source
  end

  defp back_date!(source, at) do
    Repo.update_all(from(s in Source, where: s.id == ^source.id),
      set: [inserted_at: at, updated_at: at]
    )
  end

  defp attribute!(source) do
    {:ok, fact} = Facts.create_fact(test_actor(), %{kind: "trait"})
    {:ok, _} = Facts.attribute(test_actor(), confirm(source, %{fact_id: fact.id}))
    from(a in Attribution, where: a.fact_id == ^fact.id and a.source_id == ^source.id)
  end

  test "Ingested is the first applied batch, Updated the latest" do
    source = imported_source()
    applied_package!(source, @t2, inserted_at: ~U[2026-09-30 00:00:00Z])
    applied_package!(source, @t1, inserted_at: ~U[2026-09-30 00:00:00Z])

    applied_package!(source, nil,
      status: :awaiting_review,
      batch_status: :ready,
      inserted_at: ~U[2026-09-30 00:00:00Z]
    )

    assert %{source.id => %{ingested: @t1, updated: @t2, legacy?: false}} ==
             Import.source_dates([source.id])
  end

  test "a later change to an attribution of the Source moves Updated" do
    source = imported_source()
    applied_package!(source, @t1, inserted_at: ~U[2026-09-30 00:00:00Z])
    attribution = attribute!(source)
    Repo.update_all(attribution, set: [inserted_at: @t1, updated_at: @t1])

    assert %{updated: @t1} = Import.source_dates([source.id])[source.id]

    Repo.update_all(attribution, set: [updated_at: @t3])

    assert %{ingested: @t1, updated: @t3, legacy?: false} ==
             Import.source_dates([source.id])[source.id]
  end

  test "a Source with no applied package is from the old data, with no dates" do
    legacy = source_fixture("Old cynipid notes", "1920")
    back_date!(legacy, ~U[2026-01-01 00:00:00Z])
    in_review = source_fixture("Old cynipid survey", "1921")
    back_date!(in_review, ~U[2026-01-01 00:00:00Z])
    applied_package!(in_review, nil, status: :awaiting_review, batch_status: :ready)
    attribute!(legacy)

    assert %{
             legacy.id => %{ingested: nil, updated: nil, legacy?: true},
             in_review.id => %{ingested: nil, updated: nil, legacy?: true}
           } == Import.source_dates([legacy.id, in_review.id])
  end

  test "a Source from the old data that later got a package is updated, not ingested, by it" do
    source = source_fixture("Gallformers notes of old", "2020")
    back_date!(source, ~U[2026-01-01 00:00:00Z])
    applied_package!(source, @t2, inserted_at: ~U[2026-10-20 15:00:00Z])

    assert %{ingested: nil, updated: @t2, legacy?: true} ==
             Import.source_dates([source.id])[source.id]
  end

  test "a reading fix moves Updated, never Ingested: it brings nothing in (87a1)" do
    reading = %{"source" => %{"reading_of" => %{"gallformers_source_id" => 1}}}
    source = imported_source()
    applied_package!(source, @t2, inserted_at: ~U[2026-09-30 00:00:00Z])

    applied_package!(source, @t1, inserted_at: ~U[2026-09-29 00:00:00Z], content: reading)
    applied_package!(source, @t3, inserted_at: ~U[2026-11-02 00:00:00Z], content: reading)

    assert %{ingested: @t2, updated: @t3, legacy?: false} ==
             Import.source_dates([source.id])[source.id]

    old = source_fixture("Old cynipid notes", "1920")
    back_date!(old, ~U[2026-01-01 00:00:00Z])
    applied_package!(old, @t3, content: reading)

    assert %{ingested: nil, updated: @t3, legacy?: true} == Import.source_dates([old.id])[old.id]
  end

  test "every Source asked for is answered; none asked, none answered" do
    assert Import.source_dates([]) == %{}
    assert %{-1 => %{ingested: nil, updated: nil, legacy?: true}} == Import.source_dates([-1])
  end
end
