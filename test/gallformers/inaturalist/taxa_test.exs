defmodule Gallformers.INaturalist.TaxaTest do
  @moduledoc """
  iNaturalist's taxa (matter `cb28` Task 2): searching by name
  (`/v1/taxa/autocomplete`, with the name that matched), or by an
  iNaturalist link or number; reading one taxon with its ancestors,
  children and names (`/v1/taxa/:id?all_names=true`). Against responses
  recorded from the real API (`Gallformers.INaturalistFixtures`).
  """
  use ExUnit.Case, async: true

  import Gallformers.INaturalistFixtures

  alias Gallformers.INaturalist.Taxa
  alias Gallformers.INaturalist.Taxon

  describe "search/1" do
    test "a name: each result with its rank, common name, observations and the name that matched" do
      stub_inat_taxa(self())

      assert {:ok, [arguti, hybrid]} = Taxa.search("Rubus pensilvanicus")

      assert arguti == %{
               id: 1_449_402,
               name: "Arguti",
               rank: "section",
               common: "Field Highbush Blackberries",
               matched: "Rubus pensilvanicus",
               observations: 22_268,
               active?: true
             }

      assert hybrid.name == "Rubus × floricomus"
      assert hybrid.common == nil

      assert_received {:inat_request, "/v1/taxa/autocomplete", %{"q" => "Rubus pensilvanicus"}}
    end

    test "nothing found is an empty list; a blank name asks nothing" do
      stub_inat_taxa(self())

      assert {:ok, []} = Taxa.search("Rubus villosus var. frondosus")
      assert {:ok, []} = Taxa.search("  ")
      assert_received {:inat_request, _, %{"q" => "Rubus villosus var. frondosus"}}
      refute_received {:inat_request, _, _}
    end

    test "an iNaturalist link or number reads that taxon" do
      stub_inat_taxa(self())

      assert {:ok, [%{id: 49_995, name: "Syrphidae", rank: "family", matched: nil}]} =
               Taxa.search("https://www.inaturalist.org/taxa/49995-Syrphidae")

      assert_received {:inat_request, "/v1/taxa/49995", _}

      assert {:ok, [%{id: 168_056, name: "Rubus frondosus"}]} = Taxa.search("168056")
      assert {:ok, []} = Taxa.search("999999999")
    end

    @tag :capture_log
    test "iNaturalist down is an error" do
      stub_inat_down()
      assert {:error, _} = Taxa.search("Syrphidae")
    end
  end

  describe "fetch/1" do
    test "a taxon with its ancestors, children and names" do
      stub_inat_taxa(self())

      assert {:ok, %Taxon{} = t} = Taxa.fetch(1_449_402)
      assert_received {:inat_request, "/v1/taxa/1449402", %{"all_names" => "true"}}

      assert t.id == 1_449_402
      assert t.name == "Arguti"
      assert t.rank == "section"
      assert t.active? == true
      assert t.replaced_by == []
      assert t.kingdom == "Plantae"
      assert t.common == "Field Highbush Blackberries"
      assert t.observations == 22_268
      assert t.url == "https://www.inaturalist.org/taxa/1449402"

      assert Enum.map(t.ancestors, &{&1.name, &1.rank}) == [
               {"Plantae", "kingdom"},
               {"Tracheophyta", "phylum"},
               {"Angiospermae", "subphylum"},
               {"Magnoliopsida", "class"},
               {"Rosales", "order"},
               {"Rosaceae", "family"},
               {"Rosoideae", "subfamily"},
               {"Rubeae", "tribe"},
               {"Rubus", "genus"},
               {"Rubus", "subgenus"}
             ]

      assert %{id: 47_148, name: "Rosaceae", rank: "family"} = Enum.at(t.ancestors, 5)
      assert length(t.children) == 26

      assert %{name: "Rubus frondosus", rank: "species", active?: true, id: 168_056} =
               Enum.find(t.children, &(&1.name == "Rubus frondosus"))

      assert %{name: "Rubus pensilvanicus", lexicon: "scientific-names"} in t.names
      assert %{name: "Pennsylvania Blackberry", lexicon: "english"} in t.names
    end

    test "an animal's kingdom; a rank we don't use is as iNaturalist gives it" do
      stub_inat_taxa()

      assert {:ok, %{kingdom: "Animalia", rank: "family"} = syrphidae} = Taxa.fetch(49_995)
      assert {"Aschiza", "zoosection"} in Enum.map(syrphidae.ancestors, &{&1.name, &1.rank})
      assert {:ok, %{rank: "complex", name: "Alleghenienses"}} = Taxa.fetch("1449411")
    end

    test "an inactive taxon says what replaced it" do
      stub_inat_taxa()

      assert {:ok, %{active?: false, replaced_by: [1_449_402], name: "Rubus pensilvanicus"}} =
               Taxa.fetch(78_894)
    end

    test "a taxon iNaturalist doesn't have" do
      stub_inat_taxa()
      assert {:error, :not_found} = Taxa.fetch(999_999_999)
    end
  end

  describe "parse_taxon_id/1" do
    test "reads a link or a number" do
      assert Taxa.parse_taxon_id("1449402") == {:ok, 1_449_402}

      assert Taxa.parse_taxon_id(" https://www.inaturalist.org/taxa/1449402-Arguti ") ==
               {:ok, 1_449_402}

      assert Taxa.parse_taxon_id("https://inaturalist.org/taxa/49995") == {:ok, 49_995}
      assert Taxa.parse_taxon_id("Syrphidae") == :error
      assert Taxa.parse_taxon_id("https://example.com/taxa/1") == :error
    end
  end

  test "the requests name the app, never a person" do
    test_pid = self()

    Req.Test.stub(Gallformers.INaturalist, fn conn ->
      send(test_pid, {:user_agent, Plug.Conn.get_req_header(conn, "user-agent")})
      Req.Test.json(conn, %{"results" => []})
    end)

    Taxa.search("Syrphidae")
    assert_received {:user_agent, [agent]}
    assert agent =~ ~r/^Gallformers/
    refute agent =~ "@"
  end
end
