defmodule GallformersWeb.FactsComponentsTest do
  @moduledoc """
  The Facts view's taxonomy parts (matter `f923` Task 10): an applied
  taxonomic statement's curator mark in the taxonomy changes, and a
  taxon's position (`taxonomic_position/1`): the Source its placement and
  name come from, and the papers that disagree. And the form of an edit
  open on a Fact (`fact_editor/1`).
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.FactsComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  defp words do
    %{
      term: nil,
      value_as_written: nil,
      names: [],
      evidence: [],
      when_as_written: nil,
      stage_as_written: nil,
      statement_text: nil,
      status_as_written: nil,
      authorship_as_written: nil
    }
  end

  defp act(id, kind, value, decision, source \\ %{source_id: 7, name: "Weld 1990"}) do
    %{
      ref: nil,
      batch_id: nil,
      fact_id: id,
      kind: kind,
      category: :taxonomy,
      gall: nil,
      value: value,
      words: words(),
      stance: :confirm,
      status: nil,
      standing: if(decision && decision.state == :accepted, do: :current, else: :unsupported),
      question: nil,
      why: nil,
      edits: [],
      source: source,
      decision: decision
    }
  end

  defp genus, do: %{taxon_id: 1, name: "Viewa", rank: :genus}
  defp family(name), do: %{taxon_id: 2, name: name, rank: :family}

  @at ~U[2026-11-03 10:00:00Z]

  describe "facts_taxonomy, applied" do
    test "marks each statement accepted, declined (with the reason) or awaiting" do
      acts = [
        act(1, :placement, %{taxon: genus(), parent: family("Viewidae")}, %{
          state: :accepted,
          by: "Ada Curator",
          at: @at,
          reason: nil
        }),
        act(2, :name, %{taxon: genus(), name: "Viewella"}, %{
          state: :declined,
          by: "Ada Curator",
          at: @at,
          reason: "A misspelling"
        }),
        act(3, :placement, %{taxon: genus(), parent: nil}, %{
          state: :awaiting,
          by: nil,
          at: nil,
          reason: nil
        })
      ]

      assigns = %{taxonomy: %{new_taxa: [], acts: acts}}

      html =
        rendered_to_string(~H"""
        <.facts_taxonomy taxonomy={@taxonomy} mode={:public} />
        """)

      assert text(html, "[data-decision=accepted]") =~ "accepted"
      assert text(html, "[data-decision=accepted]") =~ "by Ada Curator, Nov 3, 2026"
      assert text(html, "[data-decision=declined]") =~ "Declined: A misspelling"
      assert text(html, "[data-decision=awaiting]") =~ "awaiting a curator"
      assert text(html, "[data-decision=awaiting]") =~ "at the root"
      # An undecided statement's standing (unsupported) is not shown beside its mark.
      assert count(html, ".gf-mark-standing") == 1
      refute html =~ "unsupported"
      refute html =~ "approving adds"
    end

    test "the preview shows no decisions" do
      entry =
        act(1, :placement, %{taxon: genus(), parent: family("Viewidae")}, nil)
        |> Map.put(:ref, "a1")
        |> Map.put(:batch_id, 4)
        |> Map.put(:status, :new)
        |> Map.delete(:decision)

      assigns = %{taxonomy: %{new_taxa: [], acts: [entry]}}

      html =
        rendered_to_string(~H"""
        <.facts_taxonomy taxonomy={@taxonomy} />
        """)

      assert count(html, "[data-decision]") == 0
      assert html =~ "approving adds"
    end
  end

  describe "taxonomic_position" do
    defp position(disagreeing) do
      %{
        placement: %{
          fact_id: 10,
          parent: family("Viewidae"),
          source: %{source_id: 7, name: "Weld 1990"}
        },
        name: %{
          fact_id: 11,
          name: "Viewa",
          rank: :genus,
          authorship: "Kinsey, 1930",
          sensu: nil,
          source: %{source_id: 8, name: "Gallformers legacy data"}
        },
        disagreeing: disagreeing
      }
    end

    test "the Sources of the placement and name, and the papers that disagree" do
      disagreeing = [
        act(
          20,
          :placement,
          %{taxon: genus(), parent: family("Otherviewidae")},
          %{state: :declined, by: "Ada Curator", at: @at, reason: "Not followed"},
          %{source_id: 9, name: "Smith 2001"}
        ),
        act(
          21,
          :name,
          %{taxon: genus(), name: "Viewella"},
          %{state: :awaiting, by: nil, at: nil, reason: nil},
          %{source_id: 12, name: "Jones 2010"}
        )
      ]

      assigns = %{position: position(disagreeing)}

      html =
        rendered_to_string(~H"""
        <.taxonomic_position id="pos" position={@position} />
        """)

      assert text(html, "[data-part=placement]") =~ "Viewidae"
      assert count(html, "[data-part=placement] a[href='/source/7']") == 1
      assert text(html, "[data-part=name]") =~ "Kinsey, 1930"
      assert count(html, "[data-part=name] a[href='/source/8']") == 1

      assert text(html, "[data-part=disagreeing] [data-decision=declined]") =~ "Otherviewidae"
      assert text(html, "[data-part=disagreeing] [data-decision=declined]") =~ "Not followed"
      assert count(html, "[data-part=disagreeing] a[href='/source/9']") == 1
      assert text(html, "[data-part=disagreeing] [data-decision=awaiting]") =~ "Viewella"
    end

    test "no disagreeing papers, no such line; no position, nothing" do
      assigns = %{position: position([])}

      html =
        rendered_to_string(~H"""
        <.taxonomic_position id="pos" position={@position} />
        """)

      assert count(html, "[data-part=disagreeing]") == 0

      assigns = %{position: %{placement: nil, name: nil, disagreeing: []}}

      html =
        rendered_to_string(~H"""
        <.taxonomic_position id="pos" position={@position} />
        """)

      assert String.trim(html) == ""
    end
  end

  describe "fact_editor" do
    defp pick(attrs),
      do: Map.merge(%{query: "", results: [], selected: nil, values: [], note: ""}, attrs)

    test "the title, the note and Save and Cancel; no search or values unless asked" do
      assigns = %{pick: pick(%{note: "As written"})}

      html =
        rendered_to_string(~H"""
        <.fact_editor
          id="ed"
          title="Drop this Fact."
          on_submit="save"
          target="#here"
          pick={@pick}
          note_label="Note (optional)"
          save_text="Drop it"
        />
        """)

      assert count(html, "form#ed[phx-submit=save][phx-target='#here']") == 1
      assert count(html, "#ed-cancel[phx-target='#here']") == 1
      assert text(html, "form#ed > p") == "Drop this Fact."
      assert text(html, "label[for=ed-note]") == "Note (optional)"
      assert text(html, "textarea#ed-note[name=note]") == "As written"
      assert text(html, "#ed-save") == "Drop it"
      assert count(html, "#ed-cancel[phx-click=edit_cancel]") == 1
      assert count(html, "#ed-taxon") == 0
      assert count(html, "#ed-values") == 0
      assert count(html, "#ed-error") == 0
    end

    test "a taxon search, the values to tick, the caller's fields and the refusal" do
      assigns = %{pick: pick(%{values: ["red"]})}

      html =
        rendered_to_string(~H"""
        <.fact_editor
          id="ed"
          title="Change it."
          on_submit="save"
          pick={@pick}
          search_label="The plant"
          search_event="search_plant"
          values={[{"red", "Red."}, {"brown", nil}]}
          note_label="Note: why (required)"
          error="Write the note."
          save_text="Save"
          save_variant="danger"
        >
          <input id="ed-extra" type="checkbox" name="accept" />
        </.fact_editor>
        """)

      assert count(html, "#ed-taxon") == 1
      assert html =~ "search_plant"
      assert count(html, "#ed-values-red[checked]") == 1
      assert count(html, "#ed-values-brown[checked]") == 0
      assert count(html, "#ed-extra") == 1
      assert text(html, "#ed-error") == "Write the note."
    end
  end
end
