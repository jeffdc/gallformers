defmodule Gallformers.Audit.ChangeLogTest do
  @moduledoc """
  The curators' change log (`Gallformers.Audit.ChangeLog`): their audited
  transactions, grouped and described down to each Fact.

  A test runs in one database transaction, so the audit trail would record
  one change for it. These tests write the curators' transactions and their
  changes into the trail directly, over real Galls, plants and Facts.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.AuditFixtures
  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.ChangeLog
  alias Gallformers.Catalog

  defp tx(who, operation, minutes_ago, changes),
    do: curator_change(who, operation, minutes_ago, changes)

  setup do
    gall = gall_fixture(%{name: "Andricus fixturi"})
    oak = plant_fixture(name: "Quercus alba")
    source = source_fixture("Weld", "1959")

    {:ok, host} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: oak.id, object_gall_id: gall.id},
        confirm(source)
      )

    %{gall: gall, oak: oak, source: source, package: package_for(source), host_fact: host.fact}
  end

  test "a curator's import: who, what, the Source, and each Fact in words", ctx do
    tx("Adam", "import.apply_batch", 5, [
      {"import_batches", "update", %{id: 1, package_id: ctx.package.id}},
      {"facts", "insert", %{id: ctx.host_fact.id, kind: "gall_relationship", standing: "current"}}
    ])

    [change] = ChangeLog.groups(limit: 10)

    assert change.who == "Adam"
    assert change.title == "Applied an import"
    assert change.source == %{id: ctx.source.id, title: ctx.source.title}
    assert change.galls == [%{id: ctx.gall.id, name: "Andricus fixturi"}]

    assert [
             %{
               change: :added,
               what: "host: Quercus alba",
               gall: %{id: _, name: "Andricus fixturi"}
             }
           ] = change.facts

    assert change.counts == %{added: 1}
  end

  test "consecutive changes by one curator, of one kind, on one Source, are one group", ctx do
    q = fn ->
      {"queue_items", "update",
       %{id: System.unique_integer([:positive]), package_id: ctx.package.id}}
    end

    tx("Adam", "import.decide_queue_item", 30, [q.()])
    tx("Adam", "import.decide_queue_item", 20, [q.()])
    tx("Jeff", "import.decide_queue_item", 10, [q.()])

    assert [
             %{who: "Jeff", title: "Decided a question"},
             %{who: "Adam", title: "Decided 2 questions"}
           ] =
             ChangeLog.groups(limit: 10)
  end

  test "system work and re-checked imports are left out", ctx do
    tx(:system, "import.register_package", 3, [
      {"import_packages", "insert", %{id: ctx.package.id}}
    ])

    tx("Adam", "import.resolve_package", 2, [{"import_packages", "update", %{id: ctx.package.id}}])

    assert ChangeLog.groups(limit: 10) == []
  end

  test "a Fact added and made current in one change reads as added", ctx do
    tx("Adam", "import.apply_batch", 5, [
      {"facts", "insert", %{id: ctx.host_fact.id, standing: "unsupported"}},
      {"facts", "update", %{id: ctx.host_fact.id, standing: "current"}}
    ])

    assert [%{facts: [%{change: :added}], counts: %{added: 1}}] = ChangeLog.groups(limit: 10)
  end

  test "a standing change is named by the standing it reached", ctx do
    tx("Adam", "import.apply_batch", 5, [
      {"facts", "update", %{id: ctx.host_fact.id, standing: "withdrawn"}}
    ])

    assert [%{facts: [%{change: :withdrawn}], counts: %{withdrawn: 1}}] =
             ChangeLog.groups(limit: 10)
  end

  test "new taxon names, with each taxon's rank and kingdom", ctx do
    tx("Adam", "import.decide_queue_item", 5, [
      {"queue_items", "update", %{id: 1, package_id: ctx.package.id}},
      {"taxon_names", "insert", %{taxon_id: ctx.oak.id, name: "Quercus alba"}}
    ])

    assert [%{names: [%{id: id, name: "Quercus alba", rank: "species", kingdom: "Plantae"}]}] =
             ChangeLog.groups(limit: 10)

    assert id == ctx.oak.id
  end

  test "since: only changes after it", ctx do
    q = {"queue_items", "update", %{id: 1, package_id: ctx.package.id}}
    tx("Adam", "import.decide_queue_item", 60 * 24 * 10, [q])
    tx("Jeff", "import.decide_queue_item", 5, [q])

    since = NaiveDateTime.add(NaiveDateTime.utc_now(), -7, :day)
    assert [%{who: "Jeff"}] = ChangeLog.groups(limit: 10, since: since)
  end

  test "a transaction that changed nothing is left out" do
    tx("Adam", "import.decide_queue_item", 5, [])
    assert ChangeLog.groups(limit: 10) == []
  end

  test "a direct edit of a Gall is worded, and names the Gall", ctx do
    tx("Adam", "catalog.update_gall_editorial", 5, [
      {"galls", "update", %{id: ctx.gall.id, name: "Andricus fixturi", abundance_id: 2}}
    ])

    assert [%{title: "Edited a Gall", galls: [%{id: id, name: "Andricus fixturi"}], source: nil}] =
             ChangeLog.groups(limit: 10)

    assert id == ctx.gall.id
  end

  test "an edit of the taxonomy names the taxa it touched", ctx do
    tx("Adam", "import.record_taxonomy_edit", 5, [
      {"taxa", "update", %{id: ctx.oak.id, rank: "species", kingdom: "Plantae", abundance_id: 1}}
    ])

    assert [
             %{
               title: "Edited the taxonomy",
               taxa: [%{id: id, name: "Quercus alba", rank: "species", kingdom: "Plantae"}]
             }
           ] =
             ChangeLog.groups(limit: 10)

    assert id == ctx.oak.id
  end

  test "deletes and merges are worded", ctx do
    tx("Adam", "import.record_deletion", 6, [{"galls", "delete", %{id: ctx.gall.id}}])
    tx("Jeff", "import.record_merge", 5, [{"galls", "update", %{id: ctx.gall.id}}])

    assert [%{title: "Merged two records"}, %{title: "Deleted a record"}] =
             ChangeLog.groups(limit: 10)
  end

  test "an operation without its own wording still reads as a change" do
    tx("Adam", "facts.attribute", 5, [{"attributions", "insert", %{id: 1}}])
    assert [%{title: "Made a change"}] = ChangeLog.groups(limit: 10)
  end

  describe "fact_words/1: a Fact in the change log's words" do
    test "each kind of Fact" do
      assert ChangeLog.fact_words({:trait, "plant_part", "leaf midrib"}) ==
               "plant part: leaf midrib"

      assert ChangeLog.fact_words({:relationship, "host_of", "Quercus alba"}) ==
               "host: Quercus alba"

      assert ChangeLog.fact_words({:relationship, "inducer_of", "Andricus foo"}) ==
               "inducer: Andricus foo"

      assert ChangeLog.fact_words({:relationship, "alternate_generation_of", "Andricus bar"}) ==
               "alternate generation of Andricus bar"

      assert ChangeLog.fact_words({:range, "exclude", "Europe"}) == "range exclude: Europe"
      assert ChangeLog.fact_words({:occurrence, "Virginia"}) == "recorded in Virginia"
      assert ChangeLog.fact_words(:description) == "a description"
      assert ChangeLog.fact_words({:alias, "oak apple"}) == "also known as oak apple"
      assert ChangeLog.fact_words({:common_name, "white oak"}) == ~s(common name "white oak")
    end

    test "a missing name reads as ?" do
      assert ChangeLog.fact_words({:relationship, "host_of", nil}) == "host: ?"
    end
  end
end
