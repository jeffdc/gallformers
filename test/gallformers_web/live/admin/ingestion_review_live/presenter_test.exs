defmodule GallformersWeb.Admin.IngestionReviewLive.PresenterTest do
  use Gallformers.DataCase, async: true

  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  import Gallformers.IngestionPipelineFixtures

  alias Gallformers.Accounts

  describe "source_ingestion_review_view!/1 species collation" do
    test "collapses duplicate species names into one entry with sibling_ids" do
      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: "auth0|presenter-test-#{System.unique_integer([:positive])}",
          display_name: "Presenter Reviewer"
        })

      ingestion =
        review_ready_ingestion_fixture(%{uploaded_by_id: user.id})

      _entry_a =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus csokai",
          extracted_authority: nil
        })

      _entry_b =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Andricus csokai",
          extracted_authority: "Melika & Tavakoli, 2008"
        })

      _entry_c =
        source_ingestion_species_fixture(ingestion, 2, %{
          extracted_name: "Andricus paradoxus"
        })

      review_view = Presenter.source_ingestion_review_view!(ingestion.id)
      entries = review_view.species_entries

      assert length(entries) == 2

      collated = Enum.find(entries, &(&1.extracted_name == "Andricus csokai"))
      assert collated.extracted_authority == "Melika & Tavakoli, 2008"
      assert length(collated.sibling_ids) == 1

      solo = Enum.find(entries, &(&1.extracted_name == "Andricus paradoxus"))
      assert solo.sibling_ids == []
    end
  end

  describe "load_existing_gall_data/1" do
    test "returns hosts, aliases, traits for a gall with associations" do
      # Species 100 (Andricus quercuscalifornicus) has:
      #   hosts: species 6 (Thymus alpinus), species 8 (Mentha arvensis)
      #   aliases: alias 3 (Oak Apple Gall Wasp)
      #   gall_traits: detachable=integral
      result = Presenter.load_existing_gall_data(100)

      assert is_map(result)
      assert length(result.hosts) == 2
      assert Enum.any?(result.hosts, &(&1.host_name == "Thymus alpinus")) == true
      assert Enum.any?(result.hosts, &(&1.host_name == "Mentha arvensis")) == true

      assert length(result.aliases) == 1
      assert hd(result.aliases).name == "Oak Apple Gall Wasp"

      assert is_map(result.traits)
    end

    test "returns empty collections for a gall with no associations" do
      # Species 102 (Callirhytis quercuspunctata) has no hosts, no aliases
      result = Presenter.load_existing_gall_data(102)

      assert is_map(result)
      assert result.hosts == []
      assert result.aliases == []
      assert is_map(result.traits)
    end

    test "returns nil for nil species_id" do
      assert Presenter.load_existing_gall_data(nil) == nil
    end

    test "includes description from species-source mapping when available" do
      # Create a source and species_source for species 100
      {:ok, source} =
        Gallformers.Sources.create_source(%{
          title: "Test Source",
          author: "Author",
          pubyear: "2026",
          link: "https://example.com",
          citation: "Test citation",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/"
        })

      {:ok, _species_source} =
        Gallformers.Sources.create_species_source(%{
          species_id: 100,
          source_id: source.id,
          description: "A round gall on oak leaves."
        })

      result = Presenter.load_existing_gall_data(100)
      assert result.description == "A round gall on oak leaves."
    end
  end

  describe "load_suggested_match/1" do
    test "finds exact name match in gall catalog" do
      # Species 100: Andricus quercuscalifornicus (gall)
      result = Presenter.load_suggested_match("Andricus quercuscalifornicus")

      assert result != nil
      assert result.id == 100
      assert result.name == "Andricus quercuscalifornicus"
      assert result.host_count == 2
      assert result.alias_count == 1
    end

    test "returns nil when no match exists" do
      assert Presenter.load_suggested_match("Nonexistent gallus impossibilis") == nil
    end

    test "returns nil for nil input" do
      assert Presenter.load_suggested_match(nil) == nil
    end

    test "returns nil for empty string" do
      assert Presenter.load_suggested_match("") == nil
    end
  end
end
