defmodule GallformersWeb.FilterGuideControllerTest do
  @moduledoc """
  The filter guide shows each Trait's values with their definitions from the
  contract vocabulary (`Gallformers.Catalog.list_trait_values/0`, loaded
  from `traits.json` when `make test-db` converts the seeds).
  """
  use GallformersWeb.ConnCase

  # The vocabulary rows are loaded from the contract by the catalog migration.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Catalog

  test "GET /filterguide renders the filter guide page", %{conn: conn} do
    html = conn |> get(~p"/filterguide") |> html_response(200)

    assert html =~ "ID Tool Filter Guide"
    assert html =~ "Alignment"
    assert html =~ "Detachable"
  end

  test "GET /filterguide shows each value's definition from the contract", %{conn: conn} do
    html = conn |> get(~p"/filterguide") |> html_response(200)

    for trait <- ~w(alignment cells form plant_part shape texture walls detachable season),
        value <- Catalog.list_trait_values(),
        value.trait == trait and value.definition != nil do
      assert html =~ Phoenix.HTML.html_escape(value.value) |> Phoenix.HTML.safe_to_string()

      assert html =~
               Phoenix.HTML.html_escape(value.definition) |> Phoenix.HTML.safe_to_string()
    end

    assert html =~ "Galls are located on the upper (adaxial) side of the leaf."
    assert html =~ "The Gall forms and grows in spring."
    refute html =~ ">unknown<"
  end

  test "GET /filterguide sets page metadata", %{conn: conn} do
    conn = get(conn, ~p"/filterguide")

    assert conn.assigns.page_title == "Filter Guide"
    assert conn.assigns.page_url == "/filterguide"
  end
end
