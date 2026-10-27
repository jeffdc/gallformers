defmodule GallformersWeb.API.SourceControllerTest do
  @moduledoc """
  API tests for source endpoints (`803b` Task 13): a Source's Galls are read
  from the new back-end. Every response is checked against its OpenAPI
  operation's schema.

  Partly the converted seeds (`priv/repo/test_seeds.sql`): Source 59 is
  Gall 300's legacy citation; Source 58 (Gallformers ID Notes) has notes on
  Galls 300 and 301.
  """
  use GallformersWeb.ConnCase, async: true

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]
  import OpenApiSpex.TestAssertions

  alias Gallformers.Catalog
  alias Gallformers.Sources

  @index "GallformersWeb.API.SourceController.index"
  @show "GallformersWeb.API.SourceController.show"

  defp valid!(conn, operation_id) do
    assert_operation_response(conn, operation_id)
    Jason.decode!(conn.resp_body)
  end

  describe "GET /api/v2/sources" do
    test "lists every Source with the total", %{conn: conn} do
      response = conn |> get(~p"/api/v2/sources") |> valid!(@index)

      assert response["total"] == Sources.count_sources()
      assert length(response["data"]) == response["total"]

      assert %{"id" => 59, "title" => "Cynipid galls of the seed slope", "pubyear" => "1957"} =
               Enum.find(response["data"], &(&1["id"] == 59))
    end

    test "searches and pages with the matching total", %{conn: conn} do
      for n <- 1..3, do: source_fixture("Zzyzxian galls #{n}", "1990")

      response = conn |> get(~p"/api/v2/sources?q=zzyzxian&limit=2&offset=1") |> valid!(@index)

      assert response["total"] == 3
      assert length(response["data"]) == 2
    end
  end

  describe "GET /api/v2/sources/:id" do
    test "a Source with the Galls it cites, each with its citation", %{conn: conn} do
      response = conn |> get(~p"/api/v2/sources/59") |> valid!(@show)

      assert %{"id" => 59, "title" => "Cynipid galls of the seed slope"} = response

      assert [
               %{
                 "id" => 300,
                 "name" => "Andricus seedii (agamic)",
                 "taxoncode" => "gall",
                 "externallink" => "https://example.com/seed-slope#p12",
                 "description" => description
               }
             ] = response["species"]

      assert description =~ "seed citation"
    end

    test "the Gallformers Source's Galls carry their newest note's text", %{conn: conn} do
      response = conn |> get(~p"/api/v2/sources/58") |> valid!(@show)

      assert [%{"id" => 300} = agamic, %{"id" => 301} = sexgen] = response["species"]
      assert agamic["description"] =~ "seed note"
      assert sexgen["description"] =~ "sexgen seed note"
    end

    test "a Source attributing Facts lists their Galls, with no citation text", %{conn: conn} do
      source = source_fixture("Weld", "1959")
      gall = gall_fixture(name: "Attributed gall")

      {:ok, _} =
        Catalog.assert_alias(
          test_actor(),
          %{gall_id: gall.id, name: "attributed common name"},
          confirm(source)
        )

      response = conn |> get(~p"/api/v2/sources/#{source.id}") |> valid!(@show)

      assert [%{"id" => id, "name" => "Attributed gall", "description" => nil}] =
               response["species"]

      assert id == gall.id
    end

    test "404 for a missing Source, 400 for an invalid ID", %{conn: conn} do
      assert %{"error" => _} = conn |> get(~p"/api/v2/sources/999999999") |> valid!(@show)
      assert json_response(get(conn, ~p"/api/v2/sources/invalid"), 400)
    end
  end
end
