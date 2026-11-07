defmodule GallformersWeb.FeedbackComponentsTest do
  @moduledoc """
  The design system's feedback and overlays: notice, dialog, progress_bar,
  loading_spinner (docs/design-system/components.md).
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.FeedbackComponents

  alias Phoenix.LiveView.JS

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  defp attr(html, selector, name) do
    [value] = html |> query(selector) |> LazyHTML.attribute(name)
    value
  end

  # A JS command rendered into an attribute, decoded back to its ops.
  defp js_ops(html, selector, name), do: html |> attr(selector, name) |> Jason.decode!()

  describe "notice" do
    test "is an info status by default, with the kind's icon" do
      assigns = %{}
      html = rendered_to_string(~H|<.notice>Saved drafts are kept for 30 days.</.notice>|)

      assert count(html, "[role=status][data-kind=info]") == 1
      assert count(html, "[role=alert]") == 0
      assert count(html, ".ph-info") == 1
      assert text(html, "[data-part=message]") == "Saved drafts are kept for 30 days."
      assert count(html, "[data-part=title]") == 0
      assert count(html, "button") == 0
    end

    test "each kind marks itself and has its own icon; danger is an alert" do
      for {kind, role, icon} <- [
            {:info, "status", "ph-info"},
            {:ok, "status", "ph-check-circle"},
            {:warn, "status", "ph-warning"},
            {:danger, "alert", "ph-warning-circle"}
          ] do
        assigns = %{kind: kind}
        html = rendered_to_string(~H|<.notice kind={@kind}>message</.notice>|)

        assert count(html, "[role=#{role}][data-kind=#{kind}]") == 1
        assert count(html, ".#{icon}") == 1
      end
    end

    test "takes a title, an icon override and an action" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.notice id="conflict" kind={:warn} title="Holds approval" icon="ph-hourglass">
          Leaving this open holds approval of the Source's Gall statements.
          <:action><a href="/review">Review</a></:action>
        </.notice>
        """)

      assert count(html, "#conflict[data-kind=warn]") == 1
      assert text(html, "[data-part=title]") == "Holds approval"
      assert text(html, "[data-part=message]") =~ "holds approval of the Source's Gall statements"
      assert count(html, ".ph-hourglass") == 1
      assert count(html, ".ph-warning") == 0
      assert count(html, "[data-part=action] a[href='/review']") == 1
    end

    test "with on_dismiss, shows a Dismiss button that runs it" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.notice id="saved" kind={:ok} on_dismiss={JS.hide(to: "#saved")}>Saved</.notice>
        """)

      assert count(html, ~s(button[aria-label="Dismiss"])) == 1
      assert [["hide", %{"to" => "#saved"}]] = js_ops(html, "button", "phx-click")
    end
  end

  describe "dialog" do
    test "is a labelled modal dialog, hidden until shown" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.dialog id="rename" title="Rename taxon">
          <p>body</p>
          <:actions><button type="submit">Rename</button></:actions>
        </.dialog>
        """)

      assert count(html, "#rename.hidden") == 1

      assert count(
               html,
               ~s([role=dialog][aria-modal=true][aria-labelledby="rename-title"])
             ) == 1

      assert count(html, "h2#rename-title") == 1
      assert text(html, "#rename-title") == "Rename taxon"
      assert text(html, "[role=dialog] [data-part=body] p") == "body"
      # Not opened on mount unless asked
      assert count(html, "#rename[phx-mounted]") == 0
    end

    test "traps focus inside the panel" do
      assigns = %{}
      html = rendered_to_string(~H|<.dialog id="d" title="T">body</.dialog>|)

      assert count(html, ~s([role=dialog][phx-hook="Phoenix.FocusWrap"])) == 1
    end

    test "the header has a Close button that cancels" do
      assigns = %{}
      html = rendered_to_string(~H|<.dialog id="d" title="T">body</.dialog>|)

      assert count(html, ~s([data-part=header] button[aria-label="Close"])) == 1
      assert count(html, ~s(button[aria-label="Close"] .ph-x)) == 1

      assert [["exec", %{"attr" => "data-cancel", "to" => "#d"}]] =
               js_ops(html, ~s(button[aria-label="Close"]), "phx-click")
    end

    test "Escape cancels only while open; a click on the backdrop cancels" do
      assigns = %{}
      html = rendered_to_string(~H|<.dialog id="d" title="T">body</.dialog>|)

      assert attr(html, "[role=dialog]", "phx-key") =~ ~r/^escape$/i

      assert [["exec", %{"attr" => "data-cancel", "to" => "#d[data-open]"}]] =
               js_ops(html, "[role=dialog]", "phx-window-keydown")

      assert [["exec", %{"attr" => "data-cancel", "to" => "#d"}]] =
               js_ops(html, "[role=dialog]", "phx-click-away")

      assert count(html, "#d-backdrop.bg-overlay") == 1
    end

    test "cancelling runs on_cancel, then hides the dialog" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.dialog id="d" title="T" on_cancel={JS.push("cancel_delete")}>body</.dialog>
        """)

      assert [["push", %{"event" => "cancel_delete"}], ["exec", %{"attr" => "phx-remove"}]] =
               js_ops(html, "#d", "data-cancel")

      assert "#d" in for(["hide", %{"to" => to}] <- js_ops(html, "#d", "phx-remove"), do: to)
    end

    test "actions sit in a row after the body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.dialog id="d" title="Delete the taxon Acanthaceae?">
          Its 3 synonyms are deleted with it.
          <:actions>
            <button type="button" id="cancel">Cancel</button>
            <button type="button" id="confirm">Delete taxon</button>
          </:actions>
        </.dialog>
        """)

      assert count(html, "[role=dialog] [data-part=body] + [data-part=actions] #cancel") == 1
      assert count(html, "[data-part=actions] #confirm") == 1
      assert count(html, "[data-part=body] button") == 0
    end

    test "has no actions row without actions" do
      assigns = %{}
      html = rendered_to_string(~H|<.dialog id="d" title="T">body</.dialog>|)
      assert count(html, "[data-part=actions]") == 0
    end

    test "is medium by default and takes a size" do
      for size <- [:sm, :md, :lg, :full] do
        assigns = %{size: size}
        html = rendered_to_string(~H|<.dialog id="d" title="T" size={@size}>body</.dialog>|)
        assert count(html, "[role=dialog][data-size=#{size}]") == 1
      end

      assigns = %{}
      html = rendered_to_string(~H|<.dialog id="d" title="T">body</.dialog>|)
      assert count(html, "[role=dialog][data-size=md]") == 1
    end

    test "with show, opens itself when mounted" do
      assigns = %{}
      html = rendered_to_string(~H|<.dialog id="d" title="T" show>body</.dialog>|)

      assert ["show", %{"to" => "#d"}] in js_ops(html, "#d", "phx-mounted")
    end
  end

  describe "show_dialog/2 and hide_dialog/2" do
    test "show_dialog shows the dialog, marks it open, locks scrolling and moves focus in" do
      assert %JS{ops: ops} = show_dialog("d")

      assert ["show", %{to: "#d"}] in ops
      assert ["set_attr", %{to: "#d", attr: ["data-open", "true"]}] in ops
      assert ["add_class", %{to: "body", names: ["overflow-hidden"]}] in ops
      assert ["push_focus", %{}] in ops
      # Into the panel, and to the body's first control when it has one (the last focus wins)
      assert [["focus_first", %{to: "#d-panel"}], ["focus_first", %{to: "#d-body"}]] =
               Enum.filter(ops, &match?(["focus_first", _], &1))
    end

    test "hide_dialog hides it, unmarks it, unlocks scrolling and returns focus" do
      assert %JS{ops: ops} = hide_dialog("d")

      assert "#d" in for(["hide", %{to: to}] <- ops, do: to)
      assert ["remove_attr", %{to: "#d", attr: "data-open"}] in ops
      assert ["remove_class", %{to: "body", names: ["overflow-hidden"]}] in ops
      assert ["pop_focus", %{}] in ops
    end

    test "both compose onto an existing command" do
      assert %JS{ops: [["push", %{event: "open"}] | _]} = show_dialog(JS.push("open"), "d")
      assert %JS{ops: [["push", %{event: "close"}] | _]} = hide_dialog(JS.push("close"), "d")
    end
  end

  describe "progress_bar" do
    test "with a label it is a progressbar with its value, filled to scale" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.progress_bar id="sync" value={30} max={120} label="Hosts synced" />
        """)

      assert attr(html, "#sync", "role") == "progressbar"
      assert attr(html, "#sync", "aria-label") == "Hosts synced"
      assert attr(html, "#sync", "aria-valuenow") == "30"
      assert attr(html, "#sync", "aria-valuemax") == "120"
      assert count(html, "#sync.gf-progress") == 1
      assert attr(html, "#sync rect[data-bar]", "width") == "25.0%"
      assert attr(html, "#sync rect[data-bar]", "data-tone") == "brand"
    end

    test "without a label it is decorative: the words beside it say the numbers" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar id="p" value={1} max={4} tone={:ok} />|)

      assert attr(html, "#p", "aria-hidden") == "true"
      assert count(html, "#p[role]") == 0
      assert attr(html, "#p rect[data-bar]", "data-tone") == "ok"
    end

    test "segments are drawn one after another" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.progress_bar id="r" max={10} segments={[{2, :ok}, {5, :info}]} size="sm" />
        """)

      assert html |> query("#r rect[data-bar]") |> LazyHTML.attribute("width") == [
               "20.0%",
               "50.0%"
             ]

      assert html |> query("#r rect[data-bar]") |> LazyHTML.attribute("x") == ["0.0%", "20.0%"]
      assert count(html, "#r.gf-progress-sm") == 1
    end

    test "a zero max draws an empty bar, and a value over max fills it" do
      assigns = %{}
      empty = rendered_to_string(~H|<.progress_bar id="e" value={0} max={0} />|)
      assert attr(empty, "#e rect[data-bar]", "width") == "0.0%"

      full = rendered_to_string(~H|<.progress_bar id="f" value={9} max={4} />|)
      assert attr(full, "#f rect[data-bar]", "width") == "100.0%"
    end
  end

  describe "loading_spinner" do
    test "is brand by default and takes the text colour around it with tone :current" do
      brand = render_component(&GallformersWeb.UIComponents.loading_spinner/1, size: "sm")
      assert count(brand, "svg[role=status].text-brand") == 1

      current =
        render_component(&GallformersWeb.UIComponents.loading_spinner/1,
          size: "sm",
          tone: :current
        )

      assert count(current, "svg[role=status]") == 1
      assert count(current, "svg.text-brand") == 0
    end
  end
end
