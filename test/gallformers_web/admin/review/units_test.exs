defmodule GallformersWeb.Admin.Review.UnitsTest do
  @moduledoc """
  A Source's review as units of work, one at a time (matter `6611`, Task 3):
  the one tally every count on the page comes from, the stages, the units
  in order, and what comes next.
  """
  use ExUnit.Case, async: true

  alias GallformersWeb.Admin.Review.Units

  # An entry as `GallformersWeb.Admin.ReviewLive.Loader.entries/3` shapes it,
  # with only what the units read.
  defp entry(id, section, opts \\ []) do
    status = Keyword.get(opts, :status, :open)

    %{
      item: %{id: id, status: status},
      question: %{
        section: %{id: section, title: "Section #{section}"},
        proposal: Keyword.get(opts, :proposal)
      },
      holds: status == :open and Keyword.get(opts, :holds, false),
      rejected: Keyword.get(opts, :rejected, false)
    }
  end

  @firm %{label: "Use Quercus lobata", firm: true, pending: false, decision: %{"taxon_id" => 1}}
  @weak %{label: "Antistrophus s-gracile-flower-gall", firm: false, pending: false, decision: %{}}

  defp keys(units), do: Enum.map(units, &Units.key/1)

  describe "tally/1" do
    test "answered and to go, the ones needed before approving, hedged statements apart" do
      entries = [
        entry(1, :hosts, holds: true),
        entry(2, :hosts, status: :decided),
        entry(3, :trait_terms),
        entry(4, :hedge_names),
        entry(5, :hedge_host),
        entry(6, :hedge_host, status: :decided)
      ]

      assert Units.tally(entries) == %{done: 1, left: 2, total: 3, holding: 1, hedged: 2}
    end
  end

  describe "units/2" do
    test "the steps' questions in order, the hedged statements left out, the Facts last" do
      entries = [
        entry(1, :trait_terms),
        entry(2, :hedge_host),
        entry(3, :named_galls),
        entry(4, :hosts),
        entry(5, :which_taxon),
        entry(6, :hosts, status: :decided)
      ]

      assert keys(Units.units(entries)) == ["q-4", "q-5", "q-3", "q-1", "facts"]
    end

    test "a question about the Source itself comes before every step's" do
      entries = [entry(1, :hosts), entry(2, :source), entry(3, :trait_terms)]

      assert keys(Units.units(entries)) == ["q-2", "q-1", "q-3", "facts"]
    end

    test "a section's firm suggestions are one batch, ahead of its other questions" do
      entries = [
        entry(1, :trait_terms),
        entry(2, :trait_terms, proposal: @firm),
        entry(3, :trait_terms, proposal: @weak),
        entry(4, :trait_terms, proposal: @firm)
      ]

      assert [{:batch, %{id: :trait_terms}, batch} | rest] = Units.units(entries)
      assert Enum.map(batch, & &1.item.id) == [2, 4]
      assert keys(rest) == ["q-1", "q-3", "facts"]
    end

    test "one firm suggestion alone is a question of its own, and a rejected one isn't batched" do
      entries = [
        entry(1, :hosts, proposal: @firm),
        entry(2, :hosts, proposal: @firm, rejected: true)
      ]

      assert keys(Units.units(entries)) == ["q-1", "q-2", "facts"]
    end

    test "creating a new Gall or a per-Gall answer is never batched, even when firm" do
      new = %{@firm | decision: %{"new" => true}}
      per_gall = %{@firm | decision: %{"categories" => %{"g1" => "red"}}}

      entries = [
        entry(1, :undescribed_galls, proposal: new),
        entry(2, :undescribed_galls, proposal: new),
        entry(3, :trait_terms, proposal: per_gall),
        entry(4, :trait_terms, proposal: per_gall)
      ]

      assert keys(Units.units(entries)) == ["q-1", "q-2", "q-3", "q-4", "facts"]
    end

    test "an unticked suggestion stays in its batch and comes next on its own" do
      entries = [
        entry(1, :trait_terms, proposal: @firm),
        entry(2, :trait_terms, proposal: @firm),
        entry(3, :trait_terms, proposal: @firm)
      ]

      assert [{:batch, _, batch}, second | _] = Units.units(entries, unticked: MapSet.new([2]))
      assert Enum.map(batch, & &1.item.id) == [1, 2, 3]
      assert Units.key(second) == "q-2"
    end

    test "with every suggestion unticked there is no batch" do
      entries = [entry(1, :hosts, proposal: @firm), entry(2, :hosts, proposal: @firm)]

      assert keys(Units.units(entries, unticked: MapSet.new([1, 2]))) == ["q-1", "q-2", "facts"]
    end

    test "a chosen stage's work comes first, the rest keep their order" do
      entries = [entry(1, :hosts), entry(2, :named_galls), entry(3, :trait_terms)]

      assert keys(Units.units(entries, stage: :traits)) == ["q-3", "q-1", "q-2", "facts"]
    end

    test "skipped units go to the end, before the Facts, in the order skipped" do
      entries = [entry(1, :hosts), entry(2, :hosts), entry(3, :named_galls)]

      assert keys(Units.units(entries, skipped: ["q-2", "q-1"])) ==
               ["q-3", "q-2", "q-1", "facts"]
    end
  end

  describe "stages/2" do
    test "each step but the hedges, with what's left, the current one marked" do
      entries = [
        entry(1, :hosts),
        entry(2, :named_galls, status: :decided),
        entry(3, :trait_terms),
        entry(4, :trait_terms),
        entry(5, :hedge_host)
      ]

      current = Units.units(entries) |> List.first()

      assert Units.stages(entries, current) == [
               %{id: :names, title: "Names", state: :current, left: 1},
               %{id: :galls, title: "Galls", state: :done, left: 0},
               %{id: :disputes, title: "Disputes", state: :done, left: 0},
               %{id: :traits, title: "Traits", state: :todo, left: 2}
             ]
    end

    test "on the Facts step no stage is current" do
      assert Enum.map(Units.stages([], :facts), & &1.state) == [:done, :done, :done, :done]
    end
  end

  describe "label/1" do
    test "a unit in one line: its section and the Source's words, or what it holds" do
      one = entry(1, :hosts) |> put_in([:question, :written], "N. crepideneus")
      batch = {:batch, %{id: :trait_terms, title: "Trait terms"}, [entry(2, :x), entry(3, :x)]}

      assert Units.label({:one, %{title: "Host plants"}, one}) == "Host plants: N. crepideneus"
      assert Units.label(batch) == "Trait terms: 2 suggested answers to look over"
      assert Units.label(:facts) == "What approving will add"
    end
  end

  describe "next/2" do
    test "the three units after the current one" do
      entries = for id <- 1..6, do: entry(id, :hosts)

      assert keys(Units.next(Units.units(entries))) == ["q-2", "q-3", "q-4"]
    end
  end
end
