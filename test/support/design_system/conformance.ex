defmodule GallformersWeb.DesignSystem.Conformance do
  @moduledoc """
  Finds styling that bypasses the design system, so it can only shrink.

  The design system (docs/design-system/) styles through semantic tokens and
  components. This ratchet scans templates and stylesheets for the things it
  replaces: Tailwind's raw palette and type scale, off-system radii and
  shadows, arbitrary values, `dark:` variants, inline styles, hex colors and
  all-caps text.

  It is a `Heartwood.Guardrails.Patterns` ratchet: counts per file and rule,
  against the baseline `test/support/design_system_baseline.json`. The test
  fails when a file goes over its baseline (new off-system styling) and when
  it goes under (an improvement to lock in with
  `mix heartwood.baseline GallformersWeb.DesignSystem.Conformance`).
  """
  use Heartwood.Guardrails.Patterns

  @templates ["lib/gallformers_web/**/*.ex", "lib/gallformers_web/**/*.heex"]
  @css ["assets/css/**/*.css"]

  @palette ~w(gray slate zinc neutral stone red orange amber yellow lime green emerald teal
              cyan sky blue indigo violet purple fuchsia pink rose)
  @legacy_palette ~w(gf-maroon gf-sky-blue gf-autumn gf-cream cadet-blue canary independence
                     new-york-pink persian-orange table-header table-selected)
  @color_props ~w(text bg border border-t border-b border-l border-r border-x border-y ring
                  outline divide fill stroke from via to placeholder decoration accent caret)

  # A class token may carry variants (hover:, md:, group-hover: …) before it.
  @variants "(?:[a-z0-9-]+:)*"
  @start "(?<![\\w-])"

  @impl Heartwood.Guardrails.Ratchet
  def subject, do: "off-system styling"

  @impl Heartwood.Guardrails.Ratchet
  def baseline_path, do: "test/support/design_system_baseline.json"

  @impl Heartwood.Guardrails.Patterns
  def intro, do: "New styling bypasses the design system (docs/design-system/)."

  @impl Heartwood.Guardrails.Patterns
  def outro,
    do:
      "If the new code is right and the system lacks what it needs, extend the\n" <>
        "system first (tokens or a documented component), then use it."

  @impl Heartwood.Guardrails.Patterns
  def rules do
    [
      [
        name: :palette_color,
        files: @templates,
        pattern:
          ~r/#{@start}#{@variants}(?:#{Enum.join(@color_props, "|")})-(?:(?:#{Enum.join(@palette, "|")})-\d{2,3}|black|white)(?:\/\d+)?(?![\w-])/,
        hint:
          "Use a semantic color: text-ink / text-ink-2 / text-muted, bg-paper / bg-surface / " <>
            "bg-surface-2, border-line / border-line-strong, text-on-fill, and the state pairs " <>
            "text-ok bg-ok-bg (also warn, danger, info)."
      ],
      [
        name: :legacy_palette,
        files: @templates,
        pattern:
          ~r/#{@start}#{@variants}(?:#{Enum.join(@color_props, "|")})-(?:#{Enum.join(@legacy_palette, "|")})(?:\/\d+)?(?![\w-])/,
        hint:
          "Use the semantic brand colors: text-brand, bg-brand-fill, bg-sky, bg-sky-soft, text-autumn."
      ],
      [
        name: :type_scale,
        files: @templates,
        pattern: ~r/#{@start}#{@variants}text-(?:xs|sm|base|lg|xl|[2-9]xl)(?![\w-])/,
        hint:
          "Use the semantic sizes: text-page, text-section, text-subsection, text-lead, " <>
            "text-body, text-ui, text-meta, text-caption."
      ],
      [
        name: :radius,
        files: @templates,
        pattern:
          ~r/#{@start}#{@variants}rounded(?:-(?:t|b|l|r|s|e|tl|tr|bl|br|ss|se|es|ee))?(?:-(?:none|xs|sm|md|lg|xl|2xl|3xl))?(?![\w-])/,
        hint: "Use rounded-ctl (controls, chips), rounded-panel (panels, images) or rounded-full."
      ],
      [
        name: :shadow,
        files: @templates,
        pattern: ~r/#{@start}#{@variants}shadow(?:-(?:2xs|xs|sm|md|lg|xl|2xl|inner))?(?![\w-])/,
        hint: "Only floating things (menus, dialogs, toasts) cast a shadow: shadow-float."
      ],
      [
        name: :arbitrary_value,
        files: @templates,
        pattern: ~r/#{@start}#{@variants}-?[a-z][a-z0-9-]*-\[[^\]\s"]+\]/,
        hint: "Use a token. If none fits, propose one in docs/design-system/foundations.md first."
      ],
      [
        name: :dark_variant,
        files: @templates,
        pattern: ~r/#{@start}dark:/,
        hint: "Don't use dark: variants. The tokens switch themselves between light and dark."
      ],
      [
        name: :inline_style,
        files: @templates,
        pattern: ~r/#{@start}style=/,
        hint:
          "Use classes. A computed value (a progress width) belongs inside a documented component."
      ],
      [
        name: :hex_color,
        files: @templates ++ @css,
        # The token file is where hex values belong.
        exempt: ["assets/css/system/tokens.css"],
        pattern: ~r/#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![0-9a-zA-Z_-])/,
        # "#123" is an issue number, not a color: a hex color has a letter or six digits.
        filter: fn "#" <> hex -> String.match?(hex, ~r/[a-fA-F]/) or String.length(hex) >= 6 end,
        hint: "Colors come from tokens in assets/css/system/tokens.css."
      ],
      [
        # Matches the class and the CSS value alike (`text-transform: uppercase`).
        name: :letter_case,
        files: @templates ++ @css,
        exempt: ["assets/css/system/tokens.css"],
        pattern: ~r/#{@start}#{@variants}(?:uppercase|tracking-(?:wide|wider|widest))(?![\w-])/,
        hint:
          "Text is in sentence case, labels too: a label is text-meta text-muted, like " <>
            "fact_list's. A small label over a heading is an eyebrow; delete it."
      ]
    ]
  end
end
