defmodule GallformersWeb.DesignSystem.Conformance do
  @moduledoc """
  Finds styling that bypasses the design system, so it can only shrink.

  The design system (docs/design-system/) styles through semantic tokens and
  components. This module scans templates and stylesheets for the things it
  replaces: Tailwind's raw palette and type scale, off-system radii and
  shadows, arbitrary values, `dark:` variants, inline styles and hex colors.

  A ratchet keeps it honest. `counts/0` tallies findings per file and rule;
  the baseline (`#{"test/support/design_system_baseline.json"}`) records the
  tallies the code had when it was locked in. The conformance test fails when
  a file goes over its baseline (new off-system styling) and when it goes
  under (an improvement that should be locked in with
  `mix gallformers.design_system.baseline`).
  """

  @baseline_path "test/support/design_system_baseline.json"

  @template_globs ["lib/gallformers_web/**/*.ex", "lib/gallformers_web/**/*.heex"]
  # Stylesheets other than the token file, which is where hex values belong.
  @css_globs ["assets/css/**/*.css"]
  @css_exempt ["assets/css/system/tokens.css"]

  @palette ~w(gray slate zinc neutral stone red orange amber yellow lime green emerald teal
              cyan sky blue indigo violet purple fuchsia pink rose)
  @legacy_palette ~w(gf-maroon gf-sky-blue gf-autumn gf-cream cadet-blue canary independence
                     new-york-pink persian-orange table-header table-selected)
  @color_props ~w(text bg border border-t border-b border-l border-r border-x border-y ring
                  outline divide fill stroke from via to placeholder decoration accent caret)

  # A class token may carry variants (hover:, md:, group-hover: …) before it.
  @variants "(?:[a-z0-9-]+:)*"
  @start "(?<![\\w-])"

  @rules [
    palette_color: [
      pattern:
        ~r/#{@start}#{@variants}(?:#{Enum.join(@color_props, "|")})-(?:(?:#{Enum.join(@palette, "|")})-\d{2,3}|black|white)(?:\/\d+)?(?![\w-])/,
      hint:
        "Use a semantic color: text-ink / text-ink-2 / text-muted, bg-paper / bg-surface / " <>
          "bg-surface-2, border-line / border-line-strong, text-on-fill, and the state pairs " <>
          "text-ok bg-ok-bg (also warn, danger, info)."
    ],
    legacy_palette: [
      pattern:
        ~r/#{@start}#{@variants}(?:#{Enum.join(@color_props, "|")})-(?:#{Enum.join(@legacy_palette, "|")})(?:\/\d+)?(?![\w-])/,
      hint:
        "Use the semantic brand colors: text-brand, bg-brand-fill, bg-sky, bg-sky-soft, text-autumn."
    ],
    type_scale: [
      pattern: ~r/#{@start}#{@variants}text-(?:xs|sm|base|lg|xl|[2-9]xl)(?![\w-])/,
      hint:
        "Use the semantic sizes: text-page, text-section, text-subsection, text-lead, " <>
          "text-body, text-ui, text-meta, text-caption."
    ],
    radius: [
      pattern:
        ~r/#{@start}#{@variants}rounded(?:-(?:t|b|l|r|s|e|tl|tr|bl|br|ss|se|es|ee))?(?:-(?:none|xs|sm|md|lg|xl|2xl|3xl))?(?![\w-])/,
      hint: "Use rounded-ctl (controls, chips), rounded-panel (panels, images) or rounded-full."
    ],
    shadow: [
      pattern: ~r/#{@start}#{@variants}shadow(?:-(?:2xs|xs|sm|md|lg|xl|2xl|inner))?(?![\w-])/,
      hint: "Only floating things (menus, dialogs, toasts) cast a shadow: shadow-float."
    ],
    arbitrary_value: [
      pattern: ~r/#{@start}#{@variants}-?[a-z][a-z0-9-]*-\[[^\]\s"]+\]/,
      hint: "Use a token. If none fits, propose one in docs/design-system/foundations.md first."
    ],
    dark_variant: [
      pattern: ~r/#{@start}dark:/,
      hint: "Don't use dark: variants. The tokens switch themselves between light and dark."
    ],
    inline_style: [
      pattern: ~r/#{@start}style=/,
      hint:
        "Use classes. A computed value (a progress width) belongs inside a documented component."
    ],
    hex_color: [
      pattern: ~r/#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![0-9a-zA-Z_-])/,
      hint: "Colors come from tokens in assets/css/system/tokens.css."
    ]
  ]

  @css_rules [:hex_color]

  @typedoc "One piece of off-system styling."
  @type finding :: %{rule: atom(), line: pos_integer(), match: String.t()}

  @typedoc ~S|Findings per file, per rule: %{"lib/…/x.ex" => %{"radius" => 3}}.|
  @type counts :: %{String.t() => %{String.t() => pos_integer()}}

  @doc "Scans template text and returns every finding, in order."
  @spec scan(String.t(), [atom()] | :all) :: [finding()]
  def scan(text, only \\ :all) do
    rules = if only == :all, do: @rules, else: Keyword.take(@rules, only)

    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line_text, line} ->
      for {rule, opts} <- rules,
          [match] <- Regex.scan(opts[:pattern], line_text),
          counts_as?(rule, match),
          do: %{rule: rule, line: line, match: match}
    end)
    |> Enum.sort_by(&{&1.line, &1.rule})
  end

  # "#123" is an issue number, not a color: a hex color has a letter or six digits.
  defp counts_as?(:hex_color, "#" <> hex),
    do: String.match?(hex, ~r/[a-fA-F]/) or String.length(hex) >= 6

  defp counts_as?(_rule, _match), do: true

  @doc "Tallies findings per file and rule across the templates and stylesheets."
  @spec counts(Path.t()) :: counts()
  def counts(root \\ File.cwd!()) do
    template_counts = tally(root, @template_globs, :all)
    css_counts = tally(root, @css_globs, @css_rules, @css_exempt)
    Map.merge(template_counts, css_counts)
  end

  defp tally(root, globs, only, exempt \\ []) do
    globs
    |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.reject(&(&1 in exempt))
    |> Enum.reduce(%{}, fn file, acc ->
      by_rule =
        root
        |> Path.join(file)
        |> File.read!()
        |> scan(only)
        |> Enum.frequencies_by(&Atom.to_string(&1.rule))

      if by_rule == %{}, do: acc, else: Map.put(acc, file, by_rule)
    end)
  end

  @doc "Reads the locked-in baseline."
  @spec read_baseline(Path.t()) :: counts()
  def read_baseline(root \\ File.cwd!()) do
    path = Path.join(root, @baseline_path)
    if File.exists?(path), do: path |> File.read!() |> Jason.decode!(), else: %{}
  end

  @doc "Writes the current counts as the baseline. Returns the path written."
  @spec write_baseline(Path.t()) :: Path.t()
  def write_baseline(root \\ File.cwd!()) do
    path = Path.join(root, @baseline_path)
    json = root |> counts() |> sorted() |> Jason.encode_to_iodata!(pretty: true)
    File.write!(path, [json, "\n"])
    path
  end

  # Jason.OrderedObject keeps files and rules alphabetical, so diffs stay readable.
  defp sorted(counts) do
    counts
    |> Enum.sort()
    |> Enum.map(fn {file, rules} -> {file, Jason.OrderedObject.new(Enum.sort(rules))} end)
    |> Jason.OrderedObject.new()
  end

  @doc """
  Explains files that went over their baseline: each new finding with its
  line and the system's replacement.
  """
  @spec explain([{String.t(), String.t(), pos_integer(), non_neg_integer()}]) :: String.t()
  def explain([]), do: ""

  def explain(worse) do
    sections =
      Enum.map(worse, fn {file, rule, count, allowed} ->
        rule_atom = String.to_existing_atom(rule)
        only = if String.ends_with?(file, ".css"), do: @css_rules, else: [rule_atom]

        lines =
          File.read!(file)
          |> scan(only)
          |> Enum.filter(&(&1.rule == rule_atom))
          |> Enum.map_join("\n", &"      line #{&1.line}: #{&1.match}")

        """
          #{file}: #{rule} #{count} (baseline #{allowed})
        #{lines}
            → #{@rules[rule_atom][:hint]}
        """
      end)

    """
    New styling bypasses the design system (docs/design-system/).

    #{Enum.join(sections, "\n")}
    If the new code is right and the system lacks what it needs, extend the
    system first (tokens or a documented component), then use it.
    """
  end
end
