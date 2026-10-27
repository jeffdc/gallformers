defmodule GallformersWeb.API.TaxonomyControllerTest do
  @moduledoc """
  API tests for taxonomy endpoints, read from the new back-end (`803b` Task
  13). Higher-taxon IDs are the new taxa's IDs, so taxa are found by name.
  Every response is checked against its OpenAPI operation's schema.

  Partly the converted seeds (`priv/repo/test_seeds.sql`): Cynipidae >
  Cynipinae (subfamily) > Cynipini (tribe) > Andricus, Cynips, Neuroterus;
  Andricus seedii induces Galls 300 and 301, Andricus crystallinus Gall
  200, and the genus Andricus itself the undescribed Gall 304. Fagaceae >
  Notholithocarpus ("Tanoaks") > plant 10.
  """
  use GallformersWeb.ConnCase, async: true

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import OpenApiSpex.TestAssertions

  alias Gallformers.Taxa

  @controller "GallformersWeb.API.TaxonomyController"

  defp valid!(conn, action) do
    assert_operation_response(conn, "#{@controller}.#{action}")
    Jason.decode!(conn.resp_body)
  end

  defp named(name, rank), do: name |> Taxa.get_by_name(rank) |> hd()

  describe "GET /api/v2/genera" do
    test "lists every genus with the total", %{conn: conn} do
      response = conn |> get(~p"/api/v2/genera") |> valid!(:genera)
      notholithocarpus = named("Notholithocarpus", :genus)

      assert response["total"] == Taxa.paginate_taxa(:genus, []).total
      assert length(response["data"]) == response["total"]
      assert response["data"] |> Enum.map(& &1["type"]) |> Enum.uniq() == ["genus"]

      assert %{
               "id" => notholithocarpus.id,
               "name" => "Notholithocarpus",
               "type" => "genus",
               "description" => "Tanoaks",
               "parent_id" => named("Fagaceae", :family).id
             } in response["data"]
    end

    test "pages with limit and offset", %{conn: conn} do
      first = conn |> get(~p"/api/v2/genera?limit=2") |> valid!(:genera)
      second = conn |> get(~p"/api/v2/genera?limit=2&offset=2") |> valid!(:genera)

      assert length(first["data"]) == 2
      assert first["total"] == Taxa.paginate_taxa(:genus, []).total

      ids = &MapSet.new(&1["data"], fn genus -> genus["id"] end)
      assert MapSet.intersection(ids.(first), ids.(second)) == MapSet.new()
    end

    test "searches names", %{conn: conn} do
      assert %{"total" => 1, "data" => [%{"name" => "Andricus", "type" => "genus"}]} =
               conn |> get(~p"/api/v2/genera?q=Andr") |> valid!(:genera)
    end
  end

  describe "GET /api/v2/families" do
    test "every family with its children, intermediates typed and ranked", %{conn: conn} do
      families = conn |> get(~p"/api/v2/families") |> valid!(:families)
      cynipidae = Enum.find(families, &(&1["name"] == "Cynipidae"))

      assert %{"type" => "family", "description" => nil} = cynipidae
      refute Map.has_key?(cynipidae, "genera")

      assert [%{"name" => "Cynipinae", "type" => "intermediate", "rank" => "Subfamily"} = child] =
               cynipidae["children"]

      assert child["parent_id"] == cynipidae["id"]

      fagaceae = Enum.find(families, &(&1["name"] == "Fagaceae"))
      assert [%{"name" => "Notholithocarpus", "type" => "genus"} = genus] = fagaceae["children"]
      refute Map.has_key?(genus, "rank")
    end
  end

  describe "GET /api/v2/families/:id" do
    test "a family with its children", %{conn: conn} do
      cynipidae = named("Cynipidae", :family)
      response = conn |> get(~p"/api/v2/families/#{cynipidae.id}") |> valid!(:family)

      assert %{"id" => id, "name" => "Cynipidae", "type" => "family"} = response
      assert id == cynipidae.id
      assert [%{"name" => "Cynipinae", "rank" => "Subfamily"}] = response["children"]
    end

    test "404 for an ID that is no family, 400 for an invalid ID", %{conn: conn} do
      andricus = named("Andricus", :genus)

      assert %{"error" => _} = conn |> get(~p"/api/v2/families/999999999") |> valid!(:family)
      assert json_response(get(conn, ~p"/api/v2/families/#{andricus.id}"), 404)
      assert json_response(get(conn, ~p"/api/v2/families/invalid"), 400)
    end
  end

  describe "GET /api/v2/genera/:id" do
    test "a genus with its family and the Galls its species induce", %{conn: conn} do
      andricus = named("Andricus", :genus)
      response = conn |> get(~p"/api/v2/genera/#{andricus.id}") |> valid!(:genus)

      assert %{"name" => "Andricus", "type" => "genus", "family" => family} = response
      assert family == %{"id" => named("Cynipidae", :family).id, "name" => "Cynipidae"}

      assert Enum.map(response["species"], &{&1["id"], &1["taxoncode"]}) == [
               {200, "gall"},
               {304, "gall"},
               {300, "gall"},
               {301, "gall"}
             ]
    end

    test "a plant genus lists its plants", %{conn: conn} do
      genus = named("Notholithocarpus", :genus)
      response = conn |> get(~p"/api/v2/genera/#{genus.id}") |> valid!(:genus)

      assert response["description"] == "Tanoaks"
      assert response["family"]["name"] == "Fagaceae"

      assert response["species"] == [
               %{
                 "id" => 10,
                 "name" => "Notholithocarpus densiflorus",
                 "taxoncode" => "plant",
                 "genus_placeholder" => false
               }
             ]
    end

    test "404 for an ID that is no genus", %{conn: conn} do
      assert %{"error" => _} = conn |> get(~p"/api/v2/genera/10") |> valid!(:genus)
    end
  end

  describe "GET /api/v2/intermediates/:id" do
    test "an intermediate rank with its rank, parent and children", %{conn: conn} do
      cynipinae = named("Cynipinae", :subfamily)
      response = conn |> get(~p"/api/v2/intermediates/#{cynipinae.id}") |> valid!(:intermediate)

      assert %{"name" => "Cynipinae", "type" => "intermediate", "rank" => "Subfamily"} = response

      assert response["parent"] == %{
               "id" => named("Cynipidae", :family).id,
               "name" => "Cynipidae",
               "type" => "family"
             }

      assert [%{"name" => "Cynipini", "type" => "intermediate", "rank" => "Tribe"}] =
               response["children"]
    end

    test "a tribe's genus children", %{conn: conn} do
      cynipini = named("Cynipini", :tribe)
      response = conn |> get(~p"/api/v2/intermediates/#{cynipini.id}") |> valid!(:intermediate)

      assert response["parent"]["name"] == "Cynipinae"
      assert response["parent"]["type"] == "intermediate"

      assert Enum.map(response["children"], &{&1["name"], &1["type"]}) == [
               {"Andricus", "genus"},
               {"Cynips", "genus"},
               {"Neuroterus", "genus"}
             ]
    end

    test "404 for a genus or a missing ID", %{conn: conn} do
      andricus = named("Andricus", :genus)

      assert %{"error" => _} =
               conn |> get(~p"/api/v2/intermediates/#{andricus.id}") |> valid!(:intermediate)

      assert json_response(get(conn, ~p"/api/v2/intermediates/999999999"), 404)
    end
  end

  describe "sections" do
    setup do
      genus = named("Notholithocarpus", :genus)

      section =
        plant_fixture(name: "Notholithocarpus sect. Testia", rank: :section, parent_id: genus.id)

      plant = plant_fixture(name: "Notholithocarpus testii", parent_id: section.id)
      %{genus: genus, section: section, plant: plant}
    end

    test "GET /api/v2/sections lists sections with their genus", %{
      conn: conn,
      genus: genus,
      section: section
    } do
      sections = conn |> get(~p"/api/v2/sections") |> valid!(:sections)

      assert %{
               "id" => section.id,
               "name" => "Notholithocarpus sect. Testia",
               "type" => "section",
               "description" => nil,
               "genus_id" => genus.id,
               "genus_name" => "Notholithocarpus",
               "species_count" => 1
             } in sections
    end

    test "GET /api/v2/sections/:id has the section's plants", %{
      conn: conn,
      section: section,
      plant: plant
    } do
      response = conn |> get(~p"/api/v2/sections/#{section.id}") |> valid!(:section)

      assert %{"name" => "Notholithocarpus sect. Testia", "type" => "section"} = response
      assert [%{"id" => id, "taxoncode" => "plant"}] = response["species"]
      assert id == plant.id
    end

    test "GET /api/v2/sections/:id 404s for a genus", %{conn: conn, genus: genus} do
      assert %{"error" => _} = conn |> get(~p"/api/v2/sections/#{genus.id}") |> valid!(:section)
    end
  end
end
