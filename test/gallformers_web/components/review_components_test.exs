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

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

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

    test "with use, an option is taken in one click: Use this sends the pick with use" do
      html =
        render_component(&ReviewComponents.review_option/1,
          id: "o",
          name: "q",
          value: 2,
          label: "Leave this Host out",
          summary: "Drops 1 statement.",
          use: true,
          on_pick: "pick"
        )

      refute has?(html, "input[type=radio]")
      assert text(html, "[data-role=label]") =~ "Leave this Host out"
      assert text(html, "[data-role=summary]") =~ "Drops 1 statement."

      assert text(html, "button[phx-click=pick][phx-value-choice='2'][phx-value-use='1']") =~
               "Use this"
    end

    test "with use, the recommended option is marked Suggested and its button is the primary one" do
      html =
        render_component(&ReviewComponents.review_option/1,
          id: "o",
          name: "q",
          value: 0,
          label: "Use Potentilla norvegica L.",
          recommended: true,
          use: true,
          on_pick: "pick"
        )

      assert has?(html, "[data-recommended]")
      assert text(html, "[data-role=recommended]") =~ "Suggested"
      assert has?(html, "button.gf-btn-primary[phx-value-use='1']")
    end

    test "with use, an option that needs input opens it first: Search… picks it without use" do
      closed = render_use_search(false)

      assert text(closed, "button[phx-click=pick][phx-value-choice='1']:not([phx-value-use])") =~
               "Search…"

      refute closed =~ "The search"

      open = render_use_search(true)
      assert text(open, "[data-role=follow]") =~ "The search"
    end

    test "with use and href, the option is a link that opens in a new tab" do
      html =
        render_component(&ReviewComponents.review_option/1,
          id: "o",
          name: "q",
          value: "add",
          label: "Add a new plant",
          summary: "Not in Gallformers or WCVP? Add it, then search for it here.",
          use: true,
          href: "/admin/taxonomy/new?name=R.+ursinus",
          open_label: "Add… ↗",
          on_pick: "pick"
        )

      assert has?(html, "a[href='/admin/taxonomy/new?name=R.+ursinus'][target=_blank]")
      assert text(html, "a[target=_blank]") =~ "Add… ↗"
      refute has?(html, "button")
    end

    test "with use and tags, a weak suggestion is a Best guess, not the primary answer" do
      html =
        render_component(&ReviewComponents.review_option/1,
          id: "o",
          name: "q",
          value: 0,
          label: "It's Antistrophus s-gracile-flower-gall",
          tags: [%{text: "Best guess", kind: :best}],
          use: true,
          on_pick: "pick"
        )

      assert text(html, "[data-role=tag-best]") =~ "Best guess"
      refute has?(html, "button.gf-btn-primary")
    end

    test "a compact value list: checkboxes in columns, each definition in a tooltip" do
      html =
        render_component(&ReviewComponents.review_value_list/1,
          id: "v",
          type: "checkbox",
          compact: true,
          values: [{"tan", "Tan to light brown."}, {"white", nil}],
          selected: ["tan"],
          noted: ["white"],
          note: "suggested",
          on_pick: "pick"
        )

      assert has?(html, "#v.grid input#v-tan[type=checkbox][checked][phx-value-value=tan]")
      assert text(html, "#v [role=tooltip]") =~ "Tan to light brown."
      # The dotted underline is `fact_ref`'s ("who says so"): a definition is
      # marked by a line above the values instead.
      assert squish(text(html, "[data-role=values-hint]")) ==
               "Hover a value to see its definition."

      refute html =~ "border-dotted"
      assert text(html, "label[for=v-white]") =~ "suggested"
      refute has?(html, "[data-chosen]")
    end

    test "a compact value list with no definitions has no hover hint" do
      html =
        render_component(&ReviewComponents.review_value_list/1,
          id: "v",
          type: "checkbox",
          compact: true,
          values: [{"green", nil}],
          on_pick: "pick"
        )

      refute has?(html, "[data-role=values-hint]")
    end

    test "a value list sends its params with each value, to say whose value it is" do
      html =
        render_component(&ReviewComponents.review_value_list/1,
          id: "v",
          type: "checkbox",
          values: [{"green", nil}],
          params: %{ref: "g2"},
          on_pick: "pick"
        )

      assert has?(html, "input[phx-click=pick][phx-value-value=green][phx-value-ref=g2]")
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

  defp render_use_search(checked) do
    assigns = %{checked: checked}

    rendered_to_string(~H"""
    <ReviewComponents.review_option
      id="o"
      name="q"
      value={1}
      checked={@checked}
      label="Another plant…"
      summary="Search Gallformers and WCVP by name."
      use
      on_pick="pick"
    >
      <:follow>The search</:follow>
    </ReviewComponents.review_option>
    """)
  end

  describe "review_wcvp_panel, as a line" do
    defp wcvp_line(host),
      do:
        render_component(&ReviewComponents.review_wcvp_panel/1,
          id: "w",
          written: "N. crepideneus",
          host: host,
          line: true
        )

    @record %{id: "1", name: "Nabalus crepidineus", authors: "DC.", status: "Accepted"}

    test "says in one plain line what WCVP has and whether we have it" do
      html = wcvp_line(%{match: :near, wcvp: @record, accepted: nil, held: nil})

      assert squish(text(html, "[data-role=wcvp]")) ==
               "WCVP doesn't have “N. crepideneus” as written. Nearest spelling: " <>
                 "Nabalus crepidineus DC. (Accepted). We don't have it yet."

      refute has?(html, "[role=status], [role=alert]")
      refute has?(html, "a[href*='powo']")
    end

    test "a synonym names its accepted plant, and the plant we have links to it" do
      html =
        wcvp_line(%{
          match: :exact,
          wcvp: %{@record | status: "Synonym"},
          accepted: %{name: "Prenanthes crepidinea", authors: "Michx."},
          held: %{name: "Prenanthes crepidinea", taxon_id: 9}
        })

      assert squish(text(html, "[data-role=wcvp]")) =~
               "WCVP: Nabalus crepidineus DC., a synonym of Prenanthes crepidinea Michx. " <>
                 "We have it as Prenanthes crepidinea."

      assert has?(html, "a[href='/admin/taxonomy/9'][target=_blank]")
    end

    test "with nothing in WCVP, it offers POWO and IPNI" do
      html = wcvp_line(%{match: nil, wcvp: nil, accepted: nil, held: nil})

      assert text(html, "[data-role=wcvp]") =~ "WCVP doesn't have “N. crepideneus”"
      assert has?(html, "a[href*='powo.science.kew.org'][target=_blank]")
      assert has?(html, "a[href*='ipni.org'][target=_blank]")
    end
  end

  describe "review_rail" do
    @tally %{done: 12, left: 23, total: 35, holding: 22, hedged: 81}
    @stages [
      %{id: :names, title: "Names", state: :current, left: 3},
      %{id: :galls, title: "Galls", state: :todo, left: 19},
      %{id: :disputes, title: "Disputes", state: :done, left: 0}
    ]

    defp rail(opts) do
      render_component(
        &ReviewComponents.review_rail/1,
        Keyword.merge(
          [
            title: "Field Guide to the Herb & Bramble Gall Wasps",
            tally: @tally,
            stages: @stages,
            next: ["Host plants: N. crepideneus"],
            approval: {:waiting, ["Names"]},
            on_stage: "stage",
            on_hedges: "hedges",
            on_approve: "approve",
            on_deny: "deny"
          ],
          opts
        )
      )
    end

    test "how far along, in words, from the one tally" do
      html = rail([])

      assert text(html, "[data-role=answered]") =~ "12 of 35 answered"
      assert text(html, "[data-role=to-go]") =~ "23 to go."

      assert squish(text(html, "[data-role=to-go]")) =~
               "22 of them must be answered before you can approve."
    end

    test "the stages are buttons with what's left, the current one marked, a finished one done" do
      html = rail([])

      assert text(html, "button[phx-click=stage][phx-value-id=names][aria-current=step]") =~
               "3 left"

      assert text(html, "button[phx-click=stage][phx-value-id=galls]") =~ "19 left"
      assert text(html, "button[phx-click=stage][phx-value-id=disputes]") =~ "done"
    end

    test "links to the Source in Gallformers when there is one" do
      refute has?(rail([]), "a[href^='/admin/sources/']")
      assert has?(rail(source_id: 42), "a[href='/admin/sources/42']")
    end

    test "the hedged statements are a link, and Up next lists what comes" do
      html = rail([])

      assert text(html, "button[phx-click=hedges]") =~
               "81 hedged statements were left out. Review them"

      assert text(html, "[data-role=next]") =~ "Host plants: N. crepideneus"
    end

    test "Approve waits, saying why, until nothing must be answered first" do
      waiting = rail([])
      assert has?(waiting, "button[phx-click=approve][disabled]")

      assert text(waiting, "[data-role=approve-why]") =~
               "You can approve once the 22 marked questions are answered."

      ready = rail(approval: {:ready, []}, tally: %{@tally | holding: 0})
      refute has?(ready, "button[phx-click=approve][disabled]")
      refute has?(ready, "[data-role=approve-why]")
      assert has?(ready, "button[phx-click=deny]")
    end

    test "a Source still being read, or already approved, says so" do
      assert text(rail(approval: :resolving), "[data-role=approve-why]") =~ "still being read"
      approved = rail(approval: :approved)
      refute has?(approved, "button[phx-click=approve]")
      assert text(approved, "[data-role=approve-why]") =~ "Approved"
    end
  end

  describe "review_card" do
    defp card(kind, opts, inner \\ "") do
      assigns = %{kind: kind, opts: opts, inner: inner}

      rendered_to_string(~H"""
      <ReviewComponents.review_card id="card" kind={@kind} {@opts}>
        {@inner}
      </ReviewComponents.review_card>
      """)
    end

    @question [
      section: "Host plants",
      holds: true,
      heading: "Which plant is “N. crepideneus”?",
      affects: [
        %{name: "Diastrophus nebulosus", undescribed: false, what: "its Host"},
        %{name: "Rubus stem gall", undescribed: true, what: "the Gall itself"}
      ],
      quotes: [
        %{text: "On N. crepideneus.", where: "p. 12"},
        %{text: "Also on N. crepideneus.", where: nil},
        %{text: "A third.", where: nil}
      ],
      notes: [%{text: "Checked POWO.", author_name: "Jeff", inserted_at: nil}],
      skip_key: "q-7",
      item_id: 7,
      on_note: "note",
      note_target: "#q-7",
      on_read: "read",
      on_skip: "skip"
    ]

    test "a question: its kind, what it affects, the question, two quotes, earlier notes, the footer" do
      html = card(:question, @question, "the answers")

      assert squish(text(html, "[data-role=kind]")) =~
               "Host plants · needed before you can approve"

      assert text(html, "[data-role=affects]") =~ "Diastrophus nebulosus"
      assert squish(text(html, "[data-role=affects]")) =~ "its Host"
      assert has?(html, "h2.text-wrap")
      assert text(html, "h2") =~ "Which plant is “N. crepideneus”?"
      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("blockquote") |> Enum.count() == 2
      assert text(html, "blockquote") =~ "p. 12"
      assert text(html, "[data-role=notes]") =~ "Checked POWO."
      assert text(html, "[data-role=answers]") =~ "the answers"
      assert has?(html, "button[phx-click=note][phx-value-id='7']")
      assert has?(html, "button[phx-click=read][phx-value-item='7']")
      assert has?(html, "button[phx-click=note][phx-target='#q-7']")
      assert has?(html, "button[phx-click=skip][phx-value-key=q-7]")
    end

    test "nothing about approval, Affects or notes when there are none" do
      html = card(:question, Keyword.merge(@question, holds: false, affects: [], notes: []))

      refute text(html, "[data-role=kind]") =~ "needed before"
      refute has?(html, "[data-role=affects]")
      refute has?(html, "[data-role=notes]")
    end

    @rows [
      %{id: 1, trait: "texture", term: "lumpy", answer: "Keep as text", covers: 1},
      %{id: 2, trait: "texture", term: "smooth", answer: "smooth", covers: 3},
      %{id: 3, trait: nil, term: "Q. alba", answer: "Quercus alba", covers: 1}
    ]

    defp batch(opts) do
      card(
        :batch,
        Keyword.merge(
          [
            section: "Trait terms",
            stage: "Traits",
            of: 13,
            rows: @rows,
            unticked: MapSet.new(),
            skip_key: "batch-trait_terms",
            on_tick: "tick",
            on_accept: "accept",
            on_skip: "skip"
          ],
          opts
        )
      )
    end

    test "a batch: the suggested answers ticked, each with its term and answer" do
      html = batch([])

      assert text(html, "h2") =~ "3 of the 13 Traits questions have suggested answers"
      assert squish(text(html, "[data-role=intro]")) =~ "Untick any you want to check yourself."
      assert squish(text(html, "[data-role=intro]")) =~ "the other 10 come up one at a time"
      assert has?(html, "input[type=checkbox][phx-click=tick][phx-value-id='2'][checked]")
      assert squish(text(html, "li[data-id='2']")) =~ "texture: smooth → smooth (3 Galls)"
      assert squish(text(html, "li[data-id='3']")) == "Q. alba → Quercus alba"
      assert text(html, "button[phx-click=accept]") =~ "Accept all 3"
      assert has?(html, "button[phx-click=accept][phx-value-ids='1,2,3']")
      assert has?(html, "button[phx-click=skip][phx-value-key=batch-trait_terms]")
    end

    test "a batch with some unticked accepts the ticked ones; with all of a stage, says so" do
      some = batch(unticked: MapSet.new([2]))
      refute has?(some, "input[phx-value-id='2'][checked]")
      assert text(some, "button[phx-click=accept]") =~ "Accept the 2 ticked"
      assert has?(some, "button[phx-click=accept][phx-value-ids='1,3']")

      none = batch(unticked: MapSet.new([1, 2, 3]))
      assert has?(none, "button[phx-click=accept][disabled]")

      all = batch(of: 3)
      assert text(all, "h2") =~ "All 3 Traits questions have suggested answers"
      refute text(all, "[data-role=intro]") =~ "the other"
    end

    test "the hedged statements, grouped, each to add, and a way back" do
      html =
        card(:hedges,
          groups: [
            {"Host plants", [%{id: 4, text: "possibly on Q. rubra"}]},
            {"Places", [%{id: 5, text: "may occur in Texas"}, %{id: 6, text: "presumed in Ohio"}]}
          ],
          on_add: "add",
          on_back: "back"
        )

      assert text(html, "h2") =~ "Hedged statements"
      assert squish(text(html, "h3")) =~ "Places 2"
      assert text(html, "li[data-id='5']") =~ "may occur in Texas"
      assert has?(html, "li[data-id='5'] button[phx-click=add][phx-value-id='5']")
      assert text(html, "button[phx-click=back]") =~ "Back to the questions"
    end

    test "what approving will add: working it out, then the Facts" do
      loading = card(:facts, loading: true)
      assert text(loading, "h2") =~ "What approving will add"
      assert has?(loading, "[role=status]")
      refute has?(loading, "button[phx-click=skip]")

      ready = card(:facts, [loading: false], "the Facts")
      refute has?(ready, "[role=status]")
      assert text(ready, "[data-role=answers]") =~ "the Facts"
    end
  end
end
