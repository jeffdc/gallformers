defmodule Gallformers.Facts.EventsTest do
  @moduledoc """
  "Facts changed" events (`Gallformers.Facts.Events`): after standings are
  stored, the registered listeners hear which Facts changed standing — a
  Fact that became current, or stopped being current — inside the
  attribution's transaction. Read models depend only on current Facts, so
  a write that changes no standing is not an event.

  Not async: swaps the registered listeners (application environment).
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Facts
  alias Gallformers.Facts.Events
  alias Gallformers.Sources

  defmodule Recorder do
    @moduledoc false
    @behaviour Gallformers.Facts.Events

    @impl true
    def facts_changed(fact_ids) do
      send(self(), {:facts_changed, Enum.sort(fact_ids), Gallformers.Repo.in_transaction?()})
      :ok
    end
  end

  setup do
    configured = Application.get_env(:gallformers, Events)
    Application.put_env(:gallformers, Events, listeners: [Recorder])
    on_exit(fn -> Application.put_env(:gallformers, Events, configured) end)
    %{configured: configured}
  end

  defp source_fixture(title, authored) do
    {:ok, source} =
      Sources.create_source(%{
        title: "#{title} #{System.unique_integer([:positive])}",
        author: "Kinsey, A. C.",
        pubyear: String.slice(authored, 0, 4),
        link: "https://example.com/#{System.unique_integer([:positive])}",
        citation: "#{title}.",
        license: "Public Domain / Copyright Expired"
      })

    {:ok, source} =
      Sources.update_source_details(test_actor(), source, %{
        kind: "publication",
        authored: authored
      })

    source
  end

  defp fact_fixture(attrs \\ %{}) do
    {:ok, fact} = Facts.create_fact(test_actor(), Map.merge(%{kind: "trait"}, attrs))
    fact
  end

  defp attribute!(fact, source, stance) do
    {:ok, _} =
      Facts.attribute(test_actor(), %{fact_id: fact.id, source_id: source.id, stance: stance})

    :ok
  end

  test "the Catalog listens, registered through application config", %{configured: configured} do
    assert Gallformers.Catalog.FactListener in Keyword.fetch!(configured, :listeners)
    assert Events.listeners() == [Recorder]
  end

  test "a Fact made current is an event, inside the attribution's transaction" do
    fact = fact_fixture()
    attribute!(fact, source_fixture("Weld", "1959"), :confirm)

    assert_received {:facts_changed, [id], true}
    assert id == fact.id
  end

  test "restating an attribution changes no standing and is no event" do
    fact = fact_fixture()
    source = source_fixture("Weld", "1959")
    attribute!(fact, source, :confirm)
    assert_received {:facts_changed, _, _}

    attribute!(fact, source, :confirm)
    attribute!(fact, source_fixture("Kinsey", "1930"), :confirm)
    refute_received {:facts_changed, _, _}
  end

  test "a later denial withdrawing a current Fact is an event" do
    fact = fact_fixture()
    attribute!(fact, source_fixture("Weld", "1959"), :confirm)
    assert_received {:facts_changed, _, _}

    attribute!(fact, source_fixture("Revision", "1990"), :deny)
    assert_received {:facts_changed, [id], true}
    assert id == fact.id
  end

  test "a newer value in a slot changes both Facts' standings" do
    older = fact_fixture(%{slot: "gall:1:detachable"})
    newer = fact_fixture(%{slot: "gall:1:detachable"})
    attribute!(older, source_fixture("Weld", "1959"), :confirm)
    assert_received {:facts_changed, _, _}

    attribute!(newer, source_fixture("Revision", "1990"), :confirm)
    assert_received {:facts_changed, ids, true}
    assert ids == Enum.sort([older.id, newer.id])
  end

  test "removing the only attribution is an event" do
    fact = fact_fixture()
    source = source_fixture("Weld", "1959")
    attribute!(fact, source, :confirm)
    assert_received {:facts_changed, _, _}

    {:ok, _conflicts} = Facts.remove_attribution(test_actor(), fact.id, source.id)
    assert_received {:facts_changed, [id], true}
    assert id == fact.id
  end

  test "dispatching outside a transaction is refused" do
    assert_raise ArgumentError, fn -> Events.dispatch([1]) end
  end

  test "a listener returning anything but :ok rolls the change back" do
    defmodule Broken do
      @moduledoc false
      def facts_changed(_ids), do: :error
    end

    Application.put_env(:gallformers, Events, listeners: [Broken])
    fact = fact_fixture()
    source = source_fixture("Weld", "1959")

    assert_raise ArgumentError, fn ->
      Facts.attribute(test_actor(), %{fact_id: fact.id, source_id: source.id, stance: :confirm})
    end
  end
end
