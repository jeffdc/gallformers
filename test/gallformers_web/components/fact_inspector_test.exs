defmodule GallformersWeb.FactInspectorTest do
  @moduledoc """
  `fact_ref` and the Fact inspector as readers see them (matter `87a1`,
  task 4): a Fact-backed value that opens who says so, and the inspector's
  reading state. The Facts are in `Gallformers.Import.gall_facts/1`'s shape.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.FactsComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  defp text(html, selector),
    do: html |> query(selector) |> LazyHTML.text() |> String.split() |> Enum.join(" ")

  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

  defp line(attrs) do
    Map.merge(
      %{
        source_id: 59,
        name: "Weld 1959",
        own?: false,
        gallformers?: false,
        stated_on: ~D[1959-01-01],
        precision: :year,
        date: "1959",
        stance: :confirm,
        words: [],
        statement: nil,
        quotes: [],
        observations: [],
        state: :counts,
        reason: nil
      },
      Map.new(attrs)
    )
  end

  defp original_data,
    do:
      line(
        source_id: 1,
        name: "Gallformers legacy data",
        own?: true,
        stated_on: nil,
        precision: nil,
        date: nil
      )

  defp host(attrs \\ []) do
    Map.merge(
      %{
        key: {:host, 7},
        fact_id: 123,
        kind: :host,
        trait: nil,
        value: %{
          type: "host_of",
          subject: %{taxon_id: 7, name: "Rosa carolina", rank: :species},
          object: %{gall_id: 5076, name: "Diplolepis rosae"}
        },
        standing: {:holds, 2},
        gallformers: nil,
        sources: [line(source_id: 60, name: "Kinsey 1920", date: "1920"), line([])]
      },
      Map.new(attrs)
    )
  end

  defp gall, do: %{name: "Diplolepis rosae", undescribed?: false}

  defp inspector(fact) do
    assigns = %{fact: fact, gall: gall()}

    rendered_to_string(~H"""
    <.fact_inspector id="fact-inspector" fact={@fact} of={@gall} on_close="close_fact" />
    """)
  end

  describe "fact_ref" do
    test "a button that opens who says so, and says whether it's selected" do
      assigns = %{fact: host()}

      html =
        rendered_to_string(~H"""
        <.fact_ref fact={@fact} selected={nil} on_select="select_fact" />
        """)

      assert count(html, "button[phx-click=select_fact][phx-value-key='host:7']") == 1
      assert attr(html, "button", "aria-pressed") == ["false"]
      assert attr(html, "button", "aria-controls") == ["fact-inspector"]
      assert attr(html, "button", "title") == ["Who says so?"]
      assert text(html, "button") == "Rosa carolina"

      selected =
        rendered_to_string(~H"""
        <.fact_ref fact={@fact} selected={{:host, 7}} on_select="select_fact" />
        """)

      assert attr(selected, "button", "aria-pressed") == ["true"]
    end

    test "each kind of Fact reads as the page writes it" do
      place = %{id: 31, code: "CA-AB", name: "Alberta"}

      for {fact, words} <- [
            {host(
               kind: :trait,
               key: {:trait, "color", "red"},
               value: %{trait: "color", value: "red"}
             ), "red"},
            {host(
               kind: :range,
               key: {:range, :exclude, 31},
               value: %{adjustment: :exclude, place: place}
             ), "not in Alberta"},
            {host(
               kind: :range,
               key: {:range, :only, 31},
               value: %{adjustment: :only, place: place}
             ), "only in Alberta"},
            {host(kind: :occurrence, key: {:occurrence, 31}, value: %{place: place}),
             "recorded in Alberta"},
            {host(
               kind: :alias,
               key: {:alias, "rose bedeguar"},
               value: %{name: "rose bedeguar", kind: :common_name}
             ), "rose bedeguar"}
          ] do
        assigns = %{fact: fact}

        html =
          rendered_to_string(~H"""
          <.fact_ref fact={@fact} selected={nil} on_select="select_fact" />
          """)

        assert text(html, "button") == words
      end
    end

    test "a proposed value is marked proposed and can't be selected" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_ref proposed text="recorded in Indiana" />
        """)

      assert count(html, "button") == 0
      assert text(html, "[data-proposed]") =~ "recorded in Indiana"
      assert text(html, "[data-proposed]") =~ "proposed"
    end
  end

  describe "fact_inspector, reading" do
    test "the kind, the value and what it is of" do
      html = inspector(host())

      assert text(html, "[data-part=kind]") == "Host"
      assert text(html, "[data-part=value]") == "Rosa carolina"
      assert text(html, "[data-part=of]") =~ "A Host of Diplolepis rosae"
    end

    test "a Host's page is linked" do
      assert attr(inspector(host()), "[data-part=of] a", "href") == ["/host/7"]
    end

    test "holds, stated by the Sources that count" do
      assert text(inspector(host()), "[data-part=standing]") =~ "Holds Stated by 2 Sources."

      assert text(inspector(host(standing: {:holds, 1})), "[data-part=standing]") =~
               "Stated by 1 Source."
    end

    test "unconfirmed when only Gallformers' original data states it" do
      html = inspector(host(standing: :unconfirmed, gallformers: original_data(), sources: []))

      assert text(html, "[data-part=standing]") =~
               "Unconfirmed Only in Gallformers' original data; no other Source states it."
    end

    test "Gallformers first, its original data undated, then the others as given" do
      html = inspector(host(gallformers: original_data()))

      assert [first | rest] = html |> query("[data-part=statement]") |> Enum.map(&LazyHTML.text/1)

      assert first |> String.split() |> Enum.join(" ") =~
               "Gallformers says so · original data, undated"

      assert Enum.map(rest, &(&1 =~ "Kinsey 1920")) == [true, false]
      assert attr(html, "[data-part=statement][data-source='60'] a", "href") == ["/source/60"]
    end

    test "Gallformers' own dated change shows its date" do
      change =
        line(
          source_id: 58,
          name: "Gallformers",
          own?: true,
          gallformers?: true,
          date: "Jul 14, 2025"
        )

      html = inspector(host(gallformers: change))

      assert text(html, "[data-part=statement][data-source=gallformers]") =~
               "Gallformers says so · Jul 14, 2025"
    end

    test "with nothing from Gallformers, readers see no Gallformers block" do
      assert count(inspector(host()), "[data-part=statement][data-source=gallformers]") == 0
    end

    test "a Source that says it isn't so, one awaiting a curator, one declined" do
      html =
        inspector(
          host(
            sources: [
              line(source_id: 61, name: "Denier 1990", stance: :deny),
              line(source_id: 62, name: "Waiting 1991", state: :awaiting),
              line(source_id: 63, name: "Declined 1992", state: :declined, reason: "Misread.")
            ]
          )
        )

      assert text(html, "[data-source='61']") =~ "Denier 1990 says it isn't so"
      assert text(html, "[data-source='62']") =~ "awaiting a curator"
      assert text(html, "[data-source='63']") =~ "declined: Misread."
    end

    test "the Source's words as written" do
      html = inspector(host(sources: [line(words: ["Rosa humilis", "Carolina rose"])]))

      assert text(html, "[data-part=words]") == "Written as “Rosa humilis”, “Carolina rose”"
    end

    test "the observations a statement rests on: linked, each with its grade and thumbnail" do
      observation = %{
        provider: :inaturalist,
        id: "318135694",
        url: nil,
        quality_grade: "needs_id",
        thumbnail_url: "https://example.org/thumb.jpg"
      }

      change =
        line(
          source_id: 58,
          name: "Gallformers",
          own?: true,
          gallformers?: true,
          date: "Jul 14, 2025",
          observations: [observation]
        )

      html = inspector(host(gallformers: change))
      based = "[data-source=gallformers] [data-part=observation]"

      assert text(html, based) == "Based on iNaturalist observation 318135694 (Needs ID)"

      assert attr(html, "#{based} a", "href") == [
               "https://www.inaturalist.org/observations/318135694"
             ]

      assert attr(html, "#{based} img", "src") == ["https://example.org/thumb.jpg"]
    end

    test "two quotes shown with their pages, the rest counted" do
      quotes = [
        %{quote: "On Rosa humilis.", page: "41"},
        %{quote: "Common on wild roses.", page: nil},
        %{quote: "Also on R. blanda.", page: "42"}
      ]

      html = inspector(host(sources: [line(quotes: quotes)]))

      assert count(html, "blockquote") == 2
      assert text(html, "blockquote") =~ "On Rosa humilis. p. 41"
      assert text(html, "[data-part=more-quotes]") == "1 more quote"
    end

    test "a labelled region, placed as the sheet, that the values control" do
      html = inspector(host())

      assert attr(html, "section#fact-inspector", "aria-label") == ["Who says so: Host"]
      assert attr(html, "section#fact-inspector", "class") == ["gf-sheet"]
    end

    test "Close sends the page's event" do
      assert count(inspector(host()), "button[phx-click=close_fact][aria-label=Close]") == 1
    end
  end

  describe "fact_inspector, Edit mode" do
    test "Gallformers' block holds the page's actions" do
      assigns = %{fact: host(gallformers: original_data())}

      html =
        rendered_to_string(~H"""
        <.fact_inspector id="fact-inspector" fact={@fact} of={gall()} on_close="close" editing>
          <:actions><button>Deny…</button></:actions>
        </.fact_inspector>
        """)

      assert text(html, "[data-source=gallformers]") =~ "Gallformers says so"
      assert text(html, "[data-source=gallformers] [data-part=actions]") == "Deny…"
      assert count(html, "[data-source='60'] [data-part=actions]") == 0
    end

    test "when Gallformers hasn't stated the Fact, its block says so, with the actions" do
      assigns = %{fact: host()}

      html =
        rendered_to_string(~H"""
        <.fact_inspector id="fact-inspector" fact={@fact} of={gall()} on_close="close" editing>
          <:actions><button>Confirm…</button></:actions>
        </.fact_inspector>
        """)

      assert text(html, "[data-source=gallformers]") =~ "Gallformers hasn't stated this"
      assert text(html, "[data-source=gallformers] [data-part=actions]") == "Confirm…"
    end

    test "reading, no actions even when the page gives them" do
      assigns = %{fact: host()}

      html =
        rendered_to_string(~H"""
        <.fact_inspector id="fact-inspector" fact={@fact} of={gall()} on_close="close">
          <:actions><button>Deny…</button></:actions>
        </.fact_inspector>
        """)

      assert count(html, "[data-part=actions]") == 0
      assert count(html, "[data-source=gallformers]") == 0
    end

    test "a new Fact: what it will be, for which Gall, and the page's form" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_inspector id="fact-inspector" state={:new} new="Host" of={gall()} on_close="close" editing>
          <form id="new-fact-form"></form>
        </.fact_inspector>
        """)

      assert text(html, "[data-part=kind]") == "New Host"
      assert text(html, "[data-part=of]") == "For Diplolepis rosae"
      assert count(html, "section#fact-inspector #new-fact-form") == 1
      assert attr(html, "section#fact-inspector", "aria-label") == ["New Host"]
    end
  end

  describe "fact_inspector, an observation" do
    test "Add from observation: its head, and the page's form" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_inspector id="fact-inspector" state={:observation} of={gall()} on_close="close" editing>
          <form id="observation-form"></form>
        </.fact_inspector>
        """)

      assert text(html, "[data-part=kind]") == "Add from observation"
      assert text(html, "[data-part=of]") == "For Diplolepis rosae"

      assert count(
               html,
               "section#fact-inspector[aria-label='Add from observation'] #observation-form"
             ) == 1
    end
  end
end
