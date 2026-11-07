defmodule Gallformers.Audit.ChangeBroadcastTest do
  @moduledoc """
  A curator's audited write, once it commits, tells the pages listing the
  curators' changes (`Gallformers.Audit.ChangeLog.subscribe/0`): once per
  outermost transaction, never on a rollback, and not for system work.

  Not async: the topic is global, so another test's write would reach these
  subscribers.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Ecto.Multi
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Audit.ChangeLog
  alias Gallformers.Import
  alias Gallformers.Taxa

  @changed {:change_log, :changed}

  setup do
    actor = Actor.user(1, "Tess Taxa")
    put_test_actor(actor)
    %{actor: actor}
  end

  defp subscribe! do
    :ok = ChangeLog.subscribe()
  end

  test "a taxonomy admin save reaches a subscriber", %{actor: actor} do
    family = plant_fixture(rank: :family, name: "Broadcastaceae")
    genus = plant_fixture(rank: :genus, name: "Broadcastia", parent: family)
    plant = plant_fixture(name: "Broadcastia oldname", parent: genus)
    subscribe!()

    {:ok, _} = Import.record_taxonomy_edit(actor, {:rename, plant, "Broadcastia newname"})

    assert Taxa.accepted_name(plant.id) == "Broadcastia newname"
    assert_receive @changed
    refute_receive @changed, 50
  end

  test "a rolled-back transaction tells no one", %{actor: actor} do
    subscribe!()

    assert {:error, :nope} =
             Audit.transaction(actor, "test.rollback", fn -> Repo.rollback(:nope) end)

    refute_receive @changed, 50
  end

  test "nested transactions tell once, after the outermost commits", %{actor: actor} do
    subscribe!()

    {:ok, :ok} =
      Audit.transaction(actor, "test.outer", fn ->
        {:ok, :ok} = Audit.transaction(actor, "test.inner", fn -> :ok end)
        {:ok, _} = Audit.run_multi(Multi.put(Multi.new(), :x, 1), actor, "test.inner_multi")
        refute_received @changed
        :ok
      end)

    assert_receive @changed
    refute_receive @changed, 50
  end

  test "an audited write inside a transaction that rolls back tells no one", %{actor: actor} do
    subscribe!()

    {:error, :dry_run} =
      Repo.transaction(fn ->
        {:ok, :ok} = Audit.transaction(actor, "test.inner", fn -> :ok end)
        Repo.rollback(:dry_run)
      end)

    refute_receive @changed, 50
  end

  test "a multi tells once when it commits, and not when it fails", %{actor: actor} do
    subscribe!()

    {:ok, _} = Audit.run_multi(Multi.put(Multi.new(), :x, 1), actor, "test.multi")
    assert_receive @changed
    refute_receive @changed, 50

    {:error, :x, :nope, _} =
      Multi.new() |> Multi.error(:x, :nope) |> Audit.run_multi(actor, "test.multi")

    refute_receive @changed, 50
  end

  test "system work tells no one: the change log lists curators' changes" do
    system = Actor.system("test")
    # The test's sandbox transaction keeps one actor (`test_actor/0`).
    put_test_actor(system)
    subscribe!()

    {:ok, :ok} = Audit.transaction(system, "test.system", fn -> :ok end)

    refute_receive @changed, 50
  end

  test "flush/0 drops the notices already waiting" do
    subscribe!()
    ChangeLog.changed()
    ChangeLog.changed()

    assert_receive @changed
    :ok = ChangeLog.flush()
    refute_received @changed
  end
end
