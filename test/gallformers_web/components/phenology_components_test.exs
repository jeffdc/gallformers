defmodule GallformersWeb.PhenologyComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Gallformers.Phenology
  alias GallformersWeb.PhenologyComponents

  test "collapsed panel has an accessible toggle and no form" do
    html = render_component(&PhenologyComponents.phenology_summary/1, species_id: 1)
    assert html =~ ~s(aria-expanded="false")
    refute html =~ ~s(id="gall-phenology-latitude")
  end

  test "empty expanded panel reports absent evidence" do
    html = render_component(&PhenologyComponents.phenology_summary/1, species_id: 1, open: true)
    assert html =~ "No phenology observations"
    refute html =~ "View full chart"
  end

  test "both presentations render the exact same prediction dates and sparse warnings" do
    obs = %{
      species_id: 1,
      species_name: "Example (agamic)",
      date: ~D[2023-12-28],
      latitude: 30.0,
      longitude: -98.0,
      phenophase: "maturing",
      source_type: "inat"
    }

    assert {:ok, [p]} = Phenology.predict([obs], 40, [:emergence])
    assert {:ok, [compact]} = Phenology.predict([obs], 40, [:emergence], contours: false)
    assert Map.delete(p, :contours) == Map.delete(compact, :contours)
    assert compact.contours == []
    expected = render_component(&PhenologyComponents.prediction_results/1, predictions: [p])

    html =
      render_component(&PhenologyComponents.phenology_summary/1,
        species_id: 1,
        open: true,
        count: 1,
        predictions: [compact],
        target_lat: 40
      )

    assert html =~ expected
    assert html =~ "Few records"
    assert html =~ "Extrapolation: 40.0°N is outside the recorded range"
    assert html =~ "(30.0°N)"
    assert html =~ "Timing at this latitude is unverified"
    refute html =~ "geographic cells"
    refute html =~ "One-cell"
    assert html =~ "species_id=1"
    assert html =~ "lat=40"
  end

  defp developing(day, lat \\ 30.0) do
    %{
      species_id: 1,
      species_name: "Example (agamic)",
      date: Date.add(~D[2023-01-01], day - 1),
      latitude: lat,
      longitude: -98.0,
      phenophase: "developing",
      source_type: "inat"
    }
  end

  test "onset shows a single approximate date and a linked, dated anchor" do
    record = Map.put(developing(196), :page_url, "https://www.inaturalist.org/observations/123")
    {:ok, predictions} = Phenology.predict([record], 30, [:onset])
    html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)

    assert text_at(html, "[data-event='onset'] p:first-child") ==
             "Fresh galls may start appearing around Jul 15."

    refute html =~ "Jul 15–Jul 15"
    refute html =~ "percentile"
    assert html =~ "Earliest recorded development, latitude-adjusted"
    assert html =~ ~s(href="https://www.inaturalist.org/observations/123")
    assert html =~ "Jul 15, 2023 at 30.0°N"
    refute html =~ "confirmed"
  end

  test "anchor links allow only safe URLs and fall back to the source" do
    for page <- [nil, "javascript:alert(1)", "data:text/html,test"] do
      record =
        Map.merge(developing(196), %{page_url: page, source_url: "https://example.org/paper"})

      {:ok, predictions} = Phenology.predict([record], 30, [:onset])
      html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
      assert html =~ ~s(href="https://example.org/paper")
      refute html =~ "javascript:"
      refute html =~ "data:text"
    end

    {:ok, predictions} = Phenology.predict([developing(196)], 30, [:onset])
    html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
    refute html =~ "Anchor record"
    assert html =~ "Jul 15, 2023 at 30.0°N"
  end

  test "answers lead with sentences while methods stay in one closed disclosure" do
    records = [
      Map.put(developing(196), :page_url, "https://www.inaturalist.org/observations/123"),
      %{developing(355) | phenophase: "maturing"},
      %{developing(5) | phenophase: "Free-living"},
      Map.put(developing(250), :viability, "viable")
    ]

    {:ok, predictions} = Phenology.predict(records, 30, [:onset, :emergence, :rearing])
    html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
    document = LazyHTML.from_document(html)
    assert length(LazyHTML.query(document, "details") |> Enum.to_list()) == 1
    assert LazyHTML.query(document, "details[open]") |> Enum.empty?()
    assert text_at(html, "summary") == "Evidence & methods"

    assert text_at(html, "[data-event='emergence'] p:first-child") ==
             "Look for emerging or active adults around Dec 21–Jan 5."

    assert text_at(html, "[data-event='rearing'] p:first-child") ==
             "Try collecting galls for rearing around Sep 7."

    assert text_at(html, "[data-event='onset'] strong") == "Jul 15"
    assert text_at(html, "[data-event='emergence'] strong") == "Dec 21–Jan 5"
    refute text_at(html, "[data-event]") =~ "Middle 80%"
    refute text_at(html, "[data-event]") =~ "median"
    refute text_at(html, "[data-event]") =~ "latitude-adjusted"
    refute text_at(html, "[data-event]") =~ "Anchor record"
    assert text_at(html, "[data-event]") =~ "Few records"
    assert text_at(html, "[data-event]") =~ "Limited latitude coverage"
    assert text_at(html, "details") =~ "middle 50%"
    assert text_at(html, "details") =~ "Middle 80%"
    assert text_at(html, "details") =~ "median"
    assert text_at(html, "details") =~ "Anchor record"

    for input <- [predictions, Enum.reverse(predictions)] do
      ordered =
        render_component(&PhenologyComponents.prediction_results/1, predictions: input)
        |> LazyHTML.from_document()

      assert ordered |> LazyHTML.query("[data-event]") |> LazyHTML.attribute("data-event") ==
               ["onset", "rearing", "emergence"]

      assert ordered |> LazyHTML.query("details .font-medium") |> Enum.map(&LazyHTML.text/1) ==
               [
                 "Fresh gall onset · Agamic generation",
                 "Viable collections · Agamic generation",
                 "Adult emergence · Agamic generation"
               ]
    end
  end

  test "generation headings group answers without changing their dates" do
    records =
      for name <- ["Example (agamic)", "Example (sexgen)", "Example"] do
        %{developing(196) | species_name: name}
      end

    {:ok, predictions} = Phenology.predict(records, 30, [:onset])
    html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)

    for {generation, label} <- [
          agamic: "Agamic generation",
          sexgen: "Sexual generation",
          unknown: "Generation unspecified"
        ] do
      assert html =~ label
      assert text_at(html, "[data-generation='#{generation}'] strong") == "Jul 15"
    end

    empty = render_component(&PhenologyComponents.prediction_results/1, predictions: [])
    refute empty =~ "<details"
    refute empty =~ "data-event"
  end

  defp text_at(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  test "warnings distinguish few records, narrow latitude coverage and extrapolation" do
    narrow = Enum.map(150..160, &developing(&1))
    {:ok, predictions} = Phenology.predict(narrow, 30, [:onset])
    html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
    assert html =~ "Limited latitude coverage (30.0°N)"
    refute html =~ "Few records"
    refute html =~ "Extrapolation:"
    refute html =~ "geographic cells"

    broad = Enum.map(30..45, &developing(150, &1))
    {:ok, predictions} = Phenology.predict(broad, 40, [:onset])
    html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
    refute html =~ "Limited latitude coverage"
    refute html =~ "Few records"
    refute html =~ "Extrapolation:"

    {:ok, predictions} = Phenology.predict(broad, 50, [:onset])
    html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
    assert html =~ "Extrapolation: 50.0°N is outside the recorded range"
    assert html =~ "(30.0°N–45.0°N)"
  end

  test "coverage disclosures respect the five-record and two-degree thresholds" do
    for count <- [4, 5] do
      records = Enum.map(1..count, &developing(150, 29 + &1))
      {:ok, predictions} = Phenology.predict(records, 30, [:onset])
      html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
      assert String.contains?(html, "Few records") == count < 5
    end

    for span <- [1.9, 2.0] do
      records = [developing(150, 30), developing(160, 30 + span)]
      {:ok, predictions} = Phenology.predict(records, 31, [:onset])
      html = render_component(&PhenologyComponents.prediction_results/1, predictions: predictions)
      assert String.contains?(html, "Limited latitude coverage") == span < 2
    end
  end
end
