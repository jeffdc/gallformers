defmodule GallformersWeb.ReviewComponentsTest do
  @moduledoc """
  The review pages' step bar and question parts (matter `d213`, Tasks 15
  and 16), in each of their states.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.ReviewComponents

  defp has?(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.any?()

  defp text(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.text()

  defp summaries(left_by_step) do
    for step <- Steps.all() do
      {left, holding} = Map.get(left_by_step, step.id, {0, 0})
      %{step: step, total: left, left: left, recommended: 0, holding: holding}
    end
  end

  defp bar(approval, opts \\ []) do
    render_component(&ReviewComponents.review_step_bar/1,
      base: "/admin/review/sources/1",
      current: Keyword.get(opts, :current, :overview),
      summaries: summaries(%{names: {2, 2}, traits: {3, 0}}),
      approval: approval,
      confirm: Keyword.get(opts, :confirm, false)
    )
  end

  describe "review_step_bar" do
    test "each step with what's left or a check, a dot where it holds approval" do
      html = bar({:waiting, ["Names"]}, current: :names)

      assert has?(
               html,
               "#step-bar-names[aria-current=page][href='/admin/review/sources/1/names']"
             )

      assert text(html, "#step-bar-names [data-role=left]") =~ "2"
      assert has?(html, "#step-bar-names [data-role=holds]")
      assert has?(html, "#step-bar-galls [data-role=done]")
      refute has?(html, "#step-bar-traits [data-role=holds]")
      refute has?(html, "#step-bar-overview[aria-current]")
    end

    test "the current step carries the class that keeps its label white over the site's link colour" do
      html = bar({:waiting, ["Names"]}, current: :names)

      assert has?(html, "#step-bar-names.gf-step-current")
      refute has?(html, "#step-bar-galls.gf-step-current")
    end

    test "waiting, it says for what; ready, Approve; confirming, what stays open" do
      assert text(bar({:waiting, ["Names", "Galls"]}), "#approve-wait") =~
               "Approve appears once Names and Galls are settled"

      ready = bar({:ready, ["3 trait terms", "1 hedge"]})
      assert has?(ready, "#approve-open")
      refute has?(ready, "#approve-confirm")

      confirm =
        text(bar({:ready, ["3 trait terms", "1 hedge"]}, confirm: true), "#approve-confirm")

      assert confirm =~ "3 trait terms and 1 hedge are still open"
      assert confirm =~ "can be settled after"

      assert text(bar({:ready, ["1 hedge"]}, confirm: true), "#approve-confirm") =~
               "1 hedge is still open"

      approved = bar(:approved)
      refute has?(approved, "#approve-open")
      assert text(approved, "#step-bar") =~ "Approved"
    end
  end

  describe "the question's parts" do
    test "a row is a button whose chevron turns when open" do
      closed = render_row(false)
      assert has?(closed, "button#q-row[aria-expanded=false]")
      refute has?(closed, "[data-role=chevron].rotate-90")
      refute has?(closed, "#q-detail")

      open = render_row(true)
      assert has?(open, "button#q-row[aria-expanded=true]")
      assert has?(open, "[data-role=chevron].rotate-90")
      assert text(open, "#q-detail") =~ "The question"
    end

    test "an option's follow-up shows only once chosen; the recommended one is tagged" do
      unchosen = render_option(false)
      assert text(unchosen, "[data-role=recommended]") =~ "Recommended"
      assert text(unchosen, "label") =~ "2 of 3 readers"
      refute has?(unchosen, "[data-role=follow]")

      assert text(render_option(true), "[data-role=follow]") =~ "The search"
    end

    test "Decide is disabled, saying what is missing, until the answer is complete" do
      missing =
        render_component(&ReviewComponents.review_decide_bar/1,
          id: "q",
          ok: false,
          effect: "Pick a taxon from the search.",
          on_decide: "decide"
        )

      assert has?(missing, "#q-decide[disabled]")
      assert text(missing, "#q-effect") =~ "Pick a taxon from the search."

      complete =
        render_component(&ReviewComponents.review_decide_bar/1,
          id: "q",
          ok: true,
          effect: "Adds the plant.",
          on_decide: "decide"
        )

      refute has?(complete, "#q-decide[disabled]")
      assert text(complete, "#q-effect") =~ "Adds the plant."
    end

    test "an option says who chose it, recommended or not" do
      html =
        render_component(&ReviewComponents.review_option/1,
          id: "o",
          name: "q",
          value: 1,
          label: "polythalamous",
          tally: "Chosen by checker 2, for all 10 Galls",
          on_pick: "pick"
        )

      assert text(html, "[data-role=tally]") =~ "Chosen by checker 2, for all 10 Galls"
      refute has?(html, "[data-role=recommended]")
    end

    test "a value list: each value with its definition, the chosen and the readers' marked" do
      html =
        render_component(&ReviewComponents.review_value_list/1,
          id: "v",
          type: "checkbox",
          values: [{"green", "Green."}, {"yellow", nil}],
          selected: ["green"],
          noted: ["green"],
          note: "a reader chose it",
          on_pick: "toggle_value"
        )

      assert has?(html, "input#v-green[type=checkbox][checked]")
      refute has?(html, "input#v-yellow[checked]")
      assert text(html, "label[for=v-green]") =~ "Green."
      assert text(html, "label[for=v-green]") =~ "a reader chose it"
      refute text(html, "label[for=v-yellow]") =~ "a reader chose it"
    end

    test "segmented choices mark the recommended one" do
      html =
        render_component(&ReviewComponents.review_segmented/1,
          id: "s",
          key: "g1",
          label: "form for the knot gall",
          options: [{"globular", "globular"}, {"__text__", "keep as text"}],
          recommended: "globular",
          on_pick: "pick_gall"
        )

      assert text(html, "[data-recommended]") =~ "globular"
      assert text(html, "[data-recommended]") =~ "rec."
      refute text(html, "label[for=s-__text__]") =~ "rec."
    end
  end

  defp render_row(open) do
    assigns = %{open: open}

    rendered_to_string(~H"""
    <ReviewComponents.review_question_row id="q" open={@open} on_toggle="toggle">
      <:written>Q. lobata</:written>
      <:answer>Quercus lobata</:answer>
      <:detail>The question</:detail>
    </ReviewComponents.review_question_row>
    """)
  end

  defp render_option(checked) do
    assigns = %{checked: checked}

    rendered_to_string(~H"""
    <ReviewComponents.review_option
      id="o"
      name="q"
      value={0}
      checked={@checked}
      recommended
      by="2 of 3 readers"
      label="tan"
      summary="Light brown."
      on_pick="pick"
    >
      <:follow>The search</:follow>
    </ReviewComponents.review_option>
    """)
  end
end
