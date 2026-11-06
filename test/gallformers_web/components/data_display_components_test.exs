defmodule GallformersWeb.DataDisplayComponentsTest do
  @moduledoc """
  Tests for data display components.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GallformersWeb.DataDisplayComponents

  describe "taxon_name" do
    defp name_html(name, attrs \\ %{}),
      do:
        render_component(
          &DataDisplayComponents.taxon_name/1,
          Map.put(attrs, :name, name)
        )

    defp italic(html),
      do: html |> LazyHTML.from_fragment() |> LazyHTML.query("em") |> Enum.map(&LazyHTML.text/1)

    test "a binomial is italic" do
      assert italic(name_html("Andricus quercuslanigera")) == ["Andricus quercuslanigera"]
    end

    test "a Gall's generation and other parenthetical qualifiers stay upright" do
      html = name_html("Callirhytis quercuscornigera (agamic)")
      assert italic(html) == ["Callirhytis quercuscornigera"]
      assert html =~ "(agamic)"

      assert italic(name_html("Phytoplasma pruni (on Trillium)")) == ["Phytoplasma pruni"]
    end

    test "rank words and authorities stay upright; infraspecific names are italic" do
      assert italic(name_html("Quercus chrysolepis var. vaccinifolia")) ==
               ["Quercus chrysolepis", "vaccinifolia"]

      assert italic(name_html("Quercus imbricaria Michx.")) == ["Quercus imbricaria"]
    end

    test "an undescribed Gall's placeholder name is not a scientific name: upright" do
      assert italic(name_html("Unknown (Cynipidae) q-rubra-spur-gall")) == []
    end

    test "a genus alone is italic; ranks above genus are not" do
      assert italic(name_html("Amphibolips", %{rank: "genus"})) == ["Amphibolips"]
      assert italic(name_html("Cynipidae", %{rank: "family"})) == []
    end
  end
end
