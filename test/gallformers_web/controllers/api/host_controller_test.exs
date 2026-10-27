defmodule GallformersWeb.API.HostControllerTest do
  @moduledoc """
  API tests for host endpoints, read from the new back-end (`803b` Task 13):
  hosts are plant taxa at species rank or below, with their old IDs. Every
  response is checked against its OpenAPI operation's schema.

  Partly the converted seeds (`priv/repo/test_seeds.sql`): plant 10,
  Notholithocarpus densiflorus ("tanoak"), native in US-CA and introduced in
  RO-B, with an image, is the Host of Galls 300–304 (304 undescribed).
  """
  use GallformersWeb.ConnCase, async: true

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import OpenApiSpex.TestAssertions

  alias Gallformers.Taxa

  @index "GallformersWeb.API.HostController.index"
  @show "GallformersWeb.API.HostController.show"
  @images "GallformersWeb.API.HostController.images"
  @galls "GallformersWeb.API.HostController.galls"

  defp valid!(conn, operation_id) do
    assert_operation_response(conn, operation_id)
    Jason.decode!(conn.resp_body)
  end

  describe "GET /api/v2/hosts" do
    test "lists every plant with the total", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts")
      assert conn.status == 200

      assert %{"data" => data, "total" => total, "offset" => 0} = valid!(conn, @index)
      assert total == Taxa.count_plants()
      assert length(data) == total

      assert %{
               "id" => 10,
               "name" => "Notholithocarpus densiflorus",
               "taxoncode" => "plant",
               "datacomplete" => true
             } in data
    end

    test "simple=true adds each plant's place codes", %{conn: conn} do
      response = conn |> get(~p"/api/v2/hosts?simple=true&q=tanoak") |> valid!(@index)

      assert [%{"id" => 10, "taxoncode" => "plant", "places" => places}] = response["data"]
      assert Enum.sort(places) == ["RO-B", "US-CA"]
    end

    test "pages with limit and offset; the total is every plant", %{conn: conn} do
      first = conn |> get(~p"/api/v2/hosts?limit=3") |> valid!(@index)
      second = conn |> get(~p"/api/v2/hosts?limit=3&offset=3") |> valid!(@index)

      assert length(first["data"]) == 3
      assert first["total"] == Taxa.count_plants()

      ids = &MapSet.new(&1["data"], fn host -> host["id"] end)
      assert MapSet.intersection(ids.(first), ids.(second)) == MapSet.new()
    end

    test "searches with q over names, synonyms and common names", %{conn: conn} do
      for n <- 1..3, do: plant_fixture(name: "Zzyzxia planta#{n}")

      response = conn |> get(~p"/api/v2/hosts?q=zzyzxia&limit=2&offset=1") |> valid!(@index)

      assert response["total"] == 3
      assert Enum.map(response["data"], & &1["name"]) == ["Zzyzxia planta2", "Zzyzxia planta3"]

      assert %{"total" => 1, "data" => [%{"id" => 10}]} =
               conn |> get(~p"/api/v2/hosts?q=lithocarpus") |> valid!(@index)
    end
  end

  describe "GET /api/v2/hosts/:id" do
    test "a plant with its place codes and its Galls", %{conn: conn} do
      host = conn |> get(~p"/api/v2/hosts/10") |> valid!(@show)

      assert %{
               "id" => 10,
               "name" => "Notholithocarpus densiflorus",
               "taxoncode" => "plant",
               "datacomplete" => true
             } = host

      assert Enum.sort(host["places"]) == ["RO-B", "US-CA"]

      assert %{"id" => 300, "name" => "Andricus seedii (agamic)", "undescribed" => false} in host[
               "galls"
             ]

      assert %{"id" => 304, "undescribed" => true} =
               Enum.find(host["galls"], &(&1["id"] == 304))
    end

    test "simple=true leaves out the Galls", %{conn: conn} do
      host = conn |> get(~p"/api/v2/hosts/10?simple=true") |> valid!(@show)

      assert %{"id" => 10, "places" => [_, _]} = host
      refute Map.has_key?(host, "galls")
    end

    test "404 for an ID that is no plant, 400 for an invalid ID", %{conn: conn} do
      genus = plant_fixture(rank: :genus)

      assert %{"error" => _} = conn |> get(~p"/api/v2/hosts/999999999") |> valid!(@show)
      assert json_response(get(conn, ~p"/api/v2/hosts/#{genus.id}"), 404)
      assert json_response(get(conn, ~p"/api/v2/hosts/300"), 404)
      assert %{"error" => _} = json_response(get(conn, ~p"/api/v2/hosts/invalid"), 400)
    end
  end

  describe "GET /api/v2/hosts/:id/images" do
    test "a plant's images", %{conn: conn} do
      assert [%{"id" => 2, "path" => "gall/10/10_seed_original.jpg", "url" => _}] =
               conn |> get(~p"/api/v2/hosts/10/images") |> valid!(@images)
    end

    test "404 for an ID that is no plant, 400 for an invalid ID", %{conn: conn} do
      assert %{"error" => _} =
               conn |> get(~p"/api/v2/hosts/999999999/images") |> valid!(@images)

      assert %{"error" => _} = conn |> get(~p"/api/v2/hosts/invalid/images") |> valid!(@images)
    end
  end

  describe "GET /api/v2/hosts/:id/galls" do
    test "the Galls on a plant, by name, with undescribed and completeness", %{conn: conn} do
      galls = conn |> get(~p"/api/v2/hosts/10/galls") |> valid!(@galls)

      assert Enum.map(galls, & &1["id"]) == [304, 300, 301, 302, 303]

      assert %{
               "id" => 300,
               "name" => "Andricus seedii (agamic)",
               "undescribed" => false,
               "datacomplete" => true
             } in galls
    end

    test "404 for an ID that is no plant, 400 for an invalid ID", %{conn: conn} do
      assert %{"error" => _} = conn |> get(~p"/api/v2/hosts/999999999/galls") |> valid!(@galls)
      assert %{"error" => _} = conn |> get(~p"/api/v2/hosts/invalid/galls") |> valid!(@galls)
    end
  end
end
