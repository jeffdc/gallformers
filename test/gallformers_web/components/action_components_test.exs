defmodule GallformersWeb.ActionComponentsTest do
  @moduledoc "The design system's actions: button, segmented_switch (docs/design-system/components.md)."
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.ActionComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

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

    test "link: a text action that reads as a link (87a1)" do
      assigns = %{}

      html =
        rendered_to_string(
          ~H|<.button variant="link" icon="ph-plus" phx-click="add">Add a host</.button>|
        )

      assert count(html, "button.gf-btn.gf-btn-link[phx-click=add]") == 1
      assert count(html, "button .ph-plus") == 1
    end

    test "every variant but secondary (the base .gf-btn) has its style" do
      css = File.read!(Path.expand("../../../assets/css/system/components.css", __DIR__))

      for variant <- ~w(primary ghost danger link) do
        assert css =~ ".gf-btn-#{variant} {", "no .gf-btn-#{variant} rule in components.css"
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

  describe "segmented_switch" do
    test "a labelled group of buttons, the current one pressed, each sending the event" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.segmented_switch label="View" value={:table} event="galls_view" param="view">
          <:option value={:photos}>Photos</:option>
          <:option value={:table}>Table</:option>
        </.segmented_switch>
        """)

      assert attr(html, "[role=group]", "aria-label") == ["View"]
      assert count(html, "[role=group] button[type=button]") == 2
      assert attr(html, "button", "phx-click") == ["galls_view", "galls_view"]
      assert attr(html, "button", "phx-value-view") == ["photos", "table"]
      assert attr(html, "button", "aria-pressed") == ["false", "true"]
      assert count(html, "button[aria-pressed=true].bg-brand-fill") == 1
      assert html =~ "Photos"
    end

    test "compares values as strings, sends value by default, and targets a component" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.segmented_switch label="Type" value="native" event="set_type" target="#drill">
          <:option value={:native} id="type-native">Native</:option>
          <:option value={:introduced} id="type-introduced">Introduced</:option>
        </.segmented_switch>
        """)

      assert attr(html, "#type-native", "aria-pressed") == ["true"]
      assert attr(html, "#type-introduced", "phx-value-value") == ["introduced"]
      assert attr(html, "button", "phx-target") == ["#drill", "#drill"]
    end

    test "an icon-only option is named by its label, and the switch can be disabled" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.segmented_switch label="View" value={:grid} event="toggle_view" param="view" disabled>
          <:option value={:grid} icon="ph-squares-four" label="Grid view" />
          <:option value={:table} icon="ph-list" label="Table view" />
        </.segmented_switch>
        """)

      assert attr(html, "button", "aria-label") == ["Grid view", "Table view"]
      assert attr(html, "button", "title") == ["Grid view", "Table view"]
      assert count(html, "button[disabled]") == 2
      assert count(html, "button [class*=ph-squares-four]") == 1
    end
  end
end
