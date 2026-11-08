defmodule Gallformers.Import.FactsViewStatementsTest do
  @moduledoc """
  Every Source's statement of a Fact, as the Fact inspector shows it
  (matter `87a1`, task 1): `Gallformers.Import.FactsView.statements/1`, and
  the `lines` it gives each of `Gallformers.Import.facts_for_gall/1`'s
  entries.

  Not async: the vocabularies are loaded (`Gallformers.CatalogFixtures`)
  and one test makes the one Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.FactsView
  alias Gallformers.Sources

  setup :audit_test_metadata

  setup do
    load_vocab!()
    %{gall: gall_fixture()}
  end

  defp trait!(gall, trait, value, attribution) do
    {:ok, %{fact: fact}} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: trait, value: value},
        attribution
      )

    fact
  end

  defp lines(fact), do: Map.fetch!(FactsView.statements([fact.id]), fact.id)

  describe "statements/1" do
    test "each Source's statement of a Fact, oldest first, undated first", %{gall: gall} do
      newer = source_fixture("Newer", "2001")
      older = source_fixture("Older", "1959")
      legacy = Sources.get_legacy_data_source()

      fact = trait!(gall, "color", "red", confirm(newer))
      trait!(gall, "color", "red", confirm(older))
      trait!(gall, "color", "red", confirm(legacy, %{stated: nil}))

      assert Enum.map(lines(fact), & &1.source_id) == [legacy.id, older.id, newer.id]
    end

    test "a statement's date at its precision, in the site's date style", %{gall: gall} do
      source = source_fixture("Dated", "1959")
      year = trait!(gall, "color", "red", confirm(source, %{stated: "1959"}))
      month = trait!(gall, "color", "brown", confirm(source, %{stated: "1959-06"}))
      day = trait!(gall, "color", "green", confirm(source, %{stated: "1959-06-14"}))
      undated = trait!(gall, "color", "yellow", confirm(source, %{stated: nil}))

      assert [%{date: "1959", stated_on: ~D[1959-01-01], precision: :year}] = lines(year)
      assert [%{date: "Jun 1959", precision: :month}] = lines(month)
      assert [%{date: "Jun 14, 1959", stated_on: ~D[1959-06-14], precision: :day}] = lines(day)
      assert [%{date: nil, stated_on: nil, precision: nil}] = lines(undated)
    end

    test "the Source's words as written, its statement and its quotes with their pages",
         %{gall: gall} do
      source = source_fixture("Quoted", "1959")

      fact =
        trait!(
          gall,
          "color",
          "red",
          confirm(source, %{
            value_as_written: "reddish",
            term: "reddish",
            statement_text: "The gall is reddish.",
            evidence: [
              %{quote: "Galls reddish when fresh", page: "41"},
              %{quote: "becoming brown"}
            ]
          })
        )

      assert [line] = lines(fact)
      assert line.words == ["reddish"]
      assert line.statement == "The gall is reddish."

      assert line.quotes == [
               %{quote: "Galls reddish when fresh", page: "41"},
               %{quote: "becoming brown", page: nil}
             ]
    end

    test "a statement with no words or quotes has none", %{gall: gall} do
      fact = trait!(gall, "color", "red", confirm(source_fixture("Plain", "1959")))

      assert [%{words: [], quotes: [], observations: []}] = lines(fact)
    end

    test "its Observations, each with its link, quality grade and thumbnail", %{gall: gall} do
      source = gallformers_source()

      fact =
        trait!(
          gall,
          "color",
          "red",
          confirm(source, %{
            statement_text: "Seen in iNaturalist observation 318135694.",
            observations: [
              %{
                provider: :inaturalist,
                external_id: "318135694",
                url: "https://www.inaturalist.org/observations/318135694",
                quality_grade: "needs_id",
                thumbnail_url: "https://example.org/318135694/square.jpg"
              }
            ]
          })
        )

      assert [line] = lines(fact)

      assert line.observations == [
               %{
                 provider: :inaturalist,
                 id: "318135694",
                 url: "https://www.inaturalist.org/observations/318135694",
                 quality_grade: "needs_id",
                 thumbnail_url: "https://example.org/318135694/square.jpg"
               }
             ]
    end

    test "Gallformers' own Sources are marked own, and the Gallformers Source as Gallformers'",
         %{gall: gall} do
      gallformers = gallformers_source()
      legacy = Sources.get_legacy_data_source()
      paper = source_fixture("Paper", "1959")

      fact = trait!(gall, "color", "red", confirm(legacy, %{stated: nil}))
      trait!(gall, "color", "red", confirm(paper))
      trait!(gall, "color", "red", confirm(gallformers, %{statement_text: "Seen."}))

      by_source = Map.new(lines(fact), &{&1.source_id, &1})

      assert %{own?: true, gallformers?: false} = by_source[legacy.id]
      assert %{own?: true, gallformers?: true} = by_source[gallformers.id]
      assert %{own?: false, gallformers?: false} = by_source[paper.id]
      assert by_source[paper.id].name =~ "Weld"
    end

    test "a denial reads as a denial", %{gall: gall} do
      source = source_fixture("Denies", "1959")
      fact = trait!(gall, "color", "red", deny(source))

      assert [%{stance: :deny, state: :counts}] = lines(fact)
    end

    test "a taxonomic statement awaiting a curator, accepted, and declined with its reason" do
      {:ok, fact} =
        Facts.create_fact(test_actor(), %{
          kind: "taxon_placement",
          slot: "taxon:#{System.unique_integer([:positive])}:placement"
        })

      waiting = source_fixture("Waiting", "1990")
      accepted = source_fixture("Accepted", "1991")
      declined = source_fixture("Declined", "1992")

      ids =
        for source <- [waiting, accepted, declined] do
          {:ok, %{attribution: a}} =
            Facts.attribute(test_actor(), %{
              fact_id: fact.id,
              source_id: source.id,
              stance: :confirm
            })

          a.id
        end

      [_, accepted_id, declined_id] = ids
      {:ok, _} = Facts.accept(test_actor(), accepted_id)
      {:ok, _} = Facts.decline(test_actor(), declined_id, "Not followed by later work.")

      assert [
               %{state: :awaiting, reason: nil},
               %{state: :counts},
               %{state: :declined, reason: "Not followed by later work."}
             ] = lines(fact)
    end

    test "no Facts, no statements" do
      assert FactsView.statements([]) == %{}
    end
  end

  describe "facts_for_gall/1 lines" do
    test "each entry carries its statement lines", %{gall: gall} do
      source = source_fixture("Lined", "1959")
      trait!(gall, "color", "red", confirm(source, %{value_as_written: "reddish"}))

      assert [%{facts: facts}] = Import.facts_for_gall(gall.id)
      assert [red] = facts.traits["color"]
      assert [%{source_id: id, words: ["reddish"]}] = red.lines
      assert id == source.id
    end

    test "words that only repeat the value are left out", %{gall: gall} do
      source = source_fixture("Repeats", "1959")
      trait!(gall, "color", "red", confirm(source, %{value_as_written: "Red", term: "red"}))

      assert [%{facts: facts}] = Import.facts_for_gall(gall.id)
      assert [%{lines: [%{words: []}]}] = facts.traits["color"]
    end
  end
end
