defmodule GallformersWeb.API.StatsControllerTest do
  @moduledoc """
  API tests for the stats endpoint (`803b` Task 13): Gall and host counts
  come from the new back-end. The response is checked against its OpenAPI
  operation's schema.
  """
  use GallformersWeb.ConnCase, async: true

  import Gallformers.CatalogFixtures
  import OpenApiSpex.TestAssertions

  alias Gallformers.Catalog
  alias Gallformers.Taxa

  defp stats(conn) do
    conn = get(conn, ~p"/api/v2/stats")
    assert_operation_response(conn, "GallformersWeb.API.StatsController.index")
    json_response(conn, 200)
  end

  test "counts Galls, undescribed Galls, plants, Sources, glossary entries and images",
       %{conn: conn} do
    stats = stats(conn)

    assert stats["galls"] == Catalog.count_galls()
    assert stats["undescribed_galls"] == Catalog.gall_counts().undescribed
    assert stats["hosts"] == Taxa.count_plants()

    for key <- ["sources", "glossary", "images"] do
      assert is_integer(stats[key])
    end
  end

  test "a new Gall without an Inducer counts as a Gall and as undescribed; a plant as a host",
       %{conn: conn} do
    before = stats(conn)
    gall_fixture()
    plant_fixture()
    after_ = stats(conn)

    assert after_["galls"] == before["galls"] + 1
    assert after_["undescribed_galls"] == before["undescribed_galls"] + 1
    assert after_["hosts"] == before["hosts"] + 1
  end
end
