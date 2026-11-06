defmodule GallformersWeb.CurationComponentsTest do
  @moduledoc """
  The inline-editing components (matters bc0d, ec2c): `edit_toggle`,
  `edit_scope`, `fact_row`, `change_tray` and `review_apply`, driven by
  data in the change-set contract's shapes (`Gallformers.Curation`, built
  by the ingestion side): items with their display text and flags, each
  flag `%{kind, text}` with its words from the back end.
  """
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.CurationComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

  describe "edit_toggle" do
    test "off: Edit, linking to the page with Edit on" do
      assigns = %{}
      html = rendered_to_string(~H|<.edit_toggle editing={false} path="/gall/821" />|)

      assert attr(html, "a", "href") == ["/gall/821?edit"]
      assert attr(html, "a", "aria-pressed") == ["false"]
      assert text(html, "a") == "Edit"
    end

    test "on: Editing · Done, linking back to the page" do
      assigns = %{}
      html = rendered_to_string(~H|<.edit_toggle editing={true} path="/gall/821" />|)

      assert attr(html, "a", "href") == ["/gall/821"]
      assert attr(html, "a", "aria-pressed") == ["true"]
      assert text(html, "a") =~ "Done"
    end
  end

  describe "edit_scope" do
    test "edited on another page: says where, linked" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.edit_scope kind={:elsewhere} href="/admin/galls/1#images">
          Photos: in the photo manager
        </.edit_scope>
        """)

      assert attr(html, "[data-scope]", "data-scope") == ["elsewhere"]
      assert text(html, "[data-scope]") =~ "Photos: in the photo manager"
      assert attr(html, "[data-scope] a", "href") == ["/admin/galls/1#images"]
    end

    test "follows from other data: says from what" do
      assigns = %{}

      html =
        rendered_to_string(~H|<.edit_scope kind={:follows}>From the Traits below.</.edit_scope>|)

      assert attr(html, "[data-scope]", "data-scope") == ["follows"]
      assert count(html, "[data-scope] a") == 0
    end
  end

  describe "fact_row" do
    test "a Fact, the Sources stating it, and its actions, each sending its key" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <ul>
          <.fact_row
            fact_key={{:host, 7}}
            sources={["Weld (1959)", "Felt (1940)"]}
            actions={[:withdraw, :correct, :note]}
          >
            Quercus alba
          </.fact_row>
        </ul>
        """)

      assert attr(html, "li", "id") == ["fact-host-7"]
      assert text(html, "[data-part=fact]") == "Quercus alba"
      assert text(html, "[data-part=sources]") == "Weld (1959) · Felt (1940)"

      assert attr(html, "button[phx-click=fact_action]", "phx-value-action") ==
               ~w(withdraw correct note)

      assert attr(html, "button[phx-click=fact_action]", "phx-value-key") |> Enum.uniq() == [
               "host:7"
             ]
    end

    test "in the tray: marked, struck through when withdrawn, no actions" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <ul>
          <.fact_row fact_key={{:host, 7}} pending={%{action: :withdraw, state: :in_tray}}>
            Quercus alba
          </.fact_row>
        </ul>
        """)

      assert text(html, "[data-part=pending]") == "in your tray"
      assert count(html, "[data-part=fact].line-through") == 1
      assert count(html, "button[phx-click=fact_action]") == 0
    end

    test "submitted: waiting for its outcome" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <ul>
          <.fact_row fact_key={{:host, 7}} pending={%{action: :add, state: :waiting}}>
            Quercus alba
          </.fact_row>
        </ul>
        """)

      assert text(html, "[data-part=pending]") == "waiting to apply"
    end
  end

  describe "fact_chip" do
    test "a Trait value: its Sources as its title, ✕ withdraws it" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_chip fact_key={{:trait, "season", "Spring"}} sources={["Weld (1959)"]} target="#ed">
          Spring
        </.fact_chip>
        """)

      assert attr(html, "span#fact-trait-season-Spring", "title") == ["Weld (1959)"]
      assert attr(html, "button[phx-click=fact_action]", "phx-value-action") == ["withdraw"]

      assert attr(html, "button[phx-click=fact_action]", "phx-value-key") == [
               "trait:season:Spring"
             ]

      assert attr(html, "button[phx-click=fact_action]", "phx-target") == ["#ed"]
    end

    test "withdrawn in the tray: struck through; added in the tray: marked; neither has ✕" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_chip
          fact_key={{:trait, "season", "Spring"}}
          pending={%{action: :withdraw, state: :in_tray}}
        >
          Spring
        </.fact_chip>
        <.fact_chip fact_key={{:trait, "season", "Summer"}} pending={%{action: :add, state: :in_tray}}>
          Summer
        </.fact_chip>
        """)

      assert count(html, "#fact-trait-season-Spring.line-through") == 1
      assert count(html, "#fact-trait-season-Summer[data-pending]") == 1
      assert count(html, "button") == 0
    end
  end

  describe "fact_row's target" do
    test "its actions go to the given target" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <ul>
          <.fact_row fact_key={{:host, 7}} target="#ed">Quercus alba</.fact_row>
        </ul>
        """)

      assert attr(html, "button[phx-click=fact_action]", "phx-target") |> Enum.uniq() == ["#ed"]
    end
  end

  describe "change_tray" do
    test "nothing in the tray: nothing shown" do
      assigns = %{}
      assert rendered_to_string(~H|<.change_tray summary={nil} />|) |> String.trim() == ""

      assert rendered_to_string(
               ~H|<.change_tray summary={%{count: 0, lines: [], oldest_at: nil}} />|
             )
             |> String.trim() == ""
    end

    test "the count, the changes, Discard and Review and apply" do
      assigns = %{
        summary: %{
          count: 3,
          lines: ["withdraw host: Quercus alba", "add Season: fall", "completeness: complete"],
          oldest_at: nil
        }
      }

      html = rendered_to_string(~H|<.change_tray summary={@summary} />|)

      assert text(html, "#change-tray [data-part=count]") == "3 changes in your tray"

      assert text(html, "#change-tray [data-part=lines]") =~
               "withdraw host: Quercus alba · add Season: fall"

      assert count(html, "#change-tray button[phx-click=tray_discard]") == 1
      assert count(html, "#change-tray button[phx-click=tray_review]") == 1
    end
  end

  describe "review_apply" do
    defp items do
      [
        %{
          id: 1,
          kind: :fact,
          text: "Withdraw host: Quercus alba",
          flags: [
            %{kind: :supersedes, text: "Supersedes Weld 1959's host"},
            %{kind: :needs_reason, text: "A reason is needed"}
          ]
        },
        %{id: 2, kind: :fact, text: "Add Season: fall", flags: [%{kind: :new, text: "New"}]},
        %{
          id: 3,
          kind: :editorial,
          text: "Gallformers code: q-alba-cup",
          flags: [%{kind: :needs_confirmation, text: "iNaturalist links use the code"}]
        },
        %{
          id: 4,
          kind: :fact,
          text: "Add host: Quercus rubra",
          flags: [%{kind: :blocked, text: "No such plant"}],
          state: :waiting
        }
      ]
    end

    defp review(opts \\ []) do
      assigns = %{
        items: items(),
        evidence: Keyword.get(opts, :evidence, %{text: "", observations: [], source_id: nil}),
        confirmed: Keyword.get(opts, :confirmed, [])
      }

      rendered_to_string(~H"""
      <.review_apply id="review" items={@items} evidence={@evidence} confirmed={@confirmed} />
      """)
    end

    test "each change with its flags, in the back end's words" do
      html = review()

      assert text(html, "#review-item-1 [data-part=text]") == "Withdraw host: Quercus alba"

      assert attr(html, "#review-item-1 [data-flag]", "data-flag") == [
               "supersedes",
               "needs_reason"
             ]

      assert text(html, "#review-item-1 [data-flag=supersedes]") == "Supersedes Weld 1959's host"
    end

    test "a change that needs a reason or is blocked can't be applied alone; it says why" do
      html = review()

      assert count(html, "#review-item-1 button[phx-click=apply_item][disabled]") == 1
      assert count(html, "#review-item-4 button[phx-click=apply_item][disabled]") == 1
      assert count(html, "#review-item-2 button[phx-click=apply_item]:not([disabled])") == 1
    end

    test "a change needing confirmation has its confirmation box; confirmed, it can be applied" do
      assert count(
               review(),
               "#review-item-3 input[type=checkbox][phx-click=toggle_confirm][phx-value-id='3']"
             ) == 1

      assert count(review(), "#review-item-3 button[phx-click=apply_item][disabled]") == 1

      assert count(
               review(confirmed: [3]),
               "#review-item-3 button[phx-click=apply_item]:not([disabled])"
             ) == 1
    end

    test "a submitted change waits for its outcome" do
      assert text(review(), "#review-item-4 [data-part=state]") == "Waiting to apply"
    end

    test "evidence for the Fact changes: a reason, observations as links, a Source" do
      html =
        review(
          evidence: %{
            text: "Seen on site",
            observations: [
              %{provider: "inaturalist", id: "123"},
              %{provider: "bugguide", id: "77"}
            ],
            source_id: nil
          }
        )

      assert count(html, "form#review-evidence[phx-change=set_evidence]") == 1
      assert text(html, "form#review-evidence textarea[name='evidence[text]']") == "Seen on site"

      assert attr(html, "form#review-evidence input[name='evidence[observations]']", "value") == [
               "https://www.inaturalist.org/observations/123, https://bugguide.net/node/view/77"
             ]

      # The Source: a typeahead outside the form (its own events)
      assert count(html, "form#review-evidence #review-evidence-source") == 0
      assert count(html, "#review-evidence-source input") == 1
    end

    test "the Source chosen as evidence is shown by its title" do
      assigns = %{items: items()}

      html =
        rendered_to_string(~H"""
        <.review_apply
          id="review"
          items={@items}
          evidence={%{text: "", observations: [], source_id: 9}}
          source={%{id: 9, title: "Felt 1940"}}
        />
        """)

      assert html =~ "Felt 1940"
    end

    test "adds_statement: its words shown, informational, nothing blocked" do
      assigns = %{
        items: [
          %{
            id: 9,
            kind: :fact,
            text: "Add host: Quercus alba",
            flags: [
              %{kind: :held, text: "Already held: Weld 1959"},
              %{kind: :adds_statement, text: "Adds Gallformers' statement to it"}
            ]
          }
        ]
      }

      html =
        rendered_to_string(~H"""
        <.review_apply
          id="review"
          items={@items}
          evidence={%{text: "", observations: [], source_id: nil}}
        />
        """)

      assert text(html, "#review-item-9 [data-flag=adds_statement]") ==
               "Adds Gallformers' statement to it"

      assert count(html, "#review-item-9 [data-flag=adds_statement][data-variant=info]") == 1
      assert count(html, "#review-item-9 button[phx-click=apply_item]:not([disabled])") == 1
    end

    test "every change can be taken out; the set applied, its count shown" do
      html = review()

      assert count(html, "button[phx-click=remove_item]") == 4
      assert text(html, "button[phx-click=apply_all]") == "Apply 4 changes"
    end
  end
end
