defmodule Gallformers.Facts.StandingTest do
  @moduledoc """
  The standing rules (`9449` §2, `8567` Sources–Facts design), as a pure
  function of a Fact's attributions and, in a slot, its competitors'.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Facts.Standing
  alias Gallformers.Facts.Standing.Conflict
  alias Gallformers.Sources.PartialDate

  # An attribution as Standing sees it. `on` is a partial date ("1897",
  # "1897-05", "1897-05-14") or nil for an undated statement.
  defp stmt(id, stance, on, opts \\ []) do
    {date, precision} =
      case on do
        nil ->
          {nil, nil}

        partial ->
          {:ok, parsed} = PartialDate.parse(partial)
          parsed
      end

    %{
      id: id,
      stance: stance,
      stated_on: date,
      stated_precision: precision,
      retracted: Keyword.get(opts, :retracted, false)
    }
  end

  defp fact(id, attributions, previous \\ :unsupported),
    do: %{id: id, previous: previous, attributions: attributions}

  defp standing_of(fact) do
    {%{} = standings, conflicts} = Standing.resolve(fact)
    {Map.fetch!(standings, fact.id), conflicts}
  end

  describe "resolve/1 for one Fact" do
    test "the newest confirmation makes it current" do
      f = fact(1, [stmt(:a, :deny, "1890"), stmt(:b, :confirm, "1923")])
      assert standing_of(f) == {:current, []}
    end

    test "the newest denial withdraws it" do
      f = fact(1, [stmt(:a, :confirm, "1890"), stmt(:b, :deny, "1923-05-01")])
      assert standing_of(f) == {:withdrawn, []}
    end

    test "the order attributions arrive in does not matter" do
      a = stmt(:a, :confirm, "1890")
      b = stmt(:b, :deny, "1923")

      assert standing_of(fact(1, [a, b])) == standing_of(fact(1, [b, a]))
    end

    test "support only from retracted Sources is retracted" do
      f = fact(1, [stmt(:a, :confirm, "1990", retracted: true)])
      assert standing_of(f) == {:retracted, []}
    end

    test "a retracted Source's stance is ignored when others remain" do
      f =
        fact(1, [
          stmt(:a, :confirm, "1950"),
          stmt(:b, :deny, "2001", retracted: true)
        ])

      assert standing_of(f) == {:current, []}
    end

    test "no attributions at all is unsupported" do
      assert standing_of(fact(1, [], :current)) == {:unsupported, []}
    end

    test "a year and a month in that year tie; opposite stances are a conflict and keep the previous standing" do
      a = stmt(:a, :confirm, "1897")
      b = stmt(:b, :deny, "1897-05")

      assert {:current, [conflict]} = standing_of(fact(1, [a, b], :current))
      assert %Conflict{type: :same_date, fact_ids: [1]} = conflict
      assert Enum.sort(Enum.map(conflict.attributions, & &1.id)) == [:a, :b]

      assert {:withdrawn, [_]} = standing_of(fact(1, [a, b], :withdrawn))
    end

    test "a conflict with no previous standing leaves the Fact unsupported" do
      f = fact(1, [stmt(:a, :confirm, "1897"), stmt(:b, :deny, "1897-05")], nil)
      assert {:unsupported, [%Conflict{type: :same_date}]} = standing_of(f)
    end

    test "a tie with the same stance is no conflict" do
      f = fact(1, [stmt(:a, :confirm, "1897"), stmt(:b, :confirm, "1897-05-14")])
      assert standing_of(f) == {:current, []}
    end

    test "different months in one year do not tie" do
      f = fact(1, [stmt(:a, :confirm, "1897-03"), stmt(:b, :deny, "1897-08")])
      assert standing_of(f) == {:withdrawn, []}
    end

    test "a later month outranks an earlier one even when a year-only date ties with both" do
      # 1897-03 is older than 1897-08; "1897" ties with both. The newest
      # statements are "1897" and "1897-08", which agree.
      f =
        fact(1, [
          stmt(:a, :deny, "1897-03"),
          stmt(:b, :confirm, "1897"),
          stmt(:c, :confirm, "1897-08")
        ])

      assert standing_of(f) == {:current, []}
    end

    test "an undated statement loses to any dated one" do
      f = fact(1, [stmt(:legacy, :confirm, nil), stmt(:a, :deny, "1801")])
      assert standing_of(f) == {:withdrawn, []}

      f = fact(1, [stmt(:legacy, :deny, nil), stmt(:a, :confirm, "1801")])
      assert standing_of(f) == {:current, []}
    end

    test "undated statements alone decide when nothing is dated" do
      assert standing_of(fact(1, [stmt(:legacy, :confirm, nil)])) == {:current, []}
    end
  end

  describe "resolve_slot/1" do
    test "the current Fact with the newest confirmation wins; the others are superseded" do
      older = fact(1, [stmt(:a, :confirm, "1900")], :current)
      newer = fact(2, [stmt(:b, :confirm, "1950")])

      assert Standing.resolve_slot([older, newer]) == {%{1 => :superseded, 2 => :current}, []}
    end

    test "Facts that are not current keep their own standing" do
      current = fact(1, [stmt(:a, :confirm, "1900")])
      withdrawn = fact(2, [stmt(:b, :confirm, "1950"), stmt(:c, :deny, "1960")])
      unsupported = fact(3, [])

      assert Standing.resolve_slot([current, withdrawn, unsupported]) ==
               {%{1 => :current, 2 => :withdrawn, 3 => :unsupported}, []}
    end

    test "a newer confirmation of the old value takes the slot back" do
      a = fact(1, [stmt(:x, :confirm, "1900"), stmt(:gf, :confirm, "2026-10-24")], :superseded)
      b = fact(2, [stmt(:y, :confirm, "1950")], :current)

      assert Standing.resolve_slot([a, b]) == {%{1 => :current, 2 => :superseded}, []}
    end

    test "a tie between competing Facts is a conflict; each keeps its previous standing" do
      a = fact(1, [stmt(:x, :confirm, "1950")], :current)
      b = fact(2, [stmt(:y, :confirm, "1950-06")], :unsupported)
      old = fact(3, [stmt(:z, :confirm, "1900")], :superseded)

      assert {standings, [conflict]} = Standing.resolve_slot([a, b, old])
      assert standings == %{1 => :current, 2 => :unsupported, 3 => :superseded}
      assert %Conflict{type: :slot_tie} = conflict
      assert Enum.sort(conflict.fact_ids) == [1, 2]
      assert Enum.sort(Enum.map(conflict.attributions, & &1.id)) == [:x, :y]
    end

    test "a Fact's same-date conflict is reported alongside the slot's outcome" do
      contested = fact(1, [stmt(:a, :confirm, "1950"), stmt(:b, :deny, "1950")], :current)
      other = fact(2, [stmt(:c, :confirm, "1900")], :superseded)

      assert {%{1 => :current, 2 => :superseded}, [%Conflict{type: :same_date, fact_ids: [1]}]} =
               Standing.resolve_slot([contested, other])
    end

    test "an undated confirmation loses the slot to any dated one" do
      legacy = fact(1, [stmt(:legacy, :confirm, nil)], :current)
      dated = fact(2, [stmt(:a, :confirm, "1801")])

      assert Standing.resolve_slot([legacy, dated]) == {%{1 => :superseded, 2 => :current}, []}
    end
  end
end
