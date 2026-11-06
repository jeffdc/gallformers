defmodule GallformersWeb.ActionComponentsTest do
  @moduledoc "The design system's button (docs/design-system/components.md)."
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.ActionComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  describe "button" do
    test "is a secondary button by default" do
      assigns = %{}
      html = rendered_to_string(~H|<.button>Rename</.button>|)
      assert count(html, "button.gf-btn.gf-btn-secondary") == 1
    end

    test "renders each variant" do
      for variant <- ~w(primary secondary ghost danger) do
        assigns = %{variant: variant}
        html = rendered_to_string(~H|<.button variant={@variant}>Go</.button>|)
        assert count(html, "button.gf-btn-#{variant}") == 1
      end
    end

    test "maps retiring variants onto the system's" do
      assigns = %{}
      html = rendered_to_string(~H|<.button variant="soft">Go</.button>|)
      assert count(html, "button.gf-btn-secondary") == 1

      html =
        rendered_to_string(~H|<.button variant="warning" shape="pill" size="lg">Go</.button>|)

      assert count(html, "button.gf-btn-secondary") == 1
      assert count(html, ".gf-btn-pill, .gf-btn-lg") == 0
    end

    test "is type=button unless told otherwise, and never twice" do
      assigns = %{}
      html = rendered_to_string(~H|<.button>Go</.button>|)
      assert count(html, "button[type=button]") == 1

      html = rendered_to_string(~H|<.button type="submit">Save</.button>|)
      assert count(html, "button[type=submit]") == 1
      assert length(Regex.scan(~r/type=/, html)) == 1
    end

    test "is a link when it navigates" do
      assigns = %{}
      html = rendered_to_string(~H|<.button navigate="/admin">Admin</.button>|)
      assert count(html, "a.gf-btn[href='/admin']") == 1
    end

    test "an icon-only button is labelled for assistive technology" do
      assigns = %{}
      html = rendered_to_string(~H|<.button icon="ph-x" label="Close" icon_only />|)
      assert count(html, ~s(button.gf-btn-icon[aria-label="Close"])) == 1
      assert count(html, "button .icon, button [class*=ph-x]") >= 1
    end

    test "shows its icon before its label" do
      assigns = %{}
      html = rendered_to_string(~H|<.button icon="ph-plus">Add synonym</.button>|)
      assert html =~ "Add synonym"
      assert count(html, "button [class*=ph-plus]") == 1
    end
  end
end
