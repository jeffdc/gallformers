defmodule GallformersWeb.UIComponentsTest do
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.UIComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  describe "see_also" do
    test "names its links See also and searches each resource for the name" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.see_also name="Andricus weldi (agamic)" type={:gall} />
        """)

      assert text(html, "[data-part=label]") == "See also"

      assert html |> query("a") |> LazyHTML.attribute("href") |> hd() ==
               "https://www.inaturalist.org/search?q=Andricus%20weldi"
    end
  end
end
