defmodule GallformersWeb.DesignSystem.ConformanceTest do
  use ExUnit.Case, async: true

  alias GallformersWeb.DesignSystem.Conformance

  defp rules(text), do: text |> Conformance.scan() |> Enum.map(& &1.rule) |> Enum.sort()

  describe "scan/1" do
    test "a template on the system has no findings" do
      text = ~S"""
      <div class="bg-surface text-ink border border-line rounded-panel p-panel">
        <h2 class="text-section">Hosts</h2>
        <p class="text-meta text-muted">14 recorded</p>
        <span class="shadow-float rounded-ctl rounded-full shadow-none">x</span>
      </div>
      """

      assert Conformance.scan(text) == []
    end

    test "flags Tailwind palette colors, black and white" do
      assert rules(~S(<p class="text-gray-500 hover:bg-blue-50 border-red-200/50">)) ==
               [:palette_color, :palette_color, :palette_color]

      assert rules(~S(<p class="bg-white text-black">)) == [:palette_color, :palette_color]
    end

    test "flags the legacy brand palette" do
      assert rules(~S(<p class="text-gf-maroon bg-gf-sky-blue bg-cadet-blue">)) ==
               [:legacy_palette, :legacy_palette, :legacy_palette]
    end

    test "flags the default type scale but not the semantic sizes" do
      assert rules(~S(<p class="text-sm md:text-2xl text-body text-caption">)) ==
               [:type_scale, :type_scale]
    end

    test "flags off-system radii and shadows" do
      assert rules(~S(<p class="rounded rounded-lg rounded-t-md shadow shadow-md">)) ==
               [:radius, :radius, :radius, :shadow, :shadow]
    end

    test "flags arbitrary values, dark variants and inline styles" do
      assert rules(~S(<p class="top-[78px] dark:bg-surface" style="width: 3px">)) ==
               [:arbitrary_value, :dark_variant, :inline_style]
    end

    test "flags all-caps and tracked-out text but not tight tracking" do
      assert rules(~S(<dt class="uppercase tracking-wide md:tracking-wider tracking-tight">)) ==
               [:letter_case, :letter_case, :letter_case]

      assert rules(".gf-x { text-transform: uppercase; }") == [:letter_case]
    end

    test "flags hex colors but not issue numbers or anchors" do
      assert rules(~S(<p data-c="#661419" data-d="#fff">see #123 and #top</p>)) ==
               [:hex_color, :hex_color]
    end

    test "reports the line of each finding" do
      [finding] = Conformance.scan("<div>\n  <p class=\"text-gray-500\">\n</div>")
      assert finding.line == 2
      assert finding.match == "text-gray-500"
    end
  end

  describe "the codebase" do
    test "no file has more off-system styling than its baseline" do
      current = Conformance.counts()
      baseline = Conformance.read_baseline()

      worse =
        for {file, rules} <- current,
            {rule, count} <- rules,
            allowed = get_in(baseline, [file, rule]) || 0,
            count > allowed,
            do: {file, rule, count, allowed}

      assert worse == [], Conformance.explain(worse)
    end

    test "the baseline is tight: improvements are locked in" do
      current = Conformance.counts()
      baseline = Conformance.read_baseline()

      loose =
        for {file, rules} <- baseline,
            {rule, count} <- rules,
            (get_in(current, [file, rule]) || 0) < count,
            do: {file, rule}

      assert loose == [],
             "Off-system styling went down in #{length(loose)} place(s). Lock it in with:\n\n" <>
               "    mix gallformers.design_system.baseline\n"
    end
  end
end
