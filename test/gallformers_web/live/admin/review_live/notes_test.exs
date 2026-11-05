defmodule GallformersWeb.Admin.ReviewLive.NotesTest do
  @moduledoc """
  The Gallformers notes on their Source's review page (`6611` Task 7): which
  group a note falls in, what it adds (its chips) and what it set aside.
  Pure functions, no database.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Import.QueueItem
  alias GallformersWeb.Admin.ReviewLive.Notes

  describe "group/1" do
    test "a note of an undescribed Gall is an undescribed Gall's, Observations or not" do
      assert Notes.group(%{undescribed: true, text: "A gall on oak.", observations: false}) ==
               :undescribed

      text = "Added from [this](https://www.inaturalist.org/observations/123)."
      assert Notes.group(%{undescribed: true, text: text, observations: true}) == :undescribed
    end

    test "a note linking to an iNaturalist Observation is Hosts and sightings" do
      text =
        "Quercus douglasii is added as a host based on " <>
          "[this observation](https://www.inaturalist.org/observations/123)."

      assert Notes.group(%{undescribed: false, text: text, observations: false}) ==
               :observations
    end

    test "a note linking to BugGuide is Hosts and sightings" do
      text = "Reared, see https://bugguide.net/node/view/12345."

      assert Notes.group(%{undescribed: false, text: text, observations: false}) ==
               :observations
    end

    test "Observations cited in the Facts' evidence count too" do
      assert Notes.group(%{undescribed: false, text: nil, observations: true}) == :observations
    end

    test "any other note is taxonomy, rulings and other notes" do
      text = "See the [iNat taxon](https://www.inaturalist.org/taxa/123) for the current name."
      assert Notes.group(%{undescribed: false, text: text, observations: false}) == :other
      assert Notes.group(%{undescribed: false, text: nil, observations: false}) == :other
    end

    test "every group has a title and an explanation, in the design's order" do
      assert [:undescribed, :observations, :other] = Enum.map(Notes.groups(), & &1.id)

      for group <- Notes.groups(),
          do: assert(%{title: <<_, _::binary>>, explanation: <<_, _::binary>>} = group)
    end
  end

  describe "observations?/1" do
    test "whether any Fact's evidence cites an Observation" do
      cited = %{
        "facts" => [
          %{"evidence" => [%{"quote" => "q", "observations" => [%{"provider" => "inaturalist"}]}]}
        ]
      }

      assert Notes.observations?(cited) == true
      assert Notes.observations?(%{"facts" => [%{"evidence" => [%{"quote" => "q"}]}]}) == false
      assert Notes.observations?(%{}) == false
    end
  end

  # A note's gall batch, its Facts given.
  defp content(facts) do
    %{
      "taxa" => [
        %{"ref" => "t1", "name_as_written" => "Andricus quercuscalifornicus"},
        %{"ref" => "t2", "name_as_written" => "Quercus douglasii"},
        %{"ref" => "t3", "name_as_written" => "Quercus lobata"},
        %{"ref" => "t4", "name_as_written" => "Quercus garryana"}
      ],
      "galls" => [%{"ref" => "g1", "name_as_written" => "the gall"}],
      "facts" => facts
    }
  end

  defp host(id, taxon),
    do: %{"id" => id, "kind" => "relationship", "type" => "host_of", "subject" => taxon}

  defp trait(id, trait, value),
    do: %{"id" => id, "kind" => "trait", "gall" => "g1", "trait" => trait, "value" => value}

  defp seen(id, code, as_written),
    do: %{
      "id" => id,
      "kind" => "occurrence",
      "gall" => "g1",
      "place" => %{"value" => code, "as_written" => as_written}
    }

  describe "adds/2" do
    test "what a note adds, by kind, in the design's order" do
      facts = [
        trait("f1", "color", %{"value" => "red"}),
        %{"id" => "f2", "kind" => "description", "gall" => "g1"},
        host("f3", "t2"),
        %{"id" => "f4", "kind" => "relationship", "type" => "inducer_of", "subject" => "t1"},
        trait("f5", "shape", %{"value" => "globular"}),
        trait("f6", "plant_part", %{"value" => "stem"}),
        trait("f7", "plant_part", %{"value" => "bud"}),
        seen("f8", "US-CA", "Contra Costa County, California"),
        seen("f9", "US-OR", "Oregon")
      ]

      places = %{"US-CA" => "California"}

      assert Notes.adds(content(facts), places) == [
               "description",
               "Host Quercus douglasii",
               "Inducer",
               "color",
               "shape",
               "2 plant parts",
               "seen in California",
               "seen in Oregon"
             ]
    end

    test "Hosts are named when there are two at most, else counted" do
      assert Notes.adds(content([host("f1", "t2"), host("f2", "t3")]), %{}) == [
               "Host Quercus douglasii",
               "Host Quercus lobata"
             ]

      assert Notes.adds(content([host("f1", "t2"), host("f2", "t3"), host("f3", "t4")]), %{}) ==
               ["3 Hosts"]
    end

    test "many places are counted; the same place is one" do
      facts =
        for {code, i} <- Enum.with_index(~w(US-CA US-OR US-WA US-ID)),
            do: seen("f#{i}", code, code)

      assert Notes.adds(content(facts), %{}) == ["seen in 4 places"]

      assert Notes.adds(content([seen("f1", "US-CA", "CA"), seen("f2", "US-CA", "CA")]), %{
               "US-CA" => "California"
             }) ==
               ["seen in California"]
    end

    test "other Facts are named by what they are; a denial is not an addition" do
      facts = [
        %{"id" => "f1", "kind" => "relationship", "type" => "parasitoid_in", "subject" => "t1"},
        %{"id" => "f2", "kind" => "alias", "gall" => "g1", "name" => "oak apple"},
        %{"id" => "f3", "kind" => "range", "gall" => "g1", "adjustment" => "exclude"},
        %{"id" => "f4", "kind" => "qualifier", "of" => "f1"},
        Map.put(host("f5", "t2"), "stance", "deny")
      ]

      assert Notes.adds(content(facts), %{}) == ["parasitoid in", "common name", "range"]
    end

    test "a batch with no Facts adds nothing" do
      assert Notes.adds(%{}, %{}) == []
      assert Notes.adds(nil, %{}) == []
    end
  end

  describe "set_aside/1" do
    defp item(kind, status, decision \\ nil),
      do: %QueueItem{kind: kind, status: status, decision: decision}

    test "counts what was set aside, terms and statements apart" do
      items = [
        item(:set_aside_term, :open),
        item(:set_aside_term, :decided, %{"keep" => true}),
        item(:set_aside_statement, :open),
        item(:dispute, :open)
      ]

      assert Notes.set_aside(items) == ["2 terms set aside", "1 statement set aside"]
    end

    test "a term mapped or a statement stated is no longer set aside" do
      items = [
        item(:set_aside_term, :decided, %{"trait_value" => "globular"}),
        item(:set_aside_statement, :decided, %{"state" => %{"kind" => "host"}})
      ]

      assert Notes.set_aside(items) == []
    end
  end
end
