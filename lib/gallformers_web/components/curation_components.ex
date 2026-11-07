defmodule GallformersWeb.CurationComponents do
  @moduledoc """
  Inline editing (design system, matters bc0d and ec2c): `edit_toggle`,
  `edit_scope`, `fact_row`, `fact_chip`, `change_tray` and `review_apply`.

  They take data in the change-set contract's shapes (`Gallformers.Curation`,
  matter ec2c): items with their display text and flags, each flag
  `%{kind: atom, text: String.t()}` with its words from the back end. Their
  events go to the page (or the tray's LiveView): `fact_action`,
  `tray_review`, `tray_discard`, `remove_item`, `apply_item`, `apply_all`,
  `toggle_confirm`, `set_evidence`. Fact keys travel as strings
  (`GallformersWeb.FactKey`).
  """
  use Phoenix.Component

  import GallformersWeb.ActionComponents, only: [button: 1]
  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.DataComponents, only: [chip: 1]
  import GallformersWeb.FormComponents, only: [typeahead: 1]

  alias GallformersWeb.FactKey

  @doc """
  Edit mode's switch in a page header: "Edit" (off) or "Editing · Done"
  (on), a link to the page with `?edit` or without it. Admins only (the
  page decides).
  """
  attr :editing, :boolean, required: true
  attr :path, :string, required: true, doc: "the page's path, without ?edit"

  def edit_toggle(assigns) do
    ~H"""
    <.link
      patch={if @editing, do: @path, else: @path <> "?edit"}
      aria-pressed={to_string(@editing)}
      class={[
        "inline-flex h-8 items-center gap-1.5 rounded-ctl border px-2.5 text-meta font-semibold hover:no-underline",
        if(@editing,
          do: "border-brand-fill bg-brand-fill text-on-fill",
          else: "border-line-strong bg-surface text-ink-2 hover:border-brand"
        )
      ]}
    >
      <.icon name="ph-pencil-simple" class="size-4" />
      {if @editing, do: "Editing · Done", else: "Edit"}
    </.link>
    """
  end

  @doc """
  With Edit on, what isn't edited here: `:elsewhere` (edited on another
  page: says where, with Open ↗ to `href`) or `:follows` (follows from other
  data: says from what).
  """
  attr :kind, :atom, required: true, values: [:elsewhere, :follows]
  attr :href, :string, default: nil
  attr :class, :any, default: nil, doc: "layout only"
  slot :inner_block, required: true

  def edit_scope(assigns) do
    ~H"""
    <p
      data-scope={@kind}
      class={[
        "flex items-baseline gap-1.5 text-meta",
        if(@kind == :follows, do: "text-muted", else: "text-ink-2"),
        @class
      ]}
    >
      <.icon
        name={if @kind == :follows, do: "ph-info", else: "ph-arrow-square-out"}
        class="size-3.5 shrink-0 translate-y-0.5"
      />
      <span>
        {render_slot(@inner_block)}<.link :if={@href} href={@href} class="ml-1">Open ↗</.link>
      </span>
    </p>
    """
  end

  @doc """
  One Fact with Edit on, in a list: what it says (the inner block), the
  Sources stating it, and its actions (`:withdraw`, `:correct`, `:note`),
  each sending `fact_action` with its action and key. Once in the tray
  (`pending`: `%{action, state: :in_tray | :waiting}`) it is marked, struck
  through when withdrawn, and has no actions.
  """
  attr :fact_key, :any, required: true, doc: "the Fact's key (`GallformersWeb.FactKey`)"
  attr :sources, :list, default: []
  attr :actions, :list, default: [:withdraw, :correct, :note]
  attr :pending, :map, default: nil
  attr :target, :any, default: nil, doc: "phx-target for the actions (a LiveComponent's)"
  slot :inner_block, required: true

  def fact_row(assigns) do
    assigns = assign(assigns, :key, FactKey.encode(assigns.fact_key))

    ~H"""
    <li
      id={"fact-" <> String.replace(@key, ~r/[^a-zA-Z0-9]+/, "-")}
      class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5"
    >
      <span
        data-part="fact"
        class={["text-ui", @pending && @pending.action == :withdraw && "text-muted line-through"]}
      >
        {render_slot(@inner_block)}
      </span>
      <span data-part="sources" class="min-w-0 flex-1 truncate text-meta text-muted">
        {Enum.join(@sources, " · ")}
      </span>
      <span :if={@pending} data-part="pending">
        <.chip variant={:info} size="sm">{pending_word(@pending.state)}</.chip>
      </span>
      <span :if={!@pending} class="flex gap-1">
        <.button
          :for={action <- @actions}
          variant="ghost"
          size="sm"
          phx-click="fact_action"
          phx-value-action={action}
          phx-value-key={@key}
          phx-target={@target}
        >
          {action_label(action)}
        </.button>
      </span>
    </li>
    """
  end

  @doc """
  One value of a Trait with Edit on, as a chip: the value (the inner
  block), its Sources as its title, and ✕ to withdraw it (`fact_action`,
  action `withdraw`). In the tray (`pending`: `%{action, state}`) it has no
  ✕: struck through when withdrawn, marked (`data-pending`) when added.
  """
  attr :fact_key, :any, required: true, doc: "the Fact's key (`GallformersWeb.FactKey`)"
  attr :sources, :list, default: []
  attr :pending, :map, default: nil
  attr :target, :any, default: nil, doc: "phx-target for ✕ (a LiveComponent's)"
  slot :inner_block, required: true

  def fact_chip(assigns) do
    assigns = assign(assigns, :key, FactKey.encode(assigns.fact_key))

    ~H"""
    <span
      id={"fact-" <> String.replace(@key, ~r/[^a-zA-Z0-9]+/, "-")}
      title={@sources != [] && Enum.join(@sources, " · ")}
      data-pending={@pending && to_string(@pending.action)}
      class={[
        "inline-flex items-center gap-1 rounded-ctl border px-2 py-0.5 text-ui",
        cond do
          @pending && @pending.action == :withdraw -> "border-line bg-surface text-muted line-through"
          @pending -> "border-ok bg-ok-bg text-ok"
          true -> "border-line bg-surface text-ink"
        end
      ]}
    >
      {render_slot(@inner_block)}
      <button
        :if={!@pending}
        type="button"
        phx-click="fact_action"
        phx-value-action="withdraw"
        phx-value-key={@key}
        phx-target={@target}
        aria-label="Withdraw"
        class="text-muted hover:text-danger"
      >
        <.icon name="ph-x" class="size-3" />
      </button>
    </span>
    """
  end

  defp pending_word(:waiting), do: "waiting to apply"
  defp pending_word(_), do: "in your tray"

  defp action_label(:withdraw), do: "Withdraw"
  defp action_label(:correct), do: "Correct…"
  defp action_label(:note), do: "Note…"

  @doc """
  The curator's tray, pinned at the foot of every page while it holds
  changes (`summary`: `%{count, lines, oldest_at}`): the count, the
  changes, Discard (`tray_discard`, confirmed by the page) and Review and
  apply (`tray_review`). Nothing when empty.
  """
  attr :summary, :map, default: nil

  def change_tray(assigns) do
    ~H"""
    <div
      :if={@summary && @summary.count > 0}
      id="change-tray"
      class="fixed inset-x-0 bottom-0 z-50 border-t border-line bg-surface shadow-float"
    >
      <div class="mx-auto flex max-w-page flex-wrap items-center gap-x-4 gap-y-2 px-page-x py-2.5">
        <span data-part="count" class="font-semibold text-ink">
          {@summary.count} {if @summary.count == 1, do: "change", else: "changes"} in your tray
        </span>
        <span data-part="lines" class="min-w-0 flex-1 truncate text-meta text-muted">
          {Enum.join(@summary.lines, " · ")}
        </span>
        <.button variant="ghost" size="sm" phx-click="tray_discard">Discard</.button>
        <.button variant="primary" size="sm" phx-click="tray_review">Review and apply</.button>
      </div>
    </div>
    """
  end

  @doc """
  Review and apply, the body of its dialog: each change with its flags (the
  back end's words), its confirmation box when it needs one, Apply for it
  alone (not while it needs a reason, is blocked, waits for confirmation or
  is already submitted) and Take out, and under it a Fact change's own
  evidence (its text, its observations as links, its Source); then the
  evidence for the Fact changes without their own (a reason,
  observations, a Source), not shown when every one has its own; then
  Apply all. `confirmed` lists the item ids the curator has confirmed.
  """
  attr :id, :string, required: true

  attr :items, :list,
    required: true,
    doc:
      "maps with `id`, `kind`, `text`, `flags`, optional `state` and `evidence` " <>
        "(the item's own: `%{text, observations, source}`, `source` `%{id, title}` or nil)"

  attr :evidence, :map, required: true, doc: "`%{text, observations, source_id}`"
  attr :confirmed, :list, default: []
  attr :source, :map, default: nil, doc: "the Source chosen as evidence: `%{id, title}`"
  attr :source_query, :string, default: ""
  attr :source_results, :list, default: [], doc: "Sources found by title: `%{id, title}`"

  def review_apply(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-section">
      <ul class="flex flex-col divide-y divide-line">
        <li :for={item <- @items} id={"#{@id}-item-#{item.id}"} class="flex flex-col gap-1.5 py-2">
          <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span data-part="text" class="min-w-0 flex-1 text-ui text-ink">{item.text}</span>
            <span :if={item[:state] == :waiting} data-part="state" class="text-meta text-muted">
              Waiting to apply
            </span>
            <.button
              variant="ghost"
              size="sm"
              phx-click="apply_item"
              phx-value-id={item.id}
              disabled={not appliable?(item, @confirmed)}
            >
              Apply
            </.button>
            <button
              type="button"
              phx-click="remove_item"
              phx-value-id={item.id}
              class="text-muted hover:text-danger"
              aria-label={"Take out: #{item.text}"}
            >
              <.icon name="ph-x" class="size-4" />
            </button>
          </div>
          <div class="flex flex-wrap items-center gap-1.5">
            <span
              :for={flag <- item.flags}
              data-flag={flag.kind}
              data-variant={flag_variant(flag.kind)}
            >
              <.chip variant={flag_variant(flag.kind)} size="sm">{flag.text}</.chip>
            </span>
            <label
              :if={needs?(item, :needs_confirmation)}
              class="flex items-center gap-1.5 text-meta text-ink-2"
            >
              <input
                type="checkbox"
                class="gf-checkbox"
                phx-click="toggle_confirm"
                phx-value-id={item.id}
                checked={item.id in @confirmed}
              /> I'm sure
            </label>
          </div>
          <div
            :if={item[:evidence]}
            data-part="evidence"
            class="flex flex-col gap-0.5 text-meta text-ink-2"
          >
            <span class="text-muted">Its own evidence</span>
            <span :if={item.evidence.text}>{item.evidence.text}</span>
            <span :if={item.evidence.observations != []} class="flex flex-wrap gap-x-3">
              <a
                :for={observation <- item.evidence.observations}
                href={observation_url(observation)}
                target="_blank"
                rel="noopener"
              >
                {observation_url(observation)}
              </a>
            </span>
            <span :if={item.evidence.source}>
              Source:
              <a href={"/source/#{item.evidence.source.id}"} target="_blank" rel="noopener">
                {item.evidence.source.title}
              </a>
            </span>
          </div>
        </li>
      </ul>

      <form
        :if={shared_evidence?(@items)}
        id={"#{@id}-evidence"}
        phx-change="set_evidence"
        class="flex flex-col gap-2"
      >
        <h3 class="text-subsection">Evidence for the Fact changes</h3>
        <p class="text-meta text-muted">
          Asked once, for the Fact changes without evidence of their own. A change that supersedes a Source needs a reason, an observation or a Source.
        </p>
        <label class="gf-label" for={"#{@id}-evidence-text"}>Why</label>
        <textarea
          id={"#{@id}-evidence-text"}
          name="evidence[text]"
          rows="2"
          class="gf-textarea max-w-xl"
        >{@evidence.text}</textarea>
        <label class="gf-label" for={"#{@id}-evidence-observations"}>Observations</label>
        <input
          id={"#{@id}-evidence-observations"}
          name="evidence[observations]"
          value={Enum.map_join(@evidence.observations, ", ", &observation_url/1)}
          placeholder="An iNaturalist or BugGuide observation's link"
          class="gf-input max-w-xl"
          autocomplete="off"
          phx-debounce="400"
        />
      </form>

      <.typeahead
        :if={shared_evidence?(@items)}
        id={"#{@id}-evidence-source"}
        label="A Source"
        placeholder="A Source's title"
        query={@source_query}
        results={@source_results}
        selected={@source}
        search_event="search_evidence_source"
        select_event="select_evidence_source"
        clear_event="clear_evidence_source"
        display_fn={& &1.title}
        class="max-w-xl"
      />

      <div class="flex justify-end">
        <.button variant="primary" phx-click="apply_all">
          Apply {length(@items)} {if length(@items) == 1, do: "change", else: "changes"}
        </.button>
      </div>
    </div>
    """
  end

  defp observation_url(%{provider: "bugguide", id: id}),
    do: "https://bugguide.net/node/view/#{id}"

  defp observation_url(%{id: id}), do: "https://www.inaturalist.org/observations/#{id}"

  # The set's evidence is asked while a Fact item has none of its own.
  defp shared_evidence?(items),
    do: Enum.any?(items, &(&1.kind == :fact and is_nil(&1[:evidence])))

  defp needs?(item, kind), do: Enum.any?(item.flags, &(&1.kind == kind))

  defp appliable?(item, confirmed) do
    item[:state] != :waiting and not needs?(item, :needs_reason) and not needs?(item, :blocked) and
      (not needs?(item, :needs_confirmation) or item.id in confirmed)
  end

  defp flag_variant(:new), do: :ok
  defp flag_variant(:held), do: :neutral
  defp flag_variant(:supersedes), do: :warn
  defp flag_variant(:changed_since), do: :warn
  defp flag_variant(:needs_confirmation), do: :warn
  defp flag_variant(:editorial), do: :info
  defp flag_variant(:adds_statement), do: :info
  defp flag_variant(:needs_reason), do: :danger
  defp flag_variant(:blocked), do: :danger
  defp flag_variant(_), do: :neutral
end
