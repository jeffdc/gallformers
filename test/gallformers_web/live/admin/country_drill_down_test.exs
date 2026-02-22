defmodule GallformersWeb.Admin.CountryDrillDownTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gallformers.Places
  alias GallformersWeb.Admin.CountryDrillDown

  describe "rendering" do
    test "renders closed state by default" do
      html =
        render_component(CountryDrillDown,
          id: "drill-down",
          exact_places: [],
          country_places: [],
          all_places: Places.list_places()
        )

      refute html =~ "Country-level range"
    end
  end
end
