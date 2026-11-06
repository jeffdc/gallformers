defmodule Gallformers.Catalog.HomeReadsTest do
  @moduledoc """
  The home page's reads (matter bc0d): the Host genera with the most Galls,
  and the Gallformer families gathered into plain-language groups.
  """
  use Gallformers.DataCase, async: true

  # These read the converted seeds' gall index.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Catalog

  describe "Catalog.top_host_genera/1" do
    test "the Host genera by how many distinct Galls they carry, most first" do
      genera = Catalog.top_host_genera(3)

      assert length(genera) <= 3
      assert hd(genera).name == "Notholithocarpus"
      assert hd(genera).count == 5
      assert genera == Enum.sort_by(genera, &{-&1.count, &1.name})
      assert Enum.reject(genera, &Map.has_key?(&1, :image_url)) == []
    end
  end

  describe "Catalog.host_gall_counts/0" do
    test "distinct Galls on each plant taxon with a page, by taxon ID" do
      counts = Catalog.host_gall_counts()
      genus_id = taxon_id("Notholithocarpus")

      assert %{count: 5, image_url: _} = counts[genus_id]
      assert Enum.reject(Map.values(counts), &(&1.count > 0)) == []
    end
  end

  describe "Catalog.gall_photo_urls/0" do
    test "a small photo URL for each Gall with an image, and none for the rest" do
      urls = Catalog.gall_photo_urls()

      %{rows: with_image} =
        Repo.query!("select gall_id from gall_index where image_id is not null")

      assert Enum.sort(Map.keys(urls)) == with_image |> List.flatten() |> Enum.sort()
      assert Enum.reject(Map.values(urls), &(&1 =~ "small")) == []
    end
  end

  describe "Catalog.place_gall_counts/0" do
    test "distinct Galls known to occur in each place or any place under it, by code" do
      %{counts: counts, everywhere: everywhere} = Catalog.place_gall_counts()

      north_america =
        scalar("""
        select count(*) from gall_index g
        where g.known_place_ids && (
          select array_agg(id) from place where code in ('XN', 'US', 'CA', 'MX', 'US-CA', 'CA-AB', 'MX-JAL'))
        """)

      assert counts["XN"] == north_america
      assert counts["XN"] >= counts["US"]
      assert counts["US"] >= counts["US-CA"]
      assert counts["XB"] == counts["BS"]
      assert everywhere == scalar("select count(*) from gall_index where everywhere")
    end
  end

  describe "Catalog.place_gall_counts/0, a continent reached two ways" do
    test "counts a Gall in a leaf country and a Gall in a country's state together" do
      # The Caribbean (XB) holds the Bahamas (BS, a leaf country): Gall 101
      # is known there. Add a country with a state, and Gall 102 there.
      %{rows: [[xb]]} = Repo.query!("select id from place where code = 'XB'")

      %{rows: [[country]]} =
        Repo.query!(
          "insert into place (name, code, type) values ('Fixtureland', 'ZQ', 'country') returning id"
        )

      %{rows: [[state]]} =
        Repo.query!(
          "insert into place (name, code, type) values ('Fixture State', 'ZQ-A', 'state') returning id"
        )

      Repo.query!("insert into place_hierarchy (place_id, parent_id) values ($1, $2), ($3, $4)", [
        country,
        xb,
        state,
        country
      ])

      Repo.query!(
        "update gall_index set known_place_ids = array[$1::bigint] where gall_id = 102",
        [state]
      )

      Repo.query!(
        "update gall_index set known_place_ids = array[(select id from place where code = 'BS')] where gall_id = 101"
      )

      %{counts: counts} = Catalog.place_gall_counts()

      assert counts["ZQ-A"] == 1
      assert counts["ZQ"] == 1
      assert counts["BS"] == 1
      assert counts["XB"] == 2
    end
  end

  defp scalar(sql) do
    %{rows: [[value]]} = Repo.query!(sql)
    value
  end

  describe "Catalog.gall_search_details/1" do
    test "each Gall's photo, its Hosts' names and its plant part and season" do
      %{300 => seedii, 301 => sexgen} = Catalog.gall_search_details([300, 301])

      assert seedii.image_url =~ "small"
      assert "Notholithocarpus densiflorus" in seedii.hosts
      assert is_list(seedii.plant_part) and is_list(seedii.season)
      assert sexgen.image_url == nil
    end

    test "no IDs, no details" do
      assert Catalog.gall_search_details([]) == %{}
    end
  end

  defp taxon_id(name) do
    %{rows: [[id]]} =
      Repo.query!(
        "select taxon_id from taxon_names where name = $1 and status = 'accepted'",
        [name]
      )

    id
  end

  describe "Catalog.inducer_groups/0" do
    test "families gathered into named groups, with their counts, most Galls first" do
      groups = Catalog.inducer_groups()
      wasps = Enum.find(groups, &(&1.name == "Gall wasps"))

      assert wasps.slug == "gall-wasps"
      assert wasps.count == 8
      assert [%{name: "Cynipidae", count: 8}] = wasps.families
      assert groups == Enum.sort_by(groups, &(-&1.count))
      assert Enum.reject(groups, &(&1.count > 0)) == []
    end

    test "a family no group names falls in Other" do
      assert Catalog.InducerGroups.group_of("Fixturnovidae") == "Other"
      assert Catalog.InducerGroups.group_of("Cecidomyiidae") == "Gall midges"
    end
  end
end
