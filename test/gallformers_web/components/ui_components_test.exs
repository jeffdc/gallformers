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

  describe "tooltip" do
    test "its text shows on hover or focus of what it explains, which it describes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tooltip id="tip" text="Tan to light brown.">tan</.tooltip>
        """)

      assert text(html, "#tip [role=tooltip]") == "Tan to light brown."
      assert query(html, "#tip [aria-describedby=tip-text]") |> Enum.any?()
      assert query(html, "#tip-text[role=tooltip]") |> Enum.any?()
      assert html =~ "tan"
    end
  end
end
