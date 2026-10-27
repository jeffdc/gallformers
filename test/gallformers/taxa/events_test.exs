defmodule Gallformers.Taxa.EventsTest do
  @moduledoc """
  "Taxon changed" events (`8567` rule 6): Taxa calls the registered
  listeners inside its own transaction, and a listener's error fails the
  taxonomy change.

  Not async: listeners are registered in the application environment.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.Ancestry
  alias Gallformers.Taxa.Event
  alias Gallformers.Taxa.Events

  defmodule Recorder do
    @moduledoc false
    @behaviour Gallformers.Taxa.Events

    import Ecto.Query

    alias Gallformers.Repo

    # Reports each event to the test process, with what the listener sees of
    # the database, and answers as the test asks.
    @impl true
    def taxon_changed(%Event{} = event) do
      case Process.get(__MODULE__) do
        nil ->
          :ok

        {test_pid, reply} ->
          seen = %{
            in_transaction: Repo.in_transaction?(),
            parent_id: parent_id(event.taxon_id),
            names: names(event.taxon_id)
          }

          send(test_pid, {__MODULE__, event, seen})
          reply
      end
    end

    defp parent_id(id), do: Repo.one(from t in "taxa", where: t.id == ^id, select: t.parent_id)

    defp names(id) do
      Repo.all(
        from n in "taxon_names",
          where: n.taxon_id == ^id,
          select: {n.name, n.status},
          order_by: n.id
      )
    end
  end

  defmodule Second do
    @moduledoc false
    @behaviour Gallformers.Taxa.Events

    @impl true
    def taxon_changed(event) do
      if pid = Process.get(__MODULE__), do: send(pid, {__MODULE__, event})
      :ok
    end
  end

  defp register(listeners) do
    previous = Application.get_env(:gallformers, Gallformers.Taxa.Events)
    Application.put_env(:gallformers, Gallformers.Taxa.Events, listeners: listeners)
    on_exit(fn -> Application.put_env(:gallformers, Gallformers.Taxa.Events, previous) end)
  end

  defp reply_with(reply), do: Process.put(Recorder, {self(), reply})

  defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

  defp audit_change_count, do: Repo.aggregate(test_audit_changes(), :count)

  setup do
    family = taxon_fixture(rank: :family, name: "Cynipidae")
    other_family = taxon_fixture(rank: :family, name: "Figitidae")
    genus = taxon_fixture(rank: :genus, name: "Andricus", parent: family)
    species = taxon_fixture(rank: :species, name: "Andricus foo", parent: genus)

    %{family: family, other_family: other_family, genus: genus, species: species}
  end

  describe "a move" do
    test "calls each listener within the transaction, after the change", ctx do
      register([Recorder, Second])
      reply_with(:ok)
      Process.put(Second, self())

      assert {:ok, _} = Taxa.place(test_actor(), ctx.genus, ctx.other_family)

      assert_received {Recorder, %Event{type: :move} = event, seen}
      assert event.taxon_id == ctx.genus.id
      assert event.from_parent_id == ctx.family.id
      assert event.to_parent_id == ctx.other_family.id
      assert seen.in_transaction == true
      assert seen.parent_id == ctx.other_family.id

      assert_received {Second, %Event{type: :move}}
    end

    test "a listener's error rolls the change back", ctx do
      register([Recorder, Second])
      reply_with({:error, :name_collision})
      Process.put(Second, self())
      before = audit_change_count()

      assert {:error, {:rejected, Recorder, :name_collision}} =
               Taxa.place(test_actor(), ctx.genus, ctx.other_family)

      assert parent_id(ctx.genus) == ctx.family.id
      assert ctx.family.id in Enum.map(Taxa.ancestors(ctx.species), & &1.id)
      assert Taxa.descendants(ctx.other_family) == []
      assert audit_change_count() == before

      # Listeners after the one that failed are not called.
      refute_received {Second, _}
    end

    test "a listener that raises rolls the change back", ctx do
      register([Recorder])
      reply_with(:not_a_valid_reply)

      assert_raise ArgumentError, fn -> Taxa.place(test_actor(), ctx.genus, ctx.other_family) end
      assert parent_id(ctx.genus) == ctx.family.id
    end

    test "a rejected placement calls no listener", ctx do
      register([Recorder])
      reply_with(:ok)

      assert {:error, _} = Taxa.place(test_actor(), ctx.genus, ctx.species)
      refute_received {Recorder, _, _}
    end

    test "placing a taxon where it already is calls no listener", ctx do
      register([Recorder])
      reply_with(:ok)

      assert {:ok, _} = Taxa.place(test_actor(), ctx.genus, ctx.family)
      refute_received {Recorder, _, _}
    end
  end

  describe "a rename" do
    test "calls listeners with the old and new names, after the change", ctx do
      register([Recorder])
      reply_with(:ok)

      assert {:ok, _} = Taxa.rename(test_actor(), ctx.species, "Andricus bar")

      assert_received {Recorder, %Event{type: :rename} = event, seen}
      assert event.taxon_id == ctx.species.id
      assert {event.old_name, event.new_name} == {"Andricus foo", "Andricus bar"}
      assert seen.in_transaction == true
      assert seen.names == [{"Andricus foo", "synonym"}, {"Andricus bar", "accepted"}]
    end

    test "a listener's error rolls it back", ctx do
      register([Recorder])
      reply_with({:error, :name_collision})

      assert {:error, {:rejected, Recorder, :name_collision}} =
               Taxa.rename(test_actor(), ctx.species, "Andricus bar")

      assert Taxa.accepted_name(ctx.species) == "Andricus foo"
      assert Taxa.resolve_name("Andricus bar") == :none
    end
  end

  test "no listeners registered is fine", ctx do
    register([])

    assert {:ok, _} = Taxa.place(test_actor(), ctx.genus, ctx.other_family)
    assert {:ok, _} = Taxa.rename(test_actor(), ctx.species, "Andricus bar")
    assert parent_id(ctx.genus) == ctx.other_family.id
  end

  test "dispatching outside a transaction is refused" do
    register([])

    assert_raise ArgumentError, fn ->
      Events.dispatch(%Event{type: :move, taxon_id: 1})
    end
  end

  test "the closure is untouched by a rolled-back move", ctx do
    register([Recorder])
    reply_with({:error, :no})
    rows = Repo.aggregate(Ancestry, :count)

    {:error, _} = Taxa.place(test_actor(), ctx.genus, ctx.other_family)
    assert Repo.aggregate(Ancestry, :count) == rows
  end
end
