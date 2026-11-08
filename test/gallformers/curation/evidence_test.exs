defmodule Gallformers.Curation.EvidenceTest do
  @moduledoc """
  A change's evidence from what a curator writes as its "Why" (matter
  `87a1`, its question 2): one box for an observation's link, a paper or a
  reason; the iNaturalist and BugGuide links in it become the statement's
  Observations, the words stay its text. The one parser of observation
  links in a curator's words (the tray's evidence form uses it too).
  """
  use ExUnit.Case, async: true

  alias Gallformers.Curation

  describe "observation_links/1" do
    test "iNaturalist and BugGuide links, separated any way; anything else ignored" do
      text = """
      Seen at https://www.inaturalist.org/observations/318135694, and
      bugguide.net/node/view/12345 per Weld (1959). See also https://example.com/1
      """

      assert Curation.observation_links(text) == [
               %{provider: "inaturalist", id: "318135694"},
               %{provider: "bugguide", id: "12345"}
             ]
    end

    test "each once" do
      link = "https://www.inaturalist.org/observations/42"

      assert Curation.observation_links("#{link} #{link}") == [
               %{provider: "inaturalist", id: "42"}
             ]
    end

    test "none in plain words, or nothing" do
      assert Curation.observation_links("Galls on the leaf underside.") == []
      assert Curation.observation_links(nil) == []
    end
  end

  describe "evidence_from_why/1" do
    test "the words as its text, the links as its Observations" do
      why = "On this plant: https://www.inaturalist.org/observations/7"

      assert Curation.evidence_from_why(why) == %{
               text: why,
               observations: [%{provider: "inaturalist", id: "7"}],
               source_id: nil
             }
    end

    test "nothing written: no evidence" do
      assert Curation.evidence_from_why("  ") == nil
      assert Curation.evidence_from_why(nil) == nil
    end
  end
end
