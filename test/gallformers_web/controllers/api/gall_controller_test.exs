defmodule GallformersWeb.API.GallControllerTest do
  @moduledoc """
  API tests for gall endpoints, read from the new back-end (`803b` Task 13).
  Every response is checked against its OpenAPI operation's schema.

  Partly the converted seeds (`priv/repo/test_seeds.sql`): Gall 300 is
  Andricus seedii (agamic) on plant 10 (native in US-CA, introduced in
  RO-B), with an image, a default citation (Source 59) and a Gallformers
  note (Source 58).

  Not async: one test uses the Gallformers Source (see
  `Gallformers.CatalogFixtures`).
  """
  use GallformersWeb.ConnCase, async: false

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]
  import OpenApiSpex.TestAssertions

  alias Gallformers.Catalog
  alias Gallformers.Images.Image
  alias Gallformers.Sources

  @index "GallformersWeb.API.GallController.index"
  @show "GallformersWeb.API.GallController.show"
  @images "GallformersWeb.API.GallController.images"
  @sources "GallformersWeb.API.GallController.sources"

  defp valid!(conn, operation_id) do
    assert_operation_response(conn, operation_id)
    Jason.decode!(conn.resp_body)
  end

  describe "GET /api/v2/galls" do
    test "lists every Gall with the total", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls")

      assert conn.status == 200

      assert %{"data" => data, "total" => total, "limit" => nil, "offset" => 0} =
               valid!(conn, @index)

      assert total == Catalog.count_galls()
      assert length(data) == total

      assert %{
               "id" => 300,
               "gall_id" => 300,
               "name" => "Andricus seedii (agamic)",
               "datacomplete" => true,
               "abundance_id" => 1,
               "abundance" => "common",
               "detachable" => "detachable",
               "undescribed" => false,
               "aliases" => [
                 %{"name" => "seed oak apple", "type" => "common"},
                 %{"name" => "Callirhytis seedii", "type" => "scientific"}
               ]
             } = Enum.find(data, &(&1["id"] == 300))
    end

    test "pages with limit and offset; the total is every Gall", %{conn: conn} do
      first = conn |> get(~p"/api/v2/galls?limit=3") |> valid!(@index)
      second = conn |> get(~p"/api/v2/galls?limit=3&offset=3") |> valid!(@index)

      assert length(first["data"]) == 3
      assert {first["limit"], second["offset"]} == {3, 3}
      assert first["total"] == Catalog.count_galls()

      ids = &MapSet.new(&1["data"], fn gall -> gall["id"] end)
      assert MapSet.intersection(ids.(first), ids.(second)) == MapSet.new()
    end

    test "searches with q, paged, with the matching total", %{conn: conn} do
      for n <- 1..3, do: gall_fixture(name: "Zzyzxia testgall #{n}")
      gall_fixture(name: "Unrelated gall")

      response = conn |> get(~p"/api/v2/galls?q=zzyzxia&limit=2") |> valid!(@index)

      assert response["total"] == 3

      assert Enum.map(response["data"], & &1["name"]) == [
               "Zzyzxia testgall 1",
               "Zzyzxia testgall 2"
             ]

      all = conn |> get(~p"/api/v2/galls?q=zzyzxia") |> valid!(@index)
      assert {all["total"], length(all["data"])} == {3, 3}
    end

    test "returns JSON", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls?limit=1")

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end
  end

  describe "GET /api/v2/galls/:id" do
    test "a Gall with its aliases, Hosts, Traits and range codes", %{conn: conn} do
      gall = conn |> get(~p"/api/v2/galls/300") |> valid!(@show)

      assert %{
               "id" => 300,
               "gall_id" => 300,
               "name" => "Andricus seedii (agamic)",
               "undescribed" => false,
               "detachable" => "detachable",
               "hosts" => [%{"id" => 10, "name" => "Notholithocarpus densiflorus"}],
               "colors" => [],
               "shapes" => [],
               "textures" => [],
               "plant_parts" => [],
               "alignments" => [],
               "walls" => [],
               "cells" => [],
               "seasons" => [],
               "forms" => []
             } = gall

      assert Enum.sort(gall["places"]) == ["RO-B", "US-CA"]
      assert length(gall["aliases"]) == 2
    end

    test "Traits are filter fields with their value IDs and definitions", %{conn: conn} do
      load_vocab!()
      gall = gall_fixture()
      source = source_fixture("Weld", "1959")

      for {trait, value} <- [{"color", "red"}, {"plant_part", "bud"}, {"season", "Spring"}] do
        {:ok, _} =
          Catalog.assert_trait(
            test_actor(),
            %{gall_id: gall.id, trait: trait, value: value},
            confirm(source)
          )
      end

      red = Catalog.get_trait_value("color", "red")
      response = conn |> get(~p"/api/v2/galls/#{gall.id}") |> valid!(@show)

      assert response["colors"] == [
               %{"id" => red.id, "field" => "red", "description" => red.definition}
             ]

      assert [%{"field" => "bud"}] = response["plant_parts"]
      assert [%{"field" => "Spring"}] = response["seasons"]
    end

    test "a Gall whose range is everywhere (no Host range data) has no place codes",
         %{conn: conn} do
      gall = gall_fixture()

      assert %{"places" => [], "hosts" => [], "undescribed" => true} =
               conn |> get(~p"/api/v2/galls/#{gall.id}") |> valid!(@show)
    end

    test "404 for an ID that is no Gall, 400 for an invalid ID", %{conn: conn} do
      assert %{"error" => _} = conn |> get(~p"/api/v2/galls/999999999") |> valid!(@show)
      assert json_response(get(conn, ~p"/api/v2/galls/10"), 404)
      assert %{"error" => _} = json_response(get(conn, ~p"/api/v2/galls/invalid"), 400)
    end
  end

  describe "GET /api/v2/galls/:id/images" do
    test "a Gall's images", %{conn: conn} do
      assert [image] = conn |> get(~p"/api/v2/galls/300/images") |> valid!(@images)

      assert %{"id" => 1, "path" => "gall/300/300_seed_original.jpg", "url" => url} = image
      assert url == "#{Image.base_url()}/gall/300/300_seed_original.jpg"
    end

    test "none for a Gall without images; 400 for an invalid ID", %{conn: conn} do
      assert conn |> get(~p"/api/v2/galls/#{gall_fixture().id}/images") |> valid!(@images) ==
               []

      assert json_response(get(conn, ~p"/api/v2/galls/invalid/images"), 400)
    end
  end

  describe "GET /api/v2/galls/:id/sources" do
    test "the default citation, then the Gallformers note", %{conn: conn} do
      assert [citation, note] = conn |> get(~p"/api/v2/galls/300/sources") |> valid!(@sources)

      assert %{
               "id" => 59,
               "title" => "Cynipid galls of the seed slope",
               "pubyear" => "1957",
               "externallink" => "https://example.com/seed-slope#p12"
             } = citation

      assert citation["description"] =~ "seed citation"
      assert %{"id" => 58, "title" => "Gallformers ID Notes"} = note
      assert note["description"] =~ "seed note"
    end

    test "the newest note's text", %{conn: conn} do
      gallformers = gallformers_source()
      gall = gall_fixture()
      {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "Old.", ~D[2020-01-01])
      {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "New.", ~D[2024-01-01])

      assert [%{"id" => id, "description" => "New."}] =
               conn |> get(~p"/api/v2/galls/#{gall.id}/sources") |> valid!(@sources)

      assert id == gallformers.id
    end

    test "404 for an ID that is no Gall, 400 for an invalid ID", %{conn: conn} do
      assert %{"error" => _} =
               conn |> get(~p"/api/v2/galls/999999999/sources") |> valid!(@sources)

      assert %{"error" => _} =
               conn |> get(~p"/api/v2/galls/invalid/sources") |> valid!(@sources)
    end
  end
end
