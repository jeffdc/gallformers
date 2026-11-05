defmodule GallformersWeb.ReviewComponents do
  @moduledoc """
  The pieces of the import review pages (`6611` Task 6, after the approved
  design `docs/plans/review-redesign.html`; the steps and the question
  layout after matter `d213`, Tasks 15 and 16): the step bar on every page
  of a Source, the overview of its steps and a step page's head; a section
  card of questions with its count, what leaving them means and a bulk
  action; a question's row, a button that opens it, and its parts when
  open (the question and its scope, the Source's quotes, the options as
  radio cards with their follow-up input, the Decide bar, the notes, and
  disclosures for details); progress; the two readers' cases and the
  definitions in play; a Trait term's Galls; and the tucked-away technical
  details. What an answer shows besides (Names and Galls steps): a taxon's
  identity line and whether it holds the Source's name, a Host's WCVP
  panel, a candidate Gall's side-by-side comparison, and small radio
  choices for a follow-up (a statement to keep or leave out; a Gall's
  value, the recommended one marked); a Trait's values to choose from,
  each defined (Traits step). `review_row/1` is the older compact row with actions, which the
  vocabulary page uses.

  Built from the site's styles (`gf-card`, `gf-badge`, Tailwind) and the
  core components; the review LiveViews (`GallformersWeb.Admin.ReviewLive`)
  use them.
  """
  use Phoenix.Component
  use GallformersWeb, :verified_routes

  import GallformersWeb.CoreComponents, only: [badge: 1, button: 1, chip: 1, icon: 1]
  import GallformersWeb.FormComponents, only: [search_input: 1]

  # The question row's columns: the chevron, the Source's words, an arrow,
  # the answer (the design's `.item-row`).
  @question_cols "md:grid-cols-[1.1rem_minmax(12rem,1.2fr)_1.4rem_minmax(12rem,1.5fr)]"

  @doc """
  A section of questions: a card whose header (title, count, explanation,
  what holds approval) opens and closes it on a click, as its chevron
  shows, with an optional bulk action in the header, an optional
  confirmation strip under it, and the rows.

  `on_toggle` is the click on the header (an event name or `JS`), with
  `phx-value-section` set to `section`.
  """
  attr :id, :string, required: true
  attr :section, :string, required: true, doc: "the section's id, sent with on_toggle"
  attr :title, :string, required: true
  attr :count, :string, required: true, doc: "what is left, e.g. \"· 3 to decide\""
  attr :explanation, :string, default: nil

  attr :holds, :string,
    default: nil,
    doc: "what leaving its questions open holds; nil shows nothing"

  attr :holds_approval, :boolean, default: false
  attr :done, :boolean, default: false, doc: "every question decided"
  attr :closed, :boolean, default: false
  attr :on_toggle, :any, required: true

  attr :layout, :atom,
    default: :row,
    values: [:row, :question, :none],
    doc:
      "the column heads over the rows: `:row` for `review_row/1`, `:question` for " <>
        "`review_question_row/1`, `:none` for none"

  slot :actions, doc: "a bulk action in the header"
  slot :confirm, doc: "an inline confirmation under the header"
  slot :inner_block, required: true, doc: "the rows"

  def review_section(assigns) do
    assigns = assign(assigns, question_cols: @question_cols)

    ~H"""
    <section id={@id} class="gf-card mt-4 overflow-hidden">
      <div
        class="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-2.5 border-b border-gray-200 cursor-pointer"
        phx-click={@on_toggle}
        phx-value-section={@section}
        data-role="section-head"
      >
        <.icon
          name="ph-caret-down"
          class={["size-4 text-gray-500 transition-transform", @closed && "-rotate-90"]}
        />
        <div class="flex-1 min-w-[16rem]">
          <h2 class="text-lg font-semibold text-gray-900">
            {@title} <span class="font-medium text-gray-500 tabular-nums">{@count}</span>
          </h2>
          <p :if={@explanation} class="text-sm text-gray-500">{@explanation}</p>
        </div>
        <%= cond do %>
          <% @done -> %>
            <.badge variant="success">Done</.badge>
          <% @holds_approval -> %>
            <.badge variant="warning">{@holds}</.badge>
          <% @holds -> %>
            <.review_tag>{@holds}</.review_tag>
          <% true -> %>
        <% end %>
        {render_slot(@actions)}
      </div>
      <div :if={!@closed and @confirm != []}>{render_slot(@confirm)}</div>
      <div
        :if={!@closed and @layout == :row}
        data-role="columns"
        class="hidden md:grid md:grid-cols-[minmax(10rem,1.1fr)_1.4rem_minmax(12rem,1.6fr)_auto] gap-x-3 px-4 py-1 bg-gray-50 border-b border-gray-200 text-xs font-semibold uppercase tracking-wide text-gray-500"
      >
        <span>The Source wrote</span>
        <span aria-hidden="true"></span>
        <span>Gallformers proposes</span>
        <span></span>
      </div>
      <div
        :if={!@closed and @layout == :question}
        data-role="columns"
        class={[
          "hidden md:grid gap-x-3 px-4 py-1 bg-gray-50 border-b border-gray-200",
          "text-xs font-semibold uppercase tracking-wide text-gray-500",
          @question_cols
        ]}
      >
        <span aria-hidden="true"></span>
        <span>The Source wrote</span>
        <span aria-hidden="true"></span>
        <span>Answer</span>
      </div>
      <div :if={!@closed} class="divide-y divide-gray-200">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  @doc """
  A compact, expandable row: the Source's words, an arrow, the answer and
  the actions on one line, opening and closing on a click anywhere on it
  (the actions' own clicks stay theirs), with its detail under it when
  open. `on_toggle` is the row's click (an event name or `JS`);
  `target` its `phx-target`.
  """
  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :decided, :boolean, default: false
  attr :on_toggle, :any, default: nil
  attr :target, :any, default: nil

  slot :written, required: true, doc: "the Source's words, with a line of context"
  slot :answer, required: true, doc: "the proposed answer, or what there is instead"
  slot :actions, doc: "Accept, Reject, Decide…"
  slot :detail, doc: "shown under the row when open"
  slot :inner_block, doc: "shown under the row whether open or not (an error, say)"

  def review_row(assigns) do
    ~H"""
    <div id={@id} class={[@decided && "opacity-75"]}>
      <div
        id={"#{@id}-row"}
        class={[
          "grid grid-cols-1 md:grid-cols-[minmax(10rem,1.1fr)_1.4rem_minmax(12rem,1.6fr)_auto]",
          "items-center gap-x-3 gap-y-1 px-4 py-2 hover:bg-gray-50",
          @on_toggle && "cursor-pointer"
        ]}
        phx-click={@on_toggle}
        phx-target={@target}
        data-role="row"
      >
        <div class="font-semibold text-gray-900 break-words">{render_slot(@written)}</div>
        <div class="hidden md:block text-center text-gray-400" aria-hidden="true">→</div>
        <div class="min-w-0">{render_slot(@answer)}</div>
        <div class="flex flex-wrap gap-1.5 md:justify-end">{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
      <div
        :if={@open and @detail != []}
        id={"#{@id}-detail"}
        class="grid gap-3 px-4 pt-1 pb-4 bg-gray-50 border-t border-dashed border-gray-200"
      >
        {render_slot(@detail)}
      </div>
    </div>
    """
  end

  @doc "A plain tag, for what holds nothing (a section's badge, a Source's kind)."
  slot :inner_block, required: true

  def review_tag(assigns) do
    ~H"""
    <span class="gf-badge bg-gray-50 text-gray-600 border border-gray-200">
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  A quote from the Source, with where in it. The `passage` slot, when
  given, is the Source's passage around it (`review_passage/1`), behind
  "Show the passage" ("Hide the passage" once open; matter `d213`, Task 22).

  Where reading the passage is costly, the page can load it on request
  instead (the Facts page, matter `f14c`): with `on_passage` and no
  `passage` slot, "Show the passage" sends `on_passage` with
  `phx-value-key` set to `passage_key`; given the slot then, with
  `passage_open`, the passage shows open. A quote citing a whole item has
  no `text`.
  """
  attr :text, :string, default: nil, doc: "the quote; nil when it cites a whole item"
  attr :where, :string, default: nil
  attr :on_passage, :any, default: nil, doc: "loads the passage on request"
  attr :passage_key, :string, default: nil, doc: "sent with on_passage"
  attr :passage_open, :boolean, default: false
  slot :passage, doc: "the passage the quote sits in, shown on request"

  def review_quote(assigns) do
    ~H"""
    <blockquote class="bg-orange-50/60 border-l-4 border-gf-autumn rounded-r-md px-3 py-2 text-sm text-gray-700">
      <%= if @text do %>
        “{@text}”
      <% else %>
        <span class="italic text-gray-500">The whole passage</span>
      <% end %>
      <span :if={@where} class="block text-xs text-gray-500 mt-0.5">{@where}</span>
      <details
        :if={@passage != []}
        class="group mt-1 text-xs"
        data-role="passage"
        open={@passage_open}
      >
        <summary class="cursor-pointer text-gf-maroon">
          <span class="group-open:hidden">Show the passage</span>
          <span class="hidden group-open:inline">Hide the passage</span>
        </summary>
        <div class="mt-1 text-sm">{render_slot(@passage)}</div>
      </details>
      <button
        :if={@passage == [] and @on_passage != nil}
        type="button"
        class="block mt-1 text-xs text-gf-maroon hover:underline"
        data-role="show-passage"
        phx-click={@on_passage}
        phx-value-key={@passage_key}
      >
        Show the passage
      </button>
    </blockquote>
    """
  end

  @doc "How much is decided, and how much of the rest has a proposed answer, as a bar."
  attr :done, :integer, required: true
  attr :proposed, :integer, required: true
  attr :total, :integer, required: true
  attr :class, :any, default: nil

  def review_progress(assigns) do
    total = max(assigns.total, 1)

    assigns =
      assign(assigns,
        done_pct: Float.round(100 * assigns.done / total, 1),
        proposed_pct: Float.round(100 * assigns.proposed / total, 1)
      )

    ~H"""
    <div class={["flex h-1.5 rounded-full bg-gray-200 overflow-hidden", @class]} aria-hidden="true">
      <span class="block h-full bg-green-700" style={"width: #{@done_pct}%"}></span>
      <span class="block h-full bg-cadet-blue" style={"width: #{@proposed_pct}%"}></span>
    </div>
    """
  end

  @doc """
  What a Gallformers note adds, as chips, then what it set aside, muted
  (`GallformersWeb.Admin.ReviewLive.Notes.adds/2` and `set_aside/1`).
  """
  attr :adds, :list, required: true
  attr :aside, :list, default: []
  attr :class, :any, default: nil

  def review_chips(assigns) do
    ~H"""
    <div class={["flex flex-wrap gap-1", @class]}>
      <.chip :for={add <- @adds} size="sm"><span data-role="chip">{add}</span></.chip>
      <span :for={aside <- @aside} data-role="aside">
        <.review_tag>{aside}</.review_tag>
      </span>
    </div>
    """
  end

  @doc "A count in a Source's summary."
  attr :value, :any, required: true
  attr :label, :string, required: true

  def review_stat(assigns) do
    ~H"""
    <span class="bg-gray-50 border border-gray-200 rounded-md px-2.5 py-1 text-sm text-gray-700">
      <b class="tabular-nums text-gray-900">{@value}</b> {@label}
    </span>
    """
  end

  @doc """
  The producer's and the checker's cases, side by side: each one's
  position in a sentence (titled "The producer kept it", "A checker
  questioned it"), or the full arguments.
  """
  attr :id, :string, default: nil
  attr :checker, :list, default: []
  attr :producer, :list, default: []
  attr :producer_title, :string, default: "The producer"
  attr :checker_title, :string, default: "The checker"

  def review_voices(assigns) do
    ~H"""
    <div :if={@checker != [] or @producer != []} id={@id} class="grid md:grid-cols-2 gap-3">
      <div class="bg-white border border-gray-200 rounded-md px-3 py-2 text-sm text-gray-700">
        <h4 class="text-xs uppercase tracking-wider text-gray-500 mb-1">{@producer_title}</h4>
        <p :for={text <- @producer}>{text}</p>
      </div>
      <div class="bg-white border border-gray-200 rounded-md px-3 py-2 text-sm text-gray-700">
        <h4 class="text-xs uppercase tracking-wider text-gray-500 mb-1">{@checker_title}</h4>
        <p :for={text <- @checker}>{text}</p>
      </div>
    </div>
    """
  end

  @doc "The values in play, each with whose it is (if given) and its definition."
  attr :definitions, :list, required: true, doc: "`%{who, value, definition}` maps"

  def review_definitions(assigns) do
    ~H"""
    <div :if={@definitions != []} class="grid sm:grid-cols-2 gap-3" data-role="definitions">
      <div
        :for={d <- @definitions}
        class="bg-white border border-gray-200 rounded-md px-3 py-2 text-sm text-gray-700"
      >
        <span :if={d.who} class="text-xs uppercase tracking-wider text-gray-500">{d.who}</span>
        <b class="block text-gray-900">{d.value}</b>
        {d.definition}
      </div>
    </div>
    """
  end

  @doc """
  One Gall a Trait term's question covers: its name, the Source's quotes,
  what the producer and each checker said, and (the inner block) its
  category choice. The `passage` slot, given a quote (`:let`), is the
  passage that quote sits in (`review_quote/1`).
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :quotes, :list, default: [], doc: "`%{text, item}` maps"
  attr :said, :list, default: [], doc: "the readers' words, one line each"
  slot :inner_block, doc: "the Gall's category choice"
  slot :passage, doc: "a quote's passage, given the quote"

  def review_term_gall(assigns) do
    ~H"""
    <div
      id={@id}
      class="grid md:grid-cols-[minmax(12rem,2fr)_minmax(10rem,1fr)] gap-x-3 gap-y-2 bg-white border border-gray-200 rounded-md px-3 py-2"
    >
      <div class="grid gap-1.5 min-w-0">
        <b class="text-gray-900 break-words">{@name}</b>
        <.review_quote :for={quote <- @quotes} text={quote.text}>
          <:passage :if={@passage != []}>{render_slot(@passage, quote)}</:passage>
        </.review_quote>
        <ul class="text-sm text-gray-700 grid gap-0.5">
          <li :for={line <- @said}>{line}</li>
        </ul>
      </div>
      <div :if={@inner_block != []} class="grid content-start gap-1">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  A name several species hold, compared: what the Source says in the first
  row, then each candidate (`Gallformers.Import.candidate_comparison/1`)
  with the names it holds, its Galls' Hosts and its Galls.
  """
  attr :id, :string, required: true
  attr :source, :map, required: true, doc: "`%{who, written, quote}`: what the Source says"
  attr :candidates, :list, required: true

  def review_comparison(assigns) do
    ~H"""
    <div id={@id} data-role="comparison" class="overflow-x-auto">
      <table class="gf-table gf-table-compact bg-white">
        <thead>
          <tr>
            <th>Species</th>
            <th>Holds the name as</th>
            <th>Hosts in Gallformers</th>
            <th>Its Galls</th>
          </tr>
        </thead>
        <tbody>
          <tr class="bg-orange-50/60">
            <td><b>{@source.who}</b></td>
            <td>{@source.written}</td>
            <td></td>
            <td>{@source.quote && "“#{@source.quote}”"}</td>
          </tr>
          <tr :for={c <- @candidates}>
            <td>
              <a
                href={~p"/admin/taxonomy/#{c.taxon_id}"}
                class="italic text-gf-maroon hover:underline"
              >
                {c.name}
              </a>
              <span :if={c.authorship} class="text-gray-500">{c.authorship}</span>
            </td>
            <td>{c.names |> Enum.map(& &1.name) |> Enum.join(", ")}</td>
            <td>
              {c.galls
              |> Enum.flat_map(& &1.hosts)
              |> Enum.map(& &1.name)
              |> Enum.uniq()
              |> Enum.join(", ")}
            </td>
            <td>
              <a
                :for={gall <- c.galls}
                href={~p"/gall/#{gall.gall_id}"}
                class="block text-gf-maroon hover:underline"
              >
                {gall.name}
              </a>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc "Refs, method codes and the like, for debugging, tucked away."
  attr :text, :string, required: true

  def review_technical(assigns) do
    ~H"""
    <details class="text-xs text-gray-500">
      <summary class="cursor-pointer">Technical details</summary>
      <code class="text-xs">{@text}</code>
    </details>
    """
  end

  # -- what an answer shows besides (matter d213, Names and Galls steps) -------

  @doc """
  A taxon's or plant's identity line under its answer (matter `d213`,
  "Research burden"): its family, its Galls and their Hosts in Gallformers,
  and Open ↗ to its admin page in a new tab; the names it also holds under
  it. `identity` is `GallformersWeb.Admin.Review.Choice`'s: `%{family,
  galls, hosts, host_count, synonyms, path, held}`; a plant shows only
  that Gallformers holds it.
  """
  attr :identity, :map, required: true

  def review_identity(assigns) do
    ~H"""
    <span class="block text-sm text-gray-600" data-role="identity">
      <%= if @identity.galls do %>
        <span class="font-medium">{@identity.family || "Family not recorded"}</span>
        · {galls_text(@identity)}
      <% else %>
        <span :if={@identity.held}>In Gallformers</span>
      <% end %>
      <span :if={@identity.path}>
        ·
        <a
          href={@identity.path}
          target="_blank"
          rel="noopener"
          class="text-gf-maroon hover:underline"
          data-role="open"
        >
          Open ↗
        </a>
      </span>
    </span>
    <span
      :if={@identity.synonyms != []}
      class="block text-xs text-gray-500"
      data-role="also-holds"
    >
      Also holds: {also_holds(@identity.synonyms)}
    </span>
    """
  end

  defp also_holds(names) when length(names) > 4,
    do: Enum.join(Enum.take(names, 4), ", ") <> "…"

  defp also_holds(names), do: Enum.join(names, ", ")

  defp galls_text(%{galls: 0}), do: "No Galls in Gallformers"

  defp galls_text(%{galls: n, hosts: hosts, host_count: count}) do
    galls = "#{n} #{if n == 1, do: "Gall", else: "Galls"} in Gallformers"

    case hosts do
      [] ->
        galls

      _ when count > length(hosts) ->
        "#{galls}, on #{and_list(hosts)} and #{count - length(hosts)} more"

      _ ->
        "#{galls}, on #{and_list(hosts)}"
    end
  end

  @doc """
  Whether a taxon answer already holds the Source's name, in a line:
  `holding` is `%{kind: :yes | :near | :no, text}`.
  """
  attr :holding, :map, required: true

  def review_alias(assigns) do
    ~H"""
    <span
      class={[
        "block text-sm font-medium",
        case @holding.kind do
          :yes -> "text-green-800"
          :near -> "text-amber-800"
          :no -> "text-gray-600"
        end
      ]}
      data-role="alias"
      data-kind={@holding.kind}
    >
      {@holding.text}
    </span>
    """
  end

  @doc """
  What WCVP holds for a Host name (`Gallformers.Import.ReviewContext.host/2`):
  the name as written or its nearest spelling, its status and accepted name,
  and whether Gallformers holds that plant; with nothing in WCVP, links to
  search POWO and IPNI in a new tab, and (given `new_plant`) to create the
  plant (`review_new_plant/1`). `host` is nil while it is read.
  """
  attr :id, :string, required: true
  attr :written, :string, required: true
  attr :host, :map, default: nil

  attr :new_plant, :map,
    default: nil,
    doc: "the plant to create when WCVP has nothing (`review_new_plant/1`'s `prefill`)"

  def review_wcvp_panel(assigns) do
    ~H"""
    <div
      id={@id}
      data-role="wcvp"
      class="rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-gray-700"
    >
      <b>WCVP</b>
      <%= cond do %>
        <% @host == nil -> %>
          <span class="italic text-gray-500">is being looked up…</span>
        <% @host.wcvp == nil -> %>
          doesn't hold “{@written}” or a near spelling. Search the web:
          <a
            href={"https://powo.science.kew.org/results?q=#{URI.encode_www_form(@written)}"}
            target="_blank"
            rel="noopener"
            class="text-gf-maroon hover:underline"
          >
            POWO ↗
          </a>
          ·
          <a
            href={"https://www.ipni.org/?q=#{URI.encode_www_form(@written)}"}
            target="_blank"
            rel="noopener"
            class="text-gf-maroon hover:underline"
          >
            IPNI ↗
          </a>
          <.review_new_plant :if={@new_plant} id={"#{@id}-new-plant"} prefill={@new_plant} />
        <% true -> %>
          {wcvp_text(@host, @written)}
          <a
            :if={@host.held}
            href={~p"/admin/taxonomy/#{@host.held.taxon_id}"}
            target="_blank"
            rel="noopener"
            class="text-gf-maroon hover:underline"
          >
            Open ↗
          </a>
      <% end %>
    </div>
    """
  end

  @doc """
  A Host neither Gallformers nor WCVP holds: a link to the taxonomy
  admin's New Taxon page, in a new tab, started with the plant `prefill`
  (`%{name, rank, parent_id}`, any nil; always Plantae). The question's
  plant search then finds the plant created there.
  """
  attr :id, :string, required: true
  attr :prefill, :map, required: true

  def review_new_plant(assigns) do
    ~H"""
    <p id={@id} data-role="new-plant" class="text-sm text-gray-600">
      Not in Gallformers or WCVP?
      <a
        href={new_plant_href(@prefill)}
        target="_blank"
        rel="noopener"
        class="text-gf-maroon hover:underline"
      >
        Create a new plant ↗
      </a>
      (opens in a new tab), then search for it here.
    </p>
    """
  end

  defp new_plant_href(prefill) do
    query =
      for {key, value} <- [
            name: prefill[:name],
            rank: prefill[:rank],
            kingdom: "Plantae",
            parent_id: prefill[:parent_id]
          ],
          value not in [nil, ""],
          do: {key, value}

    ~p"/admin/taxonomy/new?#{query}"
  end

  defp wcvp_text(host, written) do
    record = full_name(host.wcvp.name, host.wcvp.authors)

    holds =
      if host.match == :exact,
        do: "holds #{record}",
        else: "doesn't hold “#{written}” as written. Nearest spelling: #{record}"

    status =
      case host do
        %{accepted: %{name: name, authors: authors}} ->
          ", a synonym of #{full_name(name, authors)}"

        %{wcvp: %{status: status}} when is_binary(status) ->
          " (#{status})"

        _ ->
          ""
      end

    held =
      case host.held do
        %{name: name} -> ", which Gallformers holds as #{name}."
        nil -> ", which Gallformers doesn't hold yet."
      end

    "#{holds}#{status}#{held}"
  end

  defp full_name(name, nil), do: name
  defp full_name(name, authors), do: "#{name} #{authors}"

  @doc """
  A candidate Gall compared with what the Source says, field by field: the
  Source's side and the Gall's, each row marked ✓ agrees, ≠ differs,
  ⚠ conflicts or not stated, then the two descriptions; with the Gall's
  photos and Sources, Open ↗ to its admin page, and whether its description
  comes from this Source. `comparison` is
  `GallformersWeb.Admin.Review.Choice`'s.
  """
  attr :id, :string, required: true
  attr :comparison, :map, required: true

  def review_gall_comparison(assigns) do
    ~H"""
    <div id={@id} data-role="gall-comparison" class="grid gap-1">
      <span
        :if={@comparison.quoted_in}
        class="text-sm font-medium text-green-800"
        data-role="quoted"
      >
        {@comparison.quoted_in}
      </span>
      <span class="text-sm text-gray-600" data-role="gall-meta">
        {@comparison.meta} ·
        <a
          href={@comparison.path}
          target="_blank"
          rel="noopener"
          class="text-gf-maroon hover:underline"
        >
          Open ↗
        </a>
      </span>
      <div class="overflow-x-auto">
        <table class="gf-table gf-table-compact bg-white text-sm">
          <thead>
            <tr>
              <th></th>
              <th>{@comparison.who}</th>
              <th>{@comparison.gall}</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @comparison.rows} data-mark={row.mark}>
              <td class="font-medium text-gray-600">{row.label}</td>
              <td>{row.source || not_stated("not stated")}</td>
              <td>{row.gall || not_stated("not recorded")}</td>
              <td class={["whitespace-nowrap", mark_class(row.mark)]} data-role="mark">
                {mark_text(row.mark)}
              </td>
            </tr>
            <tr>
              <td class="font-medium text-gray-600">Description</td>
              <td class="text-gray-700">
                {description_text(elem(@comparison.description, 0), "not stated")}
              </td>
              <td class="text-gray-700" colspan="2">
                {description_text(elem(@comparison.description, 1), "no description")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp not_stated(text),
    do: Phoenix.HTML.raw(~s(<span class="italic text-gray-400">#{text}</span>))

  defp mark_text(:agree), do: "✓ agrees"
  defp mark_text(:differ), do: "≠ differs"
  defp mark_text(:conflict), do: "⚠ conflicts"
  defp mark_text(_none), do: "not stated"

  defp mark_class(:agree), do: "text-green-800"
  defp mark_class(:differ), do: "text-amber-800"
  defp mark_class(:conflict), do: "text-red-700 font-semibold"
  defp mark_class(_none), do: "text-gray-400"

  @description_length 220

  defp description_text(text, _none) when is_binary(text) do
    if String.length(text) > @description_length,
      do: "“#{String.slice(text, 0, @description_length)}…”",
      else: "“#{text}”"
  end

  defp description_text(_text, none), do: not_stated(none)

  @doc """
  A small set of radio choices in a row, for a follow-up within an option
  (keep or leave out a statement; what a synonym becomes). Each sends
  `on_pick` with `phx-value-key` (`key`) and `phx-value-value`.
  """
  attr :id, :string, required: true
  attr :key, :string, required: true
  attr :label, :string, required: true, doc: "what the choices are about, for screen readers"
  attr :options, :list, required: true, doc: "`{value, label}` pairs"
  attr :value, :any, default: nil, doc: "the chosen value"
  attr :recommended, :any, default: nil, doc: "the recommended value, marked \"rec.\""
  attr :on_pick, :any, required: true
  attr :target, :any, default: nil

  def review_segmented(assigns) do
    ~H"""
    <div id={@id} role="radiogroup" aria-label={@label} class="flex flex-wrap gap-1.5">
      <label
        :for={{value, label} <- @options}
        for={"#{@id}-#{value}"}
        class={[
          "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-sm cursor-pointer",
          cond do
            @value == value -> "border-gf-maroon bg-gf-maroon/5 text-gray-900"
            @recommended == value -> "border-gf-maroon bg-white text-gf-maroon"
            true -> "border-gray-300 bg-white text-gray-700 hover:border-gray-400"
          end
        ]}
        data-recommended={@recommended == value || nil}
      >
        <input
          type="radio"
          id={"#{@id}-#{value}"}
          name={@id}
          value={value}
          checked={@value == value}
          class="gf-radio"
          phx-click={@on_pick}
          phx-value-key={@key}
          phx-value-value={value}
          phx-target={@target}
        />
        {label}
        <span
          :if={@recommended == value}
          class="text-[0.66rem] font-bold uppercase tracking-wider text-gf-maroon"
        >
          rec.
        </span>
      </label>
    </div>
    """
  end

  @doc """
  The Source's statements a chosen Gall disagrees with, each to keep or
  leave out, and for a Host also another plant, labelled by the
  statement's `other` ("He means another plant"; "On another plant" for a
  Host above species rank), the `reading` slot rendered under it once
  chosen (the plant search) with the statement's `note`. `settled` maps a
  statement's key to `"keep"`, `"leave"` or `"other"`; `who` names the
  Source.
  """
  attr :id, :string, required: true
  attr :who, :string, required: true
  attr :statements, :list, required: true
  attr :settled, :map, default: %{}
  attr :on_settle, :any, required: true
  attr :target, :any, default: nil
  slot :reading, doc: "the plant search, under a Host read as another plant"

  def review_settle_list(assigns) do
    ~H"""
    <div id={@id} class="grid gap-2" data-role="settle">
      <p class="text-sm text-gray-600">
        {@who} disagrees with this Gall on {length(@statements)} {if length(@statements) == 1,
          do: "statement",
          else: "statements"}. For each, keep it or leave it out. A statement left out never becomes a Fact; the quote stays in {@who}'s text.
      </p>
      <div
        :for={s <- @statements}
        id={"#{@id}-#{s.key}"}
        class="grid gap-1.5 rounded-md border border-gray-200 px-3 py-2"
      >
        <span class="text-sm font-medium text-gray-800">{s.label}</span>
        <.review_segmented
          id={"#{@id}-#{s.key}-choice"}
          key={s.key}
          label={s.label}
          options={settle_options(s)}
          value={@settled[s.key]}
          on_pick={@on_settle}
          target={@target}
        />
        <div :if={@settled[s.key] == "other"} class="grid gap-1">
          {render_slot(@reading)}
          <span :if={s.note} class="text-xs text-gray-500">{s.note}</span>
        </div>
      </div>
    </div>
    """
  end

  defp settle_options(%{reading: reading, keep: keep, other: other}) when is_binary(reading),
    do: [{"keep", keep}, {"other", other}, {"leave", "Leave it out"}]

  defp settle_options(%{keep: keep}), do: [{"keep", keep}, {"leave", "Leave it out"}]

  # -- a Source's steps (matter d213, Task 15) ---------------------------------

  @doc """
  The bar on every page of a Source's review: the overview and each step
  (`GallformersWeb.Admin.Review.Steps.summarize/1`), with what is left or a
  check, a dot on the steps holding approval, and at the right Approve or
  what it waits for.

  `approval` is `:approved`; `{:waiting, titles}`, what still holds it;
  `{:ready, later}`, nothing holds it and `later` names what stays open
  ("3 trait terms"); `:resolving`; or `:none`. With `confirm`, Approve asks
  first, in place. The events are `approve_ask`, `approve_cancel` and
  `approve`. It sticks under the site header, which is sticky itself and
  78px tall (as `GallformersWeb.KeyComponents.path_tracker/1`).
  """
  attr :id, :string, default: "step-bar"
  attr :base, :string, required: true, doc: "the overview's path; a step's is `base/slug`"
  attr :current, :atom, required: true, doc: "`:overview` or the step's id"
  attr :summaries, :list, required: true
  attr :approval, :any, required: true
  attr :confirm, :boolean, default: false

  def review_step_bar(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Steps for this Source"
      class="sticky top-[78px] z-40 mt-4 py-2 bg-gray-100/95 backdrop-blur border-b border-gray-200"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <div class="flex flex-wrap gap-1.5 flex-1 min-w-0">
          <.link
            id={"#{@id}-overview"}
            navigate={@base}
            aria-current={@current == :overview && "page"}
            class={step_class(@current == :overview)}
          >
            Overview
          </.link>
          <.link
            :for={s <- @summaries}
            id={"#{@id}-#{s.step.slug}"}
            navigate={"#{@base}/#{s.step.slug}"}
            aria-current={@current == s.step.id && "page"}
            class={step_class(@current == s.step.id)}
          >
            <span
              :if={s.holding > 0}
              data-role="holds"
              title="Holds approval"
              class="inline-block size-2 rounded-full bg-gf-autumn"
            >
            </span>
            {s.step.n} · {s.step.title}
            <span
              :if={s.left > 0}
              data-role="left"
              class={[
                "px-1.5 rounded-full text-xs tabular-nums border",
                if(@current == s.step.id,
                  do: "border-white/50",
                  else: "bg-gray-50 border-gray-200 text-gray-700"
                )
              ]}
            >
              {s.left}
            </span>
            <span
              :if={s.left == 0}
              data-role="done"
              aria-label="done"
              class={["font-bold", @current != s.step.id && "text-green-700"]}
            >
              ✓
            </span>
          </.link>
          <.link
            id={"#{@id}-facts"}
            navigate={"#{@base}/facts"}
            aria-current={@current == :facts && "page"}
            title="Every Fact approving would write"
            class={[step_class(@current == :facts), "border-dashed"]}
          >
            <.icon name="ph-list-checks" class="size-4" /> Facts
            <span class={["text-xs", @current != :facts && "text-gray-500"]}>optional</span>
          </.link>
        </div>
        <div id={"#{@id}-approve"} class="flex items-center gap-2 md:ml-auto">
          <%= case @approval do %>
            <% :approved -> %>
              <.badge variant="success">Approved</.badge>
            <% {:waiting, titles} -> %>
              <span id="approve-wait" class="text-sm text-gray-500 max-w-xs md:text-right">
                Approve appears once {and_list(titles)} {if length(titles) == 1,
                  do: "is",
                  else: "are"} settled
              </span>
            <% {:ready, _later} -> %>
              <.button id="approve-open" phx-click="approve_ask" variant="primary">
                Approve…
              </.button>
            <% :resolving -> %>
              <span class="text-sm text-gray-500">Resolving: Approve waits for it</span>
            <% :none -> %>
          <% end %>
        </div>
      </div>
      <p class="mt-1 flex items-center gap-1.5 text-xs text-gray-500">
        <span class="inline-block size-2 rounded-full bg-gf-autumn" aria-hidden="true"></span>
        Holds approval until settled
      </p>
      <div
        :if={@confirm and match?({:ready, _}, @approval)}
        id="approve-confirm"
        class="mt-2 flex flex-wrap items-center gap-2 rounded-md bg-yellow-50 px-3 py-2 text-sm text-yellow-900"
      >
        <span class="flex-1 min-w-[16rem]">
          Approving applies this Source's Facts to Gallformers.{later_text(@approval)}
        </span>
        <.button id="approve" phx-click="approve" variant="primary">Approve and apply</.button>
        <.button id="approve-cancel" phx-click="approve_cancel" variant="ghost">Cancel</.button>
      </div>
      <div
        :if={@approval == :approved}
        class="mt-2 rounded-md bg-green-50 px-3 py-2 text-sm text-green-800"
      >
        Approved: its Facts are applied by the import worker. Open Traits and Hedges stay on
        this Source's pages and can be settled any time.
      </div>
    </nav>
    """
  end

  defp step_class(true),
    do:
      "gf-step-current inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md border text-sm " <>
        "bg-gf-maroon border-gf-maroon text-white"

  defp step_class(false),
    do:
      "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md border text-sm " <>
        "bg-white border-gray-200 text-gray-700 hover:border-gray-400"

  defp later_text({:ready, []}), do: ""

  defp later_text({:ready, later}) do
    verb = if one?(later), do: "is", else: "are"
    " #{cap(and_list(later))} #{verb} still open; they stay here and can be settled after."
  end

  # "1 hedge" alone takes "is".
  defp one?([text]), do: String.starts_with?(text, "1 ")
  defp one?(_later), do: false

  @doc """
  Where a Source stands, step by step: a row per step (its number, title
  and question; what is left and how much has a recommended answer, with a
  bar; whether it holds approval), each opening its page, and "Continue"
  to the first step with work left.
  """
  attr :id, :string, default: "overview"
  attr :base, :string, required: true
  attr :summaries, :list, required: true
  attr :next, :map, default: nil, doc: "the first step with work left, or nil"
  attr :status, :string, default: nil, doc: "a line on what approval waits for"

  def review_step_overview(assigns) do
    ~H"""
    <div id={@id} class="gf-card mt-4 overflow-hidden">
      <div class="flex flex-wrap items-center gap-3 px-4 py-3 border-b border-gray-200">
        <div class="flex-1 min-w-[16rem]">
          <h2 class="text-lg font-semibold text-gray-900">Where this Source stands</h2>
          <p :if={@status} class="text-sm text-gray-500">{@status}</p>
        </div>
        <.button
          :if={@next}
          id="continue"
          navigate={"#{@base}/#{@next.slug}"}
          variant="primary"
        >
          Continue: {@next.title} →
        </.button>
      </div>
      <div class="divide-y divide-gray-200">
        <.link
          :for={s <- @summaries}
          id={"#{@id}-#{s.step.slug}"}
          navigate={"#{@base}/#{s.step.slug}"}
          class="grid grid-cols-[1.5rem_1fr] md:grid-cols-[2rem_minmax(10rem,1fr)_minmax(12rem,1.4fr)_auto] items-center gap-x-4 gap-y-1 px-4 py-3 hover:bg-gray-50"
        >
          <span class="font-bold text-gray-500 tabular-nums">{s.step.n}</span>
          <span class="font-semibold text-gray-900">
            {s.step.title}
            <span class="block text-sm font-normal text-gray-500">{s.step.question}</span>
          </span>
          <span class="col-start-2 md:col-start-auto text-sm text-gray-700">
            <%= if s.left > 0 do %>
              {s.left} of {s.total} left · {s.recommended} with a recommended answer
            <% else %>
              All settled
            <% end %>
            <.review_progress
              done={s.total - s.left}
              proposed={s.recommended}
              total={s.total}
              class="mt-1 max-w-64"
            />
          </span>
          <span class="col-start-2 md:col-start-auto">
            <%= cond do %>
              <% s.holding > 0 -> %>
                <.badge variant="warning">Holds approval</.badge>
              <% s.left == 0 -> %>
                <.badge variant="success">Done</.badge>
              <% true -> %>
                <.review_tag>Doesn't hold approval</.review_tag>
            <% end %>
          </span>
        </.link>
        <.link
          id={"#{@id}-facts"}
          navigate={"#{@base}/facts"}
          class="flex flex-wrap items-baseline gap-x-3 gap-y-0.5 px-4 py-3 hover:bg-gray-50"
        >
          <span class="font-semibold text-gf-maroon">See every Fact this Source would add →</span>
          <span class="text-sm text-gray-500">
            Optional: what approving writes, by Gall, given the answers so far. Facts can be
            edited there.
          </span>
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  A step page's head: which step of how many, whether it holds approval,
  its title and question, and a line introducing it (`intro`).
  """
  attr :step, :map, required: true
  attr :of, :integer, default: 5
  attr :intro, :string, default: nil

  def review_step_head(assigns) do
    ~H"""
    <div id="step-head" class="mt-4 grid gap-0.5">
      <span class="text-xs uppercase tracking-wider text-gray-500">
        Step {@step.n} of {@of} · {if @step.holds_approval,
          do: "holds approval",
          else: "doesn't hold approval"}
      </span>
      <h2 class="text-2xl font-semibold text-gf-maroon">{@step.title}</h2>
      <p class="text-gray-700">{@step.question}</p>
      <p :if={@intro} data-role="intro" class="text-sm text-gray-600 max-w-3xl">{@intro}</p>
    </div>
    """
  end

  @doc """
  A step page's foot: back to the step before (or the overview) and on to
  the next (or the overview). `prev` and `next` are `%{title, path}`.
  """
  attr :prev, :map, required: true
  attr :next, :map, required: true

  def review_step_foot(assigns) do
    ~H"""
    <div class="mt-4 flex flex-wrap items-center justify-between gap-2">
      <.button id="step-prev" navigate={@prev.path} variant="ghost">← {@prev.title}</.button>
      <.button id="step-next" navigate={@next.path} variant="secondary">
        {if @next.step?, do: "Next: #{@next.title} →", else: @next.title}
      </.button>
    </div>
    """
  end

  @doc "A settled step's panel: it is settled, and on to the next. `next` is `%{title, path, step?}`."
  attr :step, :map, required: true
  attr :next, :map, required: true

  def review_step_done(assigns) do
    ~H"""
    <div id="step-done" class="gf-card mt-4 flex flex-wrap items-center gap-3 px-4 py-3">
      <span class="flex-1 min-w-[16rem] font-semibold text-green-800">
        ✓ {@step.title} is settled.
      </span>
      <.button navigate={@next.path} variant="primary">
        {if @next.step?, do: "Next: #{@next.title} →", else: "Back to the overview"}
      </.button>
    </div>
    """
  end

  @doc """
  A Source's head on its review pages: its short name, its title and
  citation, its kind and status, a link to the Source in Gallformers
  (`source_id`, when it holds it), and actions (Deny) and counts in slots.
  """
  attr :name, :string, required: true, doc: "the short name, \"Ashmead 1897\""
  attr :title, :string, default: nil
  attr :citation, :string, default: nil
  attr :kind, :string, default: nil
  attr :status, :string, default: nil
  attr :status_variant, :string, default: "info"
  attr :source_id, :integer, default: nil, doc: "the Source, when Gallformers holds it"
  slot :actions
  slot :inner_block, doc: "under the head: the Source's counts"

  def review_source_head(assigns) do
    ~H"""
    <div id="source-head" class="gf-card p-4 mt-2 grid gap-3">
      <div class="flex flex-wrap items-start gap-3">
        <div class="flex-1 min-w-[16rem]">
          <p class="text-lg font-semibold leading-snug text-gray-900">{@title || @name}</p>
          <p :if={@citation && @citation != @title} class="text-sm text-gray-500">{@citation}</p>
          <div :if={@kind || @status} class="mt-1.5 flex flex-wrap gap-1.5">
            <.review_tag :if={@kind}>{@kind}</.review_tag>
            <.badge :if={@status} variant={@status_variant}>{@status}</.badge>
          </div>
          <.review_source_link :if={@source_id} source_id={@source_id} class="mt-1.5" />
        </div>
        <div :if={@actions != []} class="flex gap-2">{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A link from a Source's review to the Source in Gallformers
  (`/admin/sources/:id`).
  """
  attr :source_id, :integer, required: true
  attr :class, :any, default: nil

  def review_source_link(assigns) do
    ~H"""
    <p class={["text-sm", @class]}>
      <.link navigate={~p"/admin/sources/#{@source_id}"} class="text-gf-maroon hover:underline">
        The Source in Gallformers →
      </.link>
    </p>
    """
  end

  @doc """
  A link from a Source to its review in progress
  (`/admin/review/sources/:id`), saying how many questions are left: the
  open questions but what was set aside, as the review's Sources list
  counts them (`GallformersWeb.Admin.ReviewLive.Loader.sources/0`'s
  `to_decide`).
  """
  attr :review, :map, required: true, doc: "the Source's row of `Loader.sources/0`"
  attr :rest, :global

  def review_in_progress_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/admin/review/sources/#{@review.source_id}"}
      class="text-gf-maroon hover:underline"
      {@rest}
    >
      {review_in_progress_text(@review.to_decide)}
    </.link>
    """
  end

  defp review_in_progress_text(0), do: "Being reviewed: no questions left"
  defp review_in_progress_text(1), do: "Being reviewed: 1 question left"
  defp review_in_progress_text(n), do: "Being reviewed: #{n} questions left"

  # -- one question (matter d213, Task 16) ---------------------------------------

  @doc """
  A question's row: a button (Enter and Space open it too) with a chevron
  that turns when open, the Source's words, an arrow and the answer; under
  it, what the inner block holds (an error, the notes), and when open the
  detail. `on_toggle` and `target` are the button's `phx-click` and
  `phx-target`.
  """
  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :decided, :boolean, default: false
  attr :on_toggle, :any, required: true
  attr :target, :any, default: nil

  slot :written, required: true, doc: "the Source's words, with a line of context"
  slot :answer, required: true, doc: "the recommended or decided answer, or what there is instead"
  slot :detail, doc: "the question, shown under the row when open"
  slot :inner_block, doc: "shown under the row whether open or not (an error, the notes)"

  def review_question_row(assigns) do
    assigns = assign(assigns, question_cols: @question_cols)

    ~H"""
    <div id={@id} class={[@open && "bg-gray-50"]}>
      <button
        type="button"
        id={"#{@id}-row"}
        class={[
          "w-full text-left grid grid-cols-[1.1rem_1fr] gap-x-3 gap-y-1 items-start px-4 py-2",
          "hover:bg-gray-50 cursor-pointer group",
          @question_cols
        ]}
        phx-click={@on_toggle}
        phx-target={@target}
        aria-expanded={to_string(@open)}
        title={if @open, do: "Close", else: "Open"}
      >
        <span data-role="chevron" class={["mt-1 transition-transform", @open && "rotate-90"]}>
          <.icon
            name="ph-caret-right"
            class={[
              "size-4 group-hover:text-gf-maroon",
              if(@open, do: "text-gf-maroon", else: "text-gray-400")
            ]}
          />
        </span>
        <span class="font-semibold text-gray-900 break-words">{render_slot(@written)}</span>
        <span class="hidden md:block text-center text-gray-400" aria-hidden="true">→</span>
        <span
          data-role="answer"
          class={["col-start-2 md:col-start-auto min-w-0", @decided && "text-green-800"]}
        >
          {render_slot(@answer)}
        </span>
      </button>
      {render_slot(@inner_block)}
      <div
        :if={@open and @detail != []}
        id={"#{@id}-detail"}
        class="grid gap-4 px-4 pt-3 pb-4 bg-white border-t border-dashed border-gray-200"
      >
        {render_slot(@detail)}
      </div>
    </div>
    """
  end

  @doc """
  The question, in plain words, with a line on what the answer covers, and
  beside it an action on the question ("Read the Source ▸").
  """
  attr :question, :string, required: true
  attr :scope, :string, default: nil
  slot :action, doc: "beside the question: `review_read_source/1`"

  def review_ask(assigns) do
    ~H"""
    <div class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
      <div class="grid gap-0.5 min-w-0 flex-1 basis-[20rem]">
        <p data-role="question" class="text-lg font-semibold text-gray-900">{@question}</p>
        <p :if={@scope} data-role="scope" class="text-sm text-gray-700">{@scope}</p>
      </div>
      <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
    </div>
    """
  end

  @doc """
  One option of a question, as a radio card: what it is (`label`), what it
  does (`summary`), "Recommended" with who recommends it (`by`) when it is
  the recommended answer, who chose it (`tally`, recommended or not), and
  its follow-up input (the `follow` slot), shown only once it is chosen. The radio sends `on_pick` with
  `phx-value-choice` set to `value`.
  """
  attr :id, :string, required: true
  attr :name, :string, required: true, doc: "the radio group's name"
  attr :value, :any, required: true
  attr :checked, :boolean, default: false
  attr :recommended, :boolean, default: false
  attr :by, :string, default: nil, doc: "who recommends it, or why"
  attr :label, :string, required: true
  attr :summary, :string, default: nil
  attr :on_pick, :any, required: true
  attr :target, :any, default: nil
  attr :tags, :list, default: [], doc: "`%{text, kind: :best | :conflict}` beside the label"

  attr :tally, :string,
    default: nil,
    doc: "who chose it, shown whether recommended or not; in place of `by`"

  slot :extra, doc: "what it shows besides, under it whether chosen or not (a comparison)"
  slot :follow, doc: "the input the option needs, shown once chosen"

  def review_option(assigns) do
    ~H"""
    <div
      class={[
        "rounded-md border px-3 py-2",
        cond do
          @checked -> "border-gf-maroon bg-gf-maroon/5"
          @recommended -> "border-gf-maroon bg-white"
          true -> "border-gray-200 bg-white hover:border-gray-400"
        end
      ]}
      data-recommended={@recommended}
      data-chosen={@checked}
    >
      <label
        for={@id}
        class="grid grid-cols-[1.1rem_minmax(0,1fr)] md:grid-cols-[1.1rem_minmax(0,1fr)_auto] gap-x-2.5 gap-y-0.5 items-start cursor-pointer"
      >
        <input
          type="radio"
          id={@id}
          name={@name}
          value={@value}
          checked={@checked}
          class="gf-radio mt-1"
          phx-click={@on_pick}
          phx-value-choice={@value}
          phx-target={@target}
        />
        <span class="font-semibold text-gray-900">
          {@label}
          <span
            :if={@recommended}
            data-role="recommended"
            class="ml-1 align-[1px] rounded bg-gf-maroon/10 px-1.5 text-[0.68rem] font-bold uppercase tracking-wider text-gf-maroon"
          >
            Recommended
          </span>
          <span
            :for={tag <- @tags}
            data-role={"tag-#{tag.kind}"}
            class={[
              "ml-1 align-[1px] rounded px-1.5 text-[0.68rem] font-bold uppercase tracking-wider",
              if(tag.kind == :conflict,
                do: "bg-red-50 text-red-800",
                else: "bg-blue-50 text-blue-800"
              )
            ]}
          >
            {tag.text}
          </span>
        </span>
        <span
          :if={@tally}
          data-role="tally"
          class={[
            "col-start-2 md:col-start-auto text-sm md:text-right max-w-72",
            if(@recommended, do: "font-semibold text-gf-maroon", else: "text-gray-500")
          ]}
        >
          {@tally}
        </span>
        <span
          :if={!@tally and @recommended and @by}
          class="col-start-2 md:col-start-auto text-sm font-semibold text-gf-maroon md:text-right max-w-72"
        >
          {@by}
        </span>
        <span :if={@summary} class="col-start-2 md:col-span-2 text-sm text-gray-500">
          {@summary}
        </span>
      </label>
      <div :if={@extra != []} class="mt-1 ml-7 grid gap-1">{render_slot(@extra)}</div>
      <div :if={@checked and @follow != []} class="mt-2 md:ml-7 grid gap-2" data-role="follow">
        {render_slot(@follow)}
      </div>
    </div>
    """
  end

  @doc """
  A Trait's values to choose from, each with its definition: radios for
  one (`type="radio"`), checkboxes for several. Each input sends `on_pick`
  with `phx-value-value`; `selected` are the values chosen, `noted` those
  marked with `note` ("a reader chose it"). Input ids are
  `<id>-<value>`.
  """
  attr :id, :string, required: true
  attr :type, :string, default: "radio", values: ["radio", "checkbox"]
  attr :values, :list, required: true, doc: "`{value, definition}` pairs, in order"
  attr :selected, :list, default: []
  attr :noted, :list, default: []
  attr :note, :string, default: nil
  attr :on_pick, :any, required: true
  attr :target, :any, default: nil

  def review_value_list(assigns) do
    ~H"""
    <div id={@id} class="grid gap-1 max-h-80 overflow-y-auto" data-role="values">
      <p :if={@values == []} class="text-sm italic text-gray-500">No value matches.</p>
      <label
        :for={{value, definition} <- @values}
        for={"#{@id}-#{value}"}
        class={[
          "grid grid-cols-[1.1rem_minmax(0,1fr)] gap-x-2 rounded-md border px-2.5 py-1.5 text-sm cursor-pointer",
          if(value in @selected,
            do: "border-gf-maroon bg-gf-maroon/5",
            else: "border-gray-200 bg-white hover:border-gray-400"
          )
        ]}
      >
        <input
          type={@type}
          id={"#{@id}-#{value}"}
          name={if @type == "radio", do: @id, else: "#{@id}[]"}
          value={value}
          checked={value in @selected}
          class={if @type == "radio", do: "gf-radio mt-0.5", else: "gf-checkbox mt-0.5"}
          phx-click={@on_pick}
          phx-value-value={value}
          phx-target={@target}
        />
        <span class="font-medium text-gray-900">
          {value}
          <span :if={@note && value in @noted} class="ml-1 text-xs font-normal text-gray-500">
            {@note}
          </span>
        </span>
        <span :if={definition} class="col-start-2 text-gray-500">{definition}</span>
      </label>
    </div>
    """
  end

  @doc """
  Decide, with what the chosen option will do (`effect`), or, while the
  answer isn't complete, what is missing, Decide disabled.
  """
  attr :id, :string, required: true
  attr :ok, :boolean, required: true
  attr :effect, :string, required: true
  attr :on_decide, :any, required: true
  attr :target, :any, default: nil

  def review_decide_bar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-end gap-x-4 gap-y-2">
      <span
        id={"#{@id}-effect"}
        class={[
          "flex-1 min-w-[16rem] text-sm",
          if(@ok, do: "text-gray-700", else: "italic text-gray-500")
        ]}
      >
        {@effect}
      </span>
      <.button
        id={"#{@id}-decide"}
        phx-click={@on_decide}
        phx-target={@target}
        variant="primary"
        disabled={not @ok}
      >
        Decide
      </.button>
    </div>
    """
  end

  @doc "What a decided question was decided as, and by whom."
  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :by, :string, default: nil

  def review_decided(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex flex-wrap items-center gap-2 rounded-md bg-green-50 px-3 py-2 text-sm text-green-800"
    >
      <.icon name="ph-check" class="size-4" />
      <span class="flex-1">Decided: {@text}<span :if={@by}>, by {@by}</span>.</span>
    </div>
    """
  end

  @doc "A question's notes, oldest first, each with who wrote it and when."
  attr :id, :string, required: true
  attr :notes, :list, required: true
  attr :class, :any, default: nil

  def review_note_list(assigns) do
    ~H"""
    <ul id={@id} class={["grid gap-1 text-sm text-gray-700", @class]} data-role="notes">
      <li :for={note <- @notes} class="rounded-md bg-yellow-50 px-3 py-1.5">
        <span class="whitespace-pre-line">{note.text}</span>
        <span class="block text-xs text-gray-500">
          {note.author_name}<span :if={note.inserted_at}>, {GallformersWeb.UIComponents.format_date(note.inserted_at, :short)}</span>
        </span>
      </li>
    </ul>
    """
  end

  @doc """
  The notes of an open question, apart from the decision: its notes and a
  box to add one, saved on its own ("Save note"). `id` prefixes the ids
  (`<id>-notes`, `<id>-note-form`, `<id>-note`, `<id>-save-note`); the form
  sends `note_draft` on change and `save_note` on submit.
  """
  attr :id, :string, required: true
  attr :notes, :list, required: true
  attr :draft, :string, default: ""
  attr :target, :any, default: nil

  attr :placeholder, :string,
    default:
      "A note for the next curator: what you checked, what is still unclear. Saved on its " <>
        "own, not with the decision."

  def review_notes(assigns) do
    ~H"""
    <div class="grid gap-2 border-t border-gray-200 pt-3">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-gray-500">Notes</h3>
      <.review_note_list :if={@notes != []} id={"#{@id}-notes"} notes={@notes} />
      <.form
        for={%{}}
        id={"#{@id}-note-form"}
        phx-change="note_draft"
        phx-submit="save_note"
        phx-target={@target}
        class="flex flex-wrap items-end gap-2"
      >
        <label for={"#{@id}-note"} class="sr-only">Note</label>
        <textarea
          id={"#{@id}-note"}
          name="note"
          rows="2"
          class="gf-textarea flex-1 min-w-[16rem]"
          placeholder={@placeholder}
        >{@draft}</textarea>
        <.button id={"#{@id}-save-note"} type="submit" variant="secondary">Save note</.button>
      </.form>
    </div>
    """
  end

  @doc "Details tucked away behind a summary line."
  attr :summary, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def review_disclosure(assigns) do
    ~H"""
    <details id={@id} class="text-sm text-gray-700">
      <summary class="cursor-pointer text-gray-500">{@summary}</summary>
      <div class="mt-2 grid gap-2">{render_slot(@inner_block)}</div>
    </details>
    """
  end

  # -- the Source in context (matter d213, Task 22) ------------------------------

  # A quoted block's highlight, as the quote's own (`review_quote/1`).
  @cited_class "bg-orange-50/60 border-l-[3px] border-gf-autumn pl-2 text-gray-900"

  @doc """
  The Source's passage around a quote (`Gallformers.Import.Passages.passage/2`):
  its blocks in order, each heading bold, each quoted block highlighted
  (`data-cited`), the page given where it changes. Said so when the
  Source's text doesn't hold it.
  """
  attr :blocks, :list, required: true, doc: "`%{ref, text, page, heading?, cited?}` maps"

  def review_passage(assigns) do
    assigns = assign(assigns, paged: paged(assigns.blocks))

    ~H"""
    <div
      :if={@blocks != []}
      data-role="passage-text"
      class="grid gap-1.5 max-h-[22rem] overflow-y-auto bg-white border border-gray-200 rounded-md px-3 py-2 text-sm text-gray-700"
    >
      <.source_block :for={{block, page} <- @paged} block={block} page={page} cited={block.cited?} />
    </div>
    <p :if={@blocks == []} class="text-sm text-gray-500">The passage isn’t in the Source’s text.</p>
    """
  end

  @doc """
  "Read the Source ▸": opens the reader panel (`review_reader/1`) on a
  question, sending `on_read` with `phx-value-item` set to `item`.
  """
  attr :id, :string, required: true
  attr :item, :any, required: true
  attr :on_read, :any, required: true

  def review_read_source(assigns) do
    ~H"""
    <.button
      id={@id}
      type="button"
      size="sm"
      variant="secondary"
      phx-click={@on_read}
      phx-value-item={@item}
    >
      Read the Source ▸
    </.button>
    """
  end

  @doc """
  The reader panel: the Source's whole text (`Gallformers.Import.Passages.blocks/1`)
  beside the questions, fixed to the right on a wide screen (the page makes
  room for it) and covering the page on a narrow one. Its head names the
  Source and the question it was opened on, with a find box and Close.
  The question's quoted blocks (`cited`) are highlighted; what the find box
  holds is marked wherever it appears, ignoring case, with how many blocks
  hold it. The `SourceReader` hook scrolls to the first quoted block on
  opening, and to the first match as the find changes.

  `on_find` is the find form's `phx-change` (its field is `find`);
  `on_close` is Close's `phx-click`.
  """
  attr :id, :string, default: "source-reader"
  attr :title, :string, required: true, doc: "the Source's short name"
  attr :question, :string, default: nil, doc: "the question it was opened on"
  attr :blocks, :list, required: true, doc: "`%{ref, text, page, heading?}` maps"
  attr :cited, :list, default: [], doc: "the refs of the question's quoted blocks"
  attr :find, :string, default: ""
  attr :on_find, :any, required: true
  attr :on_close, :any, required: true

  def review_reader(assigns) do
    find = String.trim(assigns.find || "")
    cited = MapSet.new(assigns.cited)

    assigns =
      assign(assigns,
        needle: find,
        cited_set: cited,
        paged: paged(assigns.blocks),
        hits: if(find == "", do: 0, else: Enum.count(assigns.blocks, &matches?(&1.text, find)))
      )

    ~H"""
    <aside
      id={@id}
      aria-label="The Source’s text"
      class="fixed inset-y-0 right-0 z-[60] flex flex-col w-full lg:w-[min(38rem,46vw)] bg-white border-l border-gray-300 shadow-xl"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5 px-4 py-3 border-b border-gray-200">
        <b data-role="title" class="text-gray-900">{@title}</b>
        <span :if={@question} data-role="question" class="basis-full text-sm text-gray-500">
          {@question}
        </span>
        <form
          id={"#{@id}-find"}
          phx-change={@on_find}
          phx-submit={@on_find}
          class="flex-1 min-w-[12rem]"
        >
          <.search_input
            id={"#{@id}-find-input"}
            name="find"
            value={@find}
            placeholder="Find in the Source"
            size={:sm}
            phx-debounce="300"
          />
        </form>
        <.button type="button" size="sm" variant="ghost" phx-click={@on_close}>Close ✕</.button>
        <span :if={@needle != ""} id={"#{@id}-hits"} class="basis-full text-sm text-gray-500">
          {hits_text(@hits)}
        </span>
      </div>
      <div
        id={"#{@id}-body"}
        phx-hook="SourceReader"
        data-find={@needle}
        data-cited={Enum.join(@cited, " ")}
        class="relative flex-1 overflow-y-auto grid content-start gap-2 px-4 pt-3 pb-8 text-sm text-gray-700"
      >
        <.source_block
          :for={{block, page} <- @paged}
          id={"#{@id}-#{block_id(block.ref)}"}
          block={block}
          page={page}
          cited={MapSet.member?(@cited_set, block.ref)}
          find={@needle}
        />
      </div>
    </aside>
    """
  end

  attr :id, :string, default: nil
  attr :block, :map, required: true
  attr :page, :any, required: true, doc: "the page to give before it, or nil"
  attr :cited, :boolean, default: false
  attr :find, :string, default: ""

  # One block of the Source's text, in a passage or the reader.
  defp source_block(assigns) do
    assigns = assign(assigns, cited_class: @cited_class)

    ~H"""
    <p
      id={@id}
      data-role="block"
      data-cited={@cited}
      data-heading={@block.heading?}
      class={[
        "m-0 max-w-[70ch] break-words",
        @block.heading? && "font-semibold text-gray-900",
        @cited && @cited_class
      ]}
    >
      <span
        :if={@page}
        data-role="page"
        class="inline-block mr-1.5 text-xs text-gray-500 tabular-nums"
      >
        p. {@page}
      </span>
      {marked(@block.text, @find)}
    </p>
    """
  end

  # Each block with the page to give before it: its own where it changes.
  defp paged(blocks) do
    {paged, _last} =
      Enum.map_reduce(blocks, :none, fn block, last ->
        page = block.page
        {{block, if(page != last, do: page)}, page}
      end)

    paged
  end

  defp matches?(text, find), do: String.contains?(String.downcase(text), String.downcase(find))

  # The text with every match of `find` (ignoring case) in a <mark>, escaped.
  defp marked(text, ""), do: text

  defp marked(text, find) do
    ~r/#{Regex.escape(find)}/iu
    |> Regex.split(text, include_captures: true)
    |> Enum.with_index()
    |> Enum.map(fn
      {part, i} when rem(i, 2) == 1 ->
        ["<mark class=\"bg-yellow-100 text-yellow-900 rounded-sm\">", escape(part), "</mark>"]

      {part, _i} ->
        escape(part)
    end)
    |> then(&{:safe, &1})
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp hits_text(0), do: "No passage holds it."
  defp hits_text(1), do: "1 passage"
  defp hits_text(n), do: "#{n} passages"

  # A block's ref as an id: "#/texts/42" is "texts-42".
  defp block_id(ref), do: ref |> String.trim_leading("#/") |> String.replace("/", "-")

  defp and_list([]), do: ""
  defp and_list([one]), do: one
  defp and_list(list), do: Enum.join(Enum.drop(list, -1), ", ") <> " and " <> List.last(list)

  defp cap(text) do
    {first, rest} = String.split_at(text, 1)
    String.upcase(first) <> rest
  end
end
